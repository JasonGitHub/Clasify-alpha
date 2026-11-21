import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { noMail, type SendMail } from "../src/mailer";
import { pageLink, pageMailer, pageMails, pageReserve, type PageMailer } from "../src/pagemail";

// CLA-172: POST /v1/link ("Email me the link") from the beta page.

const page = "https://getmypod.app";
const hour = 60 * 60_000;
let clock = 1_000_000;
let sent: { to: string; subject: string; text: string }[];
let resendUp: boolean;
const send: SendMail = async (mail) => { if (!resendUp) return false; sent.push(mail); return true; };
const mailer = (): PageMailer => pageMailer(env.DB, send, Number(env.MAIL_DAY), () => clock);

async function ask(body: unknown, pageMail: PageMailer | undefined = mailer()) {
  const request = new Request("https://api.example/v1/link", { method: "POST", headers: { Origin: page }, body: JSON.stringify(body) });
  const response = await handle(request, env, { now: () => clock, mailer: noMail, pageMail, human: async (t: string) => t === "person" });
  return ((await response.json()) as { result: string }).result;
}
const today = () => new Date(clock).toISOString().slice(0, 10);
const dayCount = async () => (await env.DB.prepare("SELECT sent FROM mail_days WHERE day = ?").bind(today()).first<{ sent: number }>())?.sent ?? 0;

beforeEach(async () => {
  clock = 1_000_000;
  sent = [];
  resendUp = true;
  await env.DB.batch(["page_tries", "mail_days", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("POST /v1/link", () => {
  it("sends one mail with the page link, and keeps no email", async () => {
    expect(await ask({ email: " Sam@Example.com", human: "person" })).toBe("ok");
    expect(sent).toEqual([{ to: "sam@example.com", ...pageMails.link }]);
    expect(pageMails.link.text).toContain(pageLink);
    expect(pageMails.link.text).not.toContain("dl.getmypod.app");  // never the DMG
    expect(await dayCount()).toBe(1);
    const rows = (await env.DB.prepare("SELECT kind, key_hash FROM page_tries").all<{ kind: string; key_hash: string }>()).results;
    expect(rows).toEqual([{ kind: "link", key_hash: expect.stringMatching(/^[0-9a-f]{64}$/) }]);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM accounts").first<{ n: number }>())?.n).toBe(0);
  });

  it("checks the bot token first, then the address", async () => {
    expect(await ask({ email: "bad", human: "robot" })).toBe("bot");
    expect(await ask({ email: "sam@example.com" })).toBe("bot");
    expect(await ask({ email: "sam@", human: "person" })).toBe("bad");
    expect(sent).toEqual([]);
  });

  it("sends 1 a day per address", async () => {
    expect(await ask({ email: "sam@example.com", human: "person" })).toBe("ok");
    expect(await ask({ email: "SAM@example.com", human: "person" })).toBe("busy");
    clock += 24 * hour;
    expect(await ask({ email: "sam@example.com", human: "person" })).toBe("ok");
    expect(sent).toHaveLength(2);
  });

  it("sends LINK_DAY mails a day in all", async () => {
    const perDay = Number(env.LINK_DAY);
    for (let i = 0; i < perDay; i++) expect(await ask({ email: `p${i}@example.com`, human: "person" })).toBe("ok");
    expect(await ask({ email: "late@example.com", human: "person" })).toBe("busy");
    expect(sent).toHaveLength(perDay);
  });

  it("stops at MAIL_DAY - 40 mails of the day, so activation keeps its share", async () => {
    const limit = Number(env.MAIL_DAY) - pageReserve;
    await env.DB.prepare("INSERT INTO mail_days (day, sent) VALUES (?, ?)").bind(today(), limit - 1).run();
    expect(await ask({ email: "sam@example.com", human: "person" })).toBe("ok");
    expect(await ask({ email: "kim@example.com", human: "person" })).toBe("busy");
    expect(await dayCount()).toBe(limit);
    expect(await ask({ email: "kim@example.com", human: "person" })).toBe("busy");  // still no room: the refused try did not count
  });

  it("does not count a mail that did not go out", async () => {
    resendUp = false;
    expect(await ask({ email: "sam@example.com", human: "person" })).toBe("busy");
    expect(await ask({ email: "sam@example.com", human: "person" }, undefined)).toBe("busy");  // no mailer at all
    resendUp = true;
    expect(await ask({ email: "sam@example.com", human: "person" })).toBe("ok");
  });
});

describe("test server mails (CLA-172)", () => {
  it("sends nothing but answers sent and counts, only on the test server", async () => {
    const { pageMailFor } = await import("../src/index");
    const live = { ...env, RESEND_KEY: undefined, TEST_SERVER: undefined } as Env;
    expect(await pageMailFor(live, () => clock).send("sam@example.com", "link")).toBe("busy");
    expect(await dayCount()).toBe(0);
    const test = { ...live, TEST_SERVER: "1" } as Env;
    expect(await pageMailFor(test, () => clock).send("sam@example.com", "link")).toBe("sent");
    expect(await dayCount()).toBe(1);  // the same limits as a real send
    await env.DB.prepare("UPDATE mail_days SET sent = ? WHERE day = ?").bind(Number(env.MAIL_DAY) - pageReserve, today()).run();
    expect(await pageMailFor(test, () => clock).send("sam@example.com", "link")).toBe("limit");
  });
});
