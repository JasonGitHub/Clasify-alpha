import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { noMail } from "../src/mailer";
import { voteItems } from "../src/vote";

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
});
