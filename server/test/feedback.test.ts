import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { reportsPerDay } from "../src/feedback";
import type { Mailer, ReportMailer } from "../src/mailer";

// CLA-166: Help > Report a Problem.

let clock = 1_000_000;
let links: string[] = [];
let reports: Parameters<ReportMailer["send"]>[0][] = [];
let answer: "sent" | "busy" | "limit" = "sent";
const mailer: Mailer = { send: async (_to, link) => { links.push(link); return "sent"; } };
const reporter: ReportMailer = { send: async (mail) => { if (answer === "sent") reports.push(mail); return answer; } };
const mac = (n: number) => `device-${n}`.padEnd(40, "x");

async function call(path: string, device: string | undefined, body: unknown) {
  const headers: Record<string, string> = device ? { Authorization: `Device ${device}` } : {};
  const request = new Request(`https://api.example${path}`, { method: "POST", headers, body: JSON.stringify(body) });
  const response = await handle(request, env, { now: () => clock, mailer, reports: reporter, human: async () => true });
  return { status: response.status, json: await response.json() as Record<string, unknown> };
}
async function activate(device: string, email: string) {
  const code = (await call("/v1/open", device, {})).json.code;
  await call("/v1/start", undefined, { code, email, turnstile: "x" });
  await call("/v1/confirm", undefined, { token: new URL(links.at(-1)!).searchParams.get("c") });
}
const report = (device: string | undefined, body: Record<string, unknown>) => call("/v1/feedback", device, body);
const full = { text: "The wheel skips.", writeBack: true, appVersion: "1.0", build: "372", macOS: "27.0", macModel: "Mac16,1", service: "Spotify" };

beforeEach(async () => {
  clock = 1_000_000;
  links = []; reports = []; answer = "sent";
  await env.DB.batch(["reports", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("feedback", () => {
  it("mails a report from an active Mac, with the email only for a write-back", async () => {
    await activate(mac(1), "sam@example.com");
    expect(await report(mac(1), full)).toEqual({ status: 200, json: { result: "sent" } });
    expect(reports[0].replyTo).toBe("sam@example.com");
    expect(reports[0].subject).toBe("myPod problem report (build 372)");
    expect(reports[0].text).toMatch(/^The wheel skips\.\n\n---\nWrite back: sam@example\.com\nAccount: \S+\nApp: 1\.0 \(build 372\)\nmacOS: 27\.0\nMac: Mac16,1\nService: Spotify\n$/);
    expect((await report(mac(1), { text: "Again", writeBack: false })).status).toBe(200);
    expect(reports[1].replyTo).toBeUndefined();
    expect(reports[1].text).not.toContain("sam@example.com");
    expect(reports[1].text).toContain("Write back: no\n");
    expect(reports[1].subject).toBe("myPod problem report (build -)");
  });

  it("refuses a Mac that is not active, and no device", async () => {
    expect((await report(undefined, full)).status).toBe(401);
    expect((await report(mac(2), full)).status).toBe(401);  // never seen
    await call("/v1/open", mac(3), {});
    await call("/v1/start", undefined, { code: (await call("/v1/open", mac(3), {})).json.code, email: "kim@example.com", turnstile: "x" });
    expect((await report(mac(3), full)).status).toBe(401);  // waiting for the link
    await activate(mac(1), "sam@example.com");
    await env.DB.prepare("UPDATE accounts SET off = 1").run();
    expect((await report(mac(1), full)).status).toBe(401);  // account turned off
    expect(reports).toHaveLength(0);
  });

  it("takes 1 to 4000 characters of text, and cleans control characters", async () => {
    await activate(mac(1), "sam@example.com");
    for (const text of ["", "   \n ", 42, undefined, "é".repeat(4001)]) {
      expect((await report(mac(1), { ...full, text })).status, String(text).slice(0, 9)).toBe(400);
    }
    expect((await report(mac(1), { ...full, text: "😀".repeat(4000) })).status).toBe(200);
    await report(mac(1), { text: "a\u0000b\r\nc\u001b[31m", build: "1\r\nBcc: x@evil.example", writeBack: false });
    expect(reports.at(-1)!.text.startsWith("ab\nc[31m\n\n---")).toBe(true);
    expect(reports.at(-1)!.subject).toBe("myPod problem report (build 1 Bcc: x@evil.example)");
  });

  it("allows 5 reports a day per account; a report that is not sent does not count", async () => {
    await activate(mac(1), "sam@example.com");
    answer = "busy";
    expect(await report(mac(1), full)).toEqual({ status: 503, json: { error: "busy" } });
    answer = "limit";
    expect(await report(mac(1), full)).toEqual({ status: 429, json: { error: "limit" } });
    answer = "sent";
    for (let i = 0; i < reportsPerDay; i++) expect((await report(mac(1), full)).status).toBe(200);
    expect(await report(mac(1), full)).toEqual({ status: 429, json: { error: "limit" } });
    clock += 24 * 60 * 60_000;
    expect((await report(mac(1), full)).status).toBe(200);
    expect(reports).toHaveLength(reportsPerDay + 1);
  });

  it("keeps no text, device or email in the database", async () => {
    await activate(mac(1), "sam@example.com");
    await report(mac(1), full);
    const rows = await env.DB.prepare("SELECT * FROM reports").all();
    expect(rows.results).toHaveLength(1);
    expect(Object.keys(rows.results[0]).sort()).toEqual(["account_id", "at", "id"]);
  });
});
