import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { noMail } from "../src/mailer";
import { network, voteItems } from "../src/vote";

// CLA-172: POST /v1/vote from the beta page.

const day = 24 * 60 * 60_000;
let clock = Date.UTC(2026, 10, 21, 12);

async function vote(body: unknown, ip = "203.0.113.5", method = "POST") {
  const request = new Request("https://api.example/v1/vote", {
    method, headers: { Origin: "https://getmypod.app", "CF-Connecting-IP": ip }, body: method === "POST" ? JSON.stringify(body) : undefined,
  });
  const response = await handle(request, env, { now: () => clock, mailer: noMail, human: async () => false });
  return { status: response.status, result: ((await response.json()) as { result?: string }).result };
}
const counts = async () => Object.fromEntries((await env.DB.prepare("SELECT item, count FROM votes").all<{ item: string; count: number }>())
  .results.map((r) => [r.item, r.count]));

beforeEach(async () => {
  clock = Date.UTC(2026, 10, 21, 12);
  await env.DB.batch(["votes", "vote_tries", "vote_salts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("POST /v1/vote", () => {
  it("counts a vote per item, and keeps nothing about who", async () => {
    for (const item of voteItems) expect((await vote({ item })).result).toBe("ok");
    expect(await vote({ item: "nano" }, "198.51.100.7")).toMatchObject({ result: "ok" });
    expect(await counts()).toEqual({ "local-music": 1, nano: 2, radio: 1, "like-from-wheel": 1, "more-colors": 1 });
    const tries = (await env.DB.prepare("SELECT * FROM vote_tries").all<Record<string, string>>()).results;
    expect(tries.every((t) => /^[0-9a-f]{64}$/.test(t.net_hash) && !JSON.stringify(t).includes("203.0.113"))).toBe(true);
  });

  it("allows one vote per item a day per network", async () => {
    expect((await vote({ item: "radio" })).result).toBe("ok");
    expect((await vote({ item: "radio" })).result).toBe("busy");
    expect((await vote({ item: "nano" })).result).toBe("ok");  // another item
    clock += day;
    expect((await vote({ item: "radio" })).result).toBe("ok");  // the next day: a new salt
    expect(await counts()).toMatchObject({ radio: 2, nano: 1 });
  });

  it("refuses an item that is not on the list", async () => {
    for (const item of [undefined, "", "NANO", "nano ", "something-else", 3, "__proto__"]) {
      expect((await vote({ item }, "192.0.2.1")).result, String(item)).toBe("bad");
    }
    expect(await counts()).toEqual({});
  });

  it("has no GET for the counts", async () => {
    expect((await vote(null, undefined, "GET")).status).toBe(404);
  });

  it("forgets tries and salts after 2 days", async () => {
    await vote({ item: "radio" });
    clock += 3 * day;
    await vote({ item: "nano" });
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM vote_tries").first<{ n: number }>())?.n).toBe(1);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM vote_salts").first<{ n: number }>())?.n).toBe(1);
  });

  it("counts one vote per IPv6 /64, and per whole IPv4 address", async () => {
    expect((await vote({ item: "radio" }, "2001:db8:1:2::a")).result).toBe("ok");
    expect((await vote({ item: "radio" }, "2001:0db8:0001:0002:ffff:1:2:3")).result).toBe("busy");  // the same /64
    expect((await vote({ item: "radio" }, "2001:db8:1:3::a")).result).toBe("ok");  // another /64
    expect((await vote({ item: "radio" }, "192.0.2.1")).result).toBe("ok");
    expect((await vote({ item: "radio" }, "192.0.2.2")).result).toBe("ok");  // IPv4: the whole address
    expect(await counts()).toEqual({ radio: 4 });
  });
});

describe("network()", () => {
  it("keeps the /64 of an IPv6 address and the whole IPv4 address", () => {
    expect(network("2001:db8:1:2::a")).toBe("2001:db8:1:2::/64");
    expect(network("2001:0DB8:0001:0002:0000:0000:0000:0001")).toBe("2001:db8:1:2::/64");
    expect(network("2001:db8::1")).toBe("2001:db8:0:0::/64");
    expect(network("::1")).toBe("0:0:0:0::/64");
    expect(network("fe80::1%eth0")).toBe("fe80:0:0:0::/64");
    expect(network("::ffff:192.0.2.1")).toBe("192.0.2.1");
    expect(network("192.0.2.1")).toBe("192.0.2.1");
    expect(network("not an ip")).toBe("not an ip");
  });
});
