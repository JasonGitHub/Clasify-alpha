// CLA-175: the launch page for "/". Its files are in public/launch/ and are never public under
// /launch/. Only where LAUNCH_PAGE is "1" (the test server, until Jason says go live) does "/" serve
// it, and do its own files answer at the root paths the page asks for (covers/, paw/, og.png...).
// Without the switch, everything stays as before: "/" goes to /beta, and those paths are 404.
import { launchScripts, launchStyles } from "./launch-hashes";

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

/** The page as the static files have it, with its CSP and the beta page's other page headers. */
async function launchPage(request: Request, assets: Fetcher, url: URL): Promise<Response> {
  const file = await assets.fetch(new Request(new URL(launchDir + "/" + url.search, url), request));
  if (!file.ok) return file;
  const page = new Response(file.body, file);
  page.headers.set("Content-Security-Policy", launchCSP);
  page.headers.set("Referrer-Policy", "no-referrer");
  page.headers.set("X-Content-Type-Options", "nosniff");
  page.headers.set("Cache-Control", "no-cache");
  return page;
}

const notFound = () => new Response("not found", { status: 404 });

/**
 * The launch page's part of routing, or null when it is not its business. Paths with a file at the
 * root never come here (the static files come first); the page's own files are only in /launch/.
 */
export async function launchRoute(request: Request, env: Env, assets: Fetcher): Promise<Response | null> {
  const url = new URL(request.url);
  const path = url.pathname;
  // Never public under its own folder, with or without the switch.
  if (path === launchDir || path.startsWith(launchDir + "/")) return notFound();
  if (!launchOn(env) || (request.method !== "GET" && request.method !== "HEAD")) return null;
  if (path === "/") return launchPage(request, assets, url);
  if (path === "/index.html") return new Response(null, { status: 302, headers: { Location: "/" + url.search, "Cache-Control": "no-store" } });
  if (path.startsWith("/v1/")) return null;
  // A file of the launch page, at the root path the page uses. No file there: not ours.
  const file = await assets.fetch(new Request(new URL(launchDir + path, url), request));
  return file.status === 404 ? null : file;
}
