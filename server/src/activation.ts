import { beta, testBuild } from "./beta";
import { feedback } from "./feedback";
import { noReports, type Mailer, type ReportMailer } from "./mailer";
import { noPageMail, type PageMailer } from "./pagemail";
import { vote } from "./vote";
import { link, waitlist } from "./waitlist";

// Activation (CLA-128): the app opens the page with a one-time code, the person types an
// email, clicks the link in the mail, and presses Confirm. This file writes nothing to the
// logs, so no email ever lands there.

export interface Deps {
  now: () => number;
  mailer: Mailer;
  /** The page's bot check (Turnstile): true only for a person. */
  human: (token: string) => Promise<boolean>;
  /** CLA-166: sends problem reports. None: every report is "busy". */
  reports?: ReportMailer;
  /** CLA-172: the beta page's mails. None: every mail is "busy". */
  pageMail?: PageMailer;
  /** CLA-172: reads the beta feed. Default: fetch. */
  fetcher?: typeof fetch;
}

const codeLife = 15 * 60_000;
const linkLife = 60 * 60_000;
const hour = 60 * 60_000;
const day = 24 * hour;

type Account = { id: string; email: string; state: string; off: number };
type Mac = { device_hash: string; account_id: string | null; state: string; mails: number; mail_state: string; activated_at: number | null };

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const url = new URL(request.url);
  // The page's Origin (PAGE_ORIGIN, default getmypod.app). The Launch website owns the rest of that site.
  const page = env.PAGE_ORIGIN || "https://getmypod.app";
  const cors = request.headers.get("Origin") === page ? page : null;
  if (request.method === "OPTIONS" && cors) return reply(null, 204, cors);
  const route = `${request.method} ${url.pathname}`;
  const now = deps.now();
  const db = env.DB;
  const device = await deviceHash(request);
  // Any body that is not a JSON object (bad JSON, null, a number, a list) reads as {}.
  const json: unknown = request.method === "POST" ? await request.json().catch(() => ({})) : {};
  const body = (json !== null && typeof json === "object" && !Array.isArray(json) ? json : {}) as Record<string, unknown>;

  const mac = (hash: string) => db.prepare("SELECT * FROM macs WHERE device_hash = ?").bind(hash).first<Mac>();
  const account = (id: string) => db.prepare("SELECT * FROM accounts WHERE id = ?").bind(id).first<Account>();
  const activeCount = async () =>
    (await db.prepare("SELECT COUNT(*) AS n FROM accounts WHERE state = 'active'").first<{ n: number }>())?.n ?? 0;

  /** What the app shows for one Mac. */
  async function status(hash: string): Promise<Record<string, unknown>> {
    const m = await mac(hash);
    const a = m?.account_id ? await account(m.account_id) : null;
    if (!m || !a) return { state: "locked" };
    if (a.off) return { state: "off" };
    // CLA-141: About shows the email masked and the date. The full address never goes out here.
    // macs/limit: for the proposed change 362 ("1 of 2 Macs"); the app does not show them yet.
    if (m.state === "active") {
      const macs = (await db.prepare("SELECT COUNT(*) AS n FROM macs WHERE account_id = ? AND state = 'active'").bind(a.id).first<{ n: number }>())?.n ?? 0;
      return { state: "active", account: a.id, email: masked(a.email), ...(m.activated_at ? { since: m.activated_at } : {}), macs, limit: Number(env.MACS) };
    }
    if (a.state === "waitlist") return { state: "full" };
    if (m.mail_state === "busy") return { state: "busy" };
    return m.mail_state === "sent" ? { state: "waiting", email: a.email, mail: m.mails } : { state: "locked" };
  }

  /** Puts the Mac on the account and sends a new link, unless the beta is full or the account off. */
  async function start(hash: string, email: string) {
    await db.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES (?, ?, 'pending', ?) ON CONFLICT (email) DO NOTHING")
      .bind(token(), email, now).run();
    const a = (await db.prepare("SELECT * FROM accounts WHERE email = ?").bind(email).first<Account>())!;
    // An active Mac keeps its account, even when a Confirm lands while this runs.
    const moved = await db.prepare(
      "UPDATE macs SET mail_state = CASE WHEN account_id = ?1 THEN mail_state ELSE 'none' END, account_id = ?1 WHERE device_hash = ?2 AND state != 'active'",
    ).bind(a.id, hash).run();
    if (!moved.meta.changes) return status(hash);
    if (a.off) return { state: "off" };
    if (a.state !== "active" && (await activeCount()) >= Number(env.CAP)) {
      // Never over an account that a Confirm has just made active.
      const waits = await db.prepare("UPDATE accounts SET state = 'waitlist' WHERE id = ? AND state != 'active'").bind(a.id).run();
      if (waits.meta.changes) return { state: "full" };
    }
    // The guard: per address and per device, MAIL_HOUR an hour and MAIL_DAY_EACH a day. The
    // mail row is written first, in one statement with the counts, so sends at once cannot pass.
    const link = token();
    const linkHash = await sha256(link);
    const within = (column: string) =>
      `(SELECT COUNT(*) FROM mails WHERE ${column} = ? AND sent_at > ?) < ? AND (SELECT COUNT(*) FROM mails WHERE ${column} = ? AND sent_at > ?) < ?`;
    const perHour = Number(env.MAIL_HOUR), perDay = Number(env.MAIL_DAY_EACH);
    const room = await db.prepare(
      `INSERT INTO mails (token_hash, device_hash, account_id, sent_at, expires_at) SELECT ?, ?, ?, ?, ?
       WHERE ${within("account_id")} AND ${within("device_hash")}`,
    ).bind(linkHash, hash, a.id, now, now + linkLife,
      a.id, now - hour, perHour, a.id, now - 24 * hour, perDay,
      hash, now - hour, perHour, hash, now - 24 * hour, perDay).run();
    if (!room.meta.changes) {
      // Over a limit. A mail still out to this account stays "sent"; with none, the app sees busy.
      await db.prepare("UPDATE macs SET mail_state = 'busy' WHERE device_hash = ? AND account_id = ? AND state != 'active' AND mail_state != 'sent'")
        .bind(hash, a.id).run();
      return { state: "busy" };
    }
    if ((await deps.mailer.send(email, `${page}/activate/?c=${link}`)) === "busy") {
      await db.batch([
        db.prepare("DELETE FROM mails WHERE token_hash = ?").bind(linkHash),
        db.prepare("UPDATE macs SET mail_state = 'busy' WHERE device_hash = ? AND account_id = ? AND state != 'active'").bind(hash, a.id),
      ]);
      return { state: "busy" };
    }
    await db.batch([
      db.prepare("UPDATE accounts SET state = 'pending' WHERE id = ? AND state = 'waitlist'").bind(a.id),
      db.prepare("UPDATE macs SET mails = mails + 1, mail_state = 'sent' WHERE device_hash = ? AND account_id = ?").bind(hash, a.id),
    ]);
    return status(hash);
  }

  switch (route) {
    case "GET /v1/beta": {  // the beta page (CLA-172): the count and the newest beta, cached 30 s
      const answer = reply(await beta(db, Number(env.CAP), deps.fetcher ?? fetch, now, testBuild(env)), 200, cors, "max-age=30");
      answer.headers.set("Vary", "Origin");  // cacheable, so also without CORS
      return answer;
    }
    case "POST /v1/waitlist":  // the beta page's waitlist form (CLA-172)
      return reply({ result: await waitlist(db, body, now, Number(env.WAIT_DAY), deps.human, sha256, token) }, 200, cors);
    case "POST /v1/link":  // the beta page's "Email me the link" (CLA-172)
      return reply({ result: await link(db, body, now, Number(env.LINK_DAY), deps.human, sha256, deps.pageMail ?? noPageMail) }, 200, cors);
    case "POST /v1/vote":  // the beta page's "What next?" (CLA-172); no bot check, one a day per item per network
      return reply({ result: await vote(db, body, request.headers.get("CF-Connecting-IP") ?? "", now, sha256, token) }, 200, cors);
    case "POST /v1/feedback": {  // the app's Report a Problem (CLA-166)
      const answer = await feedback(db, device, body, now, deps.reports ?? noReports);
      return reply(answer.body, answer.status);
    }
    case "POST /v1/open": {  // the app, before it opens the page
      if (!device) return reply({ error: "device" }, 401);
      const code = token();
      await db.prepare(
        `INSERT INTO macs (device_hash, state, code_hash, code_expires_at, created_at, last_seen_at) VALUES (?, 'waiting', ?, ?, ?, ?)
         ON CONFLICT (device_hash) DO UPDATE SET code_hash = excluded.code_hash, code_expires_at = excluded.code_expires_at,
         last_seen_at = excluded.last_seen_at`,
      ).bind(device, await sha256(code), now + codeLife, now, now).run();
      return reply({ code });
    }
    case "GET /v1/status":  // the app, at each start
      if (!device) return reply({ error: "device" }, 401);
      // CLA-133: when the Mac was last used, so a 3rd Mac replaces the least used one.
      await db.prepare("UPDATE macs SET last_seen_at = ? WHERE device_hash = ?").bind(now, device).run();
      return reply(await status(device));
    case "POST /v1/start": {  // the page with {code, email}, or the app's "Send again" with no email
      if (device) {
        const a = (await mac(device))?.account_id;
        const email = a ? (await account(a))?.email : undefined;
        return email ? reply(await start(device, email)) : reply({ error: "email" }, 400);
      }
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply({ error: "email" }, 400, cors);
      if (typeof body.turnstile !== "string" || !(await deps.human(body.turnstile))) return reply({ error: "bot" }, 400, cors);
      const code = typeof body.code === "string" ? await sha256(body.code) : "";
      // One statement uses the code and puts a new one in its place, so two pages with the same
      // code cannot both go on. The new code lets the page "Send again" or "Use another email".
      const next = token();
      const owner = await db.prepare(
        "UPDATE macs SET code_hash = ?, code_expires_at = ? WHERE code_hash = ? AND code_expires_at > ? RETURNING device_hash",
      ).bind(await sha256(next), now + codeLife, code, now).first<{ device_hash: string }>();
      if (!owner) return reply({ error: "code" }, 400, cors);
      return reply({ ...await start(owner.device_hash, email), code: next }, 200, cors);
    }
    case "POST /v1/peek": {  // the page, when it opens from the mail: whose link is it? It changes nothing.
      const hash = typeof body.token === "string" ? await sha256(body.token) : "";
      // One answer for a used, an old and an unknown link, so nobody can tell them apart.
      const live = await db.prepare(
        `SELECT accounts.email FROM mails JOIN macs ON macs.device_hash = mails.device_hash AND macs.account_id = mails.account_id
         JOIN accounts ON accounts.id = mails.account_id WHERE mails.token_hash = ? AND mails.used_at IS NULL AND mails.expires_at > ?`,
      ).bind(hash, now).first<{ email: string }>();
      return reply(live ? { email: live.email } : { result: "expired" }, 200, cors);
    }
    case "POST /v1/confirm": {  // the page, when the person presses Confirm
      const hash = typeof body.token === "string" ? await sha256(body.token) : "";
      const mail = await db.prepare("SELECT * FROM mails WHERE token_hash = ?").bind(hash).first<{ device_hash: string; account_id: string; expires_at: number; used_at: number | null }>();
      const m = mail ? await mac(mail.device_hash) : null;
      if (mail?.used_at && m?.state === "active") return reply({ result: "ok" }, 200, cors);  // a second press
      if (!mail || !m || mail.used_at || mail.expires_at <= now || m.account_id !== mail.account_id) return reply({ result: "expired" }, 200, cors);
      const a = await account(mail.account_id);
      if (!a || a.off) return reply({ result: "off" }, 200, cors);
      // One transaction (D1 batch). The Mac becomes active only while it is still on this account,
      // is already active or fits the Mac limit, and the account is active or gets a cap slot.
      // The account and the link follow the Mac, so a refused press never keeps a slot.
      // CLA-133: a Mac over the limit first turns off the account's least used active Mac, at most
      // SWAPS times in SWAP_DAYS days. The swap row is written only when the Mac is still on the
      // account, not active, and the account already has MACS active Macs (so it is active and
      // the cap does not change). Then the Mac fits, and the activation below passes too.
      const swap = token();
      const activeMacs = "(SELECT COUNT(*) FROM macs WHERE account_id = ? AND state = 'active')";
      const isActive = "EXISTS (SELECT 1 FROM macs WHERE device_hash = ? AND account_id = ? AND state = 'active')";
      const oldest = `SELECT device_hash FROM macs WHERE account_id = ? AND state = 'active' AND device_hash != ?
             ORDER BY COALESCE(last_seen_at, created_at), device_hash LIMIT 1`;
      const [, , , step] = await db.batch([
        db.prepare(
          `INSERT INTO swaps (id, account_id, at) SELECT ?, ?, ?
           WHERE EXISTS (SELECT 1 FROM macs WHERE device_hash = ? AND account_id = ? AND state != 'active')
           AND ${activeMacs} >= ? AND (SELECT COUNT(*) FROM swaps WHERE account_id = ? AND at > ?) < ?
           AND (SELECT state FROM accounts WHERE id = ?) = 'active'`,
        ).bind(swap, a.id, now, m.device_hash, a.id, a.id, Number(env.MACS), a.id, now - Number(env.SWAP_DAYS) * day, Number(env.SWAPS), a.id),
        // The turned-off Mac's unused links are used up, so they stay dead if it joins again.
        db.prepare(`UPDATE mails SET used_at = ? WHERE used_at IS NULL AND EXISTS (SELECT 1 FROM swaps WHERE id = ?) AND device_hash = (${oldest})`)
          .bind(now, swap, a.id, m.device_hash),
        // The turned-off Mac has no account, so /v1/status answers "locked".
        db.prepare(
          `UPDATE macs SET state = 'waiting', account_id = NULL, mail_state = 'none', activated_at = NULL
           WHERE EXISTS (SELECT 1 FROM swaps WHERE id = ?) AND device_hash = (${oldest})`,
        ).bind(swap, a.id, m.device_hash),
        db.prepare(
          `UPDATE macs SET state = 'active', last_seen_at = ?, activated_at = CASE WHEN state = 'active' AND activated_at IS NOT NULL THEN activated_at ELSE ? END
           WHERE device_hash = ? AND account_id = ?
           AND (state = 'active' OR ${activeMacs} < ?)
           AND ((SELECT state FROM accounts WHERE id = ?) = 'active' OR (SELECT COUNT(*) FROM accounts WHERE state = 'active') < ?)`,
        ).bind(now, now, m.device_hash, a.id, a.id, Number(env.MACS), a.id, Number(env.CAP)),
        db.prepare(`UPDATE accounts SET state = 'active', confirmed_at = COALESCE(confirmed_at, ?) WHERE id = ? AND ${isActive}`)
          .bind(now, a.id, m.device_hash, a.id),
        db.prepare(`UPDATE mails SET used_at = ? WHERE token_hash = ? AND ${isActive}`).bind(now, hash, m.device_hash, a.id),
      ]);
      if (!step.meta.changes) {
        if ((await mac(m.device_hash))?.account_id !== a.id) return reply({ result: "expired" }, 200, cors);  // "Use another email" came first
        if ((await account(a.id))?.state === "active") return reply({ result: "macs" }, 200, cors);
        await db.prepare("UPDATE accounts SET state = 'waitlist' WHERE id = ? AND state != 'active'").bind(a.id).run();
        return reply({ result: "full" }, 200, cors);
      }
      return reply({ result: "ok" }, 200, cors);
    }
  }
  return reply({ error: "not found" }, 404);
}

/** "s***@example.com": the first character (a whole code point), "***", and the full domain. */
export function masked(email: string): string {
  const at = email.lastIndexOf("@");
  const first = Array.from(email.slice(0, Math.max(at, 0)))[0] ?? "";
  return `${first}***${at >= 0 ? email.slice(at) : ""}`;
}

/** The device ID comes from the Mac's hardware UUID (CLA-145); only its hash is stored. */
async function deviceHash(request: Request): Promise<string | null> {
  const id = request.headers.get("Authorization")?.match(/^Device ([A-Za-z0-9_-]{32,128})$/)?.[1];
  return id ? sha256(id) : null;
}

/** 32 random bytes, base64url. */
function token(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function reply(body: unknown, status = 200, cors: string | null = null, cache = "no-store"): Response {
  const headers: Record<string, string> = { "Content-Type": "application/json", "Cache-Control": cache };
  if (cors) {
    headers["Access-Control-Allow-Origin"] = cors;
    headers["Access-Control-Allow-Methods"] = "GET, POST";
    headers["Access-Control-Allow-Headers"] = "Content-Type";
    headers["Vary"] = "Origin";
  }
  return new Response(body === null ? null : JSON.stringify(body), { status, headers });
}
