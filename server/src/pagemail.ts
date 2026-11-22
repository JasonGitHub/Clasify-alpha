// CLA-172: the beta page's mails. The words wait for Jason's OK (website thread draft,
// /mnt/project-files/beta-go-live/website-inputs.md), so they are all in this one file.
import type { SendMail } from "./mailer";

/** Where both mails send people: the download page, never the DMG itself. */
export const pageLink = "https://getmypod.app/";
const needs = "myPod needs macOS 15 or later, and Apple Music or Spotify Premium.";

export const pageMails = {
  /** "Email me the link" (spec item 3). */
  link: {
    subject: "Your myPod link",
    text: `Hi,\n\nHere is the link you asked for. Open it on your Mac to get myPod:\n\n${pageLink}\n\n${needs}\n\n` +
      "Thanks for stopping by. We hope it brings back the click.\n\nThe myPod team\n\n" +
      "You asked for this link on getmypod.app. If that was not you, you can ignore this mail.",
  },
  /** A beta spot is open, for the waitlist (spec item 5). */
  spot: {
    subject: "A myPod beta spot is open",
    text: `Hi,\n\nGood news: a spot in the myPod beta is open now. Thanks for waiting for it.\n\n` +
      `Spots go to the first people who come, so come by soon. Open this link on your Mac:\n\n${pageLink}\n\n` +
      `Download myPod, open it, and type your email to turn it on.\n\n${needs}\n\nThe myPod team\n\n` +
      "You get this mail because you left your email on getmypod.app. We write to you only about your spot and the myPod launch.",
  },
} as const;

/** Sends one page mail. "limit": the day's mail count for page mails is used up. */
export interface PageMailer {
  send(to: string, kind: keyof typeof pageMails): Promise<"sent" | "busy" | "limit">;
}

export const noPageMail: PageMailer = { send: async () => "busy" };

/** The last mails of each day stay for activation link mails (spec: page mails stop at MAIL_DAY - 40). */
export const pageReserve = 40;

/** Page mails share the day count of all our mails (`mail_days.sent`) and stop at `perDay - pageReserve`. */
export function pageMailer(db: D1Database, send: SendMail, perDay: number, now: () => number): PageMailer {
  return {
    async send(to, kind) {
      const date = new Date(now()).toISOString().slice(0, 10);
      const slot = await db.prepare(
        "INSERT INTO mail_days (day, sent) VALUES (?, 1) ON CONFLICT (day) DO UPDATE SET sent = sent + 1 WHERE sent < ? RETURNING sent",
      ).bind(date, perDay - pageReserve).first<{ sent: number }>();
      if (!slot) return "limit";
      return (await send({ to, ...pageMails[kind] })) ? "sent" : "busy";
    },
  };
}
