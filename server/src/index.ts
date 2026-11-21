import { handle } from "./activation";
import { linkMailer, noMail, noReports, reportMailer, resend } from "./mailer";
import { noPageMail, pageMailer, type PageMailer } from "./pagemail";
import { betaPage, isBetaPage } from "./page";
import { openSpots } from "./spots";
import { turnstile } from "./turnstile";

export default {
  async fetch(request: Request, env: Env) {
    // CLA-172: the test server (wrangler env "test") sends every page and answer with noindex.
    if (env.TEST_SERVER === "1") {
      const path = new URL(request.url).pathname;
      // The beta page comes filled (src/page.ts). Only where the Worker has the page's files
      // (ASSETS): the live Worker has none today, so it is unchanged.
      const answer = env.ASSETS && isBetaPage(request) ? await betaPage(request, env, env.ASSETS)
        : path.startsWith("/v1/") || !env.ASSETS ? await serve(request, env) : await env.ASSETS.fetch(request);
      const marked = new Response(answer.body, answer);
      marked.headers.set("X-Robots-Tag", "noindex, nofollow");
      return marked;
    }
    return serve(request, env);
  },
  // CLA-172: once an hour, open beta spots go to the oldest waitlist people by mail.
  async scheduled(_controller: ScheduledController, env: Env) {
    await openSpots(env.DB, Number(env.CAP), pageMailFor(env, Date.now), Date.now());
  },
} satisfies ExportedHandler<Env>;

function serve(request: Request, env: Env): Promise<Response> {
  const now = Date.now;
  // Until Jason adds the RESEND_KEY secret, nothing is sent and people see "Mail is busy".
  const mailer = env.RESEND_KEY ? linkMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), env.ALERT_TO, now) : noMail;
  // CLA-166: problem reports share the link mails' day count.
  const reports = env.RESEND_KEY ? reportMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), now) : noReports;
  // Until Jason adds the TURNSTILE_SECRET secret, every page start is refused as a bot.
  return handle(request, env, { now, mailer, reports, pageMail: pageMailFor(env, now), human: turnstile(env.TURNSTILE_SECRET, botCheckHost(env)) });
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
