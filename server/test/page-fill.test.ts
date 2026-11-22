import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import headers from "../public/_headers?raw";
import page from "../public/index.html?raw";
import { edits, fill, loadingFill, parseBeta } from "../public/beta-page/logic.js";
import { forgetBeta } from "../src/beta";
import { betaPage, fillWait, isBetaPage, rewriteWait } from "../src/page";

// CLA-172: the Worker writes the beta state into the page before it sends it.

const csp = headers.split("\n").find((l) => l.trim().startsWith("Content-Security-Policy:") && l.includes("challenges.cloudflare.com"))!
  .split("Content-Security-Policy:")[1].trim();
let asked: Request[] = [];
const assets = { fetch: async (input: RequestInfo | URL) => {
  asked.push(new Request(input as RequestInfo));
  return new Response(page, { headers: { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": csp, ETag: '"abc"', "Cache-Control": "public, max-age=0, must-revalidate" } });
} } as unknown as Fetcher;
const feed = (body: unknown, delay = 0) => (async () => {
  if (delay) await new Promise((z) => setTimeout(z, delay));
  return new Response(JSON.stringify(body), { headers: { "Content-Type": "application/json" } });
}) as unknown as typeof fetch;
const good = { build: 999, url: "https://dl.getmypod.app/beta/myPod-beta-999.dmg" };
const testEnv = { ...env, CAP: "25" } as Env;

async function accounts(n: number) {
  if (n) await env.DB.batch([...Array(n)].map((_, i) =>
    env.DB.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES (?, ?, 'active', 1)").bind(`a${i}`, `a${i}@example.com`)));
}
const get = (headers: Record<string, string> = {}) => new Request("https://page.example/", { headers });

/** The page as page.js would draw it from the static file: every edit applied by hand. */
function drawn(f: ReturnType<typeof fill>): Record<string, string | null> {
  const out: Record<string, string | null> = {};
  for (const e of edits(f)) out[`${e.selector}|${e.attr ?? (e.state ? "class" : e.html !== undefined ? "html" : "text")}`] = e.state ?? e.value ?? e.text ?? e.html ?? null;
  return out;
}

/** What the server wrote, read back from its HTML. */
function served(html: string): Record<string, string | null> {
  const one = (re: RegExp) => html.match(re)?.[1] ?? null;
  return {
    "body|class": one(/<body class="one hm ([a-z]+)">/),
    ".row > a.cta|href": one(/<a class="cta"(?: href="([^"]*)")?><svg/),
    ".row > .bver b|text": one(/<p class="bver"><b>([^<]*)<\/b>/),
    "#wl button|text": one(/<button class="cta" type="submit">([^<]*)<\/button>/),
    "#wl .ok|text": one(/<p class="ok">([^<]*)<\/p>/),
    "#spots|class": one(/<div id="spots" class="([^"]*)">/),
    "#spots|html": one(/<div id="spots" class="[^"]*">(.*?)<\/div><\/div>|<div id="spots" class="[^"]*">(<p>[^]*?<\/p>)<\/div>/s),
  };
}

beforeEach(async () => {
  asked = [];
  forgetBeta();
  await env.DB.batch(["mails", "swaps", "macs", "accounts", "beta_feed"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("the server-filled beta page", () => {
  it("fills only GET /", () => {
    expect(isBetaPage(get())).toBe(true);
    expect(isBetaPage(new Request("https://page.example/", { method: "HEAD" }))).toBe(false);
    for (const p of ["/privacy/", "/activate/", "/v1/beta", "/beta-page/page.js"]) expect(isBetaPage(new Request(`https://page.example${p}`))).toBe(false);
  });

  for (const [name, taken, latest] of [["open", 12, good], ["limited", 3, good], ["full", 25, good], ["no build", 12, {}]] as const) {
    it(`writes the same state as the page would draw: ${name}`, async () => {
      await accounts(taken);
      const response = await betaPage(get(), testEnv, assets, feed(latest));
      const html = await response.text();
      const f = fill(parseBeta({ taken, cap: 25, full: taken >= 25, build: "build" in latest ? latest.build : null, url: "url" in latest ? latest.url : null }));
      const want = drawn(f);
      const got = served(html);
      for (const key of Object.keys(want)) {
        if (key === "#spots|html") expect(html).toContain(`<div id="spots" class="${f.spotsClass}">${f.spots}</div>`);
        else if (key === ".row > a.cta|href") expect(got[key]).toBe(want[key]);
        else expect(got[key]).toBe(want[key]);
      }
      expect(html).not.toContain('<body class="one hm loading">');  // page.js then asks nothing
    });
  }

  it("keeps the CSP, keeps the page 30 s at most, and drops the old validator", async () => {
    await accounts(12);
    const response = await betaPage(get({ "If-None-Match": '"abc"' }), testEnv, assets, feed(good));
    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Security-Policy")).toBe(csp);
    expect(response.headers.get("Cache-Control")).toBe("max-age=30");
    expect(response.headers.get("ETag")).toBeNull();
    expect(asked[0].headers.get("If-None-Match")).toBeNull();  // never a 304 with an old page
    const html = await response.text();
    expect(response.headers.get("Content-Length")).toBe(String(new TextEncoder().encode(html).byteLength));  // one piece
    const styles = (t: string) => t.match(/\sstyle="/g)?.length ?? 0;
    expect(styles(html)).toBe(styles(page));  // no new style attribute: the CSP allows only the page's own
  });

  it("sends the page as it is when the count is slow, and page.js loads it", async () => {
    const response = await betaPage(get(), testEnv, assets, feed(good, fillWait + 200));
    const html = await response.text();
    expect(html).toBe(page);
    expect(html).toContain('<body class="one hm loading">');
    expect(response.headers.get("ETag")).toBe('"abc"');
    expect(loadingFill().state).toBe("loading");
  });

  it("sends the page as it is when the count fails, never a 500", async () => {
    const broken = { ...testEnv, DB: { prepare() { throw new Error("D1 down"); } } } as unknown as Env;
    const response = await betaPage(get(), broken, assets, feed(good));
    expect(response.status).toBe(200);
    expect(await response.text()).toBe(page);
  });

  it("holds the first paint until the hero is whole, so a half-parsed hero never shows", () => {
    // <link rel="expect"> blocks rendering until #next is parsed. #next must come right after <main>.
    expect(page).toMatch(/<head>[\s\S]*<link rel="expect" href="#next" blocking="render">[\s\S]*<\/head>/);
    expect(page.match(/id="next"/g)).toHaveLength(1);
    // Every browser: html.hero-wait hides the hero until the script right after </main> runs. If that
    // script never runs, a CSS animation shows the hero after 3 s, in one step (no fade).
    const head = page.slice(0, page.indexOf("</head>"));
    expect(head).toContain('<script>document.documentElement.classList.add("hero-wait")</script>');
    expect(page.slice(page.indexOf("<body"), page.indexOf("</main>"))).not.toContain("<script");
    expect(page).toContain(".hero-wait main{opacity:0;animation:waited 0s 3s forwards}@keyframes waited{to{opacity:1}}");
    expect(page.match(/hero-wait/g)).toHaveLength(3);  // add, remove, the rule: nothing else uses it
    expect(page.indexOf('id="next"')).toBeGreaterThan(page.indexOf("</main>"));
    expect(page.slice(page.indexOf("</main>"), page.indexOf('id="next"'))).toBe('</main>\n<script>document.documentElement.classList.remove("hero-wait")</script>\n<div class="nextband"><section class="next" ');
  });

  it("sends the plain page when the rewrite fails, never a 500", async () => {
    await accounts(12);
    let reads = 0;
    const breaking = { fetch: async (request: Request) => {
      reads++;
      if (reads > 1) return assets.fetch(request);
      let n = 0;
      const body = new ReadableStream({ pull(c) { if (n++ === 0) c.enqueue(new TextEncoder().encode(page.slice(0, 1000))); else c.error(new Error("cut")); } });
      return new Response(body, { headers: { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": csp } });
    } } as unknown as Fetcher;
    const response = await betaPage(get(), testEnv, breaking, feed(good));
    expect(response.status).toBe(200);
    expect(reads).toBe(2);
    expect(await response.text()).toBe(page);
  });

  it("sends the plain page when the rewrite stalls, never a hang", async () => {
    await accounts(12);
    let reads = 0;
    const stalling = { fetch: async (request: Request) => {
      reads++;
      if (reads > 1) return assets.fetch(request);
      const body = new ReadableStream({ start(c) { c.enqueue(new TextEncoder().encode(page.slice(0, 1000))); } });  // never ends
      return new Response(body, { headers: { "Content-Type": "text/html; charset=utf-8", "Content-Security-Policy": csp } });
    } } as unknown as Fetcher;
    const started = Date.now();
    const response = await betaPage(get(), testEnv, stalling, feed(good));
    expect(Date.now() - started).toBeLessThan(rewriteWait + 1000);
    expect(response.status).toBe(200);
    expect(reads).toBe(2);
    expect(await response.text()).toBe(page);
  });
});
