import { handle, sha256, token } from "./activation";
import { countOpen, dropOldInviteMails, inviteOf } from "./invitelinks";
import { launchRoute, workerFirst } from "./launch";
import { countLinkOpen, linkOf, linkRedirect } from "./links";
import { linkMailer, noMail, noReports, reportMailer, resend } from "./mailer";
import { noPageMail, pageMailer, type PageMailer } from "./pagemail";
import { refreshFeed } from "./beta";
import { betaPage, betaPath, betaRedirect, isBetaPage } from "./page";
import { openSpots } from "./spots";
import { paidMailer } from "./paidmail";
import { dropOldEvents, noPaidMail, stripeHook, type PaidMailer } from "./stripehook";
import { turnstile } from "./turnstile";

export default {
  async fetch(request: Request, env: Env, ctx?: ExecutionContext) {
    // Work after the answer, such as the beta feed's refresh (src/beta.ts).
    const later = ctx ? (work: Promise<unknown>) => ctx.waitUntil(work.catch(() => null)) : undefined;
    // CLA-172: the test server (wrangler env "test") runs the Worker first for every path, and sends
    // every page and answer with noindex.
    if (env.TEST_SERVER === "1") {
      const answer = await site(request, env, later, true);
      const marked = new Response(answer.body, answer);
      marked.headers.set("X-Robots-Tag", "noindex, nofollow");
      return marked;
    }
    return site(request, env, later, false);
  },
  // CLA-172: once an hour, open beta spots go to the oldest waitlist people by mail, the kept beta
  // feed is read again (a page visit also does that when it is older than 2 minutes), and invite ids
  // from "Email me the link" older than 30 days go.
  async scheduled(_controller: ScheduledController, env: Env) {
    await dropOldInviteMails(env.DB, Date.now());  // first: it never throws, and a failure below cannot skip it
    await dropOldEvents(env.DB, Date.now());  // never throws either
    await openSpots(env.DB, Number(env.CAP), pageMailFor(env, Date.now), Date.now());
    await refreshFeed(env.DB, fetch, Date.now()).catch(() => null);
  },
} satisfies ExportedHandler<Env>;

/**
 * The site and the API. Live: the static files are served before the Worker, except the paths in
 * run_worker_first (`workerFirst`); a path with no file comes here. The test server sends every path
 * here (`everyPath`), so the files come first in the same way. Then the launch page (CLA-175, only
 * with LAUNCH_PAGE "1"), "/" to /beta, the filled beta page (src/page.ts), and the API.
 */
async function site(request: Request, env: Env, later: ((work: Promise<unknown>) => void) | undefined, everyPath: boolean): Promise<Response> {
  if (!env.ASSETS) return serve(request, env, later);
  const path = new URL(request.url).pathname;
  const file = everyPath && !path.startsWith("/v1/") && !workerFirst(path) ? await env.ASSETS.fetch(request) : null;
  if (file && file.status !== 404) return file;
  // CLA-193: a short link (/hn, /r/<name>) counts once, after the answer, and goes to /beta.
  const link = request.method === "GET" || request.method === "HEAD" ? linkOf(request) : null;
  if (link) {
    if (request.method === "GET" && later) later(countLinkOpen(env.DB, link, request.headers.get("CF-Connecting-IP") ?? "", Date.now(), sha256, token));
    return linkRedirect(link);
  }
  const launch = await launchRoute(request, env, env.ASSETS, fetch, later);
  if (launch) {
    if (path === "/" && launch.ok && request.method === "GET") countInvite(request, env, later);  // CLA-175: invite links on "/" too
    return launch;
  }
  const moved = betaRedirect(request);
  if (moved) return moved;
  if (path === betaPath) {
    if (!isBetaPage(request)) return env.ASSETS.fetch(request);
    countInvite(request, env, later);
    return betaPage(request, env, env.ASSETS, fetch, later);
  }
  return file ?? serve(request, env, later);
}

/**
 * CLA-172: a page open with ?invite=<id> counts once for that id (src/invitelinks.ts). It runs after
 * the answer, so the page never waits for it, and an error is dropped.
 */
function countInvite(request: Request, env: Env, later?: (work: Promise<unknown>) => void) {
  const id = inviteOf(request.url);
  if (id && later) later(countOpen(env.DB, id, request.headers.get("CF-Connecting-IP") ?? "", Date.now(), sha256, token));
}

function serve(request: Request, env: Env, later?: (work: Promise<unknown>) => void): Promise<Response> {
  const now = Date.now;
  // CLA-175: Stripe's messages need the exact bytes, so they go here before any body is read.
  if (request.method === "POST" && new URL(request.url).pathname === "/v1/stripe") {
    const send = env.RESEND_KEY ? resend(env.RESEND_KEY) : null;
    return stripeHook(request, env, { now, newID: token, paidMail: paidMailFor(env, now), alert: send, alertTo: env.ALERT_TO });
  }
  // Until Jason adds the RESEND_KEY secret, nothing is sent and people see "Mail is busy".
  const mailer = env.RESEND_KEY ? linkMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), env.ALERT_TO, now) : noMail;
  // CLA-166: problem reports share the link mails' day count.
  const reports = env.RESEND_KEY ? reportMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), now) : noReports;
  // Until Jason adds the TURNSTILE_SECRET secret, every page start is refused as a bot.
  return handle(request, env, { now, mailer, reports, pageMail: pageMailFor(env, now), human: turnstile(env.TURNSTILE_SECRET, botCheckHost(env)), later });
}

/**
 * CLA-172: the beta page's mails share the day count of all mails and stop 40 before its end.
 * With no RESEND_KEY they are "busy", except on the test server: there a mail goes nowhere, but
 * answers "sent" and counts against the same limits, so every page state can be tested.
 */
export function pageMailFor(env: Env, now: () => number): PageMailer {
  if (env.RESEND_KEY) return pageMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), now);
  return env.TEST_SERVER === "1" ? pageMailer(env.DB, async () => true, Number(env.MAIL_DAY), now) : noPageMail;
}

/**
 * CLA-175: the "myPod is yours" mail shares the page mails' day count. With no RESEND_KEY it is
 * "busy", except on the test server: there it goes nowhere and answers "sent", as page mails do.
 */
function paidMailFor(env: Env, now: () => number): PaidMailer {
  const send = env.RESEND_KEY ? resend(env.RESEND_KEY) : env.TEST_SERVER === "1" ? async () => true : null;
  return send ? paidMailer(env.DB, send, Number(env.MAIL_DAY), Number(env.PAID_MACS), now) : noPaidMail;
}

/**
 * The host that the bot check's answer must name: PAGE_ORIGIN's. CLA-172: only the test server
 * (TEST_SERVER "1") may name another with TURNSTILE_HOST, for the test key's answers. The live
 * Worker ignores TURNSTILE_HOST.
 */
export function botCheckHost(env: Env): string {
  if (env.TEST_SERVER === "1" && env.TURNSTILE_HOST) return env.TURNSTILE_HOST;
  return new URL(env.PAGE_ORIGIN || "https://getmypod.app").hostname;
}
