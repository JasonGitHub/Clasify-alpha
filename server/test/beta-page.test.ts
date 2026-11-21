import { describe, expect, it } from "vitest";
import headers from "../public/_headers?raw";
import page from "../public/index.html?raw";
import privacy from "../public/privacy/index.html?raw";
import { dmgURL, parseBeta, view } from "../public/beta-page/logic.js";

/** The Content-Security-Policy that public/_headers gives `path`. */
function policy(path: string): string {
  const blocks = headers.split(/\n(?=\S)/);
  const block = blocks.find((b) => b.split("\n")[0].trim() === path);
  const line = block?.split("\n").find((l) => l.trim().startsWith("Content-Security-Policy:"));
  return line?.split("Content-Security-Policy:")[1].trim() ?? "";
}

async function hash(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return `'sha256-${btoa(String.fromCharCode(...new Uint8Array(digest)))}'`;
}

/** One directive's sources, such as `script-src`. */
function sources(csp: string, name: string): string[] {
  const directive = csp.split(";").map((d) => d.trim()).find((d) => d.startsWith(name + " "));
  return directive?.split(/\s+/).slice(1) ?? [];
}

const inline = (html: string, tag: string) => [...html.matchAll(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, "g"))].map((m) => m[1]);

describe("beta page CSP (CLA-172)", () => {
  it("allows each inline script and style of the page by its hash, and nothing else inline", async () => {
    const csp = policy("/");
    expect(csp).toContain("default-src 'none'");
    expect(sources(csp, "connect-src")).toEqual(["'self'", "https://api.getmypod.app"]);  // 'self': a test address
    expect(sources(csp, "frame-ancestors")).toEqual(["'none'"]);
    expect(csp).not.toContain("unsafe-inline");
    expect(csp).not.toContain("unsafe-eval");
    // The only script with a source is the page's own module; no other host.
    expect([...page.matchAll(/<script\s[^>]*>/g)].map((m) => m[0])).toEqual(['<script type="module" src="beta-page/page.js">']);
    const scripts = inline(page, "script");
    expect(scripts.length).toBeGreaterThan(0);
    for (const s of scripts) expect(sources(csp, "script-src")).toContain(await hash(s));
    for (const s of inline(page, "style")) expect(sources(csp, "style-src")).toContain(await hash(s));
    // Style attributes written in the page itself (not built by a script).
    for (const m of page.matchAll(/<[a-z][^>]*\sstyle="([^"]*)"/g)) {
      expect(sources(csp, "style-src")).toContain(await hash(m[1]));
    }
  });

  it("keeps the privacy page byte for byte as frozen, except the canonical line", async () => {
    // Jason's rule: the privacy words are frozen; any change needs his approval first.
    // This is the SHA-256 of design-review/beta-page/simple-frozen/privacy/index.html.
    const frozen = privacy.replace('<link rel="canonical" href="https://getmypod.app/privacy/">\n', "");
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(frozen));
    expect([...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join(""))
      .toBe("13b133dbe4647b71e871fc33f8f150e1eef6585251275550616ee6d0ba264b86");
  });

  it("allows the privacy page's inline style by its hash, and no script", async () => {
    const csp = policy("/privacy/*");
    expect(sources(csp, "script-src")).toEqual([]);
    for (const s of inline(privacy, "style")) expect(sources(csp, "style-src")).toContain(await hash(s));
    expect(privacy).not.toContain("<script");
  });

  it("keeps the activation page's policy as it was", () => {
    expect(policy("/activate/*")).toContain("style-src 'self';");
  });
});

describe("beta page live parts (CLA-172)", () => {
  const live = { taken: 12, cap: 25, full: false, build: 400, url: "https://dl.getmypod.app/beta/myPod-beta-400.dmg" };

  it("has no test slider and loads its live parts from one module", () => {
    expect(page).not.toContain("tslide");
    expect(page).not.toContain("URLSearchParams");
    expect(page).toContain('<script type="module" src="beta-page/page.js"></script>');
    expect(page).toContain('<link rel="canonical" href="https://getmypod.app/">');
    expect(privacy).toContain('<link rel="canonical" href="https://getmypod.app/privacy/">');
  });

  it("keeps the DMG link only on https://dl.getmypod.app", () => {
    expect(dmgURL(live.url)).toBe(live.url);
    for (const bad of [null, 3, "", "nope", "https://dl.getmypod.app/", "http://dl.getmypod.app/beta/a.dmg",
      "https://dl.getmypod.app.evil.com/beta/a.dmg", "https://evil.com/beta/a.dmg", "https://x@dl.getmypod.app/beta/a.dmg",
      "https://dl.getmypod.app:8443/beta/a.dmg", "javascript:alert(1)"]) {
      expect(dmgURL(bad)).toBeNull();
    }
  });

  it("reads the answer, and refuses a bad one", () => {
    expect(parseBeta(live)).toEqual(live);
    expect(parseBeta({ ...live, url: null })).toEqual({ ...live, build: null, url: null });  // no link: no version either
    expect(parseBeta({ ...live, build: null })).toEqual({ ...live, build: null, url: null });
    expect(parseBeta({ ...live, url: "https://evil.com/a.dmg" })).toEqual({ ...live, build: null, url: null });
    expect(parseBeta({ ...live, taken: 25, full: false })?.full).toBe(true);
    for (const bad of [null, "x", {}, { ...live, taken: -1 }, { ...live, cap: 0 }, { ...live, taken: "3" }]) expect(parseBeta(bad)).toBeNull();
  });

  it("shows the count, the bar, the button and the version for each answer", () => {
    expect(view(parseBeta({ ...live, taken: 3 }), false)).toEqual({ full: false, soon: false, form: "none", download: live.url, version: "Beta 400",
      spots: { kind: "limited", taken: 3, cap: 25, width: 0 } });
    expect(view(parseBeta(live), false)).toEqual({ full: false, soon: false, form: "none", download: live.url, version: "Beta 400",
      spots: { kind: "bar", taken: 12, cap: 25, width: 48 } });
    expect(view(parseBeta(live), true)).toEqual({ full: false, soon: false, form: "link", download: null, version: "Beta 400",
      spots: { kind: "bar", taken: 12, cap: 25, width: 48 } });
    expect(view(parseBeta({ ...live, taken: 25, full: true }), false)).toEqual({ full: true, soon: false, form: "waitlist", download: null, version: null,
      spots: { kind: "full", taken: 25, cap: 25, width: 100 } });
    // No build or url: the count stays, then "on its way", with no button, no form and no version.
    for (const phone of [false, true]) {
      expect(view(parseBeta({ ...live, build: null, url: null }), phone)).toEqual({ full: false, soon: true, form: "none", download: null, version: null,
        spots: { kind: "bar", taken: 12, cap: 25, width: 48 } });
      // No answer: "Limited to 25 testers.", then the same line.
      expect(view(null, phone)).toEqual({ full: false, soon: true, form: "none", download: null, version: null, spots: { kind: "limited", taken: 0, cap: 25, width: 0 } });
    }
    // Full with no build: the waitlist still works.
    expect(view(parseBeta({ ...live, taken: 25, build: null, url: null }), true)).toMatchObject({ full: true, soon: false, form: "waitlist" });
  });
});
