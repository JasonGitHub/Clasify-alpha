import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { noMail } from "../src/mailer";
import { markPaid } from "../src/stripe";

// CLA-175 stage 1: Buy and Bought with a fake Stripe. No network.

type Seen = { url: string; method: string; auth: string | null; body: string };
let seen: Seen[];
let answer: (url: string) => Response;
const fakeStripe = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const request = new Request(input, init);
  seen.push({ url: request.url, method: request.method, auth: request.headers.get("Authorization"), body: await request.text() });
  return answer(request.url);
}) as typeof fetch;

const stripeEnv = { ...env, STRIPE_KEY: "rk_test_fake", STRIPE_PRICE: "price_fake", SALES: "1" };
const clock = 5_000_000;
let ids = 0;
async function call(path: string, body: unknown, opts: { env?: Env; device?: string; ip?: string } = {}) {
  const headers: Record<string, string> = { Origin: "https://getmypod.app", "CF-Connecting-IP": opts.ip ?? "203.0.113.7" };
  if (opts.device) headers.Authorization = `Device ${opts.device}`;
  const request = new Request(`https://api.example${path}`, { method: "POST", headers, body: JSON.stringify(body) });
  const response = await handle(request, opts.env ?? stripeEnv, { now: () => clock, mailer: noMail, human: async () => true, fetcher: fakeStripe });
  return { status: response.status, json: await response.json() as Record<string, unknown> };
}
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { "Content-Type": "application/json" } });

const sid = "cs_live_a1B2c3D4e5F6g7H8";
const session = (extra: Record<string, unknown> = {}) => ({
  id: sid, livemode: true, mode: "payment", status: "complete", payment_status: "paid", metadata: { app: "mypod" }, payment_intent: "pi_123",
  customer_details: { email: " Pat@Example.com " }, amount_total: 2999, currency: "usd", ...extra,
});
const account = () => env.DB.prepare("SELECT state, seat, paid_at FROM accounts WHERE email = 'pat@example.com'").first();
const payments = async () => (await env.DB.prepare("SELECT session_id, payment_intent, amount, currency, state, at FROM payments").all()).results;

beforeEach(async () => {
  seen = [];
  answer = () => json(session());
  await env.DB.batch(["reversals", "bought_tries", "payments", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("Buy", () => {
  it("asks Stripe for a one-time Checkout page marked app=mypod, and answers its address", async () => {
    answer = () => json({ id: "cs_live_x", url: "https://checkout.stripe.com/c/pay/cs_live_x" });
    const device = "device-1".padEnd(40, "x");
    expect(await call("/v1/buy", {}, { device })).toEqual({ status: 200, json: { url: "https://checkout.stripe.com/c/pay/cs_live_x" } });
    expect(seen).toHaveLength(1);
    expect(seen[0]).toMatchObject({ url: "https://api.stripe.com/v1/checkout/sessions", method: "POST", auth: "Bearer rk_test_fake" });
    const form = Object.fromEntries(new URLSearchParams(seen[0].body));
    expect(form).toEqual({
      mode: "payment", "line_items[0][price]": "price_fake", "line_items[0][quantity]": "1",
      success_url: "https://getmypod.app/thanks?session={CHECKOUT_SESSION_ID}", cancel_url: "https://getmypod.app/",
      "metadata[app]": "mypod", "payment_intent_data[metadata][app]": "mypod", allow_promotion_codes: "true",
    });
    expect(seen[0].body).not.toContain("device");  // never a device ID to Stripe
  });

  it("answers sales (503) with no key, no price, a Stripe error, or an address that is not Stripe's", async () => {
    expect((await call("/v1/buy", {}, { env: { ...stripeEnv, STRIPE_KEY: undefined } })).status).toBe(503);
    expect((await call("/v1/buy", {}, { env: { ...stripeEnv, STRIPE_PRICE: undefined } })).status).toBe(503);
    expect(seen).toHaveLength(0);
    answer = () => json({ error: {} }, 500);
    expect(await call("/v1/buy", {})).toEqual({ status: 503, json: { error: "sales" } });
    answer = () => json({ url: "https://evil.example/pay" });
    expect((await call("/v1/buy", {})).status).toBe(503);
  });

  it("the stop-sales switch: only SALES \"1\" asks Stripe; Bought still works with sales off", async () => {
    answer = () => json({ id: "cs_live_x", url: "https://checkout.stripe.com/c/pay/cs_live_x" });
    for (const SALES of [undefined, "0", "", "true", "1 "]) {
      expect(await call("/v1/buy", {}, { env: { ...stripeEnv, SALES } })).toEqual({ status: 503, json: { error: "sales" } });
    }
    expect(seen).toHaveLength(0);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM bought_tries").first()).toEqual({ n: 0 });  // a stopped Buy uses no try
    answer = () => json(session());
    expect((await call("/v1/bought", { session: sid }, { env: { ...stripeEnv, SALES: "0" } })).json).toEqual({ result: "paid" });
  });

  it("allows BUY_HOUR payment pages an hour per network, without asking Stripe after that; Bought has its own count", async () => {
    answer = () => json({ id: "cs_live_x", url: "https://checkout.stripe.com/c/pay/cs_live_x" });
    const few = { ...stripeEnv, BUY_HOUR: "2", BOUGHT_HOUR: "5" };
    expect((await call("/v1/buy", {}, { env: few })).status).toBe(200);
    expect((await call("/v1/buy", {}, { env: few, ip: "2001:db8:1:2::5" })).status).toBe(200);
    expect((await call("/v1/buy", {}, { env: few })).status).toBe(200);
    expect(await call("/v1/buy", {}, { env: few })).toEqual({ status: 429, json: { error: "busy" } });
    expect((await call("/v1/buy", {}, { env: few, ip: "2001:db8:1:2::9" })).status).toBe(200);  // its own /64 count
    expect((await call("/v1/buy", {}, { env: few, ip: "2001:db8:1:2::a" })).status).toBe(429);
    expect(seen).toHaveLength(4);
    answer = () => json(session());
    expect((await call("/v1/bought", { session: sid }, { env: few })).status).toBe(200);  // Buy's count is not Bought's
    expect(env.BUY_HOUR).toBe("10");
  });
});

describe("Bought", () => {
  it("sets paid on a new account once, stores the payment once, and takes no seat", async () => {
    expect(await call("/v1/bought", { session: sid })).toEqual({ status: 200, json: { result: "paid" } });
    expect(seen[0]).toMatchObject({ url: `https://api.stripe.com/v1/checkout/sessions/${sid}`, method: "GET" });
    expect(await account()).toEqual({ state: "pending", seat: 0, paid_at: clock });
    expect(await call("/v1/bought", { session: sid })).toEqual({ status: 200, json: { result: "paid" } });
    expect(await payments()).toEqual([{ session_id: sid, payment_intent: "pi_123", amount: 2999, currency: "usd", state: "paid", at: clock }]);
  });

  it("sets paid on an existing account and keeps its state and seat", async () => {
    await env.DB.prepare("INSERT INTO accounts (id, email, state, seat, created_at) VALUES ('a', 'pat@example.com', 'active', 1, 0)").run();
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "paid" });
    expect(await account()).toEqual({ state: "active", seat: 1, paid_at: clock });
  });

  it("answers no and changes nothing for a session that is not paid, not myPod's, or of the wrong mode", async () => {
    for (const extra of [{ status: "open", payment_status: "unpaid" }, { payment_status: "no_payment_required" }, { metadata: { app: "zapper" } }, { metadata: null }, { livemode: false },
      { customer_details: null }, { amount_total: null }, { amount_total: 0 }, { mode: "subscription" }, { mode: "setup" },
      { id: "cs_live_other0000000" }]) {
      answer = () => json(session(extra));
      expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "not found" });
    }
    answer = () => json({ error: {} }, 404);
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "not found" });
    expect(await account()).toBeNull();
    expect(await payments()).toEqual([]);
  });

  it("takes a completed $0 order (a 100% off code): paid, no PaymentIntent, and a second one for the same email too", async () => {
    const free = { payment_status: "no_payment_required", amount_total: 0, payment_intent: null };
    answer = () => json(session(free));
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "paid" });
    expect(await account()).toEqual({ state: "pending", seat: 0, paid_at: clock });
    const other = "cs_live_z9Y8x7W6v5U4t3S2";
    answer = () => json(session({ ...free, id: other }));
    expect((await call("/v1/bought", { session: other })).json).toEqual({ result: "paid" });
    expect((await payments()).map((p) => [p.session_id, p.payment_intent, p.amount, p.state])).toEqual([[sid, null, 0, "paid"], [other, null, 0, "paid"]]);
  });

  it("refuses a $0 order that is not complete, not myPod's, in the wrong mode, or has money or a PaymentIntent", async () => {
    const free = { payment_status: "no_payment_required", amount_total: 0, payment_intent: null };
    for (const extra of [{ status: "open" }, { status: "expired" }, { metadata: { app: "zapper" } }, { livemode: false }, { mode: "setup" },
      { amount_total: 1 }, { amount_total: null }, { amount_total: -1 }, { payment_intent: "pi_9" }, { customer_details: null }, { payment_status: "paid" }]) {
      answer = () => json(session({ ...free, ...extra }));
      expect((await call("/v1/bought", { session: sid })).json, JSON.stringify(extra)).toEqual({ result: "not found" });
    }
    expect(await payments()).toEqual([]);
  });

  it("answers pending while Stripe waits for the money, and sets nothing", async () => {
    answer = () => json(session({ status: "complete", payment_status: "unpaid" }));
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "pending" });
    expect(await account()).toBeNull();
    answer = () => json(session({ status: "complete", payment_status: "unpaid", metadata: { app: "zapper" } }));
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "not found" });
    answer = () => json(session({ status: "open", payment_status: "unpaid" }));
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "not found" });
  });

  it("allows BOUGHT_HOUR checks an hour per network, without asking Stripe after that", async () => {
    const few = { ...stripeEnv, BOUGHT_HOUR: "2" };
    expect((await call("/v1/bought", { session: sid }, { env: few })).status).toBe(200);
    expect((await call("/v1/bought", { session: sid }, { env: few, ip: "2001:db8:1:2::5" })).status).toBe(200);
    expect((await call("/v1/bought", { session: sid }, { env: few })).status).toBe(200);
    expect(await call("/v1/bought", { session: sid }, { env: few })).toEqual({ status: 429, json: { result: "busy" } });
    expect(await call("/v1/bought", { session: sid }, { env: few, ip: "2001:db8:1:2::9" })).toMatchObject({ status: 200 });  // the same /64
    expect(await call("/v1/bought", { session: sid }, { env: few, ip: "2001:db8:1:2::a" })).toMatchObject({ status: 429 });
    expect(seen).toHaveLength(4);
    const rows = (await env.DB.prepare("SELECT net_hash FROM bought_tries").all<{ net_hash: string }>()).results;
    expect(rows.every((r) => /^[0-9a-f]{64}$/.test(r.net_hash))).toBe(true);  // never the address
  });

  it("takes test mode only on the test server", async () => {
    answer = () => json(session({ livemode: false }));
    expect((await call("/v1/bought", { session: sid }, { env: { ...stripeEnv, TEST_SERVER: "1" } })).json).toEqual({ result: "paid" });
    answer = () => json(session({ livemode: true }));
    expect((await call("/v1/bought", { session: sid }, { env: { ...stripeEnv, TEST_SERVER: "1" } })).json).toEqual({ result: "not found" });
  });

  it("never sends a bad session ID to Stripe", async () => {
    for (const session of [undefined, 5, "", "cs_live_../../customers", "pi_123", `cs_live_${"a".repeat(201)}`, "cs_live_short"]) {
      expect((await call("/v1/bought", { session })).json).toEqual({ result: "not found" });
    }
    expect(seen).toHaveLength(0);
  });

  it("does not set paid again for a refunded payment, though the session still reads paid at Stripe", async () => {
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "paid" });
    await env.DB.batch([  // as the refund in PR 4 will leave it
      env.DB.prepare("UPDATE payments SET state = 'refunded'"),
      env.DB.prepare("UPDATE accounts SET paid_at = NULL"),
    ]);
    expect((await call("/v1/bought", { session: sid })).json).toEqual({ result: "not found" });
    expect(await account()).toMatchObject({ paid_at: null });
  });

  it("markPaid answers true only the first time", async () => {
    const paid = { session: sid, paymentIntent: null, email: "pat@example.com", amount: 2999, currency: "usd" };
    const newID = () => `id${ids++}`;
    expect(await markPaid(env.DB, paid, clock, newID)).toBe(true);
    expect(await markPaid(env.DB, paid, clock + 1, newID)).toBe(false);
    expect(await account()).toEqual({ state: "pending", seat: 0, paid_at: clock });
  });
});
