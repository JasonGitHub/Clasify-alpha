import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { downloadURL, feedFresh, forgetBeta, keepFor, latestURL, refreshFeed } from "../src/beta";
import { noMail } from "../src/mailer";

// CLA-172: GET /v1/beta for the beta page.

const page = "https://getmypod.app";
let clock = 1_000_000;
let feed: () => Promise<Response>;
let asked: string[];
const fetcher = (async (input: RequestInfo | URL) => { asked.push(String(input)); return feed(); }) as typeof fetch;
const json = (body: unknown) => async () => new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } });
const good = { build: 400, date: "2026-11-21T00:00:00Z", file: "myPod-beta-400.dmg", url: "https://dl.getmypod.app/beta/myPod-beta-400.dmg" };

async function get(origin?: string, method = "GET") {
  const headers: Record<string, string> = origin ? { Origin: origin } : {};
  const response = await handle(new Request("https://api.example/v1/beta", { method, headers }), env,
    { now: () => clock, mailer: noMail, human: async () => false, fetcher });
  return { status: response.status, json: await response.json().catch(() => null) as Record<string, unknown>, headers: response.headers };
}

async function accounts(active: number, other = 0) {
  const rows = [...Array(active)].map((_, i) => [`a${i}`, "active"]).concat([...Array(other)].map((_, i) => [`w${i}`, "waitlist"]));
  if (rows.length) await env.DB.batch(rows.map(([id, state]) =>
    env.DB.prepare("INSERT INTO accounts (id, email, state, seat, created_at) VALUES (?, ?, ?, ?, 1)").bind(id, `${id}@example.com`, state, state === "active" ? 1 : 0)));
}

beforeEach(async () => {
  feed = json(good);
  asked = [];
  clock = 1_000_000;
  forgetBeta();
  await env.DB.batch(["mails", "swaps", "macs", "accounts", "beta_feed"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("GET /v1/beta", () => {
  it("gives the count, the cap of 25 and the newest beta", async () => {
    await accounts(3, 2);  // waitlist accounts do not count
    const answer = await get(page);
    expect(answer.status).toBe(200);
    expect(answer.json).toEqual({ taken: 3, cap: 25, full: false, build: 400, url: good.url });
    expect(asked).toEqual([latestURL]);
    expect(answer.headers.get("Cache-Control")).toBe("max-age=30");
    expect(answer.headers.get("Vary")).toBe("Origin");
    expect((await get()).headers.get("Vary")).toBe("Origin");  // also with no CORS
  });

  it("keeps the answer for 30 s in the isolate", async () => {
    await get(page);
    await accounts(2);
    clock += keepFor - 1;
    expect((await get(page)).json).toMatchObject({ taken: 0 });  // kept: no new read
    expect(asked).toHaveLength(1);
    clock += 1;
    expect((await get(page)).json).toMatchObject({ taken: 2 });  // the count read again
    expect(asked).toHaveLength(1);  // the feed is kept in D1, not read again
  });

  it("keeps the feed in D1 and refreshes it after the answer once it is 2 minutes old", async () => {
    const later: Promise<unknown>[] = [];
    const ask = () => handle(new Request("https://api.example/v1/beta", { headers: { Origin: page } }), env,
      { now: () => clock, mailer: noMail, human: async () => false, fetcher, later: (w) => later.push(w) });
    expect(await (await ask()).json()).toMatchObject({ build: 400 });
    expect(asked).toHaveLength(1);  // the very first time: nothing kept, so it waits for the feed
    // A new build is uploaded.
    const next = { ...good, build: 401, url: "https://dl.getmypod.app/beta/myPod-beta-401.dmg" };
    feed = json(next);
    clock += feedFresh - 1;
    expect(await (await ask()).json()).toMatchObject({ build: 400 });  // still fresh: no feed read
    expect([asked.length, later.length]).toEqual([1, 0]);
    clock += keepFor + 1;
    expect(await (await ask()).json()).toMatchObject({ build: 400 });  // old: answers at once with the kept build...
    expect(later).toHaveLength(1);
    await Promise.all(later);  // ...and reads the feed after the answer
    expect(asked).toHaveLength(2);
    clock += keepFor;
    expect(await (await ask()).json()).toMatchObject({ build: 401, url: next.url });
  });

  it("keeps the last build when the feed does not answer, and drops it when the feed is gone", async () => {
    await get(page);  // build 400 kept
    const brokenBody = async () => new Response(new ReadableStream({ pull(c) { c.error(new Error("cut")); } }));
    for (const answer of [async () => { throw new Error("timeout"); }, async () => new Response("down", { status: 503 }), brokenBody]) {
      feed = answer;
      await refreshFeed(env.DB, fetcher, clock += feedFresh);
      forgetBeta();
      expect((await get(page)).json).toMatchObject({ build: 400, url: good.url });
    }
    feed = async () => new Response("no", { status: 404 });
    await refreshFeed(env.DB, fetcher, clock += feedFresh);
    forgetBeta();
    expect((await get(page)).json).toMatchObject({ build: null, url: null });
  });

  it("checks a kept row again, like the feed", async () => {
    await env.DB.prepare("INSERT INTO beta_feed (id, build, url, checked_at) VALUES (1, 7, 'https://evil.example/x.dmg', ?)").bind(clock).run();
    expect((await get(page)).json).toMatchObject({ build: null, url: null });
    expect(asked).toHaveLength(0);
  });

  it("is full at the cap", async () => {
    await accounts(25);
    expect((await get(page)).json).toMatchObject({ taken: 25, cap: 25, full: true });
  });

  it("allows CORS only for the page", async () => {
    const mine = await get(page);
    expect(mine.headers.get("Access-Control-Allow-Origin")).toBe(page);
    expect(mine.headers.get("Access-Control-Allow-Methods")).toBe("GET, POST");
    const other = await get("https://evil.example");
    expect(other.headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect((await get(undefined)).headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect((await get(page, "OPTIONS")).status).toBe(204);
    expect((await get("https://evil.example", "OPTIONS")).status).toBe(404);
  });

  it("hides the version with no feed, a slow feed or a bad feed", async () => {
    const empty = { build: null, url: null };
    for (const answer of [
      async () => new Response("no", { status: 404 }),
      async () => { throw new Error("timeout"); },
      async () => new Response("not json"),
      json({ ...good, url: "https://evil.example/beta/x.dmg" }),
      json({ ...good, build: "400" }),
      json({ ...good, build: 0 }),
      json({ build: 400 }),
      json(null),
    ]) {
      feed = answer;
      clock += keepFor;
      await env.DB.prepare("DELETE FROM beta_feed").run();  // read the feed again
      expect((await get(page)).json).toMatchObject({ taken: 0, cap: 25, full: false, ...empty });
    }
  });
});

describe("downloadURL", () => {
  it("keeps only an https file link on dl.getmypod.app", () => {
    expect(downloadURL(good.url)).toBe(good.url);
    expect(downloadURL("HTTPS://DL.getmypod.app/beta/x.dmg")).toBe("https://dl.getmypod.app/beta/x.dmg");
    for (const value of [
      undefined, 400, "", "not a url", "https://dl.getmypod.app", "https://dl.getmypod.app/",
      "https://example.com/beta/x.dmg", "https://getmypod.app/beta/x.dmg", "https://evil.dl.getmypod.app/beta/x.dmg",
      "https://dl.getmypod.app.evil.com/beta/x.dmg", "https://dl.getmypod.app@evil.com/beta/x.dmg",
      "https://user@dl.getmypod.app/beta/x.dmg", "https://dl.getmypod.app:8443/beta/x.dmg",
      "http://dl.getmypod.app/beta/x.dmg", "javascript:alert(1)", "https://dl.getmypod.app/beta/x.dmg?a=1",
    ]) expect(downloadURL(value), String(value)).toBeNull();
  });
});

describe("TEST_BUILD (test server only)", () => {
  const withEnv = async (vars: Partial<Env>) => {
    forgetBeta();
    await env.DB.prepare("DELETE FROM beta_feed").run();
    const response = await handle(new Request("https://api.example/v1/beta", { headers: { Origin: page } }), { ...env, ...vars } as Env,
      { now: () => clock, mailer: noMail, human: async () => false, fetcher });
    return (await response.json()) as Record<string, unknown>;
  };

  it("names a stand-in build on the test server when there is no feed", async () => {
    feed = async () => new Response("", { status: 404 });
    expect(await withEnv({ TEST_SERVER: "1", TEST_BUILD: "999" }))
      .toMatchObject({ build: 999, url: "https://dl.getmypod.app/beta/myPod-beta-999.dmg" });
  });

  it("lets a real feed win", async () => {
    expect(await withEnv({ TEST_SERVER: "1", TEST_BUILD: "999" })).toMatchObject({ build: 400, url: good.url });
  });

  it("is ignored on live, and when it is not a whole number from 1", async () => {
    feed = async () => new Response("", { status: 404 });
    expect(await withEnv({ TEST_SERVER: undefined, TEST_BUILD: "999" })).toMatchObject({ build: null, url: null });
    expect(await withEnv({ TEST_SERVER: "0", TEST_BUILD: "999" })).toMatchObject({ build: null, url: null });
    for (const value of ["abc", "-1", "0", "1.5", "07", "1e3", "9999999999", " 9", ""]) {
      expect(await withEnv({ TEST_SERVER: "1", TEST_BUILD: value }), value).toMatchObject({ build: null, url: null });
    }
  });
});
