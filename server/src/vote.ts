// CLA-172: the beta page's "What next?" votes (POST /v1/vote). There is no GET for the counts:
// Jason reads them from D1 through the CTO.

/** The items, from the website thread (fixed list). Any other item is "bad". */
export const voteItems = ["local-music", "nano", "radio", "like-from-wheel", "more-colors"] as const;

/** One vote per item a day per network. "busy": this network already voted for it today. */
export async function vote(db: D1Database, body: Record<string, unknown>, ip: string, now: number,
  hash: (s: string) => Promise<string>, newSalt: () => string): Promise<"ok" | "busy" | "bad"> {
  const item = body.item;
  if (typeof item !== "string" || !(voteItems as readonly string[]).includes(item)) return "bad";
  const day = new Date(now).toISOString().slice(0, 10);
  const old = new Date(now - 2 * 24 * 60 * 60_000).toISOString().slice(0, 10);
  await db.batch([
    db.prepare("DELETE FROM vote_tries WHERE day < ?").bind(old),
    db.prepare("DELETE FROM vote_salts WHERE day < ?").bind(old),
    db.prepare("INSERT INTO vote_salts (day, salt) VALUES (?, ?) ON CONFLICT (day) DO NOTHING").bind(day, newSalt()),
  ]);
  const salt = (await db.prepare("SELECT salt FROM vote_salts WHERE day = ?").bind(day).first<{ salt: string }>())!.salt;
  const net = await hash(`${salt}:${ip}`);
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
