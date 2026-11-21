// CLA-172: the beta page comes with its live parts already in it (the button or the form,
// "Beta N", the count and the bar), so the first picture is the final one. The rules and the
// changes are logic.js's, the same ones page.js uses, so the server and the page cannot differ.
import { edits, fill, parseBeta, withState, type Fill } from "../public/beta-page/logic.js";
import { beta, testBuild } from "./beta";

/** How long the page waits for the count. Slower, and the page comes as it is (body.loading) and asks itself. */
export const fillWait = 300;

/** How long the rewrite of the whole page may take before the plain page goes out instead. */
export const rewriteWait = 2000;

/** The page paths the Worker fills. Every other asset goes out as it is. */
export function isBetaPage(request: Request): boolean {
  return request.method === "GET" && new URL(request.url).pathname === "/";
}

/**
 * The beta page, filled. Without an answer in `fillWait` (or with an error) the page goes out as
 * it is, and page.js loads the count as before. Never a 500 for the page.
 */
export async function betaPage(request: Request, env: Env, assets: Fetcher, fetcher: typeof fetch = fetch): Promise<Response> {
  // No conditional request: a 304 would bring back an older copy of the page.
  const plain = new Headers(request.headers);
  plain.delete("If-None-Match");
  plain.delete("If-Modified-Since");
  const asset = () => assets.fetch(new Request(request.url, { method: "GET", headers: plain }));
  const page = await asset();
  if (!page.ok || !(page.headers.get("Content-Type") ?? "").startsWith("text/html")) return page;
  let timer: ReturnType<typeof setTimeout> | null = null;
  const late = new Promise<null>((resolve) => { timer = setTimeout(() => resolve(null), fillWait); });
  const answer = await Promise.race([beta(env.DB, Number(env.CAP), fetcher, Date.now(), testBuild(env)), late]).catch(() => null);
  clearTimeout(timer);
  if (!answer) return page;
  // The rewrite reads the whole page. If it fails or stalls, the first body is used up: send the
  // plain page again. Never a 500, never a hang.
  let stall: ReturnType<typeof setTimeout> | null = null;
  const stalled = new Promise<null>((resolve) => { stall = setTimeout(() => resolve(null), rewriteWait); });
  const out = await Promise.race([filled(page, fill(parseBeta(answer))), stalled]).catch(() => null);
  clearTimeout(stall);
  return out ?? asset();
}

/**
 * The page with one fill written in. Same headers (the CSP), but kept 30 s at most, with no validator.
 * It goes out in one piece with its length, as the plain asset does: a page sent in pieces lets the
 * browser paint the hero half-parsed, and the next frame moves it.
 */
export async function filled(page: Response, f: Fill): Promise<Response> {
  let rewriter = new HTMLRewriter();
  for (const e of edits(f)) {
    rewriter = rewriter.on(e.selector, {
      element(el) {
        if (e.state) el.setAttribute("class", withState(el.getAttribute("class") ?? "", e.state));
        else if (e.attr) e.value == null ? el.removeAttribute(e.attr) : el.setAttribute(e.attr, e.value);
        else if (e.html !== undefined) el.setInnerContent(e.html, { html: true });
        else if (e.text !== undefined) el.setInnerContent(e.text);
      },
    });
  }
  const out = rewriter.transform(page);
  const body = await out.arrayBuffer();
  const answer = new Response(body, out);
  answer.headers.set("Cache-Control", "max-age=30");
  answer.headers.set("Content-Length", String(body.byteLength));
  answer.headers.delete("ETag");
  answer.headers.delete("Last-Modified");
  return answer;
}
