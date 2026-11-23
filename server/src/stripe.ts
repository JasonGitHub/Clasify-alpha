// CLA-175 stage 1: Stripe Checkout, hosted, one-time payment. Only fetch, no Stripe package.
// Stripe never gets a device ID. The Checkout session carries only metadata app=mypod.

const api = "https://api.stripe.com/v1";
/** A Checkout session ID as Stripe writes it. Anything else never reaches Stripe. */
const sessionPattern = /^cs_(test|live)_[A-Za-z0-9]{10,200}$/;

export type StripeEnv = Pick<Env, "STRIPE_KEY" | "STRIPE_PRICE" | "PAGE_ORIGIN" | "TEST_SERVER">;

/** The stop-sales switch: only SALES "1" makes new payment pages. Bought and Stripe's messages work either way. */
export const salesOn = (env: Pick<Env, "SALES">) => env.SALES === "1";

/**
 * The Stripe API version of every call, fixed so the account's default version cannot change what
 * we send or read. $0 orders need 2023-08-16 or later; Checkout branding needs 2025-09-30.clover.
 */
export const stripeVersion = "2025-09-30.clover";

/** The live Worker takes only real money. Only the test server (TEST_SERVER "1") takes test mode. Fixed in code. */
export const wantLive = (env: Pick<Env, "TEST_SERVER">) => env.TEST_SERVER !== "1";

async function stripe(env: StripeEnv, fetcher: typeof fetch, method: "GET" | "POST", path: string, form?: Record<string, string>) {
  if (!env.STRIPE_KEY) return null;
  const response = await fetcher(`${api}${path}`, {
    method,
    headers: { Authorization: `Bearer ${env.STRIPE_KEY}`, "Stripe-Version": stripeVersion, ...(form ? { "Content-Type": "application/x-www-form-urlencoded" } : {}) },
    body: form ? new URLSearchParams(form).toString() : undefined,
  }).catch(() => null);
  if (!response?.ok) return null;
  return (await response.json().catch(() => null)) as Record<string, unknown> | null;
}

/** Buy: a new Checkout session for one copy. Answers its payment page address, or null. */
export async function checkout(env: StripeEnv, fetcher: typeof fetch): Promise<string | null> {
  if (!env.STRIPE_PRICE) return null;
  const page = env.PAGE_ORIGIN || "https://getmypod.app";
  const session = await stripe(env, fetcher, "POST", "/checkout/sessions", {
    mode: "payment",
    "line_items[0][price]": env.STRIPE_PRICE,
    "line_items[0][quantity]": "1",
    success_url: `${page}/thanks?session={CHECKOUT_SESSION_ID}`,
    cancel_url: `${page}/`,
    "metadata[app]": "mypod",
    "payment_intent_data[metadata][app]": "mypod",
    // Jason's one-time codes (100% off) for the live test: the code field on Stripe's page. Their
    // limits (redemptions, expiry) live in Stripe. The session is made at the full price, so
    // payment_intent_data is valid; with a $0 total Stripe makes no PaymentIntent.
    allow_promotion_codes: "true",
  });
  const url = session?.url;
  return typeof url === "string" && url.startsWith("https://checkout.stripe.com/") ? url : null;
}

export type Paid = { session: string; paymentIntent: string | null; email: string; amount: number; currency: string };
/** What the "thank you" page learns: paid, pending (Stripe still waits for the money), or not found. */
export type Found = { result: "paid"; paid: Paid } | { result: "pending" } | { result: "not found" };

/**
 * Reads one Checkout session, from Stripe's answer or from a webhook message. "paid" only when
 * it is myPod's, a one-time payment in the mode this server takes, and either Stripe says it is
 * paid with more than 0, or it is a completed $0 order (a 100% off code). "pending" when the buyer
 * finished Checkout and the money is still on its way. Anything else is "not found".
 */
export function readSession(env: Pick<Env, "TEST_SERVER">, s: Record<string, unknown> | null, id?: string): Found {
  const none = { result: "not found" } as const;
  if (!s || typeof s.id !== "string" || !sessionPattern.test(s.id) || (id !== undefined && s.id !== id)) return none;
  if (s.livemode !== wantLive(env) || s.mode !== "payment") return none;
  if ((s.metadata as Record<string, unknown> | null)?.app !== "mypod") return none;
  if (s.status === "complete" && s.payment_status === "unpaid") return { result: "pending" };
  // Paid: money taken (more than 0), or a completed $0 order (a 100% off code). Stripe's guide does
  // not name the $0 payment_status, so both "paid" and "no_payment_required" count there. A $0 order
  // has no PaymentIntent, so no refund or dispute. "no_payment_required" with money never counts.
  const free = (s.payment_status === "paid" || s.payment_status === "no_payment_required") && s.status === "complete"
    && s.amount_total === 0 && s.payment_intent == null;
  const charged = s.payment_status === "paid" && typeof s.amount_total === "number" && s.amount_total > 0;
  if (!free && !charged) return none;
  const email = (s.customer_details as Record<string, unknown> | null)?.email;
  if (typeof email !== "string" || !email.includes("@") || email.length > 254) return none;
  if (typeof s.amount_total !== "number" || !Number.isSafeInteger(s.amount_total) || typeof s.currency !== "string") return none;
  return { result: "paid", paid: { session: s.id, paymentIntent: typeof s.payment_intent === "string" ? s.payment_intent : null,
    email: email.trim().toLowerCase(), amount: s.amount_total, currency: s.currency } };
}

/** Bought: asks Stripe about one session. Any error or unknown ID is "not found". */
export async function findSession(env: StripeEnv, fetcher: typeof fetch, id: unknown): Promise<Found> {
  if (typeof id !== "string" || !sessionPattern.test(id)) return { result: "not found" };
  return readSession(env, await stripe(env, fetcher, "GET", `/checkout/sessions/${id}`), id);
}

/**
 * `perHour` tries an hour per key: Bought ("bought:" network, BOUGHT_HOUR) and Buy ("buy:" network,
 * BUY_HOUR) each have their own key. The row is written in one statement with the count.
 */
export async function hourRoom(db: D1Database, netHash: string, now: number, perHour: number): Promise<boolean> {
  const hour = 60 * 60_000;
  await db.prepare("DELETE FROM bought_tries WHERE at < ?").bind(now - 24 * hour).run();
  const room = await db.prepare(
    "INSERT INTO bought_tries (net_hash, at) SELECT ?1, ?2 WHERE (SELECT COUNT(*) FROM bought_tries WHERE net_hash = ?1 AND at > ?2 - ?3) < ?4",
  ).bind(netHash, now, hour, perHour).run();
  return room.meta.changes > 0;
}

/**
 * The paid step (design doc step 5), shared by Bought and the webhook (PR 4). Finds or makes the
 * account for the email, stores the payment once, and sets paid_at while that payment is still
 * "paid". A refund or dispute that came before (table reversals) is stored with it. A Checkout session stays "paid" at Stripe after a refund, so a refunded payment row
 * keeps a later Bought call from setting paid_at again. Safe to run twice.
 * Answers true only the first time this session is stored, so the "myPod is yours" mail goes once.
 */
export async function markPaid(db: D1Database, paid: Paid, now: number, newID: () => string): Promise<boolean> {
  const [, stored] = await db.batch([
    db.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES (?, ?, 'pending', ?) ON CONFLICT (email) DO NOTHING")
      .bind(newID(), paid.email, now),
    db.prepare(
      `INSERT INTO payments (session_id, payment_intent, account_id, amount, currency, state, state_at, at)
       SELECT ?1, ?2, id, ?3, ?4, COALESCE((SELECT state FROM reversals WHERE payment_intent = ?2), 'paid'),
         COALESCE((SELECT state_at FROM reversals WHERE payment_intent = ?2), 0), ?5
       FROM accounts WHERE email = ?6 ON CONFLICT DO NOTHING`,
    ).bind(paid.session, paid.paymentIntent, paid.amount, paid.currency, now, paid.email),
    db.prepare(
      `UPDATE accounts SET paid_at = COALESCE(paid_at, ?)
       WHERE id = (SELECT account_id FROM payments WHERE session_id = ? AND state = 'paid')`,
    ).bind(now, paid.session),
  ]);
  return stored.meta.changes > 0;
}
