import type { Mailer } from "./mailer";

// Activation (CLA-128): the app opens the page with a one-time code, the person types an
// email, clicks the link in the mail, and presses Confirm. This file writes nothing to the
// logs, so no email ever lands there.

export interface Deps {
  now: () => number;
  mailer: Mailer;
}

const page = "https://getmypod.app";
const codeLife = 15 * 60_000;
const linkLife = 60 * 60_000;

type Account = { id: string; email: string; state: string; off: number };
type Mac = { device_hash: string; account_id: string | null; state: string; mails: number };

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const url = new URL(request.url);
  const cors = request.headers.get("Origin") === page;
  if (request.method === "OPTIONS" && cors) return reply(null, 204, true);
  const route = `${request.method} ${url.pathname}`;
  const now = deps.now();
  const db = env.DB;
  const device = await deviceHash(request);
  const body = request.method === "POST" ? await request.json().catch(() => ({})) as Record<string, unknown> : {};

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
    if (m.state === "active") return { state: "active", account: a.id };
    if (a.state === "waitlist") return { state: "full" };
    return m.mails > 0 ? { state: "waiting", email: a.email, mail: m.mails } : { state: "locked" };
  }

  /** Puts the Mac on the account and sends a new link, unless the beta is full or the account off. */
  async function start(hash: string, email: string) {
    await db.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES (?, ?, 'pending', ?) ON CONFLICT (email) DO NOTHING")
      .bind(token(), email, now).run();
    const a = (await db.prepare("SELECT * FROM accounts WHERE email = ?").bind(email).first<Account>())!;
    // An active Mac keeps its account, even when a Confirm lands while this runs.
    const moved = await db.prepare("UPDATE macs SET account_id = ? WHERE device_hash = ? AND state != 'active'").bind(a.id, hash).run();
    if (!moved.meta.changes) return status(hash);
    if (a.off) return { state: "off" };
    if (a.state !== "active" && (await activeCount()) >= Number(env.CAP)) {
      // Never over an account that a Confirm has just made active.
      const waits = await db.prepare("UPDATE accounts SET state = 'waitlist' WHERE id = ? AND state != 'active'").bind(a.id).run();
      if (waits.meta.changes) return { state: "full" };
    }
    const link = token();
    if ((await deps.mailer.send(email, `${page}/?c=${link}`)) === "busy") return { state: "busy" };
    await db.batch([
      db.prepare("UPDATE accounts SET state = 'pending' WHERE id = ? AND state = 'waitlist'").bind(a.id),
      db.prepare("INSERT INTO mails (token_hash, device_hash, account_id, sent_at, expires_at) VALUES (?, ?, ?, ?, ?)")
        .bind(await sha256(link), hash, a.id, now, now + linkLife),
      db.prepare("UPDATE macs SET mails = mails + 1 WHERE device_hash = ?").bind(hash),
    ]);
    return status(hash);
  }

  switch (route) {
    case "POST /v1/open": {  // the app, before it opens the page
      if (!device) return reply({ error: "device" }, 401);
      const code = token();
      await db.prepare(
        `INSERT INTO macs (device_hash, state, code_hash, code_expires_at, created_at) VALUES (?, 'waiting', ?, ?, ?)
         ON CONFLICT (device_hash) DO UPDATE SET code_hash = excluded.code_hash, code_expires_at = excluded.code_expires_at`,
      ).bind(device, await sha256(code), now + codeLife, now).run();
      return reply({ code });
    }
    case "GET /v1/status":  // the app
      return device ? reply(await status(device)) : reply({ error: "device" }, 401);
    case "POST /v1/start": {  // the page with {code, email}, or the app's "Send again" with no email
      if (device) {
        const a = (await mac(device))?.account_id;
        const email = a ? (await account(a))?.email : undefined;
        return email ? reply(await start(device, email)) : reply({ error: "email" }, 400);
      }
      const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
      if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply({ error: "email" }, 400, cors);
      const code = typeof body.code === "string" ? await sha256(body.code) : "";
      // One statement uses the code, so two pages with the same code cannot both go on.
      const owner = await db.prepare(
        "UPDATE macs SET code_hash = NULL, code_expires_at = NULL WHERE code_hash = ? AND code_expires_at > ? RETURNING device_hash",
      ).bind(code, now).first<{ device_hash: string }>();
      if (!owner) return reply({ error: "code" }, 400, cors);
      return reply(await start(owner.device_hash, email), 200, cors);
    }
    case "POST /v1/confirm": {  // the page, when the person presses Confirm
      const hash = typeof body.token === "string" ? await sha256(body.token) : "";
      const mail = await db.prepare("SELECT * FROM mails WHERE token_hash = ?").bind(hash).first<{ device_hash: string; account_id: string; expires_at: number; used_at: number | null }>();
      const m = mail ? await mac(mail.device_hash) : null;
      if (mail?.used_at && m?.state === "active") return reply({ result: "ok" }, 200, cors);  // a second press
      if (!mail || !m || mail.used_at || mail.expires_at <= now || m.account_id !== mail.account_id) return reply({ result: "expired" }, 200, cors);
      const a = await account(mail.account_id);
      if (!a || a.off) return reply({ result: "off" }, 200, cors);
      // One statement each, so two presses at once cannot pass the cap or the Mac limit together.
      const won = await db.prepare(
        `UPDATE accounts SET state = 'active', confirmed_at = COALESCE(confirmed_at, ?) WHERE id = ?
         AND (state = 'active' OR (SELECT COUNT(*) FROM accounts WHERE state = 'active') < ?)`,
      ).bind(now, a.id, Number(env.CAP)).run();
      if (!won.meta.changes) {
        await db.prepare("UPDATE accounts SET state = 'waitlist' WHERE id = ? AND state != 'active'").bind(a.id).run();
        return reply({ result: "full" }, 200, cors);
      }
      // The Mac must still be on this mail's account. A new account has no active Mac yet.
      const fits = await db.prepare(
        `UPDATE macs SET state = 'active' WHERE device_hash = ? AND account_id = ?
         AND (SELECT COUNT(*) FROM macs WHERE account_id = ? AND state = 'active') < ?`,
      ).bind(m.device_hash, a.id, a.id, Number(env.MACS)).run();
      if (!fits.meta.changes) {
        const moved = (await mac(m.device_hash))?.account_id !== a.id;  // "Use another email" came first
        return reply({ result: moved ? "expired" : "macs" }, 200, cors);
      }
      await db.prepare("UPDATE mails SET used_at = ? WHERE token_hash = ?").bind(now, hash).run();
      return reply({ result: "ok" }, 200, cors);
    }
  }
  return reply({ error: "not found" }, 404);
}

/** The device ID is a secret the app keeps in the Keychain; only its hash is stored. */
async function deviceHash(request: Request): Promise<string | null> {
  const id = request.headers.get("Authorization")?.match(/^Device ([A-Za-z0-9_-]{32,128})$/)?.[1];
  return id ? sha256(id) : null;
}

/** 32 random bytes, base64url. */
function token(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function reply(body: unknown, status = 200, cors = false): Response {
  const headers: Record<string, string> = { "Content-Type": "application/json", "Cache-Control": "no-store" };
  if (cors) {
    headers["Access-Control-Allow-Origin"] = page;
    headers["Access-Control-Allow-Methods"] = "POST";
    headers["Access-Control-Allow-Headers"] = "Content-Type";
    headers["Vary"] = "Origin";
  }
  return new Response(body === null ? null : JSON.stringify(body), { status, headers });
}
