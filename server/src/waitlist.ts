import type { PageMailer } from "./pagemail";
import { inviteID } from "../public/beta-page/logic.js";

// CLA-172: the beta page's "Join the waitlist" (POST /v1/waitlist) and "Email me the link" (POST /v1/link). The answer never tells a
// visitor that an address is known: a new address and a known one both get "ok".

export type PageResult = "ok" | "busy" | "bot" | "bad";

const hour = 60 * 60_000;
const day = 24 * hour;
/** Tries per email an hour. */
export const waitPerHour = 3;

/** The email from the page's body, trimmed and in lower case, or null when it is not an address. */
export function pageEmail(value: unknown): string | null {
  const email = typeof value === "string" ? value.trim().toLowerCase() : "";
  return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null;
}

/**
 * Writes the try first, in one statement with both counts, so tries at once cannot pass a limit:
 * `perKey` tries within `perKey.within` for this key, and `perDay` in 24 hours for this kind.
 * "key": this address is over its own limit. "total": the day's total for all addresses is used up.
 */
export async function tryOnce(db: D1Database, kind: "wait" | "link", keyHash: string, now: number,
  perKey: { count: number; within: number }, perDay: number): Promise<"ok" | "key" | "total"> {
  await db.prepare("DELETE FROM page_tries WHERE at < ?").bind(now - 2 * day).run();
  const keyCount = `(SELECT COUNT(*) FROM page_tries WHERE kind = ?1 AND key_hash = ?2 AND at > ?3 - ?4)`;
  const room = await db.prepare(
    `INSERT INTO page_tries (kind, key_hash, at) SELECT ?1, ?2, ?3
     WHERE ${keyCount} < ?5 AND (SELECT COUNT(*) FROM page_tries WHERE kind = ?1 AND at > ?3 - ?6) < ?7`,
  ).bind(kind, keyHash, now, perKey.within, perKey.count, day, perDay).run();
  if (room.meta.changes > 0) return "ok";
  const mine = await db.prepare(`SELECT ${keyCount} AS n`).bind(kind, keyHash, now, perKey.within).first<{ n: number }>();
  return (mine?.n ?? 0) >= perKey.count ? "key" : "total";
}

/**
 * "Email me the link": one mail with the download page's link. Stores no email, only its hash and
 * the time: 1 a day per address, and `perDay` link mails a day in all. A mail that did not go out
 * does not count. A second ask in a day for one address is "ok" with no mail.
 */
export async function link(db: D1Database, body: Record<string, unknown>, now: number, perDay: number,
  human: (token: string) => Promise<boolean>, hash: (s: string) => Promise<string>, mailer: PageMailer): Promise<PageResult> {
  if (typeof body.human !== "string" || !(await human(body.human))) return "bot";
  const email = pageEmail(body.email);
  if (!email) return "bad";
  const key = await hash(email);
  // Over this address's own limit: it already has the mail today, so "ok", with no new mail and no
  // new row. Only the day's total, the mail budget and a failed send are "busy".
  const room = await tryOnce(db, "link", key, now, { count: 1, within: day }, perDay);
  if (room !== "ok") return room === "key" ? "ok" : "busy";
  if ((await mailer.send(email, "link")) === "sent") return "ok";
  await db.prepare("DELETE FROM page_tries WHERE kind = 'link' AND key_hash = ? AND at = ?").bind(key, now).run();
  return "busy";
}

/**
 * The bot check first (fail closed), then the address, then the limits. Keeps email and created_at,
 * and the invite id the person came with (a valid one, else none). A known address stays as it is:
 * its invite id is set only when the account is made, and never changed.
 */
export async function waitlist(db: D1Database, body: Record<string, unknown>, now: number, perDay: number,
  human: (token: string) => Promise<boolean>, hash: (s: string) => Promise<string>, newID: () => string): Promise<PageResult> {
  if (typeof body.human !== "string" || !(await human(body.human))) return "bot";
  const email = pageEmail(body.email);
  if (!email) return "bad";
  // Over this address's own limit: it is already on the list, so "ok" and nothing new is written.
  const room = await tryOnce(db, "wait", await hash(email), now, { count: waitPerHour, within: hour }, perDay);
  if (room !== "ok") return room === "key" ? "ok" : "busy";
  // A known address, in any state, stays as it is.
  await db.prepare("INSERT INTO accounts (id, email, state, created_at, invite_id) VALUES (?, ?, 'waitlist', ?, ?) ON CONFLICT (email) DO NOTHING")
    .bind(newID(), email, now, inviteID(body.invite)).run();
  return "ok";
}
