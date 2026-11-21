import { describe, expect, it, vi } from "vitest";
import headers from "../public/_headers?raw";
import page from "../public/index.html?raw";
import privacy from "../public/privacy/index.html?raw";
import { apiBase, dmgURL, formLine, formPath, formState, loadingView, parseBeta, siteKey, view, votedFrom, voteItems, voteKept, voteState, withLimit, withVote } from "../public/beta-page/logic.js";

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
    expect(view(parseBeta({ ...live, taken: 3 }), false)).toEqual({ loading: false, full: false, soon: false, form: "none", download: live.url, version: "Beta 400",
      spots: { kind: "limited", taken: 3, cap: 25, width: 0 } });
    expect(view(parseBeta(live), false)).toEqual({ loading: false, full: false, soon: false, form: "none", download: live.url, version: "Beta 400",
      spots: { kind: "bar", taken: 12, cap: 25, width: 48 } });
    expect(view(parseBeta(live), true)).toEqual({ loading: false, full: false, soon: false, form: "link", download: null, version: "Beta 400",
      spots: { kind: "bar", taken: 12, cap: 25, width: 48 } });
    expect(view(parseBeta({ ...live, taken: 25, full: true }), false)).toEqual({ loading: false, full: true, soon: false, form: "waitlist", download: null, version: null,
      spots: { kind: "full", taken: 25, cap: 25, width: 100 } });
    // No build or url: the count stays, then "on its way", with no button, no form and no version.
    for (const phone of [false, true]) {
      expect(view(parseBeta({ ...live, build: null, url: null }), phone)).toEqual({ loading: false, full: false, soon: true, form: "none", download: null, version: null,
        spots: { kind: "bar", taken: 12, cap: 25, width: 48 } });
      // No answer: "Limited to 25 testers.", then the same line.
      expect(view(null, phone)).toEqual({ loading: false, full: false, soon: true, form: "none", download: null, version: null, spots: { kind: "limited", taken: 0, cap: 25, width: 0 } });
    }
    // Full with no build: the waitlist still works.
    expect(view(parseBeta({ ...live, taken: 25, build: null, url: null }), true)).toMatchObject({ full: true, soon: false, form: "waitlist" });
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

  it("waits for the answer with the open state drawn invisible, with no link", () => {
    // Desktop: the button row and the count with its bar, at their final size; no href.
    expect(loadingView(false)).toEqual({ loading: true, full: false, soon: false, form: "none", download: null, version: "Beta",
      spots: { kind: "bar", taken: 0, cap: 25, width: 0 } });
    // Phone: the link form in place of the button.
    expect(loadingView(true)).toMatchObject({ loading: true, form: "link", download: null });
    // Every answer ends the wait.
    for (const phone of [false, true]) {
      expect(view(null, phone).loading).toBe(false);
      expect(view(parseBeta({ taken: 12, cap: 25, full: false, build: 400, url: "https://dl.getmypod.app/beta/a.dmg" }), phone).loading).toBe(false);
    }
    // The static page starts in the wait, and its count row is already there (no jump on the first draw).
    expect(page).toContain('<body class="one hm loading">');
    expect(page).toContain('<div id="spots" class="spots"><p><b>0 of 25</b> beta spots taken</p><div class="bar"><i></i></div></div>');
  });
});
