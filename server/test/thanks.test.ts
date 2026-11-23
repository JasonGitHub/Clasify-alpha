/// <reference types="vite/client" />
import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import thanksHtml from "../public/launch/thanks.html?raw";
import wireJs from "../public/launch-page/wire.js?raw";
import thanksJs from "../public/thanks-page/thanks.js?raw";
import wrangler from "../wrangler.jsonc?raw";
import { buyResult } from "../public/launch-page/logic.js";
import { sessionID, thanksState } from "../public/thanks-page/logic.js";
import { forgetBeta } from "../src/beta";
import { launchWiring, thanksCSP } from "../src/launch";

// CLA-175: the "thank you" page (card CM) at /thanks, the Buy button's rules, and the sales switch.

const files = new Set(Object.keys(import.meta.glob("../public/**", { eager: false })).map((f) => f.slice("../public".length)));

/** The static files: launch/thanks.html with its real text, any other file as a stand-in. */
function assets(asked: string[] = []) {
  return { fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
    const r = new Request(input as RequestInfo, init);
    const path = new URL(r.url).pathname;
    asked.push(`${r.method} ${path}`);
    if (path === "/launch/") return new Response('<body><a href="#download">Try it first</a><a href="#checkout">Buy</a></body>', { headers: { "Content-Type": "text/html" } });
    if (path === "/launch/thanks") return new Response(r.method === "HEAD" ? null : thanksHtml, { headers: { "Content-Type": "text/html", ETag: "\"x\"" } });
    const file = path.endsWith("/") ? path + "index.html" : path;
    return files.has(file) ? new Response(`file ${file}`) : new Response("not found", { status: 404 });
  } } as unknown as Fetcher;
}
async function ask(url: string, vars: Partial<Env>, method = "GET", asked: string[] = []) {
  const worker = (await import("../src/index")).default;
  return worker.fetch(new Request(url, { method, redirect: "manual" }), { ...env, ASSETS: assets(asked), ...vars } as Env);
}
const on = { TEST_SERVER: "1", TEST_BUILD: "999", LAUNCH_PAGE: "1", CAP: "1" };
const sid = "cs_test_a1B2c3D4e5F6g7H8";

beforeEach(async () => {
  forgetBeta();
  await env.DB.batch(["payments", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
  // A fresh, empty feed: no outside fetch in tests. TEST_BUILD stands in for the build.
  await env.DB.prepare("INSERT INTO beta_feed (id, build, url, checked_at) VALUES (1, NULL, NULL, ?) ON CONFLICT(id) DO UPDATE SET build = NULL, url = NULL, checked_at = excluded.checked_at").bind(Date.now()).run();
});

describe("/thanks", () => {
  it("serves card CM with PAID_MACS and the newest build, also when the beta is full; never cached", async () => {
    await env.DB.prepare("INSERT INTO accounts (id, email, state, seat, created_at) VALUES ('a', 'sam@example.com', 'active', 1, 0)").run();  // 1 of 1: full
    const page = await ask(`https://getmypod.app/thanks?session=${sid}`, { ...on, PAID_MACS: "4" });
    const html = await page.text();
    expect(page.status).toBe(200);
    expect(page.headers.get("Content-Security-Policy")).toBe(thanksCSP);
    expect(page.headers.get("Cache-Control")).toBe("no-store");
    expect(page.headers.get("Referrer-Policy")).toBe("no-referrer");
    expect(page.headers.get("ETag")).toBeNull();
    expect(html).toContain("ADMIT · <span data-macs>4</span> MACS");
    expect(html).toMatch(/<a class="b" href="https:\/\/dl\.getmypod\.app\/[^"]+\.dmg" data-dl>/);
    expect(html).not.toContain(sid);  // the page never writes the session ID
    expect((await ask("https://getmypod.app/thanks", on, "HEAD")).status).toBe(200);
  });

  it("leaves the download to the page when the build is unknown, and a bad PAID_MACS shows 3", async () => {
    const html = await (await ask("https://getmypod.app/thanks", { ...on, TEST_BUILD: undefined, PAID_MACS: "<b>" })).text();
    expect(html).toContain('href="#" data-dl>');
    expect(html).toContain("<span data-macs>3</span>");
  });

  it("is only there with the launch page on; the unfilled file is never public", async () => {
    for (const vars of [{}, { TEST_SERVER: "1" }]) expect((await ask("https://getmypod.app/thanks", vars)).status).toBe(404);
    for (const path of ["/thanks.html", "/thanks/", "/thanks/x", "/launch/thanks", "/launch/thanks.html"]) {
      expect((await ask(`https://getmypod.app${path}`, on)).status, path).toBe(404);
    }
  });

  it("has a strict CSP: its own files only, no inline script or style, no other host than our API", () => {
    expect(thanksCSP).not.toMatch(/unsafe|sha256|stripe|\*/);
    expect(thanksCSP).toContain("connect-src 'self' https://api.getmypod.app");
    expect(thanksHtml).not.toMatch(/\sstyle=|<style|<script>|<script(?![^>]*src="\/)/);
    expect(thanksHtml).not.toMatch(/(?:src|href)="https?:/);
    expect(thanksJs).not.toMatch(/https?:\/\/(?!dl\.)/);
    for (const m of thanksHtml.matchAll(/\s(?:src|href)="(\/[^"]+)"/g)) expect(files.has(m[1].replace(/\/$/, "/index.html")) || m[1] === "/", m[1]).toBe(true);
  });

  it("has the 4 states of card CM and no refund text", () => {
    for (const state of ["checking", "ok", "wait", "no"]) expect(thanksHtml).toContain(`class="s s-${state}"`);
    expect(thanksHtml).toContain('<body data-state="checking">');
    expect(thanksHtml.toLowerCase()).not.toContain("refund");
  });
});

describe("the launch page's Try it first", () => {
  it("gets the newest build while the beta has room, /beta when it is full, and stays for wire.js when the answer is unknown", async () => {
    expect(await (await ask("https://getmypod.app/", on)).text()).toMatch(/<a href="https:\/\/dl\.getmypod\.app\/[^"]+\.dmg">Try it first/);
    forgetBeta();
    await env.DB.prepare("INSERT INTO accounts (id, email, state, seat, created_at) VALUES ('a', 'sam@example.com', 'active', 1, 0)").run();
    expect(await (await ask("https://getmypod.app/", on)).text()).toContain('<a href="/beta">Try it first');
    forgetBeta();
    const unknown = await ask("https://getmypod.app/", { ...on, CAP: "0" });  // no usable beta answer
    expect(await unknown.text()).toContain('<a href="#download">Try it first');
    expect(unknown.headers.get("Cache-Control")).toBe("no-cache");
  });
});

describe("the page rules", () => {
  it("thanks: paid and pending mean something; anything else is not found", () => {
    expect(thanksState({ result: "paid" })).toBe("ok");
    expect(thanksState({ result: "pending" })).toBe("wait");
    for (const answer of [{ result: "not found" }, { result: "busy" }, null, "paid", { result: "PAID" }, {}]) expect(thanksState(answer)).toBe("no");
    expect(sessionID(sid)).toBe(sid);
    for (const bad of [null, "", "cs_live_short", "pi_123", `${sid}&x=1`, "cs_live_../x1234567890"]) expect(sessionID(bad)).toBeNull();
  });

  it("buy: only Stripe's page opens; every failure has one kind", () => {
    expect(buyResult(200, { url: "https://checkout.stripe.com/c/pay/x" })).toEqual({ url: "https://checkout.stripe.com/c/pay/x" });
    expect(buyResult(200, { url: "https://evil.example/" })).toEqual({ error: "other" });
    expect(buyResult(503, { error: "sales" })).toEqual({ error: "sales" });
    expect(buyResult(429, { error: "busy" })).toEqual({ error: "busy" });
    for (const [status, json] of [[null, null], [500, "x"], [200, {}], [503, { error: "other" }]] as const) expect(buyResult(status, json)).toEqual({ error: "other" });
    expect(wireJs.match(/function buyFailed/g)).toHaveLength(1);  // one place for the failure line
  });

  it("buy: a failure shows one plain line, set as text with a class, styled from our own file", () => {
    expect(wireJs).toContain('export const buyFailLine = "Sorry, checkout isn’t open right now. Please try again later.";');
    expect(wireJs).toContain("line.textContent = buyFailLine;");
    expect(wireJs).toContain('line.className = "bfail";');
    expect(wireJs).not.toMatch(/innerHTML|setAttribute\("style"/);
    expect(files.has("/launch-page/wire.css")).toBe(true);  // its look is checked in the browser (CSS files read as empty in this test pool)
  });

  it("the launch page loads only our script; the bot check loads at the first send", () => {
    expect(launchWiring).toBe('<link rel="stylesheet" href="/launch-page/wire.css"><script type="module" src="/launch-page/wire.js"></script>');
    expect(wireJs).toContain("loadTurnstile()");
  });

  it("sales are off on live and on on the test server", () => {
    const config = JSON.parse(wrangler.replace(/^\s*\/\/.*$/gm, "")) as { vars: Record<string, string>; env: { test: { vars: Record<string, string> } } };
    expect([config.vars.SALES, config.env.test.vars.SALES]).toEqual(["0", "1"]);
    expect([config.vars.BUY_HOUR, config.env.test.vars.BUY_HOUR]).toEqual(["10", "10"]);
    expect(config.vars.STRIPE_PRICE).toBeUndefined();
  });
});
