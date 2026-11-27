// CLA-172: the beta page's "What next?" votes (POST /v1/vote). CLA-198: a vote counts only with a
// passed bot check. GET /v1/votes gives each open item's share in whole percent, never the counts
// (Jason 08:11 JST 11-28); Jason reads the counts from D1 through the CTO.

/** The items, from the website thread (fixed list). Any other item is "bad". */
export const voteItems = ["local-music", "nano", "radio", "like-from-wheel", "more-colors"] as const;
/** The "Which color first?" pick under More colors (Jason 08:20 JST 11-28): the Nano colors that
 * Silver and Black do not cover. Counted like a vote; never in the shares. */
export const colorItems = ["color-pink", "color-blue", "color-green", "color-red"] as const;
/** Items that are built: still counted on a vote, but left out of the shares. */
export const builtItems: readonly string[] = ["local-music"];

/**
 * Each open item's share of the open items' votes, in whole percent that add up to 100 (largest
 * remainder; a tie goes to the item first in `voteItems`), and `top`: the item with the most
 * votes when it leads alone, else null. No votes: an empty list.
 */
export async function shares(db: D1Database): Promise<{ shares: Record<string, number>; top: string | null }> {
  const rows = (await db.prepare("SELECT item, count FROM votes").all<{ item: string; count: number }>()).results;
  const open = voteItems.filter((i) => !builtItems.includes(i));
  const count = (i: string) => Math.max(0, rows.find((r) => r.item === i)?.count ?? 0);
  const total = open.reduce((n, i) => n + count(i), 0);
  if (!total) return { shares: {}, top: null };
  // The leader from the counts, not the rounded shares: rounding must not make a winner of a tie.
  const most = Math.max(...open.map(count));
  const leaders = open.filter((i) => count(i) === most);
  const exact = open.map((i, at) => ({ i, at, p: (count(i) * 100) / total }));
  const out = Object.fromEntries(exact.map((e) => [e.i, Math.floor(e.p)]));
  let left = 100 - Object.values(out).reduce((a, b) => a + b, 0);
  for (const e of [...exact].sort((a, b) => (b.p - Math.floor(b.p)) - (a.p - Math.floor(a.p)) || a.at - b.at)) {
    if (left-- <= 0) break;
    out[e.i] += 1;
  }
  return { shares: out, top: leaders.length === 1 ? leaders[0] : null };
}

/**
 * One vote per item a day per network. "busy": this network already voted for it today. "bot": no
 * bot check token (`human`), or the check failed or could not run (CLA-198): nothing is written.
 */
export async function vote(db: D1Database, body: Record<string, unknown>, ip: string, now: number,
  hash: (s: string) => Promise<string>, newSalt: () => string,
  human: (token: string) => Promise<boolean>): Promise<"ok" | "busy" | "bad" | "bot"> {
  const item = body.item;
  if (typeof item !== "string" || ![...voteItems, ...colorItems].includes(item as never)) return "bad";
  // Before any D1 write. The token is never stored or logged.
  if (typeof body.human !== "string" || !(await human(body.human))) return "bot";
  const day = new Date(now).toISOString().slice(0, 10);
  const old = new Date(now - 2 * 24 * 60 * 60_000).toISOString().slice(0, 10);
  await db.batch([
    db.prepare("DELETE FROM vote_tries WHERE day < ?").bind(old),
    db.prepare("DELETE FROM vote_salts WHERE day < ?").bind(old),
    db.prepare("INSERT INTO vote_salts (day, salt) VALUES (?, ?) ON CONFLICT (day) DO NOTHING").bind(day, newSalt()),
  ]);
  const salt = (await db.prepare("SELECT salt FROM vote_salts WHERE day = ?").bind(day).first<{ salt: string }>())!.salt;
  const net = await hash(`${salt}:${network(ip)}`);
  // The try and the count in one batch; the count goes up only when the try is new.
  const [tried] = await db.batch([
    db.prepare("INSERT INTO vote_tries (net_hash, item, day) VALUES (?, ?, ?) ON CONFLICT DO NOTHING").bind(net, item, day),
    db.prepare(
      `INSERT INTO votes (item, count) SELECT ?1, 1 WHERE changes() > 0
       ON CONFLICT (item) DO UPDATE SET count = count + 1`,
    ).bind(item),
  ]);
  return tried.meta.changes ? "ok" : "busy";
}

/**
 * The part of the address that names one network. IPv4: the whole address. IPv6: the first 64 bits
 * (the /64 prefix), because many home and mobile networks give each person a /64 and browsers
 * change the rest often. Any other text is used as it is.
 */
export function network(ip: string): string {
  const address = ip.trim().toLowerCase().split("%")[0];
  if (!address.includes(":")) return address;
  if (/^::ffff:\d+\.\d+\.\d+\.\d+$/.test(address)) return address.slice(7);  // IPv4 in IPv6 form
  const halves = address.split("::");
  if (halves.length > 2) return address;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const groups = halves.length === 2 ? [...head, ...Array(Math.max(0, 8 - head.length - tail.length)).fill("0"), ...tail] : head;
  if (groups.length !== 8 || !groups.every((g) => /^[0-9a-f]{1,4}$/.test(g))) return address;
  return groups.slice(0, 4).map((g) => g.replace(/^0+(?=.)/, "")).join(":") + "::/64";
}
