// CLA-172: invite links, getmypod.app/beta?invite=<id> (Jason OK 20:29 JST 11-23). The Worker counts
// the page opens for each id; the waitlist form brings the id along (src/waitlist.ts). There is no
// GET for the counts: Jason reads them from D1 through the CTO.
import { inviteID } from "../public/beta-page/logic.js";
import { network } from "./vote";
import { pageEmail } from "./waitlist";

/** At most this many different ids get a count. Past it, new ids are ignored (no row flood). */
export const inviteCap = 500;

/** The invite id in a page address, or null. Anything that is not a valid id is ignored. */
export function inviteOf(url: string): string | null {
  return inviteID(new URL(url).searchParams.get("invite"));
}

/**
 * One page open for `id`, once a day per network. "ok": counted. "seen": this network already
 * opened this id today. "full": a new id past the cap. The page never waits for this (src/index.ts).
 */
export async function countOpen(db: D1Database, id: string, ip: string, now: number,
  hash: (s: string) => Promise<string>, newSalt: () => string): Promise<"ok" | "seen" | "full"> {
  const day = new Date(now).toISOString().slice(0, 10);
  const old = new Date(now - 2 * 24 * 60 * 60_000).toISOString().slice(0, 10);
  await db.batch([
    db.prepare("DELETE FROM invite_tries WHERE day < ?").bind(old),
    db.prepare("INSERT INTO vote_salts (day, salt) VALUES (?, ?) ON CONFLICT (day) DO NOTHING").bind(day, newSalt()),
  ]);
  const salt = (await db.prepare("SELECT salt FROM vote_salts WHERE day = ?").bind(day).first<{ salt: string }>())!.salt;
  const net = await hash(`${salt}:${network(ip)}`);
  // The try and the count in one batch. A new id gets a try (and a row) only under the cap; the
  // count goes up only when the try is new.
  const [tried] = await db.batch([
    db.prepare(
      `INSERT INTO invite_tries (net_hash, id, day) SELECT ?1, ?2, ?3
       WHERE EXISTS (SELECT 1 FROM invite_opens WHERE id = ?2) OR (SELECT COUNT(*) FROM invite_opens) < ?4
       ON CONFLICT DO NOTHING`,
    ).bind(net, id, day, inviteCap),
    db.prepare(
      `INSERT INTO invite_opens (id, count) SELECT ?1, 1 WHERE changes() > 0
       ON CONFLICT (id) DO UPDATE SET count = count + 1`,
    ).bind(id),
  ]);
  if (tried.meta.changes) return "ok";
  const known = await db.prepare("SELECT 1 AS k FROM invite_opens WHERE id = ?").bind(id).first();
  return known ? "seen" : "full";
}

/** How long an invite id from "Email me the link" waits for its email to activate. */
export const inviteMailLife = 30 * 24 * 60 * 60_000;

/**
 * The key for an email in invite_mails: HMAC-SHA256 of the email (trimmed, lower case) with a Worker
 * secret (TURNSTILE_SECRET), so the table alone cannot be checked against a list of addresses.
 */
export async function emailKey(email: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(email.trim().toLowerCase()));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * "Email me the link" with a valid invite id: keeps the email's key and the id for 30 days. The first
 * id stays (set once). A new id past the 500 cap is ignored. No secret, no row. Never throws.
 */
export async function keepInviteMail(db: D1Database, body: Record<string, unknown>, secret: string | undefined, now: number): Promise<void> {
  const email = pageEmail(body.email);
  const id = inviteID(body.invite);
  if (!secret || !email || !id) return;
  await (async () => {
    await db.prepare(
      `INSERT INTO invite_mails (email_hash, id, at) SELECT ?1, ?2, ?3
       WHERE EXISTS (SELECT 1 FROM invite_opens WHERE id = ?2) OR (SELECT COUNT(*) FROM invite_opens) < ?4
       ON CONFLICT (email_hash) DO NOTHING`,
    ).bind(await emailKey(email, secret), id, now, inviteCap).run();
  })().catch(() => null);
}

/**
 * When an account activates: the invite id kept for its email (younger than 30 days) goes to the
 * account if it has none yet, and the row is deleted. Never throws, so an activation never waits on it.
 */
export async function claimInvite(db: D1Database, email: string, account: string, secret: string | undefined, now: number): Promise<void> {
  if (!secret) return;
  await (async () => {
    const key = await emailKey(email, secret);
    const kept = "SELECT id FROM invite_mails WHERE email_hash = ?1 AND at > ?3";
    await db.batch([
      db.prepare(`UPDATE accounts SET invite_id = (${kept}) WHERE id = ?2 AND invite_id IS NULL AND EXISTS (${kept})`).bind(key, account, now - inviteMailLife),
      db.prepare("DELETE FROM invite_mails WHERE email_hash = ?").bind(key),
    ]);
  })().catch(() => null);
}

/** The hourly cron: rows older than 30 days go. */
export async function dropOldInviteMails(db: D1Database, now: number): Promise<void> {
  await db.prepare("DELETE FROM invite_mails WHERE at <= ?").bind(now - inviteMailLife).run().catch(() => null);
}
