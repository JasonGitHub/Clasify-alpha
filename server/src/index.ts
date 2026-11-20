import { handle } from "./activation";
import { linkMailer, noMail, noReports, reportMailer, resend } from "./mailer";
import { turnstile } from "./turnstile";

export default {
  fetch(request, env) {
    const now = Date.now;
    // Until Jason adds the RESEND_KEY secret, nothing is sent and people see "Mail is busy".
    const mailer = env.RESEND_KEY ? linkMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), env.ALERT_TO, now) : noMail;
    // CLA-166: problem reports share the link mails' day count.
    const reports = env.RESEND_KEY ? reportMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), now) : noReports;
    // Until Jason adds the TURNSTILE_SECRET secret, every page start is refused as a bot.
    return handle(request, env, { now, mailer, reports, human: turnstile(env.TURNSTILE_SECRET, new URL(env.PAGE_ORIGIN || "https://getmypod.app").hostname) });
  },
} satisfies ExportedHandler<Env>;
