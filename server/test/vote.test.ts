import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { noMail } from "../src/mailer";
import { turnstile } from "../src/turnstile";
import { colorItems, network, voteItems } from "../src/vote";

// CLA-172: POST /v1/vote from the beta page. CLA-198: with the page's bot check token (`human`).

const day = 24 * 60 * 60_000;
let clock = Date.UTC(2026, 10, 21, 12);

/** The bot check: a token "pass…" passes; the tokens it was asked about, in order. */
let checked: string[] = [];
const passes = async (token: string) => { checked.push(token); return token.startsWith("pass"); };

async function vote(body: unknown, ip = "203.0.113.5", method = "POST", human = passes) {
  const withToken = body && typeof body === "object" && !("human" in body) ? { human: "pass-1", ...body } : body;
  const request = new Request("https://api.example/v1/vote", {
    method, headers: { Origin: "https://getmypod.app", "CF-Connecting-IP": ip }, body: method === "POST" ? JSON.stringify(withToken) : undefined,
  });
  const response = await handle(request, env, { now: () => clock, mailer: noMail, human });
  return { status: response.status, result: ((await response.json()) as { result?: string }).result };
}
const counts = async () => Object.fromEntries((await env.DB.prepare("SELECT item, count FROM votes").all<{ item: string; count: number }>())
  .results.map((r) => [r.item, r.count]));

beforeEach(async () => {
  clock = Date.UTC(2026, 10, 21, 12);
  checked = [];
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

  it("counts nothing and writes nothing without a passed bot check", async () => {
    const rows = async () => Promise.all(["votes", "vote_tries", "vote_salts"].map(async (t) =>
      (await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${t}`).first<{ n: number }>())?.n));
    for (const human of [undefined, "", 3, null, { token: "pass-1" }]) {
      expect((await vote({ item: "nano", human })).result, String(human)).toBe("bot");  // no token
    }
    expect((await vote({ item: "nano", human: "fail-1" })).result).toBe("bot");  // the check fails
    // The verify call fails (no network, an error page, no secret): the real check fails closed.
    const down = turnstile("secret", "getmypod.app", async () => { throw new Error("down"); });
    const error = turnstile("secret", "getmypod.app", async () => new Response("no", { status: 500 }));
    for (const human of [down, error, turnstile(undefined, "getmypod.app")]) {
      expect((await vote({ item: "nano" }, undefined, "POST", human)).result).toBe("bot");
    }
    expect(await rows()).toEqual([0, 0, 0]);
    expect(checked).toEqual(["", "fail-1"]);  // only text goes to the check; turnstile() refuses "" with no call
    // A passed check: ok, then busy for the same network and item.
    expect((await vote({ item: "nano", human: "pass-2" })).result).toBe("ok");
    expect((await vote({ item: "nano", human: "pass-3" })).result).toBe("busy");
    expect(await counts()).toEqual({ nano: 1 });
  });

  it("checks the item before the bot check", async () => {
    expect((await vote({ item: "x", human: "pass-1" })).result).toBe("bad");
    expect(checked).toEqual([]);
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

describe("GET /v1/votes", () => {
  const shares = async (origin = "https://getmypod.app") => {
    const response = await handle(new Request("https://api.example/v1/votes", { headers: { Origin: origin } }), env, { now: () => clock, mailer: noMail, human: passes });
    return { response, body: (await response.json()) as { shares: Record<string, number> } };
  };
  const set = (rows: Record<string, number>) =>
    env.DB.batch(Object.entries(rows).map(([item, count]) => env.DB.prepare("INSERT INTO votes (item, count) VALUES (?, ?)").bind(item, count)));

  it("gives only whole percent for the open items, never the counts, and leaves out the built item", async () => {
    expect((await shares()).body).toEqual({ shares: {} });  // no votes yet
    await set({ "local-music": 3, "more-colors": 4, nano: 3, radio: 3, "like-from-wheel": 3 });
    const { response, body } = await shares();
    // 4/13 and 3/13: largest remainder makes 100; the tie goes to the item first in the list.
    expect(body).toEqual({ shares: { nano: 23, radio: 23, "like-from-wheel": 23, "more-colors": 31 } });
    expect(response.headers.get("Cache-Control")).toBe("max-age=30");
    expect(response.headers.get("Access-Control-Allow-Origin")).toBe("https://getmypod.app");
    expect((await shares("https://evil.example")).response.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("counts a color pick like a vote, and never puts it in the shares", async () => {
    for (const item of colorItems) expect((await vote({ item })).result).toBe("ok");
    expect((await vote({ item: "color-red" })).result).toBe("busy");  // one a day per network
    expect((await vote({ item: "color-black" })).result).toBe("bad");
    expect((await vote({ item: "color-red" }, "198.51.100.9", "POST", async () => false)).result).toBe("bot");
    expect(await counts()).toMatchObject({ "color-pink": 1, "color-blue": 1, "color-green": 1, "color-red": 1 });
    expect((await shares()).body).toEqual({ shares: {} });
  });

  it("adds up to 100 and counts a new vote", async () => {
    await set({ nano: 1, radio: 1, "like-from-wheel": 1 });
    expect((await shares()).body.shares).toEqual({ nano: 34, radio: 33, "like-from-wheel": 33, "more-colors": 0 });
    expect((await vote({ item: "more-colors" })).result).toBe("ok");
    expect((await shares()).body.shares).toEqual({ nano: 25, radio: 25, "like-from-wheel": 25, "more-colors": 25 });
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
