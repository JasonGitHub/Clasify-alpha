import { handle } from "./activation";
import { linkMailer, noMail, resend } from "./mailer";

export default {
  fetch(request, env) {
    const now = Date.now;
    // Until Jason adds the RESEND_KEY secret, nothing is sent and people see "Mail is busy".
    const mailer = env.RESEND_KEY ? linkMailer(env.DB, resend(env.RESEND_KEY), Number(env.MAIL_DAY), env.ALERT_TO, now) : noMail;
    return handle(request, env, { now, mailer });
  },
} satisfies ExportedHandler<Env>;
