import { handle, sha256, token } from "./activation";
import { countOpen, dropOldInviteMails, inviteOf } from "./invitelinks";
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
    // CLA-172: the test server (wrangler env "test") sends every page and answer with noindex.
    if (env.TEST_SERVER === "1") {
      const path = new URL(request.url).pathname;
      // "/" goes to /beta, and the beta page comes filled (src/page.ts).
      const moved = env.ASSETS ? betaRedirect(request) : null;
      if (env.ASSETS && isBetaPage(request)) countInvite(request, env, later);
      const page = moved ?? (env.ASSETS && isBetaPage(request) ? await betaPage(request, env, env.ASSETS, fetch, later)
        : path.startsWith("/v1/") || !env.ASSETS ? await serve(request, env, later) : await env.ASSETS.fetch(request));
      const marked = new Response(page.body, page);
      marked.headers.set("X-Robots-Tag", "noindex, nofollow");
      return marked;
    }
    // Live: run_worker_first sends "/", "/beta" and "/beta/" here; every other file is served before
    // the Worker, and a path with no file comes here as today. "/" goes to /beta, and the beta page
    // comes filled (src/page.ts).
    if (env.ASSETS) {
      const moved = betaRedirect(request);
      if (moved) return moved;
      if (new URL(request.url).pathname === betaPath) {
        if (!isBetaPage(request)) return env.ASSETS.fetch(request);
        countInvite(request, env, later);
        return betaPage(request, env, env.ASSETS, fetch, later);
      }
    }
    return serve(request, env, later);
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
