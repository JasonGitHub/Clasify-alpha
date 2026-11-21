import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { forgetBeta } from "../src/beta";
import type { Mailer } from "../src/mailer";
import type { PageMailer } from "../src/pagemail";
import { inviteOpen, openSpots, spotsPerRun } from "../src/spots";

// CLA-172: the open-spot mails (hourly cron).

const now = 10_000_000_000;
let sent: string[];
let answer: (n: number) => "sent" | "busy" | "limit";
const mailer: PageMailer = {
  async send(to, kind) {
    expect(kind).toBe("spot");
    const result = answer(sent.length);
    if (result === "sent") sent.push(to);
    return result;
  },
};

async function add(id: string, state: string, created: number, extra: { invited?: number; off?: number } = {}) {
  await env.DB.prepare("INSERT INTO accounts (id, email, state, off, created_at, invited_at) VALUES (?, ?, ?, ?, ?, ?)")
    .bind(id, `${id}@example.com`, state, extra.off ?? 0, created, extra.invited ?? null).run();
}
async function actives(n: number) { for (let i = 0; i < n; i++) await add(`active${i}`, "active", i); }
const invited = async () => (await env.DB.prepare("SELECT id FROM accounts WHERE invited_at IS NOT NULL ORDER BY id").all<{ id: string }>())
  .results.map((r) => r.id);

beforeEach(async () => {
  sent = [];
  answer = () => "sent";
  await env.DB.batch(["page_tries", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("open-spot mails", () => {
  it("mails the oldest waitlist people for the free spots, once", async () => {
    await actives(22);
    for (const [id, at] of [["w3", 30], ["w1", 10], ["w4", 40], ["w2", 20]] as const) await add(id, "waitlist", at);
    expect(await openSpots(env.DB, 25, mailer, now)).toBe(3);
    expect(sent).toEqual(["w1@example.com", "w2@example.com", "w3@example.com"]);
    expect(await invited()).toEqual(["w1", "w2", "w3"]);
    expect(await openSpots(env.DB, 25, mailer, now + 3_600_000)).toBe(0);  // the 3 invites are still open
  });

  it("counts open invites for 7 days, until the account is active", async () => {
    await actives(23);
    await add("old", "waitlist", 1, { invited: now - inviteOpen - 1 });  // over 7 days: no longer counts
    await add("open", "pending", 2, { invited: now - 1000 });  // joined in the app, not active yet: counts
    await add("done", "active", 3, { invited: now - 1000 });  // counted once, as active
    await add("next", "waitlist", 4);
    // 25 - 24 active - 1 open = 0
    expect(await openSpots(env.DB, 25, mailer, now)).toBe(0);
    await env.DB.prepare("UPDATE accounts SET invited_at = ? WHERE id = 'open'").bind(now - inviteOpen).run();
    expect(await openSpots(env.DB, 25, mailer, now)).toBe(1);
    expect(sent).toEqual(["next@example.com"]);
  });

  it("skips accounts that are off, active, pending or already invited", async () => {
    await add("off", "waitlist", 1, { off: 1 });
    await add("pending", "pending", 2);
    await add("asked", "waitlist", 3, { invited: now - inviteOpen - 1 });
    await add("ok", "waitlist", 4);
    expect(await openSpots(env.DB, 25, mailer, now)).toBe(1);
    expect(sent).toEqual(["ok@example.com"]);
  });

  it("sends at most 10 a run", async () => {
    for (let i = 0; i < 15; i++) await add(`w${String(i).padStart(2, "0")}`, "waitlist", i);
    expect(await openSpots(env.DB, 25, mailer, now)).toBe(spotsPerRun);
    expect(sent).toHaveLength(10);
    expect(await openSpots(env.DB, 25, mailer, now + 1)).toBe(5);  // the next run: 25 - 10 open = 15 free
  });

  it("does nothing when full or over the cap", async () => {
    await actives(25);
    await add("w", "waitlist", 1);
    expect(await openSpots(env.DB, 25, mailer, now)).toBe(0);
    expect(await openSpots(env.DB, 20, mailer, now)).toBe(0);
    expect(await invited()).toEqual([]);
  });

  it("never mails more people than free spots, even when two runs overlap", async () => {
    await actives(24);
    await add("w1", "waitlist", 1);
    await add("w2", "waitlist", 2);
    const runs = await Promise.all([openSpots(env.DB, 25, mailer, now), openSpots(env.DB, 25, mailer, now)]);
    expect(runs[0] + runs[1]).toBe(1);
    expect(sent).toEqual(["w1@example.com"]);
    expect(await invited()).toEqual(["w1"]);
  });

  it("gives the spot back to the waitlist when a mail does not go out", async () => {
    await actives(20);
    for (let i = 1; i <= 4; i++) await add(`w${i}`, "waitlist", i);
    answer = (n) => (n < 2 ? "sent" : "limit");  // the day's mail limit after 2
    expect(await openSpots(env.DB, 25, mailer, now)).toBe(2);
    expect(await invited()).toEqual(["w1", "w2"]);
    answer = () => "sent";
    expect(await openSpots(env.DB, 25, mailer, now + 1)).toBe(2);
    expect(sent).toEqual(["w1@example.com", "w2@example.com", "w3@example.com", "w4@example.com"]);
  });

  it("runs from the hourly cron with the page mailer", async () => {
    const worker = (await import("../src/index")).default;
    await add("w", "waitlist", 1);
    await worker.scheduled({} as ScheduledController, { ...env, RESEND_KEY: undefined, TEST_SERVER: undefined } as Env);
    expect(await invited()).toEqual([]);  // live with no RESEND_KEY: busy, so the spot waits
    await worker.scheduled({} as ScheduledController, { ...env, RESEND_KEY: undefined, TEST_SERVER: "1" } as Env);
    expect(await invited()).toEqual(["w"]);  // the test server's mailer answers sent
  });
});

describe("the whole path (CLA-172)", () => {
  it("joins from the page, gets the spot mail, activates in the app, and the one account is active", async () => {
    let clock = now;
    const links: string[] = [];
    const mail: Mailer = { send: async (_to, link) => { links.push(link); return "sent"; } };
    const call = async (path: string, body?: unknown, device?: string) => {
      const headers: Record<string, string> = { Origin: "https://getmypod.app" };
      if (device) headers.Authorization = `Device ${device}`;
      const request = new Request(`https://api.example${path}`, { method: body === undefined ? "GET" : "POST", headers, body: body === undefined ? undefined : JSON.stringify(body) });
      const response = await handle(request, env, { now: () => clock, mailer: mail, human: async (t: string) => t === "person", fetcher: async () => new Response("", { status: 404 }) });
      return (await response.json()) as Record<string, unknown>;
    };
    await actives(24);  // one spot left

    // 1. The page: the person joins the waitlist.
    expect(await call("/v1/waitlist", { email: "Sam@Example.com", human: "person" })).toEqual({ result: "ok" });
    // 2. The cron: one spot is free, so Sam gets the spot mail.
    clock += 60 * 60_000;
    expect(await openSpots(env.DB, Number(env.CAP), mailer, clock)).toBe(1);
    expect(sent).toEqual(["sam@example.com"]);
    // 3. The app: Sam opens the page with the Mac's code, types the same email, and confirms.
    clock += 60_000;
    const device = "device-sam".padEnd(40, "x");
    const { code } = await call("/v1/open", {}, device);
    expect(await call("/v1/start", { code, email: "sam@example.com", turnstile: "person" }))
      .toMatchObject({ state: "waiting", email: "sam@example.com" });
    const token = new URL(links.at(-1)!).searchParams.get("c");
    expect(await call("/v1/confirm", { token })).toEqual({ result: "ok" });
    // 4. Active, not full, and still one account for the address.
    expect(await call("/v1/status", undefined, device)).toMatchObject({ state: "active" });
    const rows = (await env.DB.prepare("SELECT state, invited_at FROM accounts WHERE email = 'sam@example.com'").all()).results;
    expect(rows).toEqual([{ state: "active", invited_at: now + 60 * 60_000 }]);
    forgetBeta();
    expect(await call("/v1/beta")).toMatchObject({ taken: 25, cap: 25, full: true });
    // The next run has no free spot.
    expect(await openSpots(env.DB, Number(env.CAP), mailer, clock + 60 * 60_000)).toBe(0);
  });
});
