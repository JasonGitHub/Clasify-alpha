/// <reference types="vite/client" />
import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { paidLink, paidMail, paidMailer } from "../src/paidmail";

// CLA-175: the "myPod is yours" mail (card CN).

const files = Object.keys(import.meta.glob("../public/mail/*.png"));
const urls = (s: string) => [...s.matchAll(/https?:\/\/[^\s"'<)]+/g)].map((m) => m[0]);

describe("the mail", () => {
  it("says the PAID_MACS number in the text and the HTML, and nothing else changes with it", () => {
    for (const n of [3, 5]) {
      const mail = paidMail(n);
      expect(mail.subject).toBe("myPod is yours");
      expect(mail.html).toContain(`On up to ${n} Macs.`);
      expect(mail.html).toContain(`ADMIT<br>·<br>${n}<br>MACS`);
      expect(mail.text).toContain(`On up to ${n} Macs.`);
    }
    expect(paidMail(5).html.replaceAll("5", "3")).toBe(paidMail(3).html.replaceAll("5", "3"));
  });

  it("has the approved words in both parts, and no price or refund text", () => {
    const { text, html } = paidMail(3);
    for (const words of ["YOUR MYPOD TICKET", "Thank you!", "It’s yours.", "Download myPod", "Download myPod.", "Open it and type this email.",
      "Open the link we send you. You’re in.", "This is an early version of myPod.", "The full release comes to you at no extra cost.",
      "Questions? Just reply to this mail.", "myPod by Cappy · © 2026 CappyAI Ltd"]) {
      expect(text).toContain(words);
      expect(html).toContain(words);
    }
    for (const part of [text, html]) expect(part).not.toMatch(/refund|\$|€|£|¥|price/i);
  });

  it("links only the beta page and our own two images, and both images exist", () => {
    const { text, html } = paidMail(3);
    expect(paidLink).toBe("https://getmypod.app/beta");
    expect(new Set(urls(html))).toEqual(new Set([paidLink, "https://getmypod.app/mail/mypod-logo.png", "https://getmypod.app/mail/cappy-boba-240.png"]));
    expect(urls(text)).toEqual([paidLink]);
    expect(files.sort()).toEqual(["../public/mail/cappy-boba-240.png", "../public/mail/mypod-logo.png"]);
  });
});

describe("the mailer", () => {
  let sent: Record<string, unknown>[];
  beforeEach(async () => {
    sent = [];
    await env.DB.prepare("DELETE FROM mail_days").run();
  });
  const send = async (mail: Record<string, unknown>) => { sent.push(mail); return true; };

  it("sends to the buyer only, and the mail holds nothing about them but the To address", async () => {
    expect(await paidMailer(env.DB, send, 95, 3, () => 0).send("pat@example.com")).toBe("sent");
    expect(sent).toEqual([{ to: "pat@example.com", ...paidMail(3) }]);
    expect(JSON.stringify(paidMail(3))).not.toContain("pat");
  });

  it("shares the day count and stops where the page mails stop", async () => {
    const mailer = paidMailer(env.DB, send, 42, 3, () => 0);  // 42 - 40 = 2 a day
    expect(await mailer.send("a@example.com")).toBe("sent");
    expect(await mailer.send("b@example.com")).toBe("sent");
    expect(await mailer.send("c@example.com")).toBe("busy");
    expect(await paidMailer(env.DB, async () => false, 95, 3, () => 0).send("d@example.com")).toBe("busy");
  });
});
