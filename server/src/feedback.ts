import type { ReportMailer } from "./mailer";

// CLA-166 (card CG): Help > Report a Problem. Only an activated Mac may send. The report goes
// out by mail to feedback@getmypod.app and is not kept; the email is added only with writeBack.

/** Reports per account in 24 hours. */
export const reportsPerDay = 5;
export const maxText = 4000;
const day = 24 * 60 * 60_000;

/** A problem report from the app. Answers 200 sent, 400 bad text, 401 not active, 429 limit, 503 busy. */
export async function feedback(db: D1Database, device: string | null, body: Record<string, unknown>, now: number, reports: ReportMailer):
  Promise<{ status: number; body: Record<string, unknown> }> {
  if (!device) return { status: 401, body: { error: "device" } };
  const who = await db.prepare(
    `SELECT accounts.id, accounts.email FROM macs JOIN accounts ON accounts.id = macs.account_id
     WHERE macs.device_hash = ? AND macs.state = 'active' AND accounts.state = 'active' AND accounts.off = 0`,
  ).bind(device).first<{ id: string; email: string }>();
  if (!who) return { status: 401, body: { error: "device" } };
  const text = typeof body.text === "string" ? clean(body.text, true).trim() : "";
  if (!text || Array.from(text).length > maxText) return { status: 400, body: { error: "text" } };
  // The row is written first, in one statement with the count, so reports at once cannot pass.
  const id = crypto.randomUUID();
  const room = await db.prepare(
    "INSERT INTO reports (id, account_id, at) SELECT ?, ?, ? WHERE (SELECT COUNT(*) FROM reports WHERE account_id = ? AND at > ?) < ?",
  ).bind(id, who.id, now, who.id, now - day, reportsPerDay).run();
  if (!room.meta.changes) return { status: 429, body: { error: "limit" } };
  const writeBack = body.writeBack === true;
  const field = (key: string) => (typeof body[key] === "string" ? clean(body[key] as string, false).slice(0, 100) : "") || "-";
  const mail = {
    subject: `myPod problem report (build ${field("build")})`,
    text: `${text}\n\n---\nWrite back: ${writeBack ? who.email : "no"}\nAccount: ${who.id}\n` +
      `App: ${field("appVersion")} (build ${field("build")})\nmacOS: ${field("macOS")}\nMac: ${field("macModel")}\nService: ${field("service")}\n`,
    ...(writeBack ? { replyTo: who.email } : {}),
  };
  const result = await reports.send(mail);
  if (result === "sent") return { status: 200, body: { result: "sent" } };
  // Not sent: the report does not count against the person's 5. The app keeps it and tries again.
  await db.prepare("DELETE FROM reports WHERE id = ?").bind(id).run();
  return result === "limit" ? { status: 429, body: { error: "limit" } } : { status: 503, body: { error: "busy" } };
}

/** Plain text only: no control characters (lines and tabs only in the report text itself). */
function clean(s: string, lines: boolean): string {
  const t = s.replace(/\r\n?/g, "\n");
  return lines ? t.replace(/[^\P{Cc}\n\t]/gu, "") : t.replace(/\p{Cc}/gu, " ");
}
