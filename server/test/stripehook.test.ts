import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import type { Mailer } from "../src/mailer";
import { dropOldEvents, eventLife, mailTry, signed, stripeHook, type PaidMailer } from "../src/stripehook";

// CLA-175 stage 1: Stripe's signed messages, with fakes only. No network.

const secret = "whsec_test_fake";
const hookEnv = { ...env, STRIPE_WEBHOOK_SECRET: secret };
let clock = 1_800_000_000_000;
let paidMails: string[];
let paidBusy: boolean;
let alerts: string[];
let n = 0;
const paidMail: PaidMailer = { send: async (to) => { if (paidBusy) return "busy"; paidMails.push(to); return "sent"; } };

async function sign(body: string, t = Math.floor(clock / 1000), key = secret) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(`${t}.${body}`));
  return `t=${t},v1=${[...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}
async function post(event: unknown, opts: { env?: Env; header?: string; raw?: string } = {}) {
  const body = opts.raw ?? JSON.stringify(event);
  const request = new Request("https://api.example/v1/stripe", { method: "POST", body, headers: { "Stripe-Signature": opts.header ?? await sign(body) } });
  return (await stripeHook(request, opts.env ?? hookEnv, {
    now: () => clock, newID: () => `acc${n++}`, paidMail, alertTo: "alerts@example.com",
    alert: async (m) => { alerts.push(m.subject); return true; },
  })).status;
}
let ids = 0;
const event = (type: string, object: Record<string, unknown>, extra: Record<string, unknown> = {}) =>
  ({ id: `evt_${ids++}`, type, livemode: true, data: { object }, ...extra });
const session = (extra: Record<string, unknown> = {}) => ({
  id: "cs_live_a1B2c3D4e5F6g7H8", livemode: true, mode: "payment", status: "complete", payment_status: "paid",
  metadata: { app: "mypod" }, payment_intent: "pi_1", customer_details: { email: "pat@example.com" }, amount_total: 2999, currency: "usd", ...extra,
});
const paid = (extra: Record<string, unknown> = {}) => event("checkout.session.completed", session(extra));
const account = () => env.DB.prepare("SELECT state, seat, paid_at FROM accounts WHERE email = 'pat@example.com'").first();
const payment = () => env.DB.prepare("SELECT state, mailed_at FROM payments WHERE payment_intent = 'pi_1'").first();

beforeEach(async () => {
  clock = 1_800_000_000_000;
  paidMails = []; paidBusy = false; alerts = [];
  await env.DB.batch(["reversals", "stripe_events", "bought_tries", "payments", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("the signature", () => {
  it("is checked on the exact bytes, with the secret, within 5 minutes", async () => {
    const body = JSON.stringify(paid());
    const raw = new TextEncoder().encode(body);
    expect(await signed(raw, await sign(body), secret, clock)).toBe(true);
    const good = (await sign(body)).split(",")[1];
    expect(await signed(raw, `t=${clock / 1000},v1=${"0".repeat(64)},${good}`, secret, clock)).toBe(true);  // one of many v1
    expect(await signed(new TextEncoder().encode(body + " "), await sign(body), secret, clock)).toBe(false);
    expect(await signed(raw, await sign(body, undefined, "whsec_other"), secret, clock)).toBe(false);
    expect(await signed(raw, await sign(body, clock / 1000 - 301), secret, clock)).toBe(false);
    expect(await signed(raw, await sign(body, clock / 1000 + 301), secret, clock)).toBe(false);
    expect(await signed(raw, await sign(body, clock / 1000 - 299), secret, clock)).toBe(true);
    for (const header of [null, "", "t=abc,v1=00", `v1=${"a".repeat(64)}`, `t=${clock / 1000}`]) expect(await signed(raw, header, secret, clock)).toBe(false);
    expect(await signed(raw, await sign(body), "", clock)).toBe(false);  // no secret set: nothing passes
  });

  it("refuses a bad signature, bad JSON, and test messages on live, and changes nothing", async () => {
    expect(await post(paid(), { header: "t=1,v1=00" })).toBe(400);
    expect(await post(null, { raw: "not json" })).toBe(400);
    expect(await post(paid(), { env: { ...env } })).toBe(400);  // no secret on this Worker
    expect(await post({ ...paid(), livemode: false })).toBe(400);
    expect(await post(event("checkout.session.completed", session({ livemode: false }), { livemode: false }), { env: { ...hookEnv, TEST_SERVER: "1" } })).toBe(200);
    expect(await account()).toMatchObject({ paid_at: clock });  // the test server takes test mode
  });
});

describe("paid", () => {
  it("sets the account paid, stores the payment and sends the mail once, also for the same message twice", async () => {
    const message = paid();
    expect(await post(message)).toBe(200);
    expect(await post(message)).toBe(200);
    expect(await post(paid())).toBe(200);  // a new message for the same payment
    expect(await account()).toEqual({ state: "pending", seat: 0, paid_at: clock });
    expect(await payment()).toEqual({ state: "paid", mailed_at: clock });
    expect(paidMails).toEqual(["pat@example.com"]);
    expect(alerts).toEqual([]);
  });

  it("handles paid later, and does nothing while the money is on its way", async () => {
    expect(await post(paid({ payment_status: "unpaid" }))).toBe(200);
    expect(await account()).toBeNull();
    expect(await post(event("checkout.session.async_payment_succeeded", session()))).toBe(200);
    expect(await account()).toMatchObject({ paid_at: clock });
    expect(paidMails).toHaveLength(1);
  });

  it("ignores other projects' payments, other modes and amounts of 0", async () => {
    for (const extra of [{ metadata: { app: "zapper" } }, { metadata: {} }, { mode: "subscription" }, { amount_total: 0 }]) {
      expect(await post(paid(extra))).toBe(200);
    }
    expect(await post(event("payment_intent.succeeded", { id: "pi_1" }))).toBe(200);
    expect(await account()).toBeNull();
    expect(paidMails).toEqual([]);
  });

  it("answers 500 when the mail is busy, so Stripe sends the message again, and then sends it", async () => {
    const message = paid();
    paidBusy = true;
    expect(await post(message)).toBe(500);
    expect(await account()).toMatchObject({ paid_at: clock });  // paid already
    expect(await payment()).toEqual({ state: "paid", mailed_at: null });
    paidBusy = false;
    expect(await post(message)).toBe(200);
    expect(paidMails).toEqual(["pat@example.com"]);
  });

  it("does not mark the message done while another message is sending the mail", async () => {
    await post(paid());
    await env.DB.prepare("UPDATE payments SET mailed_at = NULL, mailing_at = ?").bind(clock).run();  // another send is in flight
    paidMails = [];
    const message = paid();
    expect(await post(message)).toBe(500);
    clock += mailTry + 1;  // that send was lost
    expect(await post(message)).toBe(200);
    expect(paidMails).toEqual(["pat@example.com"]);
    expect(await payment()).toEqual({ state: "paid", mailed_at: clock });
  });

  it("sends the mail after the thank-you page set paid first", async () => {
    await env.DB.prepare("INSERT INTO accounts (id, email, state, paid_at, created_at) VALUES ('a', 'pat@example.com', 'pending', 1, 0)").run();
    await env.DB.prepare("INSERT INTO payments (session_id, payment_intent, account_id, amount, currency, state, at) VALUES (?, 'pi_1', 'a', 2999, 'usd', 'paid', 1)")
      .bind(session().id).run();
    expect(await post(paid())).toBe(200);
    expect(paidMails).toEqual(["pat@example.com"]);
  });

  it("alerts Jason about a second payment for one email", async () => {
    await post(paid());
    await post(paid({ id: "cs_live_second000000", payment_intent: "pi_2" }));
    expect(paidMails).toHaveLength(2);
    expect(alerts).toEqual(["myPod: a second payment for one email"]);
  });
});

describe("refund and dispute", () => {
  let mail: string[];
  const linkMailer: Mailer = { send: async (_to, link) => { mail.push(link); return "sent"; } };
  const mac = (i: number) => `device-${i}`.padEnd(40, "x");
  async function call(method: string, path: string, opts: { device?: string; body?: unknown } = {}) {
    const headers: Record<string, string> = opts.device ? { Authorization: `Device ${opts.device}` } : {};
    const body = opts.body && path === "/v1/start" ? { turnstile: "person", ...opts.body as object } : opts.body;
    const r = await handle(new Request(`https://api.example${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined }), env,
      { now: () => clock, mailer: linkMailer, human: async () => true });
    return (await r.json()) as Record<string, unknown>;
  }
  async function signIn(device: string) {
    clock += 7 * 60 * 60_000;
    const code = (await call("POST", "/v1/open", { device })).code;
    await call("POST", "/v1/start", { body: { code, email: "pat@example.com" } });
    return (await call("POST", "/v1/confirm", { body: { token: new URL(mail.at(-1)!).searchParams.get("c") } })).result;
  }
  beforeEach(() => { mail = []; });
  const refund = (refunded = true) => event("charge.refunded", { id: "ch_1", payment_intent: "pi_1", refunded });

  it("a full refund clears paid and signs out the Macs of an account with no seat; a partial one changes nothing", async () => {
    await post(paid());
    expect(await signIn(mac(1))).toBe("ok");
    expect(await signIn(mac(2))).toBe("ok");
    expect(await post(refund(false))).toBe(200);
    expect(await account()).toMatchObject({ state: "active", paid_at: expect.any(Number) });
    expect(await post(refund())).toBe(200);
    expect(await account()).toEqual({ state: "pending", seat: 0, paid_at: null });
    expect(await payment()).toMatchObject({ state: "refunded" });
    expect(await call("GET", "/v1/status", { device: mac(1) })).toEqual({ state: "locked" });
    expect(await call("GET", "/v1/status", { device: mac(2) })).toEqual({ state: "locked" });
  });

  it("an account with a seat keeps the seat and its 2-Mac rule after a dispute", async () => {
    await env.DB.prepare("INSERT INTO accounts (id, email, state, seat, created_at) VALUES ('a', 'pat@example.com', 'active', 1, 0)").run();
    await post(paid());
    expect(await signIn(mac(1))).toBe("ok");
    expect(await post(event("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1", status: "needs_response" }))).toBe(200);
    expect(await account()).toEqual({ state: "active", seat: 1, paid_at: null });
    expect(await call("GET", "/v1/status", { device: mac(1) })).toMatchObject({ state: "active", limit: 2 });
  });

  it("a won dispute sets paid again; a lost one does not", async () => {
    await post(paid());
    await post(event("charge.dispute.created", { id: "dp_1", payment_intent: "pi_1" }));
    expect(await account()).toMatchObject({ paid_at: null });
    await post(event("charge.dispute.closed", { id: "dp_1", payment_intent: "pi_1", status: "lost" }));
    expect(await account()).toMatchObject({ paid_at: null });
    clock += 1000;
    await post(event("charge.dispute.closed", { id: "dp_1", payment_intent: "pi_1", status: "won" }));
    expect(await account()).toMatchObject({ paid_at: clock });
    expect(await payment()).toMatchObject({ state: "paid" });
  });

  it("keeps a refund or dispute that comes before the paid message", async () => {
    expect(await post(refund())).toBe(200);
    expect(await post(paid())).toBe(200);
    expect(await account()).toEqual({ state: "pending", seat: 0, paid_at: null });
    expect(await payment()).toEqual({ state: "refunded", mailed_at: null });
    expect(paidMails).toEqual([]);
    await post(event("charge.dispute.created", { id: "dp_2", payment_intent: "pi_2" }));
    await post(paid({ id: "cs_live_second000000", payment_intent: "pi_2" }));
    expect(await account()).toMatchObject({ paid_at: null });
  });

  it("ignores a refund or dispute of a payment that is not ours", async () => {
    await post(paid());
    expect(await post(event("charge.refunded", { id: "ch_9", payment_intent: "pi_other", refunded: true }))).toBe(200);
    expect(await post(event("charge.dispute.created", { id: "dp_9", payment_intent: null }))).toBe(200);
    expect(await account()).toMatchObject({ paid_at: expect.any(Number) });
  });

  it("keeps paid while another payment of the account is still paid", async () => {
    await post(paid());
    await post(paid({ id: "cs_live_second000000", payment_intent: "pi_2" }));
    await post(refund());
    expect(await account()).toMatchObject({ paid_at: expect.any(Number) });
  });
});

it("message IDs and early refunds older than 30 days go", async () => {
  await env.DB.batch([
    env.DB.prepare("INSERT INTO stripe_events (id, at) VALUES ('old', ?)").bind(clock - eventLife - 1),
    env.DB.prepare("INSERT INTO stripe_events (id, at) VALUES ('new', ?)").bind(clock - eventLife + 1),
  ]);
  await env.DB.batch([
    env.DB.prepare("INSERT INTO reversals (payment_intent, state, at) VALUES ('pi_old', 'refunded', ?)").bind(clock - eventLife - 1),
    env.DB.prepare("INSERT INTO reversals (payment_intent, state, at) VALUES ('pi_new', 'refunded', ?)").bind(clock - eventLife + 1),
  ]);
  await dropOldEvents(env.DB, clock);
  expect((await env.DB.prepare("SELECT id FROM stripe_events").all()).results).toEqual([{ id: "new" }]);
  expect((await env.DB.prepare("SELECT payment_intent FROM reversals").all()).results).toEqual([{ payment_intent: "pi_new" }]);
});
