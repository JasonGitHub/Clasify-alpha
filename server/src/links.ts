// CLA-193: short links (Jason OK 22:25 and 22:27 JST 11-25), to see per post how many people come:
// getmypod.app/r/<name> for any Reddit name, and getmypod.app/<word> for the fixed words
// (linkKey and linkWords in public/beta-page/logic.js). Counts per key only. There is no GET for
// the counts: Jason reads them from D1 through the CTO.
import { linkKey } from "../public/beta-page/logic.js";
import { betaPath } from "./page";
import { network } from "./vote";

/** At most this many different keys get a count. Past it, new keys are not counted (no row flood). */
export const linkCap = 500;

/** One network makes at most this many new keys a day, so one script cannot fill `linkCap`. */
export const newLinksPerDay = 3;

/** The key of a short link path ("/hn" → "hn", "/r/IpodClassic" → "r/ipodclassic"), or null. */
export function linkOf(request: Request): string | null {
  const path = new URL(request.url).pathname;
  return path.length <= 24 ? linkKey(path.slice(1)) : null;
}

/**
 * Always to the fixed beta page, with the key only: no other part of the address goes along, so it
 * cannot send anyone anywhere else. A 302 with no-store, as "/" to /beta.
 */
export function linkRedirect(key: string): Response {
  return new Response(null, { status: 302, headers: { Location: `${betaPath}?from=${encodeURIComponent(key)}`, "Cache-Control": "no-store" } });
}

/**
 * One count for `key` of `kind`, once a day per network (the invite_opens rule). "ok": counted.
 * "seen": this network already did it today. "full": an open of a new key past `linkCap` or past
 * this network's `newLinksPerDay`, or a Download for a key with no open counted. The page and the download never wait for this.
 */
async function countOnce(db: D1Database, kind: "open" | "download", key: string, ip: string, now: number,
  hash: (s: string) => Promise<string>, newSalt: () => string): Promise<"ok" | "seen" | "full"> {
  const day = new Date(now).toISOString().slice(0, 10);
  const old = new Date(now - 2 * 24 * 60 * 60_000).toISOString().slice(0, 10);
  await db.batch([
    db.prepare("DELETE FROM link_tries WHERE day < ?").bind(old),
    db.prepare("INSERT INTO vote_salts (day, salt) VALUES (?, ?) ON CONFLICT (day) DO NOTHING").bind(day, newSalt()),
  ]);
  const salt = (await db.prepare("SELECT salt FROM vote_salts WHERE day = ?").bind(day).first<{ salt: string }>())!.salt;
  const net = await hash(`${salt}:${network(ip)}`);
  // The try and the count in one batch. A try (and a row) only for a known key, or for an open of a
  // new key under the cap; the count goes up only when the try is new.
  const known = "EXISTS (SELECT 1 FROM link_opens WHERE link = ?2)";
  // A new key also needs room for this network today: its rows of today that made a new key (the
  // primary key starts with net_hash, so this reads only this network's rows).
  const room = `(SELECT COUNT(*) FROM link_opens) < ?5
    AND (SELECT COUNT(*) FROM link_tries WHERE net_hash = ?1 AND day = ?4 AND new = 1) < ?6`;
  const tryRow = kind === "open"
    ? db.prepare(`INSERT INTO link_tries (net_hash, link, kind, day, new) SELECT ?1, ?2, ?3, ?4, NOT ${known}
        WHERE ${known} OR (${room}) ON CONFLICT DO NOTHING`).bind(net, key, kind, day, linkCap, newLinksPerDay)
    : db.prepare(`INSERT INTO link_tries (net_hash, link, kind, day) SELECT ?1, ?2, ?3, ?4
        WHERE ${known} ON CONFLICT DO NOTHING`).bind(net, key, kind, day);
  const count = kind === "open"
    ? db.prepare("INSERT INTO link_opens (link, count) SELECT ?1, 1 WHERE changes() > 0 ON CONFLICT (link) DO UPDATE SET count = count + 1").bind(key)
    : db.prepare("INSERT INTO link_downloads (link, day, count) SELECT ?1, ?2, 1 WHERE changes() > 0 ON CONFLICT (link, day) DO UPDATE SET count = count + 1").bind(key, day);
  const [tried] = await db.batch([tryRow, count]);
  if (tried.meta.changes) return "ok";
  const opened = await db.prepare("SELECT 1 AS k FROM link_opens WHERE link = ?").bind(key).first();
  return opened ? "seen" : "full";
}

/** GET of a short link: one open for its key. */
export function countLinkOpen(db: D1Database, key: string, ip: string, now: number,
  hash: (s: string) => Promise<string>, newSalt: () => string): Promise<"ok" | "seen" | "full"> {
  return countOnce(db, "open", key, ip, now, hash, newSalt);
}

/** POST /v1/link-download { link }: a Download press after a short link. Not a valid key: "bad". */
export async function countLinkDownload(db: D1Database, body: Record<string, unknown>, ip: string, now: number,
  hash: (s: string) => Promise<string>, newSalt: () => string): Promise<"ok" | "seen" | "full" | "bad"> {
  const key = linkKey(body.link);
  return key ? countOnce(db, "download", key, ip, now, hash, newSalt) : "bad";
}
