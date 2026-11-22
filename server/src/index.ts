import { handle } from "./activation";
import { linkMailer, noMail, noReports, reportMailer, resend } from "./mailer";
import { noPageMail, pageMailer, type PageMailer } from "./pagemail";
import { refreshFeed } from "./beta";
import { betaPage, isBetaPage } from "./page";
import { openSpots } from "./spots";
import { turnstile } from "./turnstile";

export default {
  async fetch(request: Request, env: Env, ctx?: ExecutionContext) {
    // Work after the answer, such as the beta feed's refresh (src/beta.ts).
    const later = ctx ? (work: Promise<unknown>) => ctx.waitUntil(work.catch(() => null)) : undefined;
    // CLA-172: the test server (wrangler env "test") sends every page and answer with noindex.
    if (env.TEST_SERVER === "1") {
      const path = new URL(request.url).pathname;
      // The beta page comes filled (src/page.ts).
      const answer = env.ASSETS && isBetaPage(request) ? await betaPage(request, env, env.ASSETS, fetch, later)
        : path.startsWith("/v1/") || !env.ASSETS ? await serve(request, env, later) : await env.ASSETS.fetch(request);
      const marked = new Response(answer.body, answer);
      marked.headers.set("X-Robots-Tag", "noindex, nofollow");
      return marked;
    }
    // Live: run_worker_first sends only "/" here; every other file is served before the Worker,
    // and a path with no file comes here as today. The beta page comes filled (src/page.ts).
    if (env.ASSETS && new URL(request.url).pathname === "/") return isBetaPage(request) ? betaPage(request, env, env.ASSETS, fetch, later) : env.ASSETS.fetch(request);
    return serve(request, env, later);
  },
  // CLA-172: once an hour, open beta spots go to the oldest waitlist people by mail, and the kept
  // beta feed is read again (a page visit also does that when it is older than 2 minutes).
  async scheduled(_controller: ScheduledController, env: Env) {
    await openSpots(env.DB, Number(env.CAP), pageMailFor(env, Date.now), Date.now());
    await refreshFeed(env.DB, fetch, Date.now()).catch(() => null);
  },
} satisfies ExportedHandler<Env>;

function serve(request: Request, env: Env, later?: (work: Promise<unknown>) => void): Promise<Response> {
  const now = Date.now;
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
 * The host that the bot check's answer must name: PAGE_ORIGIN's. CLA-172: only the test server
 * (TEST_SERVER "1") may name another with TURNSTILE_HOST, for the test key's answers. The live
 * Worker ignores TURNSTILE_HOST.
 */
export function botCheckHost(env: Env): string {
  if (env.TEST_SERVER === "1" && env.TURNSTILE_HOST) return env.TURNSTILE_HOST;
  return new URL(env.PAGE_ORIGIN || "https://getmypod.app").hostname;
}
