/// <reference types="vite/client" />
import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import headers from "../public/_headers?raw";
import launchHtml from "../public/launch/index.html?raw";
import wrangler from "../wrangler.jsonc?raw";
import { launchCSP, workerFirstPaths } from "../src/launch";

// CLA-175: the launch page for "/", behind LAUNCH_PAGE (Jason 21:55 JST 11-23: live only when a real
// checkout works). Without the switch, the site behaves exactly as before.

/** Every file in public/, by its served path. */
const files = new Set(Object.keys(import.meta.glob("../public/**", { eager: false })).map((f) => f.slice("../public".length)));

/** The static files as Cloudflare serves them: a folder path serves its index.html; no file is a 404. */
function assets(asked: string[] = []) {
  return { fetch: async (input: RequestInfo | URL, init?: RequestInit) => {
    const r = new Request(input as RequestInfo, init);
    const url = new URL(r.url);
    asked.push(`${r.method} ${url.pathname}${url.search}`);
    const path = url.pathname.endsWith("/") ? url.pathname + "index.html" : files.has(url.pathname) ? url.pathname : url.pathname + ".html";
    if (!files.has(path)) return new Response("not found", { status: 404 });
    return new Response(r.method === "HEAD" ? null : `file ${path}`, { headers: { "Content-Type": path.endsWith(".html") ? "text/html" : "application/octet-stream" } });
  } } as unknown as Fetcher;
}

async function ask(url: string, vars: Partial<Env>, method = "GET", asked: string[] = []) {
  const worker = (await import("../src/index")).default;
  return worker.fetch(new Request(url, { method, redirect: "manual" }), { ...env, ASSETS: assets(asked), ...vars } as Env);
}

const modes = [["live", {}], ["test server", { TEST_SERVER: "1" }]] as const;

describe("launch page switched off (live today)", () => {
  for (const [name, vars] of modes) {
    it(`${name}: "/" still goes to /beta, and none of the launch page's files is public`, async () => {
      const root = await ask("https://getmypod.app/?invite=sam", vars);
      expect([root.status, root.headers.get("Location")]).toEqual([302, "/beta?invite=sam"]);
      for (const path of ["/launch", "/launch/", "/launch/index.html", "/launch/og.png", "/og.png", "/covers/abbey-road-beatles.png", "/paw/open45c-32.png", "/color-black.png"]) {
        expect((await ask(`https://getmypod.app${path}`, vars)).status, path).toBe(404);
      }
      expect((await ask("https://getmypod.app/beta", vars)).status).toBe(200);
    });
  }

  it("is off unless LAUNCH_PAGE is exactly \"1\"", async () => {
    for (const LAUNCH_PAGE of [undefined, "", "0", "true", "yes", " 1"]) {
      expect((await ask("https://getmypod.app/", { LAUNCH_PAGE })).status, String(LAUNCH_PAGE)).toBe(302);
    }
  });
});

describe("launch page switched on (the test server)", () => {
  for (const [name, vars] of modes) {
    it(`${name}: "/" serves the launch page, and its files answer at the root paths`, async () => {
      const on = { ...vars, LAUNCH_PAGE: "1" };
      const asked: string[] = [];
      const page = await ask("https://getmypod.app/?invite=sam", on, "GET", asked);
      expect([page.status, await page.text()]).toEqual([200, "file /launch/index.html"]);
      expect(page.headers.get("Content-Security-Policy")).toBe(launchCSP);
      expect(page.headers.get("Referrer-Policy")).toBe("no-referrer");
      expect(asked).toContain("GET /launch/?invite=sam");  // the query goes along
      expect((await ask("https://getmypod.app/", on, "HEAD")).status).toBe(200);
      for (const path of ["/og.png", "/covers/abbey-road-beatles.png", "/paw/open45c-32.png", "/color-silver.png", "/cappy-head-brown.webp"]) {
        expect([path, (await ask(`https://getmypod.app${path}`, on)).status]).toEqual([path, 200]);
      }
      // Still never public under /launch/; unknown paths still 404; "/index.html" goes to "/".
      for (const path of ["/launch", "/launch/", "/launch/index.html", "/launch/og.png", "/nothing.png"]) {
        expect((await ask(`https://getmypod.app${path}`, on)).status, path).toBe(404);
      }
      const old = await ask("https://getmypod.app/index.html?x=1", on);
      expect([old.status, old.headers.get("Location")]).toEqual([302, "/?x=1"]);
      // /beta, its files, the privacy page and the API stay as they are.
      expect((await ask("https://getmypod.app/beta", on)).status).toBe(200);
      expect((await ask("https://getmypod.app/beta/", on)).headers.get("Location")).toBe("/beta");
      expect((await ask("https://getmypod.app/v1/beta", on)).headers.get("Content-Type")).toContain("application/json");
    });
  }
});

describe("launch page files and CSP", () => {
  /** The Content-Security-Policy that public/_headers gives `path`. */
  const policy = (path: string) => {
    const block = headers.split(/\n(?=\S)/).find((b) => b.split("\n")[0].trim() === path);
    return block?.split("\n").find((l) => l.trim().startsWith("Content-Security-Policy:"))?.split("Content-Security-Policy:")[1].trim() ?? "";
  };
  const sources = (csp: string, name: string) => csp.split(";").map((d) => d.trim()).find((d) => d.startsWith(name + " "))?.split(/\s+/).slice(1) ?? [];
  const hash = async (s: string) => `'sha256-${btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))))}'`;

  it("allows each inline script and style by its hash, and the same hosts as the beta page", async () => {
    const csp = launchCSP;
    const beta = policy("/beta");
    for (const s of [...launchHtml.matchAll(/<script>([\s\S]*?)<\/script>/g)]) expect(sources(csp, "script-src")).toContain(await hash(s[1]));
    for (const s of [...launchHtml.matchAll(/<style>([\s\S]*?)<\/style>/g)]) expect(sources(csp, "style-src")).toContain(await hash(s[1]));
    for (const m of launchHtml.matchAll(/<[a-z][^>]*\sstyle="([^"]*)"/g)) expect(sources(csp, "style-src")).toContain(await hash(m[1]));
    expect(launchHtml).not.toMatch(/<script\s[^>]*src=/);  // no outside script tag in the page itself
    const hosts = (c: string, n: string) => sources(c, n).filter((x) => !x.startsWith("'sha256-"));
    for (const name of ["script-src", "connect-src", "frame-src", "img-src", "media-src", "default-src"]) expect(hosts(csp, name), name).toEqual(hosts(beta, name));
    expect(csp).not.toContain("unsafe-inline");
    expect(csp).not.toContain("unsafe-eval");
    expect(csp).not.toContain("itunes.apple.com");  // the page's song lookup stays blocked: no new third party
  });

  it("builds no style attribute from a computed value, and asks no outside host for the song", () => {
    // A hash cannot cover a value made at run time: built markup carries data-st, set through the CSSOM.
    expect(launchHtml).not.toMatch(/\sstyle="[^"]*'\s*\+/);
    expect(launchHtml).toContain("e.style.cssText=e.getAttribute('data-st')");
    expect(launchHtml).not.toMatch(/itunes\.apple\.com|mzstatic\.com|previewUrl/);  // left out until Jason decides
  });

  it("finds every file the page links, in /launch/ or at the root; no privacy copy", () => {
    const links = [...launchHtml.matchAll(/\s(?:href|src|poster)="([^"#][^"]*)"|url\(([^)"':]+)\)/g)].map((m) => m[1] ?? m[2])
      .filter((l) => !/^[a-z]+:/.test(l) && /[./]/.test(l));
    expect(links.length).toBeGreaterThan(5);
    for (const link of links) {
      const path = new URL(link, "https://getmypod.app/").pathname;
      const found = files.has("/launch" + path) || files.has(path) || (path.endsWith("/index.html") && files.has(path));
      expect(found, link).toBe(true);
    }
    expect(files.has("/launch/privacy/index.html")).toBe(false);  // the footer link goes to the frozen /privacy/
    expect(files.has("/launch/og.png")).toBe(true);
  });

  it("keeps every public/_headers line under Cloudflare's 2000-character limit", () => {
    for (const line of headers.split("\n")) expect(line.length).toBeLessThanOrEqual(2000);
  });

  it("keeps run_worker_first the same as workerFirstPaths, and LAUNCH_PAGE only on the test server", () => {
    const config = JSON.parse(wrangler.replace(/^\s*\/\/.*$/gm, "")) as { assets: { run_worker_first: string[] }; vars: Record<string, string>; env: { test: { vars: Record<string, string> } } };
    expect(config.assets.run_worker_first).toEqual(workerFirstPaths);
    expect(config.vars.LAUNCH_PAGE).toBeUndefined();
    expect(config.env.test.vars.LAUNCH_PAGE).toBe("1");
  });
});
