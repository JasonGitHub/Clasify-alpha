// CLA-175: the launch page for "/". Its files are in public/launch/ and are never public under
// /launch/. Only where LAUNCH_PAGE is "1" (the test server, until Jason says go live) does "/" serve
// it, and do its own files answer at the root paths the page asks for (covers/, paw/, og.png...).
// Without the switch, everything stays as before: "/" goes to /beta, and those paths are 404.
import { parseBeta } from "../public/beta-page/logic.js";
import { downloadHref, downloadSelector } from "../public/launch-page/logic.js";
import { beta, testBuild } from "./beta";
import { launchScripts, launchStyles } from "./launch-hashes";
import { fillWait } from "./page";

/** The switch. Only "1" turns the launch page on. */
export function launchOn(env: Env): boolean {
  return env.LAUNCH_PAGE === "1";
}

/** The paths that run the Worker before the static files on live: run_worker_first in wrangler.jsonc. */
export const workerFirstPaths = ["/", "/beta", "/beta/", "/launch", "/launch/*"];

export function workerFirst(path: string): boolean {
  return workerFirstPaths.some((p) => p.endsWith("/*") ? path.startsWith(p.slice(0, -1)) : path === p);
}

/** Where the launch page's files are. */
export const launchDir = "/launch";

/**
 * The page's CSP: the beta page's hosts, and its inline scripts and styles by hash only. The Worker
 * sends it, not public/_headers: with all the style hashes the line is too long for that file.
 * After a new index.html: node scripts/csp-hashes.mjs (writes src/launch-hashes.ts).
 */
export const launchCSP = [
  "default-src 'none'",
  `script-src 'self' https://challenges.cloudflare.com https://static.cloudflareinsights.com ${launchScripts.join(" ")}`,
  "frame-src https://challenges.cloudflare.com",
  "connect-src 'self' https://api.getmypod.app https://cloudflareinsights.com",
  `style-src 'self' 'unsafe-hashes' ${launchStyles.join(" ")}`,
  "img-src 'self' data:",
  "media-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

/**
 * The wiring the Worker adds to the design: wire.js and its few styles (wire.css). wire.js loads the
 * bot check (as on the beta page) only when the form is sent.
 */
export const launchWiring = '<link rel="stylesheet" href="/launch-page/wire.css"><script type="module" src="/launch-page/wire.js"></script>';

/** The beta answer (the newest build and the seats) within `fillWait`, or null. */
async function betaNow(env: Env, fetcher: typeof fetch, later?: (work: Promise<unknown>) => void) {
  let timer: ReturnType<typeof setTimeout> | null = null;
  const late = new Promise<null>((resolve) => { timer = setTimeout(() => resolve(null), fillWait); });
  const answer = await Promise.race([beta(env.DB, Number(env.CAP), fetcher, Date.now(), testBuild(env), later), late]).catch(() => null);
  clearTimeout(timer);
  return answer ? parseBeta(answer) : null;
}

/**
 * A page file from /launch/, changed by `rewriter` (GET only), with its CSP and the beta page's other
 * page headers. Sent in one piece with its length, like the beta page, so nothing moves after the
 * first paint.
 */
async function servePage(request: Request, file: Response, rewriter: HTMLRewriter, csp: string, cache: string): Promise<Response> {
  if (!file.ok) return file;
  const out = request.method === "GET" ? rewriter.transform(file) : file;
  const body = request.method === "GET" ? await out.arrayBuffer() : null;
  const page = new Response(body, out);
  page.headers.set("Content-Security-Policy", csp);
  page.headers.set("Referrer-Policy", "no-referrer");
  page.headers.set("X-Content-Type-Options", "nosniff");
  page.headers.set("Cache-Control", cache);
  if (body) page.headers.set("Content-Length", String(body.byteLength));
  page.headers.delete("ETag");
  page.headers.delete("Last-Modified");
  return page;
}

/**
 * The launch page with the wiring. "Try it first" comes with the current build when the beta
 * answer is there within `fillWait` (else wire.js fills it).
 */
async function launchPage(request: Request, env: Env, assets: Fetcher, url: URL, fetcher: typeof fetch,
  later?: (work: Promise<unknown>) => void): Promise<Response> {
  const file = await assets.fetch(new Request(new URL(launchDir + "/" + url.search, url), request));
  const href = file.ok && request.method === "GET" ? downloadHref((await betaNow(env, fetcher, later)) ?? undefined) : null;
  let rewriter = new HTMLRewriter().on("body", { element(el) { el.append(launchWiring, { html: true }); } });
  if (href) rewriter = rewriter.on(downloadSelector, { element(el) { el.setAttribute("href", href); } });
  return servePage(request, file, rewriter, launchCSP, href ? "max-age=30" : "no-cache");
}

/** Where Stripe sends the buyer back (src/stripe.ts success_url). The file is launch/thanks.html. */
export const thanksPath = "/thanks";

/**
 * The "thank you" page's CSP: its own files only (no inline script or style), and our API. No other
 * host: the page asks only our server, never Stripe.
 */
export const thanksCSP = [
  "default-src 'none'",
  "script-src 'self'",
  "connect-src 'self' https://api.getmypod.app",
  "style-src 'self'",
  "img-src 'self'",
  "base-uri 'none'",
  "form-action 'none'",
  "frame-ancestors 'none'",
].join("; ");

/**
 * The "thank you" page (card CM), with the Mac count of a purchase (PAID_MACS) and "Download for Mac"
 * set to the newest build, also when the beta is full: a buyer needs no seat. Never cached: the
 * address holds the payment's session ID.
 */
async function thanksPage(request: Request, env: Env, assets: Fetcher, url: URL, fetcher: typeof fetch,
  later?: (work: Promise<unknown>) => void): Promise<Response> {
  const file = await assets.fetch(new Request(new URL(launchDir + "/thanks", url), request));
  const dmg = file.ok && request.method === "GET" ? (await betaNow(env, fetcher, later))?.url ?? null : null;
  const macs = /^[1-9]$/.test(env.PAID_MACS) ? env.PAID_MACS : "3";
  let rewriter = new HTMLRewriter().on("[data-macs]", { element(el) { el.setInnerContent(macs); } });
  if (dmg) rewriter = rewriter.on("a[data-dl]", { element(el) { el.setAttribute("href", dmg); } });
  return servePage(request, file, rewriter, thanksCSP, "no-store");
}

const notFound = () => new Response("not found", { status: 404 });

/**
 * The launch page's part of routing, or null when it is not its business. Paths with a file at the
 * root never come here (the static files come first); the page's own files are only in /launch/.
 */
export async function launchRoute(request: Request, env: Env, assets: Fetcher, fetcher: typeof fetch = fetch,
  later?: (work: Promise<unknown>) => void): Promise<Response | null> {
  const url = new URL(request.url);
  const path = url.pathname;
  // Never public under its own folder, with or without the switch.
  if (path === launchDir || path.startsWith(launchDir + "/")) return notFound();
  if (!launchOn(env) || (request.method !== "GET" && request.method !== "HEAD")) return null;
  if (path === "/") return launchPage(request, env, assets, url, fetcher, later);
  if (path === thanksPath) return thanksPage(request, env, assets, url, fetcher, later);
  if (path.startsWith(thanksPath)) return notFound();  // /thanks.html, /thanks/: never the unfilled file
  if (path === "/index.html") return new Response(null, { status: 302, headers: { Location: "/" + url.search, "Cache-Control": "no-store" } });
  if (path.startsWith("/v1/")) return null;
  // A file of the launch page, at the root path the page uses. No file there: not ours.
  const file = await assets.fetch(new Request(new URL(launchDir + path, url), request));
  return file.status === 404 ? null : file;
}
