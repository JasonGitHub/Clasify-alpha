import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { linkDownloadPath, linkKey, linkWords, withoutFrom } from "../public/beta-page/logic.js";
import { sha256, token } from "../src/activation";
import { workerFirstPaths } from "../src/launch";
import { countLinkDownload, countLinkOpen, linkCap, linkOf } from "../src/links";

// CLA-193: short links, getmypod.app/r/<name> and getmypod.app/<word> (Jason OK 22:25 and 22:27 JST 11-25).

let clock = Date.UTC(2026, 10, 25, 12);
const day = 24 * 60 * 60_000;
const open = (key: string, ip = "203.0.113.7") => countLinkOpen(env.DB, key, ip, clock, sha256, token);
const press = (link: unknown, ip = "203.0.113.7") => countLinkDownload(env.DB, { link }, ip, clock, sha256, token);
const rows = async (table: string) => (await env.DB.prepare(`SELECT * FROM ${table}`).all<Record<string, unknown>>()).results;
const opens = async () => Object.fromEntries((await rows("link_opens")).map((r) => [r.link, r.count]));
const downloads = async () => Object.fromEntries((await rows("link_downloads")).map((r) => [`${r.link} ${r.day}`, r.count]));

beforeEach(async () => {
  clock = Date.UTC(2026, 10, 25, 12);
  await env.DB.batch(["link_opens", "link_downloads", "link_tries", "vote_salts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("short link keys", () => {
  it("takes the fixed words and any Reddit name, in lower case, each with its own key", () => {
    expect(linkKey("hn")).toBe("hn");
    expect(linkKey("HN")).toBe("hn");
    expect(linkKey("x")).toBe("x");
    expect(linkKey("r/ipodclassic")).toBe("r/ipodclassic");
    expect(linkKey("r/IpodClassic")).toBe("r/ipodclassic");
    expect(linkKey("R/mac_apps")).toBe("r/mac_apps");
    expect(linkKey("r/ab")).toBe("r/ab");
    expect(linkKey(`r/${"a".repeat(21)}`)).toBe(`r/${"a".repeat(21)}`);
    expect(linkKey("r/hn")).toBe("r/hn");  // a subreddit named hn is not the word hn
    for (const bad of ["", "r", "r/", "r/a", `r/${"a".repeat(22)}`, "r/a-b", "r/a.b", "r/a b", "r/ab/", "r/é", "ipod", "hn/", "/hn",
      "r/ipodclassic/x", "beta", 5, null, undefined, ["hn"], {}]) {
      expect(linkKey(bad), String(bad)).toBeNull();
    }
  });

  it("keeps the words short, a-z 0-9 - only, and apart from the Reddit links", () => {
    for (const w of linkWords) {
      expect(w).toMatch(/^[a-z0-9-]{1,16}$/);
      expect(w).not.toBe("r");
    }
  });

  it("reads the key from the path, and nothing else", () => {
    const of = (path: string) => linkOf(new Request(`https://getmypod.app${path}`));
    expect(of("/hn")).toBe("hn");
    expect(of("/HN")).toBe("hn");
    expect(of("/x?ref=a")).toBe("x");
    expect(of("/r/ipodclassic")).toBe("r/ipodclassic");
    expect(of("/r/IpodClassic")).toBe("r/ipodclassic");
    for (const path of ["/", "/r", "/r/", "/r/a", "/r/ipodclassic/", "/r/ipod/x", "/r/ipod%5Fclassic", "/hnx", "/hn/", "/beta", "/v1/vote", "/privacy/"]) {
      expect(of(path), path).toBeNull();
    }
  });

  it("does not shadow a file, a folder or a Worker path", () => {
    const files = Object.keys(import.meta.glob("../public/**", { query: "?url" })).map((f) => f.slice("../public/".length));
    expect(files.length).toBeGreaterThan(10);
    const tops = new Set(files.map((f) => f.split("/")[0].replace(/\.html$/, "")));
    for (const top of ["r", ...linkWords]) expect(tops.has(top), top).toBe(false);
    for (const p of workerFirstPaths) expect(linkOf(new Request(`https://getmypod.app${p.replace("/*", "/x")}`)), p).toBeNull();
  });

  it("takes ?from= out of the page address and keeps the rest", () => {
    expect(withoutFrom("/beta", "?from=hn", "")).toBe("/beta");
    expect(withoutFrom("/beta", "?from=r%2Fipodclassic", "")).toBe("/beta");
    expect(withoutFrom("/beta", "?invite=sam&from=hn", "#inv")).toBe("/beta?invite=sam#inv");
    expect(withoutFrom("/beta", "", "")).toBe("/beta");
  });
});

describe("opens per short link", () => {
  it("counts one open per key a day per network, and keeps no address", async () => {
    expect(await open("hn")).toBe("ok");
    expect(await open("hn")).toBe("seen");
    expect(await open("hn", "203.0.113.8")).toBe("ok");
    expect(await open("hn", "2001:db8:1:2::5")).toBe("ok");
    expect(await open("hn", "2001:db8:1:2:aaaa::9")).toBe("seen");  // same /64 network
    expect(await open("r/ipodclassic")).toBe("ok");
    expect(await open("r/hn")).toBe("ok");  // its own key, not hn
    expect(await opens()).toEqual({ hn: 3, "r/ipodclassic": 1, "r/hn": 1 });
    for (const r of await rows("link_tries")) {
      expect(r.net_hash).toMatch(/^[0-9a-f]{64}$/);
      expect(JSON.stringify(r)).not.toContain("203.0.113");
    }
  });

  it("counts the same network again the next day, and drops tries older than 2 days", async () => {
    await open("hn");
    clock += day;
    expect(await open("hn")).toBe("ok");
    expect(await opens()).toEqual({ hn: 2 });
    clock += 3 * day;
    await open("x");
    expect(await rows("link_tries")).toHaveLength(1);  // only today's
  });

  it(`counts no new key past ${linkCap}, and still counts the known ones`, async () => {
    const fill = [...Array(linkCap)].map((_, i) => env.DB.prepare("INSERT INTO link_opens (link, count) VALUES (?, 1)").bind(`r/name${i}`));
    for (let i = 0; i < fill.length; i += 100) await env.DB.batch(fill.slice(i, i + 100));
    expect(await open("r/onemore")).toBe("full");
    expect(await open("r/onemore", "198.51.100.1")).toBe("full");
    expect(await rows("link_tries")).toHaveLength(0);  // no row for a key past the cap
    expect(await open("r/name7")).toBe("ok");
    expect((await opens())["r/name7"]).toBe(2);
    expect(Object.keys(await opens())).toHaveLength(linkCap);
  });
});

describe("Download presses per short link", () => {
  it("counts one press per key a day per network, per UTC day", async () => {
    await open("r/ipodclassic");
    expect(await press("r/IpodClassic")).toBe("ok");
    expect(await press("r/ipodclassic")).toBe("seen");
    expect(await press("r/ipodclassic", "198.51.100.1")).toBe("ok");  // a press needs no open from the same network
    clock += day;
    expect(await press("r/ipodclassic")).toBe("ok");
    expect(await downloads()).toEqual({ "r/ipodclassic 2026-11-25": 2, "r/ipodclassic 2026-11-26": 1 });
    expect(await opens()).toEqual({ "r/ipodclassic": 1 });  // a press is not an open
  });

  it("takes only a valid key that already has an open counted, so a press makes no new row", async () => {
    for (const bad of ["", "ipod", "r/a", "/hn", 5, null, undefined, { link: "hn" }]) expect(await press(bad), String(bad)).toBe("bad");
    expect(await press("hn")).toBe("full");
    expect(await press("r/neveropened")).toBe("full");
    expect(await rows("link_tries")).toHaveLength(0);
    expect(await rows("link_downloads")).toHaveLength(0);
    expect(await rows("link_opens")).toHaveLength(0);
  });
});

describe("the Worker", () => {
  const html = '<html><body class="one hm loading"><div id="spots" class="spots"></div></body></html>';
  // Like the live files: the beta page, and nothing at the short link paths.
  const assets = { fetch: async (r: Request) => new URL(r.url).pathname.startsWith("/beta")
    ? new Response(html, { headers: { "Content-Type": "text/html" } }) : new Response("Not found", { status: 404 }) } as unknown as Fetcher;

  async function visit(url: string, init: RequestInit = {}, vars: Partial<Env> = {}, db = env.DB) {
    const worker = (await import("../src/index")).default;
    const work: Promise<unknown>[] = [];
    const ctx = { waitUntil: (p: Promise<unknown>) => work.push(p), passThroughOnException: () => {} } as unknown as ExecutionContext;
    const headers = { "CF-Connecting-IP": "203.0.113.7", ...(init.headers as Record<string, string> ?? {}) };
    const answer = await worker.fetch(new Request(url, { redirect: "manual", ...init, headers }), { ...env, ASSETS: assets, ...vars } as Env, ctx);
    await Promise.all(work);
    return answer;
  }

  for (const testServer of [false, true]) {
    it(`${testServer ? "test server" : "live"}: a short link counts after the answer and goes to /beta only`, async () => {
      const vars = testServer ? { TEST_SERVER: "1" } : {};
      const hn = await visit("https://getmypod.app/hn?to=https://evil.example/", {}, vars);
      expect(hn.status).toBe(302);
      expect(hn.headers.get("Location")).toBe("/beta?from=hn");  // nothing of the asked address goes along
      expect(hn.headers.get("Cache-Control")).toBe("no-store");
      expect((await visit("https://getmypod.app/r/IpodClassic", {}, vars)).headers.get("Location")).toBe("/beta?from=r%2Fipodclassic");
      await visit("https://getmypod.app/x", { method: "HEAD" }, vars);  // a HEAD goes to /beta too, but does not count
      expect(await opens()).toEqual({ hn: 1, "r/ipodclassic": 1 });
    });

    it(`${testServer ? "test server" : "live"}: a path that does not fit is an unknown path, as before`, async () => {
      const vars = testServer ? { TEST_SERVER: "1" } : {};
      const before = await visit("https://getmypod.app/nothing-here", {}, vars);
      for (const path of ["/r/", "/r/a", "/r/a-b", "/hnx", "/r/ipodclassic/"]) {
        const answer = await visit(`https://getmypod.app${path}`, {}, vars);
        expect(answer.status, path).toBe(before.status);
        expect(answer.headers.get("Location"), path).toBeNull();
      }
      expect(await rows("link_opens")).toHaveLength(0);
    });
  }

  it("sends to /beta past the cap too, and never breaks when the count fails", async () => {
    const fill = [...Array(linkCap)].map((_, i) => env.DB.prepare("INSERT INTO link_opens (link, count) VALUES (?, 1)").bind(`r/name${i}`));
    for (let i = 0; i < fill.length; i += 100) await env.DB.batch(fill.slice(i, i + 100));
    expect((await visit("https://getmypod.app/r/onemore")).headers.get("Location")).toBe("/beta?from=r%2Fonemore");
    expect((await opens())["r/onemore"]).toBeUndefined();
    const broken = { ...env.DB, batch: async () => { throw new Error("D1 down"); }, prepare: env.DB.prepare.bind(env.DB) } as unknown as D1Database;
    expect((await visit("https://getmypod.app/hn", {}, { DB: broken })).headers.get("Location")).toBe("/beta?from=hn");
  });

  it("counts a Download press from the page, with no preflight, and answers the page", async () => {
    await visit("https://getmypod.app/hn");
    const answer = await visit(`https://api.getmypod.app${linkDownloadPath}`, { method: "POST", body: JSON.stringify({ link: "hn" }), headers: { Origin: "https://getmypod.app", "Content-Type": "text/plain;charset=UTF-8" } });
    expect(await answer.json()).toEqual({ result: "ok" });
    expect(answer.headers.get("Access-Control-Allow-Origin")).toBe("https://getmypod.app");
    expect(Object.values(await downloads())).toEqual([1]);
  });
});
