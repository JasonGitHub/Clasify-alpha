/// <reference types="vite/client" />
import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import type { Mailer } from "../src/mailer";
import { openSpots } from "../src/spots";
import migration from "../migrations/0011_seats_and_paid.sql?raw";

// CLA-175 stage 1: a beta seat and "paid" are two facts. Only seats count toward CAP.

class FakeMailer implements Mailer {
  sent: { to: string; link: string }[] = [];
  async send(to: string, link: string) { this.sent.push({ to, link }); return "sent" as const; }
  get token() { return new URL(this.sent.at(-1)!.link).searchParams.get("c")!; }
}

let clock = 1_000_000;
let mail: FakeMailer;
const mac = (n: number) => `device-${n}`.padEnd(40, "x");
const later = 7 * 60 * 60_000;  // past the link mail limits

async function call(method: string, path: string, opts: { device?: string; body?: unknown } = {}) {
  const headers: Record<string, string> = opts.device ? { Authorization: `Device ${opts.device}` } : {};
  const body = opts.body && path === "/v1/start" ? { turnstile: "person", ...opts.body as object } : opts.body;
  const request = new Request(`https://api.example${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const response = await handle(request, env, { now: () => clock, mailer: mail, human: async (t: string) => t === "person" });
  return (await response.json()) as Record<string, unknown>;
}
const status = (device: string) => call("GET", "/v1/status", { device });
const confirm = async (token: string) => (await call("POST", "/v1/confirm", { body: { token } })).result;
async function join(device: string, email: string) {
  const code = (await call("POST", "/v1/open", { device })).code;
  const { code: _next, ...answer } = await call("POST", "/v1/start", { body: { code, email } });
  return answer;
}
async function activate(device: string, email: string) {
  clock += later;
  await join(device, email);
  return confirm(mail.token);
}
const row = (email: string) => env.DB.prepare("SELECT state, seat, paid_at FROM accounts WHERE email = ?").bind(email).first();
const seats = async () => env.DB.prepare("SELECT COUNT(*) AS n FROM accounts WHERE seat = 1").first("n");
/** n beta testers that hold a seat; the cap is 25. */
const seated = (n: number) => env.DB.batch(Array.from({ length: n }, (_, i) =>
  env.DB.prepare("INSERT INTO accounts (id, email, state, seat, created_at) VALUES (?, ?, 'active', 1, 0)").bind(`s${i}`, `s${i}@example.com`)));
const paid = (email: string, state = "pending", seat = 0) =>
  env.DB.prepare("INSERT INTO accounts (id, email, state, seat, paid_at, created_at) VALUES (?, ?, ?, ?, 5, 0)").bind(email, email, state, seat).run();

beforeEach(async () => {
  clock = 1_000_000;
  mail = new FakeMailer();
  await env.DB.batch(["mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("the migration", () => {
  it("gives a seat to every active account and to no other", async () => {
    await env.DB.batch(["active", "pending", "waitlist"].map((state) =>
      env.DB.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES (?, ?, ?, 0)").bind(state, `${state}@example.com`, state)));
    await env.DB.prepare("UPDATE accounts SET seat = 0").run();  // as before the migration
    const update = migration.split("\n").find((line) => line.startsWith("UPDATE"))!;
    await env.DB.prepare(update).run();
    expect((await env.DB.prepare("SELECT id, seat, paid_at FROM accounts ORDER BY id").all()).results).toEqual([
      { id: "active", seat: 1, paid_at: null }, { id: "pending", seat: 0, paid_at: null }, { id: "waitlist", seat: 0, paid_at: null }]);
  });

  it("keeps an existing beta account as before: 2 Macs, swaps, and the cap of 25", async () => {
    expect(await activate(mac(1), "sam@example.com")).toBe("ok");
    expect(await row("sam@example.com")).toEqual({ state: "active", seat: 1, paid_at: null });
    expect(await activate(mac(2), "sam@example.com")).toBe("ok");
    expect(await status(mac(2))).toMatchObject({ state: "active", macs: 2, limit: 2 });
    expect(await activate(mac(3), "sam@example.com")).toBe("ok");  // a 3rd Mac replaces one
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM macs WHERE state = 'active'").first("n")).toBe(2);
    await seated(24);
    expect(await join(mac(4), "kim@example.com")).toEqual({ state: "full" });
    expect(await seats()).toBe(25);
  });
});

describe("a paid account", () => {
  it("signs in with no seat while the beta is full, and gets 3 Macs", async () => {
    await seated(25);
    await paid("pat@example.com");
    expect(await activate(mac(1), "pat@example.com")).toBe("ok");
    expect(await row("pat@example.com")).toEqual({ state: "active", seat: 0, paid_at: 5 });
    expect(await seats()).toBe(25);
    expect(await activate(mac(2), "pat@example.com")).toBe("ok");
    expect(await activate(mac(3), "pat@example.com")).toBe("ok");
    expect(await status(mac(3))).toMatchObject({ state: "active", macs: 3, limit: 3 });
    expect(await activate(mac(4), "pat@example.com")).toBe("ok");  // a 4th Mac replaces one
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM macs WHERE state = 'active'").first("n")).toBe(3);
    expect(await join(mac(5), "kim@example.com")).toEqual({ state: "full" });  // the beta is still full
  });

  it("is never full when it paid after joining the waitlist", async () => {
    await seated(25);
    expect(await join(mac(1), "pat@example.com")).toEqual({ state: "full" });  // the waitlist, before paying
    await env.DB.prepare("UPDATE accounts SET paid_at = 5 WHERE email = 'pat@example.com'").run();
    expect(await status(mac(1))).not.toEqual({ state: "full" });
    clock += later;
    expect(await join(mac(1), "pat@example.com")).toEqual({ state: "waiting", email: "pat@example.com", mail: 1 });
    expect(await confirm(mail.token)).toBe("ok");
    expect(await row("pat@example.com")).toEqual({ state: "active", seat: 0, paid_at: 5 });
    expect(await seats()).toBe(25);
    expect(await activate(mac(2), "pat@example.com")).toBe("ok");
    expect(await activate(mac(3), "pat@example.com")).toBe("ok");
    expect(await status(mac(3))).toMatchObject({ state: "active", macs: 3, limit: 3 });
  });

  it("does not take a seat when the beta has room", async () => {
    await paid("pat@example.com");
    expect(await activate(mac(1), "pat@example.com")).toBe("ok");
    expect(await seats()).toBe(0);
  });

  it("keeps the seat of a beta tester who buys, with 3 Macs", async () => {
    await paid("pat@example.com", "active", 1);
    expect(await activate(mac(1), "pat@example.com")).toBe("ok");
    expect(await row("pat@example.com")).toEqual({ state: "active", seat: 1, paid_at: 5 });
    expect(await status(mac(1))).toMatchObject({ limit: 3 });
  });

  it("does not use up a free spot, and gets no open-spot mail", async () => {
    await seated(24);  // one free spot, also with a paid account signed in
    await paid("pat@example.com", "active");
    await paid("wes@example.com", "waitlist");
    await env.DB.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES ('w', 'w@example.com', 'waitlist', 1)").run();
    const spots: string[] = [];
    expect(await openSpots(env.DB, 25, { send: async (to) => { spots.push(to); return "sent"; } }, clock)).toBe(1);
    expect(spots).toEqual(["w@example.com"]);
  });
});
