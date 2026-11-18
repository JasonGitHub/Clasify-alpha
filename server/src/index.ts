import { handle } from "./activation";
import { linkMailer, noMail, resend } from "./mailer";
import { turnstile } from "./turnstile";

export default {
  fetch(request, env) {
    const now = Date.now;
    // Until Jason adds the RESEND_KEY secret, nothing is sent and people see "Mail is busy".
    const mailer = env.RESEND_KEY ? linkMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), env.ALERT_TO, now) : noMail;
    // Until Jason adds the TURNSTILE_SECRET secret, every page start is refused as a bot.
    return handle(request, env, { now, mailer, human: turnstile(env.TURNSTILE_SECRET) });
  },
} satisfies ExportedHandler<Env>;
