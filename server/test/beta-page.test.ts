import { describe, expect, it, vi } from "vitest";
import headers from "../public/_headers?raw";
import page from "../public/index.html?raw";
import privacy from "../public/privacy/index.html?raw";
import redirects from "../public/_redirects?raw";
import { apiBase, dmgURL, edits, fill, formLine, formPath, formState, loadingFill, parseBeta, siteKey, withState, votedFrom, voteItems, voteKept, voteState, withLimit, withVote } from "../public/beta-page/logic.js";

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
    // The only scripts with a source: Turnstile and the page's own module.
    expect([...page.matchAll(/<script\s[^>]*>/g)].map((m) => m[0])).toEqual([
      '<script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer>',
      '<script type="module" src="beta-page/page.js">',
    ]);
    const scripts = inline(page, "script");
    expect(scripts.length).toBeGreaterThan(0);
    for (const s of scripts) expect(sources(csp, "script-src")).toContain(await hash(s));
    for (const s of inline(page, "style")) expect(sources(csp, "style-src")).toContain(await hash(s));
    // Style attributes written in the page itself (not built by a script).
    for (const m of page.matchAll(/<[a-z][^>]*\sstyle="([^"]*)"/g)) {
      expect(sources(csp, "style-src")).toContain(await hash(m[1]));
    }
  });

  const sha256 = async (s: string) =>
    [...new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)))].map((b) => b.toString(16).padStart(2, "0")).join("");

  it("keeps the privacy page byte for byte as frozen, except the canonical line and root paths", async () => {
    // Jason's rule: the privacy words are frozen; any change needs his approval first.
    // This is the SHA-256 of design-review/beta-page/simple-frozen/privacy/index.html. The frozen
    // file links the icons with "../"; the site uses root paths (/favicon.ico etc.).
    const frozen = privacy
      .replace('<link rel="canonical" href="https://getmypod.app/privacy/">\n', "")
      .replace(/="\/(favicon\.ico|favicon-32\.png|apple-touch-icon\.png)"/g, '="../$1"');
    expect(await sha256(frozen)).toBe("ce6d5fff31fcc7ab655194375b2f6528ca5979aaf6d77d16c8735ff7acfc4c9a");
  });

  it("keeps the privacy page's visible words as Jason approved them", async () => {
    const words = privacy.replace(/<style[\s\S]*?<\/style>/g, "").replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
    expect(await sha256(words)).toBe("6be52273feed4b2b7fdb04a2865dbfd5db0d6bd0c4a0e11f4509edece664a916");
  });

  it("shows only the name top left and links the icons from the root on both pages", () => {
    for (const html of [page, privacy]) {
      expect(html).toMatch(/class="brand"[^>]*>myPod <span>BETA<\/span>/);
      expect(html).not.toContain("mypod-wheel");
      expect(html).toContain('<link rel="icon" href="/favicon.ico" sizes="any">');
      expect(html).toContain('<link rel="icon" type="image/png" sizes="32x32" href="/favicon-32.png">');
      expect(html).toContain('<link rel="apple-touch-icon" href="/apple-touch-icon.png">');
      expect(html).not.toContain("cappy-head");
    }
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
    const bar = (w: string) => `<rect width="${w}" height="8" rx="4" fill="url(#bf)"/>`;
    // Open: the button with its link, "Beta N", the count and the bar (or "Limited to" under 8).
    const open = fill(parseBeta(live));
    expect(open).toMatchObject({ state: "open", kind: "link", download: live.url, version: "Beta 400", spotsClass: "spots" });
    expect(open.spots).toContain("<p><b>12 of 25</b> beta spots taken</p>");
    expect(open.spots).toContain(bar("48%"));
    expect(fill(parseBeta({ ...live, taken: 3 }))).toMatchObject({ state: "open", download: live.url, spots: "<p><b>Limited to 25 testers.</b></p>" });
    expect(fill(parseBeta({ ...live, taken: 8 })).spots).toContain(bar("32%"));
    expect(fill(parseBeta({ ...live, taken: 1, cap: 3 })).spots).toBe("<p><b>Limited to 3 testers.</b></p>");
    // Full: the waitlist on every screen, no link, no version.
    const full = fill(parseBeta({ ...live, taken: 25, full: true }));
    expect(full).toMatchObject({ state: "full", kind: "waitlist", download: null, version: "", spotsClass: "spots full" });
    expect(full.spots).toContain(bar("100%"));
    expect(fill(parseBeta({ ...live, taken: 25, build: null, url: null }))).toMatchObject({ state: "full", kind: "waitlist" });
    // No build or url: the count stays, then "on its way": no link, no version.
    expect(fill(parseBeta({ ...live, build: null, url: null }))).toMatchObject({ state: "soon", download: null, version: "" });
    // No answer: "Limited to 25 testers.", then the same line.
    expect(fill(null)).toMatchObject({ state: "soon", download: null, version: "", spots: "<p><b>Limited to 25 testers.</b></p>" });
  });

  it("makes the same changes for the server and the page", () => {
    const f = fill(parseBeta(live));
    expect(edits(f)).toEqual([
      { selector: "body", state: "open" },
      { selector: ".row > a.cta", attr: "href", value: live.url },
      { selector: ".row > .bver b", text: "Beta 400" },
      { selector: "#wl button", text: "Email me the link" },
      { selector: "#wl .ok", text: "Sent. Open it on your Mac." },
      { selector: "#spots", attr: "class", value: "spots" },
      { selector: "#spots", html: f.spots },
    ]);
    expect(edits(fill(parseBeta({ ...live, taken: 25 })))[3]).toEqual({ selector: "#wl button", text: "Save me a spot" });
    expect(withState("one hm loading", "open")).toBe("one hm open");
    expect(withState("one hm open full", "soon")).toBe("one hm soon");
  });
});

describe("beta page forms (CLA-172)", () => {
  it("shows one state for each answer, and no answer is offline", () => {
    for (const r of ["ok", "busy", "bot", "bad"]) expect(formState({ result: r })).toBe(r);
    for (const bad of [null, undefined, "ok", {}, { result: "full" }, { error: "x" }]) expect(formState(bad)).toBe("offline");
    expect(formLine("ok", "waitlist")).toBe("You’re on the list. We’ll write to you.");
    expect(formLine("ok", "link")).toBe("Sent. Open it on your Mac.");
    const lines = new Set((["busy", "bot", "bad", "offline"] as const).map((st) => formLine(st, "link")));
    expect(lines.size).toBe(4);
    expect(formPath).toEqual({ waitlist: "/v1/waitlist", link: "/v1/link" });
  });

  it("uses the real API and Turnstile key only on getmypod.app", () => {
    expect(apiBase("getmypod.app")).toBe("https://api.getmypod.app");
    expect(siteKey("getmypod.app")).toBe("0x4AAAAAAGIRWYxmCoZOyxc0");
    for (const host of ["www.getmypod.app", "localhost", "example.workers.dev", "getmypod.app.evil.com"]) {
      expect(apiBase(host)).toBe("");  // the page's own origin
      expect(siteKey(host)).toBe("1x00000000000000000000AA");  // Cloudflare's always-pass test key
    }
  });

  it("keeps one vote per item per browser, for the five items only", () => {
    expect(Object.values(voteItems)).toEqual(["local-music", "nano", "radio", "like-from-wheel", "more-colors"]);
    for (const title of Object.keys(voteItems)) expect(page).toContain(`<h3>${title}</h3>`);
    expect([...page.matchAll(/<button class="vb[^"]*" type="button">/g)]).toHaveLength(5);
    expect(page).toContain('<a class="vb" href="mailto:feedback@getmypod.app?subject=myPod%20idea">Send an idea</a>');
    expect([...votedFrom(null)]).toEqual([]);
    expect([...votedFrom("not json")]).toEqual([]);
    expect([...votedFrom('{"nano":1}')]).toEqual([]);
    expect([...votedFrom('["nano","x","radio",3]')]).toEqual(["nano", "radio"]);
    expect(withVote(null, "nano")).toBe('["nano"]');
    expect(withVote('["radio","nano"]', "nano")).toBe('["nano","radio"]');
    expect(voteState({ result: "ok" })).toBe("ok");
    expect(voteState({ result: "busy" })).toBe("busy");
    expect(voteState({ result: "bad" })).toBe("bad");
    for (const a of [null, {}, { result: "bot" }, "ok"]) expect(voteState(a)).toBe("offline");
    // "busy" = this network already voted for this item today: the vote stays on.
    expect(voteKept("ok")).toBe(true);
    expect(voteKept("busy")).toBe(true);
    expect(voteKept("bad")).toBe(false);
    expect(voteKept("offline")).toBe(false);
  });

  it("stops waiting for the bot check after the limit, so the button works again", async () => {
    vi.useFakeTimers();
    try {
      const never = withLimit(new Promise<string>(() => {}), 60_000, null);
      vi.advanceTimersByTime(59_999);
      let done = false;
      void never.then(() => { done = true; });
      await Promise.resolve();
      expect(done).toBe(false);
      vi.advanceTimersByTime(1);
      expect(await never).toBeNull();
    } finally {
      vi.useRealTimers();
    }
    expect(await withLimit(Promise.resolve("tok"), 60_000, null)).toBe("tok");
    expect(await withLimit(Promise.reject(new Error("x")), 60_000, null)).toBeNull();
  });

  it("is the loading fill as it stands, so the first draw changes nothing", () => {
    const f = loadingFill();
    expect(f).toMatchObject({ state: "loading", kind: "link", download: null, version: "Beta" });
    expect(page).toContain('<body class="one hm loading">');
    expect(page).toContain(`<div id="spots" class="${f.spotsClass}">${f.spots}</div>`);
    expect(page).toContain('<a class="cta"><svg');  // no link before an answer
    expect(page).toContain('<p class="bver"><b>Beta</b>');
    expect(page).toContain('<button class="cta" type="submit">Email me the link</button><p class="ok">Sent. Open it on your Mac.</p>');
  });

  it("sends the app's fallback download page /beta to the beta page", () => {
    const rules = redirects.split("\n").filter((l) => l.trim() && !l.startsWith("#")).map((l) => l.trim().split(/\s+/));
    expect(rules).toEqual([["/beta", "/", "302"], ["/beta/", "/", "302"]]);
  });
});
