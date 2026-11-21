import { describe, expect, it } from "vitest";
import headers from "../public/_headers?raw";
import page from "../public/index.html?raw";
import privacy from "../public/privacy/index.html?raw";

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
    expect(sources(csp, "connect-src")).toEqual(["https://api.getmypod.app"]);
    expect(sources(csp, "frame-ancestors")).toEqual(["'none'"]);
    expect(csp).not.toContain("unsafe-inline");
    expect(csp).not.toContain("unsafe-eval");
    expect(page).not.toMatch(/<script\s[^>]*>/);  // no external or typed scripts to allow
    const scripts = inline(page, "script");
    expect(scripts.length).toBeGreaterThan(0);
    for (const s of scripts) expect(sources(csp, "script-src")).toContain(await hash(s));
    for (const s of inline(page, "style")) expect(sources(csp, "style-src")).toContain(await hash(s));
    // Style attributes written in the page itself (not built by a script).
    for (const m of page.matchAll(/<[a-z][^>]*\sstyle="([^"]*)"/g)) {
      if (m[1].includes("'+")) continue;  // built at run time by the test slider, which the wiring PR removes
      expect(sources(csp, "style-src")).toContain(await hash(m[1]));
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
