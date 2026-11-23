// CLA-172: the beta page's mails. Card CJ (Jason OK 15:28 JST 11-22): the same look as the
// activation link mail, only the words differ.
import { cardMail, type SendMail } from "./mailer";

/** Where both mails send people: the download page, never the DMG itself. */
export const pageLink = "https://getmypod.app/";

export const pageMails = {
  /** "Email me the link" (spec item 3). */
  link: {
    subject: "Your myPod download link",
    ...cardMail({
      lines: ["Here is the myPod link you asked for.", "Open it on your Mac to download myPod."],
      button: "Get myPod",
      link: pageLink,
      foot: "Did not ask for this? You can ignore this mail.",
    }),
  },
  /** A beta spot is open, for the waitlist (spec item 5). */
  spot: {
    subject: "A myPod beta spot is open",
    ...cardMail({
      lines: ["Good news: a spot in the myPod beta is open.", "Spots go fast, so get myPod soon."],
      button: "Get myPod",
      link: pageLink,
      foot: "You joined the myPod waitlist on getmypod.app.",
    }),
  },
  /**
   * CLA-175: "myPod is yours", after a payment. PLACEHOLDER WORDS: the mail design (card CN) waits
   * for Jason. The CTO puts the approved words here before this merges.
   */
  paid: {
    subject: "myPod is yours",
    ...cardMail({
      lines: ["Thank you for buying myPod.", "Download it, then sign in with this email."],
      button: "Get myPod",
      link: pageLink,
      foot: "You bought myPod on getmypod.app.",
    }),
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
