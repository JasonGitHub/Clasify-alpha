import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import type { Mailer } from "../src/mailer";

/** Keeps the links instead of sending them; answers "busy" when told to. */
class FakeMailer implements Mailer {
  sent: { to: string; link: string }[] = [];
  busy = false;
  async send(to: string, link: string) {
    if (this.busy) return "busy" as const;
    this.sent.push({ to, link });
    return "sent" as const;
  }
  get token() { return new URL(this.sent.at(-1)!.link).searchParams.get("c")!; }
}

let clock = 1_000_000;
let mail: FakeMailer;
const mac = (n: number) => `device-${n}`.padEnd(40, "x");

async function call(method: string, path: string, opts: { device?: string; body?: unknown; origin?: string } = {}) {
  const headers: Record<string, string> = {};
  if (opts.device) headers.Authorization = `Device ${opts.device}`;
  if (opts.origin) headers.Origin = opts.origin;
  const request = new Request(`https://api.example${path}`, { method, headers, body: opts.body ? JSON.stringify(opts.body) : undefined });
  const response = await handle(request, env, { now: () => clock, mailer: mail });
  return { status: response.status, json: await response.json().catch(() => null) as Record<string, unknown>, headers: response.headers };
}
const open = async (device: string) => (await call("POST", "/v1/open", { device })).json.code as string;
const status = async (device: string) => (await call("GET", "/v1/status", { device })).json;
const confirm = async (token: string) => (await call("POST", "/v1/confirm", { body: { token } })).json.result;
async function join(device: string, email: string) {
  return (await call("POST", "/v1/start", { body: { code: await open(device), email } })).json;
}
async function activate(device: string, email: string) {
  await join(device, email);
  return confirm(mail.token);
}

beforeEach(async () => {
  clock = 1_000_000;
  mail = new FakeMailer();
  await env.DB.batch(["mails", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("activation", () => {
  it("goes from locked to waiting to active", async () => {
    expect(await status(mac(1))).toEqual({ state: "locked" });
    expect(await join(mac(1), "  Sam@Example.com ")).toEqual({ state: "waiting", email: "sam@example.com", mail: 1 });
    expect(mail.sent[0]).toMatchObject({ to: "sam@example.com" });
    expect(mail.sent[0].link).toMatch(/^https:\/\/getmypod\.app\/\?c=[A-Za-z0-9_-]{43}$/);
    expect(await confirm(mail.token)).toBe("ok");
    expect(await status(mac(1))).toMatchObject({ state: "active", account: expect.any(String) });
    expect(await confirm(mail.token)).toBe("ok");  // a second press
  });

  it("Send again from the app sends a new mail with the next number", async () => {
    await join(mac(1), "sam@example.com");
    const again = await call("POST", "/v1/start", { device: mac(1) });
    expect(again.json).toEqual({ state: "waiting", email: "sam@example.com", mail: 2 });
    expect(mail.sent).toHaveLength(2);
    expect((await call("POST", "/v1/start", { device: mac(2) })).status).toBe(400);  // no email yet
  });

  it("a page code works once and for 15 minutes", async () => {
    const code = await open(mac(1));
    expect((await call("POST", "/v1/start", { body: { code, email: "sam@example.com" } })).status).toBe(200);
    expect((await call("POST", "/v1/start", { body: { code, email: "sam@example.com" } })).status).toBe(400);
    const twice = await open(mac(1));
    const both = await Promise.all(["sam@example.com", "kim@example.com"].map((email) => call("POST", "/v1/start", { body: { code: twice, email } })));
    expect(both.map((r) => r.status).sort()).toEqual([200, 400]);
    const late = await open(mac(1));
    clock += 15 * 60_000;
    expect((await call("POST", "/v1/start", { body: { code: late, email: "sam@example.com" } })).json).toEqual({ error: "code" });
  });

  it("refuses a bad email and a missing device", async () => {
    const code = await open(mac(1));
    for (const email of ["", "sam", "sam@example", "a b@example.com", `${"a".repeat(250)}@example.com`]) {
      expect((await call("POST", "/v1/start", { body: { code, email } })).json).toEqual({ error: "email" });
    }
    expect((await call("GET", "/v1/status")).status).toBe(401);
    expect((await call("POST", "/v1/open", { device: "short" })).status).toBe(401);
  });

  it("a link lives 1 hour and only for its own mail", async () => {
    await join(mac(1), "sam@example.com");
    clock += 60 * 60_000;
    expect(await confirm(mail.token)).toBe("expired");
    expect(await confirm("not-a-token")).toBe("expired");
    expect(await status(mac(1))).toEqual({ state: "waiting", email: "sam@example.com", mail: 1 });
  });

  it("holds the cap of 100 accounts and puts the rest on the waitlist", async () => {
    await env.DB.batch(Array.from({ length: 99 }, (_, i) =>
      env.DB.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES (?, ?, 'active', 0)").bind(`a${i}`, `p${i}@example.com`)));
    await join(mac(1), "sam@example.com");
    await join(mac(2), "kim@example.com");
    const samLink = mail.sent[0].link, kimLink = mail.sent[1].link;
    expect(await confirm(new URL(samLink).searchParams.get("c")!)).toBe("ok");  // number 100
    expect(await confirm(new URL(kimLink).searchParams.get("c")!)).toBe("full");
    expect(await status(mac(2))).toEqual({ state: "full" });
    expect(await join(mac(3), "lee@example.com")).toEqual({ state: "full" });
    expect(mail.sent).toHaveLength(2);
    expect(await activate(mac(4), "sam@example.com")).toBe("ok");  // an active account still adds a Mac
  });

  it("allows 2 Macs per account; a 3rd stays waiting", async () => {
    expect(await activate(mac(1), "sam@example.com")).toBe("ok");
    expect(await activate(mac(2), "SAM@example.com")).toBe("ok");
    expect(await activate(mac(3), "sam@example.com")).toBe("macs");
    expect(await status(mac(3))).toEqual({ state: "waiting", email: "sam@example.com", mail: 1 });
  });

  it("two Macs that confirm at once cannot pass the limit together", async () => {
    await activate(mac(1), "sam@example.com");
    await join(mac(2), "sam@example.com");
    await join(mac(3), "sam@example.com");
    const [two, three] = mail.sent.slice(1).map((s) => new URL(s.link).searchParams.get("c")!);
    expect((await Promise.all([confirm(two), confirm(three)])).sort()).toEqual(["macs", "ok"]);
  });

  it("an account that is off stays off", async () => {
    await activate(mac(1), "sam@example.com");
    await env.DB.prepare("UPDATE accounts SET off = 1").run();
    expect(await status(mac(1))).toEqual({ state: "off" });
    expect(await join(mac(2), "sam@example.com")).toEqual({ state: "off" });
    await env.DB.prepare("UPDATE accounts SET off = 0").run();
    await join(mac(2), "sam@example.com");
    await env.DB.prepare("UPDATE accounts SET off = 1").run();
    expect(await confirm(mail.token)).toBe("off");
  });

  it("answers busy when the mail cannot go out", async () => {
    mail.busy = true;
    expect(await join(mac(1), "sam@example.com")).toEqual({ state: "busy" });
    expect(await status(mac(1))).toEqual({ state: "locked" });
  });

  it("answers the page from getmypod.app only", async () => {
    const preflight = await call("OPTIONS", "/v1/start", { origin: "https://getmypod.app" });
    expect(preflight.status).toBe(204);
    expect(preflight.headers.get("Access-Control-Allow-Origin")).toBe("https://getmypod.app");
    const other = await call("POST", "/v1/confirm", { origin: "https://evil.example", body: { token: "x" } });
    expect(other.headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect((await call("GET", "/v1/nothing")).status).toBe(404);
  });

  it("stores no device ID, page code or link in plain text", async () => {
    const code = await open(mac(1));
    await call("POST", "/v1/start", { body: { code, email: "sam@example.com" } });
    await open(mac(1));
    const rows = await env.DB.batch(["macs", "mails"].map((t) => env.DB.prepare(`SELECT * FROM ${t}`)));
    const dump = JSON.stringify(rows.map((r) => r.results));
    for (const secret of [mac(1), code, mail.token]) expect(dump).not.toContain(secret);
  });
});
