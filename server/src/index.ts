import { handle } from "./activation";
import { linkMailer, noMail, noReports, reportMailer, resend } from "./mailer";
import { turnstile } from "./turnstile";

export default {
  async fetch(request: Request, env: Env) {
    // CLA-172: the test server (wrangler env "test") sends every page and answer with noindex.
    if (env.TEST_SERVER === "1") {
      const path = new URL(request.url).pathname;
      const answer = path.startsWith("/v1/") || !env.ASSETS ? await serve(request, env) : await env.ASSETS.fetch(request);
      const marked = new Response(answer.body, answer);
      marked.headers.set("X-Robots-Tag", "noindex, nofollow");
      return marked;
    }
    return serve(request, env);
  },
} satisfies ExportedHandler<Env>;

function serve(request: Request, env: Env): Promise<Response> {
  const now = Date.now;
  // Until Jason adds the RESEND_KEY secret, nothing is sent and people see "Mail is busy".
  const mailer = env.RESEND_KEY ? linkMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), env.ALERT_TO, now) : noMail;
  // CLA-166: problem reports share the link mails' day count.
  const reports = env.RESEND_KEY ? reportMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), now) : noReports;
  // Until Jason adds the TURNSTILE_SECRET secret, every page start is refused as a bot.
  return handle(request, env, { now, mailer, reports, human: turnstile(env.TURNSTILE_SECRET, new URL(env.PAGE_ORIGIN || "https://getmypod.app").hostname) });
}
