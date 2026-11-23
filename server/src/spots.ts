import type { PageMailer } from "./pagemail";

// CLA-172: the open-spot mails (cron, once an hour). The spot is not held: the mail says to come
// soon, and the first people to activate get the spots (Jason knows).

/** An invite counts as open for 7 days, until its account is active. */
export const inviteOpen = 7 * 24 * 60 * 60_000;
/** Mails a run. */
export const spotsPerRun = 10;

/**
 * free = CAP - seats - open invites. Mails the `free` oldest waitlist accounts that
 * were not invited yet (at most `spotsPerRun`), and sets invited_at. A mail that does not go
 * out clears its invited_at again and ends the run. Answers the number of mails sent.
 */
export async function openSpots(db: D1Database, cap: number, mailer: PageMailer, now: number): Promise<number> {
  // One statement counts the free spots and claims that many rows, so two runs at once can never
  // mail more people than there are spots, nor one person twice. LIMIT is kept at 0 or more: a
  // negative LIMIT in SQLite means no limit.
  const picked = (await db.prepare(
    `UPDATE accounts SET invited_at = ?1 WHERE id IN (
       SELECT id FROM accounts WHERE state = 'waitlist' AND off = 0 AND paid_at IS NULL AND invited_at IS NULL ORDER BY created_at, id
       LIMIT max(0, min(?2, ?3 - (SELECT COUNT(*) FROM accounts WHERE seat = 1)
         - (SELECT COUNT(*) FROM accounts WHERE state != 'active' AND invited_at > ?4))))
     AND invited_at IS NULL RETURNING id, email, created_at`,
  ).bind(now, spotsPerRun, cap, now - inviteOpen).all<{ id: string; email: string; created_at: number }>()).results
    .sort((a, b) => a.created_at - b.created_at || a.id.localeCompare(b.id));
  let sent = 0;
  for (const [i, who] of picked.entries()) {
    if ((await mailer.send(who.email, "spot")) === "sent") { sent++; continue; }
    // Not sent (Resend down or the day's limit): these people wait for the next run.
    await db.batch(picked.slice(i).map((p) => db.prepare("UPDATE accounts SET invited_at = NULL WHERE id = ? AND invited_at = ?").bind(p.id, now)));
    break;
  }
  return sent;
}
