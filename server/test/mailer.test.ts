import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { linkMail, linkMailer, resend, type SendMail } from "../src/mailer";

const sent: Parameters<SendMail>[0][] = [];
let resendWorks = true;
const send: SendMail = async (mail) => {
  sent.push(mail);
  return resendWorks;
};
const noon = Date.UTC(2026, 10, 18, 12, 0);  // 21:00 JST
const mailer = (perDay = 3, alertTo: string | undefined = "alert@example.com", now = noon) =>
  linkMailer(env.DB, send, perDay, alertTo, () => now);
const link = "https://getmypod.app/activate/?c=abc";

beforeEach(async () => {
  sent.length = 0;
  resendWorks = true;
  await env.DB.prepare("DELETE FROM mail_days").run();
});

describe("resend", () => {
  it("posts one mail with our sender and reply-to, and the key only in the header", async () => {
    let request: Request | undefined;
    const fake = (async (input: RequestInfo | URL, init?: RequestInit) => {
      request = new Request(input, init);
      return new Response("{}", { status: 200 });
    }) as typeof fetch;
    expect(await resend("re_test", fake)({ to: "sam@example.com", subject: "S", text: "T" })).toBe(true);
    expect(request!.url).toBe("https://api.resend.com/emails");
    expect(request!.headers.get("Authorization")).toBe("Bearer re_test");
    const body = await request!.json();
    expect(body).toEqual({ from: "myPod <hello@getmypod.app>", reply_to: "feedback@getmypod.app", to: ["sam@example.com"], subject: "S", text: "T" });
  });

  it("is busy for any answer that is not 2xx, and for no connection", async () => {
    for (const status of [401, 422, 429, 500]) {
      const fake = (async () => new Response("{}", { status })) as typeof fetch;
      expect(await resend("k", fake)({ to: "a@example.com", subject: "S", text: "T" })).toBe(false);
    }
    const down = (async () => { throw new Error("timeout"); }) as typeof fetch;
    expect(await resend("k", down)({ to: "a@example.com", subject: "S", text: "T" })).toBe(false);
  });
});

describe("link mailer", () => {
  it("sends the link mail of card BX", async () => {
    expect(await mailer().send("sam@example.com", link)).toBe("sent");
    expect(sent[0]).toMatchObject({ to: "sam@example.com", subject: "Your myPod link" });
    expect(sent[0].text).toBe(`Hi there,\n\nClick the button to start the myPod beta. The link works for 1 hour.\n\n${link}\n\n` +
      "Did not ask for this? You can ignore this mail.\nmyPod by Cappy · © 2026 CappyAI Ltd");
    expect(sent[0].html).toContain(`href="${link}"`);
    expect(sent[0].html).toContain(">Confirm my email</a>");
    // Card CD (CLA-160): solid colours only, and our own dark colours where the app reads them.
    expect(sent[0].html).toContain('bgcolor="#e8eef4"');
    expect(sent[0].html).toContain('bgcolor="#1f6fd1"');
    expect(sent[0].html).not.toContain("background-image");
    expect(sent[0].html).not.toContain("gradient");
    expect(sent[0].html).toContain('<meta name="color-scheme" content="light dark">');
    expect(sent[0].html).toContain('<meta name="supported-color-schemes" content="light dark">');
    const dark = sent[0].html!.match(/@media \(prefers-color-scheme: dark\)\{(.*?\})\}/)?.[1] ?? "";
    for (const rule of [".pg{background:#1b1f24!important}", ".tt{color:#f2f4f6!important}", ".tx{color:#a7b1bb!important}",
      ".ft{color:#7a838d!important}", ".bt{background:#2f80e0!important}", ".bl{color:#ffffff!important}"]) expect(dark).toContain(rule);
    for (const cls of ["pg", "tt", "tx", "ft", "bt", "bl"]) expect(sent[0].html).toContain(`class="${cls}"`);
    expect(sent[0].html).not.toContain(">myPod</div>");
    expect(sent[0].html).toContain("font-size:34px");
    expect(linkMail('https://x/?c=a"b').html).toContain('href="https://x/?c=a&quot;b"');
    expect(linkMail("https://x/?c=<b>&d").html).toContain('href="https://x/?c=&lt;b>&amp;d"');
  });

  it("stops at the day limit, sends one alert, and starts again the next day", async () => {
    for (let i = 0; i < 3; i++) expect(await mailer().send(`p${i}@example.com`, link)).toBe("sent");
    expect(await mailer().send("late@example.com", link)).toBe("busy");
    expect(await mailer().send("later@example.com", link)).toBe("busy");
    const alerts = sent.filter((m) => m.to === "alert@example.com");
    expect(alerts).toHaveLength(1);
    expect(alerts[0].subject).toBe("myPod: mail limit hit");
    expect(alerts[0].text).toContain("21:00 JST");
    expect(alerts[0].text).not.toContain("late@example.com");
    const row = await env.DB.prepare("SELECT * FROM mail_days").first();
    expect(row).toEqual({ day: "2026-11-18", sent: 3, refused: 2, failed: 0 });
    expect(await mailer(3, "alert@example.com", noon + 86_400_000).send("next@example.com", link)).toBe("sent");
  });

  it("two sends at once cannot pass the limit, and two refusals send one alert", async () => {
    const results = await Promise.all(Array.from({ length: 6 }, (_, i) => mailer().send(`p${i}@example.com`, link)));
    expect(results.filter((r) => r === "sent")).toHaveLength(3);
    expect(sent.filter((m) => m.to === "alert@example.com")).toHaveLength(1);
  });

  it("a failed mail is busy and alerts once, without the address", async () => {
    resendWorks = false;
    expect(await mailer().send("sam@example.com", link)).toBe("busy");
    expect(await mailer().send("kim@example.com", link)).toBe("busy");
    const alerts = sent.filter((m) => m.to === "alert@example.com");
    expect(alerts.map((m) => m.subject)).toEqual(["myPod: a link mail failed"]);
    expect(alerts[0].text).not.toContain("sam@example.com");
  });

  it("a failure and then the day limit send one alert each", async () => {
    resendWorks = false;
    await mailer(2).send("sam@example.com", link);
    resendWorks = true;
    await mailer(2).send("kim@example.com", link);
    await mailer(2).send("lee@example.com", link);
    await mailer(2).send("ann@example.com", link);
    const alerts = sent.filter((m) => m.to === "alert@example.com").map((m) => m.subject);
    expect(alerts).toEqual(["myPod: a link mail failed", "myPod: mail limit hit"]);
  });

  it("sends no alert when ALERT_TO is not set", async () => {
    resendWorks = false;
    await linkMailer(env.DB, send, 3, undefined, () => noon).send("sam@example.com", link);
    expect(sent.map((m) => m.to)).toEqual(["sam@example.com"]);
  });
});
