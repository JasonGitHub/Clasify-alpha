import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle, sha256 } from "../src/activation";
import { claimInvite, emailKey, inviteCap, inviteMailLife, keepInviteMail } from "../src/invitelinks";
import type { Mailer } from "../src/mailer";
import type { PageMailer } from "../src/pagemail";

// CLA-172: "Email me the link" with an invite id (Jason picked B, 20:50 JST 11-23). The id waits
// 30 days for that email to activate, then goes to the account once.

const secret = "test-secret";
let clock = Date.UTC(2026, 10, 23, 12);
const day = 24 * 60 * 60_000;
let pageSends = 0;
const pageMail: PageMailer = { send: async () => { pageSends++; return "sent"; } };
let appLinks: string[] = [];
const mailer: Mailer = { send: async (_to: string, link: string) => { appLinks.push(link); return "sent"; } };

async function call(path: string, body: unknown, device?: string, vars: Partial<Env> = { TURNSTILE_SECRET: secret }) {
  const headers: Record<string, string> = device ? { Authorization: `Device ${device}` } : {};
  const request = new Request(`https://api.example${path}`, { method: "POST", headers, body: JSON.stringify(body) });
  const response = await handle(request, { ...env, ...vars } as Env, { now: () => clock, mailer, pageMail, human: async (t: string) => t === "person" });
  return (await response.json()) as Record<string, unknown>;
}
const ask = (email: string, invite?: unknown, vars?: Partial<Env>) => call("/v1/link", { email, human: "person", invite }, undefined, vars);
/** The app's way in: open, start with the email, then Confirm from the mail. */
async function activate(email: string, device = "device-1".padEnd(40, "x"), vars?: Partial<Env>) {
  const code = (await call("/v1/open", {}, device, vars)).code;
  await call("/v1/start", { code, email, turnstile: "person" }, undefined, vars);
  const token = new URL(appLinks.at(-1)!).searchParams.get("c");
  return (await call("/v1/confirm", { token }, undefined, vars)).result;
}
const rows = async () => (await env.DB.prepare("SELECT * FROM invite_mails").all<Record<string, unknown>>()).results;
const inviteOf = async (email: string) =>
  (await env.DB.prepare("SELECT invite_id FROM accounts WHERE email = ?").bind(email).first<{ invite_id: string | null }>())?.invite_id;

beforeEach(async () => {
  clock = Date.UTC(2026, 10, 23, 12);
  pageSends = 0;
  appLinks = [];
  await env.DB.batch(["invite_mails", "invite_opens", "page_tries", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("Email me the link with an invite id", () => {
  it("keeps only a keyed hash of the email, the id and the time", async () => {
    expect((await ask("  Sam@Example.com ", "Team_1")).result).toBe("ok");
    expect(pageSends).toBe(1);
    const kept = await rows();
    expect(kept).toEqual([{ email_hash: await emailKey("sam@example.com", secret), id: "team_1", at: clock }]);
    expect(kept[0].email_hash).not.toBe(await sha256("sam@example.com"));  // keyed, not the plain hash
    expect(JSON.stringify(kept)).not.toContain("sam");
  });

  it("keeps nothing without a valid id, without the secret, or when the form is refused", async () => {
    await ask("a@example.com");
    await ask("b@example.com", "bad id");
    await ask("c@example.com", "x".repeat(33));
    await ask("d@example.com", "team", { TURNSTILE_SECRET: undefined });
    await call("/v1/link", { email: "e@example.com", human: "robot", invite: "team" });
    await ask("not an address", "team");
    expect(await rows()).toEqual([]);
  });

  it("keeps the first id for an email", async () => {
    await ask("sam@example.com", "first");
    clock += day + 1;
    await ask("sam@example.com", "second");
    expect((await rows()).map((r) => r.id)).toEqual(["first"]);
  });

  it(`ignores a new id past the ${inviteCap}-id cap`, async () => {
    const fill = [...Array(inviteCap)].map((_, i) => env.DB.prepare("INSERT INTO invite_opens (id, count) VALUES (?, 1)").bind(`id${i}`));
    for (let i = 0; i < fill.length; i += 100) await env.DB.batch(fill.slice(i, i + 100));
    await ask("a@example.com", "new-one");
    await ask("b@example.com", "id3");
    expect((await rows()).map((r) => r.id)).toEqual(["id3"]);
  });
});

describe("the id goes to the account when that email activates", () => {
  it("copies the id once and deletes the row", async () => {
    await ask("sam@example.com", "team");
    expect(await activate("Sam@Example.com")).toBe("ok");
    expect(await inviteOf("sam@example.com")).toBe("team");
    expect(await rows()).toEqual([]);
    // A new ask and a second Mac later do not change it.
    clock += day + 1;
    await ask("sam@example.com", "other");
    expect(await activate("sam@example.com", "device-2".padEnd(40, "x"))).toBe("ok");
    expect(await inviteOf("sam@example.com")).toBe("team");
    expect(await rows()).toEqual([]);
  });

  it("never overwrites an id the account already has (from the waitlist)", async () => {
    await env.DB.prepare("INSERT INTO accounts (id, email, state, created_at, invite_id) VALUES ('a1', 'sam@example.com', 'waitlist', 1, 'waitlist-id')").run();
    await ask("sam@example.com", "team");
    expect(await activate("sam@example.com")).toBe("ok");
    expect(await inviteOf("sam@example.com")).toBe("waitlist-id");
    expect(await rows()).toEqual([]);  // used up
  });

  it("does not copy to another email", async () => {
    await ask("sam@example.com", "team");
    expect(await activate("kim@example.com")).toBe("ok");
    expect(await inviteOf("kim@example.com")).toBeNull();
    expect(await rows()).toHaveLength(1);
  });

  it("does not copy after 30 days, and the hourly cron deletes old rows", async () => {
    await ask("sam@example.com", "team");
    await ask("kim@example.com", "team");
    clock += inviteMailLife;
    expect(await activate("sam@example.com")).toBe("ok");
    expect(await inviteOf("sam@example.com")).toBeNull();
    const worker = (await import("../src/index")).default;
    const now = Date.now;
    Date.now = () => clock;
    try {
      await worker.scheduled({} as ScheduledController, { ...env, CAP: "0" } as Env);
    } finally {
      Date.now = now;
    }
    expect(await rows()).toEqual([]);
  });

  it("activates as before when there is no row, no secret, or the copy fails", async () => {
    expect(await activate("a@example.com")).toBe("ok");
    expect(await activate("b@example.com", "device-2".padEnd(40, "x"), { TURNSTILE_SECRET: undefined })).toBe("ok");
    // The copy never throws, so a failing D1 cannot fail a Confirm that already went through.
    const broken = { prepare: env.DB.prepare.bind(env.DB), batch: async () => { throw new Error("D1 down"); } } as unknown as D1Database;
    await expect(claimInvite(broken, "c@example.com", "a1", secret, clock)).resolves.toBeUndefined();
    const failing = { prepare: () => { throw new Error("D1 down"); } } as unknown as D1Database;
    await expect(keepInviteMail(failing, { email: "c@example.com", invite: "team" }, secret, clock)).resolves.toBeUndefined();
  });
});
