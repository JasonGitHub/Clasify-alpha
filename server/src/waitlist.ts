// CLA-172: the beta page's "Join the waitlist" (POST /v1/waitlist). The answer never tells a
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
 * `perKey` an hour for this key, and `perDay` in 24 hours for this kind. False: over a limit.
 */
export async function tryOnce(db: D1Database, kind: "wait" | "link", keyHash: string, now: number,
  perKey: { count: number; within: number }, perDay: number): Promise<boolean> {
  await db.prepare("DELETE FROM page_tries WHERE at < ?").bind(now - 2 * day).run();
  const room = await db.prepare(
    `INSERT INTO page_tries (kind, key_hash, at) SELECT ?1, ?2, ?3
     WHERE (SELECT COUNT(*) FROM page_tries WHERE kind = ?1 AND key_hash = ?2 AND at > ?3 - ?4) < ?5
     AND (SELECT COUNT(*) FROM page_tries WHERE kind = ?1 AND at > ?3 - ?6) < ?7`,
  ).bind(kind, keyHash, now, perKey.within, perKey.count, day, perDay).run();
  return room.meta.changes > 0;
}

/** The bot check first (fail closed), then the address, then the limits. Keeps email and created_at only. */
export async function waitlist(db: D1Database, body: Record<string, unknown>, now: number, perDay: number,
  human: (token: string) => Promise<boolean>, hash: (s: string) => Promise<string>, newID: () => string): Promise<PageResult> {
  if (typeof body.human !== "string" || !(await human(body.human))) return "bot";
  const email = pageEmail(body.email);
  if (!email) return "bad";
  if (!(await tryOnce(db, "wait", await hash(email), now, { count: waitPerHour, within: hour }, perDay))) return "busy";
  // A known address, in any state, stays as it is.
  await db.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES (?, ?, 'waitlist', ?) ON CONFLICT (email) DO NOTHING")
    .bind(newID(), email, now).run();
  return "ok";
}
