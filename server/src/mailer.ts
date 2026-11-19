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

/** The link mail of card BX (334). */
export function linkMail(link: string) {
  const a = escape(link);
  const font = "-apple-system,BlinkMacSystemFont,'Helvetica Neue',Helvetica,Arial,sans-serif";
  return {
    subject: "Your myPod link",
    text: `Hi there,\n\nClick the button to start the myPod beta. The link works for 1 hour.\n\n${link}\n\n` +
      "Did not ask for this? You can ignore this mail.\nmyPod by Cappy · © 2026 CappyAI Ltd",
    // Card CD (CLA-160, change 371): solid colors only, no background-image, so Gmail's dark
    // mode darkens the whole mail in one step. Apps that read prefers-color-scheme (Apple Mail)
    // get our own dark colors: the classes let the media rule win over the inline colors.
    html: `<!DOCTYPE html><html><head><meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">` +
      `<style>:root{color-scheme:light dark;supported-color-schemes:light dark}` +
      `@media (prefers-color-scheme: dark){.pg{background:#1b1f24!important}.tt{color:#f2f4f6!important}.tx{color:#a7b1bb!important}` +
      `.ft{color:#7a838d!important}.bt{background:#2f80e0!important}.bl{color:#ffffff!important}}</style></head>` +
      `<body class="pg" style="margin:0;padding:0;background:#e8eef4"><table class="pg" role="presentation" width="100%" cellspacing="0" cellpadding="0" bgcolor="#e8eef4" ` +
      `style="background:#e8eef4"><tr>` +
      `<td align="center" style="padding:56px 40px 30px;text-align:center;font-family:${font}">` +
      `<div class="tt" style="font-weight:bold;font-size:34px;letter-spacing:-0.4px;color:#1b1f24;margin:0 0 10px">Hi there,</div>` +
      `<div class="tx" style="font-size:17px;line-height:1.45;color:#5d6772;margin:0 0 26px">Click the button to start the myPod beta.<br>The link works for 1 hour.</div>` +
      `<table role="presentation" align="center" cellspacing="0" cellpadding="0" style="margin:0 auto"><tr>` +
      `<td class="bt" bgcolor="#1f6fd1" style="height:44px;padding:0 26px;border-radius:22px;background:#1f6fd1">` +
      `<a class="bl" href="${a}" style="display:inline-block;line-height:44px;color:#ffffff;font-weight:bold;font-size:17px;text-decoration:none">Confirm my email</a></td></tr></table>` +
      `<div class="ft" style="font-size:12px;line-height:1.6;color:#8a949e;margin:56px 0 0">Did not ask for this? You can ignore this mail.<br>myPod by Cappy · © 2026 CappyAI Ltd</div>` +
      `</td></tr></table></body></html>`,
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
          ...linkMail(link),
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
