// CLA-175 stage 1: Stripe's signed messages (release design doc, "Taking a payment message").
// Paid and paid later set the account paid; a full refund or a dispute clears it; a won dispute
// sets it again. Every step is safe to run twice. Nothing here goes to the logs.
import { type SendMail } from "./mailer";
import { markPaid, readSession, wantLive } from "./stripe";

/** A message older or newer than this is refused (Stripe's own default). */
export const tolerance = 5 * 60_000;
/** Message IDs are kept this long, then deleted by the hourly run. */
export const eventLife = 30 * 24 * 60 * 60_000;

/** The "myPod is yours" mail. "busy": not sent now; Stripe sends the message again later. */
export interface PaidMailer {
  send(to: string): Promise<"sent" | "busy">;
}
export const noPaidMail: PaidMailer = { send: async () => "busy" };

export interface HookDeps {
  now: () => number;
  newID: () => string;
  paidMail: PaidMailer;
  /** Jason's alert mail: a second payment for one email. Best effort. */
  alert: SendMail | null;
  alertTo?: string;
}

const hex = (bytes: ArrayBuffer) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");

/** Stripe-Signature: t=<seconds>,v1=<hex>[,v1=<hex>]. HMAC SHA-256 of "<t>." and the exact bytes. */
export async function signed(raw: Uint8Array, header: string | null, secret: string, now: number): Promise<boolean> {
  if (!header || !secret) return false;
  const parts = header.split(",").map((p) => p.trim().split("="));
  const t = parts.find(([k]) => k === "t")?.[1] ?? "";
  const given = parts.filter(([k, v]) => k === "v1" && /^[0-9a-f]{64}$/.test(v ?? "")).map(([, v]) => v);
  if (!/^[0-9]{1,12}$/.test(t) || !given.length || Math.abs(now - Number(t) * 1000) > tolerance) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const prefix = new TextEncoder().encode(`${t}.`);
  const payload = new Uint8Array(prefix.length + raw.length);
  payload.set(prefix);
  payload.set(raw, prefix.length);
  const want = hex(await crypto.subtle.sign("HMAC", key, payload));
  // Compare every byte, so the time does not tell how much of a guess was right.
  return given.some((v) => { let diff = 0; for (let i = 0; i < 64; i++) diff |= want.charCodeAt(i) ^ v.charCodeAt(i); return diff === 0; });
}

/** Sets one payment's state and the account's paid fact from it. An account with no seat that is no longer paid loses its Macs. */
async function setState(db: D1Database, paymentIntent: unknown, state: "paid" | "refunded" | "disputed", now: number) {
  if (typeof paymentIntent !== "string" || !paymentIntent) return;
  // Not stored yet: maybe ours, before its paid message, maybe another project's. Keep the state
  // for markPaid. Only myPod's stored payments change an account.
  await db.prepare("INSERT INTO reversals (payment_intent, state, at) VALUES (?, ?, ?) ON CONFLICT DO UPDATE SET state = excluded.state, at = excluded.at")
    .bind(paymentIntent, state, now).run();
  const account = "(SELECT account_id FROM payments WHERE payment_intent = ?1)";
  const gone = `(SELECT seat = 0 AND paid_at IS NULL FROM accounts WHERE id = ${account})`;
  await db.batch([
    db.prepare("UPDATE payments SET state = ?2 WHERE payment_intent = ?1").bind(paymentIntent, state),
    db.prepare(
      `UPDATE accounts SET paid_at = CASE WHEN EXISTS (SELECT 1 FROM payments WHERE account_id = accounts.id AND state = 'paid')
       THEN COALESCE(paid_at, ?2) ELSE NULL END WHERE id = ${account}`,
    ).bind(paymentIntent, now),
    // Its unused links die, and its Macs are signed out: /v1/status answers "locked".
    db.prepare(`UPDATE mails SET used_at = ?2 WHERE used_at IS NULL AND account_id = ${account} AND ${gone}`).bind(paymentIntent, now),
    db.prepare(`UPDATE macs SET state = 'waiting', account_id = NULL, mail_state = 'none', activated_at = NULL WHERE account_id = ${account} AND ${gone}`)
      .bind(paymentIntent),
    db.prepare(`UPDATE accounts SET state = 'pending' WHERE id = ${account} AND state = 'active' AND ${gone}`).bind(paymentIntent),
  ]);
}

/** A send that takes longer than this is taken as lost, and another message may send the mail. */
export const mailTry = 60_000;

/**
 * The mail once per paid payment. The claim is one statement, so two messages at once send one
 * mail. True: the mail went out (now or before), or the payment is not paid. False: not sent, or
 * another message is sending it now; Stripe sends this message again later.
 */
async function mailOnce(db: D1Database, session: string, deps: HookDeps): Promise<boolean> {
  const now = deps.now();
  const claim = await db.prepare(
    `UPDATE payments SET mailing_at = ? WHERE session_id = ? AND state = 'paid' AND mailed_at IS NULL
     AND (mailing_at IS NULL OR mailing_at < ?) RETURNING account_id`,
  ).bind(now, session, now - mailTry).first<{ account_id: string }>();
  if (!claim) {
    const row = await db.prepare("SELECT state, mailed_at FROM payments WHERE session_id = ?").bind(session).first<{ state: string; mailed_at: number | null }>();
    return !row || row.state !== "paid" || row.mailed_at !== null;
  }
  const a = await db.prepare("SELECT email, (SELECT COUNT(*) FROM payments WHERE account_id = accounts.id) AS n FROM accounts WHERE id = ?")
    .bind(claim.account_id).first<{ email: string; n: number }>();
  if (!a || (await deps.paidMail.send(a.email)) !== "sent") {
    await db.prepare("UPDATE payments SET mailing_at = NULL WHERE session_id = ? AND mailing_at = ?").bind(session, now).run();
    return false;
  }
  await db.prepare("UPDATE payments SET mailed_at = ? WHERE session_id = ?").bind(now, session).run();
  if (a.n > 1 && deps.alert && deps.alertTo) {
    await deps.alert({ to: deps.alertTo, subject: "myPod: a second payment for one email",
      text: `One account has ${a.n} payments now. Check it in Stripe and in D1, table payments, account ${claim.account_id}.` }).catch(() => false);
  }
  return true;
}

export async function stripeHook(request: Request, env: Env, deps: HookDeps): Promise<Response> {
  const answer = (status: number) => new Response(null, { status });
  const raw = new Uint8Array(await request.arrayBuffer());
  const now = deps.now();
  if (!(await signed(raw, request.headers.get("Stripe-Signature"), env.STRIPE_WEBHOOK_SECRET ?? "", now))) return answer(400);
  let event: Record<string, unknown>;
  try { event = JSON.parse(new TextDecoder().decode(raw)) as Record<string, unknown>; } catch { return answer(400); }
  if (typeof event.id !== "string" || event.livemode !== wantLive(env)) return answer(400);  // test messages never count on live
  if (await env.DB.prepare("SELECT 1 FROM stripe_events WHERE id = ?").bind(event.id).first()) return answer(200);
  const object = ((event.data as Record<string, unknown> | null)?.object ?? null) as Record<string, unknown> | null;
  switch (event.type) {
    case "checkout.session.completed":
    case "checkout.session.async_payment_succeeded": {
      const found = readSession(env, object);  // ignores other projects' payments (no metadata app=mypod)
      if (found.result === "paid") {
        await markPaid(env.DB, found.paid, now, deps.newID);
        if (!(await mailOnce(env.DB, found.paid.session, deps))) return answer(500);  // Stripe sends it again later
      }
      break;
    }
    case "charge.refunded":  // `refunded` is true only for a full refund
      if (object?.refunded === true) await setState(env.DB, object.payment_intent, "refunded", now);
      break;
    case "charge.dispute.created":
      await setState(env.DB, object?.payment_intent, "disputed", now);
      break;
    case "charge.dispute.closed":
      if (object?.status === "won") await setState(env.DB, object.payment_intent, "paid", now);
      break;
  }
  await env.DB.prepare("INSERT INTO stripe_events (id, at) VALUES (?, ?) ON CONFLICT DO NOTHING").bind(event.id, now).run();
  return answer(200);
}

/** The hourly run: message IDs and early refunds or disputes older than 30 days go. */
export const dropOldEvents = (db: D1Database, now: number) => db.batch([
  db.prepare("DELETE FROM stripe_events WHERE at < ?").bind(now - eventLife),
  db.prepare("DELETE FROM reversals WHERE at < ?").bind(now - eventLife),
]).catch(() => null);
