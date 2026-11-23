import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { formBody, inviteID } from "../public/beta-page/logic.js";
import { sha256, token } from "../src/activation";
import { countOpen, inviteCap, inviteOf } from "../src/invitelinks";

// CLA-172: invite links, getmypod.app/beta?invite=<id> (Jason OK 20:29 JST 11-23).

let clock = Date.UTC(2026, 10, 23, 12);
const day = 24 * 60 * 60_000;
const open = (id: string, ip = "203.0.113.7") => countOpen(env.DB, id, ip, clock, sha256, token);
const counts = async () => Object.fromEntries((await env.DB.prepare("SELECT id, count FROM invite_opens ORDER BY id").all<{ id: string; count: number }>()).results.map((r) => [r.id, r.count]));
const tries = async () => (await env.DB.prepare("SELECT COUNT(*) AS n FROM invite_tries").first<{ n: number }>())!.n;

beforeEach(async () => {
  clock = Date.UTC(2026, 10, 23, 12);
  await env.DB.batch(["invite_opens", "invite_tries", "vote_salts", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("invite ids", () => {
  it("takes lower case a-z, 0-9, _ and -, 1 to 32 characters, after lower-casing", () => {
    expect(inviteID("jason")).toBe("jason");
    expect(inviteID("Jason_01-X")).toBe("jason_01-x");
    expect(inviteID("x".repeat(32))).toBe("x".repeat(32));
    for (const bad of ["", "x".repeat(33), "a b", "a/b", "a.b", "é", "ａ", "a%20", "<b>", " a", 5, null, undefined, ["a"], {}]) {
      expect(inviteID(bad), String(bad)).toBeNull();
    }
  });

  it("reads the id from the page address", () => {
    expect(inviteOf("https://getmypod.app/beta?invite=Sam")).toBe("sam");
    expect(inviteOf("https://getmypod.app/beta?from=x&invite=team-1")).toBe("team-1");
    expect(inviteOf("https://getmypod.app/beta?invite=a%2Fb")).toBeNull();
    expect(inviteOf("https://getmypod.app/beta?invite=")).toBeNull();
    expect(inviteOf("https://getmypod.app/beta")).toBeNull();
  });

  it("goes only with the waitlist form, never with Email me the link", () => {
    expect(formBody("waitlist", "a@example.com", "t", "sam")).toEqual({ email: "a@example.com", human: "t", invite: "sam" });
    expect(formBody("waitlist", "a@example.com", "t", null)).toEqual({ email: "a@example.com", human: "t" });
    expect(formBody("link", "a@example.com", "t", "sam")).toEqual({ email: "a@example.com", human: "t" });
  });
});

describe("page opens per invite id", () => {
  it("counts one open per id a day per network, and keeps no address", async () => {
    expect(await open("sam")).toBe("ok");
    expect(await open("sam")).toBe("seen");
    expect(await open("sam", "203.0.113.8")).toBe("ok");
    expect(await open("sam", "2001:db8:1:2::5")).toBe("ok");
    expect(await open("sam", "2001:db8:1:2:aaaa::9")).toBe("seen");  // same /64 network
    expect(await open("kim")).toBe("ok");  // another id from the same network
    expect(await counts()).toEqual({ kim: 1, sam: 3 });
    const rows = (await env.DB.prepare("SELECT * FROM invite_tries").all<Record<string, string>>()).results;
    for (const r of rows) {
      expect(r.net_hash).toMatch(/^[0-9a-f]{64}$/);
      expect(JSON.stringify(r)).not.toContain("203.0.113");
    }
  });

  it("counts the same network again the next day, and drops tries older than 2 days", async () => {
    await open("sam");
    clock += day;
    expect(await open("sam")).toBe("ok");
    expect(await counts()).toEqual({ sam: 2 });
    clock += 3 * day;
    await open("kim");
    expect(await tries()).toBe(1);  // only today's
  });

  it(`ignores new ids past ${inviteCap}, and still counts the known ones`, async () => {
    const rows = [...Array(inviteCap)].map((_, i) => env.DB.prepare("INSERT INTO invite_opens (id, count) VALUES (?, 1)").bind(`id${i}`));
    for (let i = 0; i < rows.length; i += 100) await env.DB.batch(rows.slice(i, i + 100));
    expect(await open("one-more")).toBe("full");
    expect(await open("one-more", "198.51.100.1")).toBe("full");
    expect(await tries()).toBe(0);  // no row for an ignored id
    expect(await open("id7")).toBe("ok");
    expect((await counts())["id7"]).toBe(2);
    expect(Object.keys(await counts())).toHaveLength(inviteCap);
  });
});

describe("the Worker counts opens of the beta page", () => {
  const html = '<html><body class="one hm loading"><div id="spots" class="spots"></div></body></html>';
  const assets = { fetch: async () => new Response(html, { headers: { "Content-Type": "text/html" } }) } as unknown as Fetcher;

  async function visit(url: string, method = "GET", vars: Partial<Env> = {}) {
    const worker = (await import("../src/index")).default;
    const work: Promise<unknown>[] = [];
    const ctx = { waitUntil: (p: Promise<unknown>) => work.push(p), passThroughOnException: () => {} } as unknown as ExecutionContext;
    const answer = await worker.fetch(new Request(url, { method, headers: { "CF-Connecting-IP": "203.0.113.7" } }), { ...env, ASSETS: assets, ...vars } as Env, ctx);
    await Promise.all(work);
    return answer;
  }

  for (const testServer of [false, true]) {
    it(`${testServer ? "test server" : "live"}: GET /beta with a valid id counts, after the answer`, async () => {
      const vars = testServer ? { TEST_SERVER: "1" } : {};
      expect((await visit("https://getmypod.app/beta?invite=Sam", "GET", vars)).status).toBe(200);
      await visit("https://getmypod.app/beta?invite=bad%20id", "GET", vars);
      await visit("https://getmypod.app/beta?invite=kim", "HEAD", vars);
      await visit("https://getmypod.app/privacy/?invite=kim", "GET", vars);
      expect(await counts()).toEqual({ sam: 1 });
      // "/" keeps the query, so the id reaches /beta.
      expect((await visit("https://getmypod.app/?invite=sam", "GET", vars)).headers.get("Location")).toBe("/beta?invite=sam");
    });
  }

  it("never breaks the page when the count fails", async () => {
    const broken = { ...env.DB, batch: async () => { throw new Error("D1 down"); }, prepare: env.DB.prepare.bind(env.DB) } as unknown as D1Database;
    const worker = (await import("../src/index")).default;
    const work: Promise<unknown>[] = [];
    const ctx = { waitUntil: (p: Promise<unknown>) => work.push(p), passThroughOnException: () => {} } as unknown as ExecutionContext;
    const answer = await worker.fetch(new Request("https://getmypod.app/beta?invite=sam"), { ...env, DB: broken, ASSETS: assets } as Env, ctx);
    expect(answer.status).toBe(200);
    await expect(Promise.all(work)).resolves.toBeDefined();  // the error is dropped
  });
});
