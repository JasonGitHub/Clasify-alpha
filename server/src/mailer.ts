/** Sends the link mail. S2 adds the Resend sender; until then nothing is sent. */
export interface Mailer {
  send(to: string, link: string): Promise<"sent" | "busy">;
}

/** Sends nothing and answers "busy", so no one waits for a mail that never comes. */
export const noMail: Mailer = { send: async () => "busy" };
