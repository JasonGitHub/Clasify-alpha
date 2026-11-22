import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { linkMail, noMail, type SendMail } from "../src/mailer";
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

  it("sends 1 a day per address; a second ask is \"ok\" with no mail and no new row", async () => {
    expect(await ask({ email: "sam@example.com", human: "person" })).toBe("ok");
    expect(await ask({ email: "SAM@example.com", human: "person" })).toBe("ok");  // it already has the mail
    expect(sent).toHaveLength(1);
    expect(await dayCount()).toBe(1);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM page_tries").first<{ n: number }>())?.n).toBe(1);
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

describe("page mails (card CJ)", () => {
  // The same look as the activation link mail: only the words differ.
  const shell = (html: string) => html.replace(/<div class="tx"[^>]*>.*?<\/div>/, "").replace(/<a class="bl"[^>]*>.*?<\/a>/, "")
    .replace(/<div class="ft"[^>]*>.*?<br>/, "");

  it("sends the download link mail with its own words and the link mail's look", () => {
    const m = pageMails.link;
    expect(m.subject).toBe("Your myPod download link");
    expect(m.html).toContain(">Here is the myPod link you asked for.<br>Open it on your Mac to download myPod.</div>");
    expect(m.html).toContain('<a class="bl" href="https://getmypod.app/" style="display:inline-block;line-height:44px;color:#ffffff;font-weight:bold;font-size:17px;text-decoration:none">Get myPod</a>');
    expect(m.html).toContain(">Did not ask for this? You can ignore this mail.<br>myPod by Cappy · © 2026 CappyAI Ltd</div>");
    expect(m.text).toBe("Hi there,\n\nHere is the myPod link you asked for. Open it on your Mac to download myPod.\n\n" +
      "https://getmypod.app/\n\nDid not ask for this? You can ignore this mail.\nmyPod by Cappy · © 2026 CappyAI Ltd");
    expect(shell(m.html)).toBe(shell(linkMail(pageLink).html));
  });

  it("sends the spot mail with its own words and the link mail's look", () => {
    const m = pageMails.spot;
    expect(m.subject).toBe("A myPod beta spot is open");
    expect(m.html).toContain(">Good news: a spot in the myPod beta is open.<br>Spots go fast, so get myPod soon.</div>");
    expect(m.html).toContain('href="https://getmypod.app/"');
    expect(m.html).toContain(">Get myPod</a>");
    expect(m.html).toContain(">You joined the myPod waitlist on getmypod.app.<br>myPod by Cappy · © 2026 CappyAI Ltd</div>");
    expect(m.text).toBe("Hi there,\n\nGood news: a spot in the myPod beta is open. Spots go fast, so get myPod soon.\n\n" +
      "https://getmypod.app/\n\nYou joined the myPod waitlist on getmypod.app.\nmyPod by Cappy · © 2026 CappyAI Ltd");
    expect(shell(m.html)).toBe(shell(linkMail(pageLink).html));
  });

  it("never links the DMG itself", () => {
    for (const m of Object.values(pageMails)) for (const part of [m.text, m.html]) expect(part).not.toContain("dl.getmypod.app");
  });
});
