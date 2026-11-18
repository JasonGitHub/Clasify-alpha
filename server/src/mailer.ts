/** Sends the link mail. */
export interface Mailer {
  send(to: string, link: string): Promise<"sent" | "busy">;
}

/** Sends nothing and answers "busy", so no one waits for a mail that never comes. */
export const noMail: Mailer = { send: async () => "busy" };

/** One mail through Resend's HTTP API. Answers true only for a 2xx answer; it logs nothing. */
export type SendMail = (mail: { to: string; subject: string; text: string; html?: string }) => Promise<boolean>;

export function resend(key: string, fetcher: typeof fetch = fetch): SendMail {
  return async ({ to, subject, text, html }) => {
    const response = await fetcher("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ from: "myPod <hello@getmypod.app>", reply_to: "feedback@getmypod.app", to: [to], subject, text, html }),
      signal: AbortSignal.timeout(10_000),
    }).catch(() => null);  // a timeout or no connection is "busy"
    return response?.ok ?? false;
  };
}

const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/"/g, "&quot;");

/**
 * The link mail, with our own day count. Resend's free plan allows 100 mails a day for the
 * whole account, so the link mails stop at `perDay` and keep the rest for the one alert a day.
 * A Resend day starts at 00:00 UTC (09:00 JST).
 */
export function linkMailer(db: D1Database, send: SendMail, perDay: number, alertTo: string | undefined, now: () => number): Mailer {
  return {
    async send(to, link) {
      const date = new Date(now()).toISOString().slice(0, 10);
      // Count and check in one statement, so two sends at once cannot pass the limit.
      const slot = await db.prepare(
        "INSERT INTO mail_days (day, sent) VALUES (?, 1) ON CONFLICT (day) DO UPDATE SET sent = sent + 1 WHERE sent < ? RETURNING sent",
      ).bind(date, perDay).first<{ sent: number }>();
      if (slot) {
        const ok = await send({
          to,
          subject: "Activate myPod",
          text: `Open this link and press Confirm to activate myPod:\n\n${link}\n\nThe link works for 1 hour. If you did not ask for this, you can ignore this mail.`,
          html: `<p>Open this link and press Confirm to activate myPod:</p><p><a href="${escape(link)}">Activate myPod</a></p><p>The link works for 1 hour. If you did not ask for this, you can ignore this mail.</p>`,
        });
        if (ok) return "sent";
      }
      // The first refusal and the first failure of a day each send one alert; later ones only count up.
      const kind = slot ? "failed" : "refused";
      const first = await db.prepare(
        `INSERT INTO mail_days (day, ${kind}) VALUES (?, 1) ON CONFLICT (day) DO UPDATE SET ${kind} = ${kind} + 1 RETURNING ${kind} AS n`,
      ).bind(date).first<{ n: number }>();
      if (first?.n === 1 && alertTo) {
        const jst = new Date(now() + 9 * 3_600_000).toISOString().slice(11, 16);
        await send({
          to: alertTo,
          subject: slot ? "myPod: a link mail failed" : "myPod: mail limit hit",
          text: `${slot ? "Resend did not take a link mail" : `Mail limit hit (${perDay} a day)`} at ${jst} JST. New people see "Mail is busy". ` +
            `The limit resets at 09:00 JST. The counts for today are in D1, table mail_days, day ${date}.`,
        });
      }
      return "busy";
    },
  };
}
