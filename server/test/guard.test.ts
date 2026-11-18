import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import type { Mailer } from "../src/mailer";
import { turnstile } from "../src/turnstile";

let clock = 1_000_000;
let sent = 0;
const mailer: Mailer = { send: async () => (sent++, "sent") };
const hour = 3_600_000;
const mac = (n: number) => `guard-${n}`.padEnd(40, "x");

async function call(path: string, opts: { device?: string; body?: object }) {
  const headers: Record<string, string> = opts.device ? { Authorization: `Device ${opts.device}` } : {};
  const request = new Request(`https://api.example${path}`, { method: "POST", headers, body: opts.body ? JSON.stringify(opts.body) : undefined });
  const response = await handle(request, env, { now: () => clock, mailer, human: async (t) => t === "person" });
  return { status: response.status, json: await response.json() as Record<string, unknown> };
}
async function status(device: string) {
  const request = new Request("https://api.example/v1/status", { headers: { Authorization: `Device ${device}` } });
  return (await handle(request, env, { now: () => clock, mailer, human: async () => true })).json();
}
async function join(device: string, email: string, bot = "person") {
  const code = (await call("/v1/open", { device })).json.code;
  return (await call("/v1/start", { body: { code, email, turnstile: bot } })).json;
}

beforeEach(async () => {
  clock = 1_000_000;
  sent = 0;
  await env.DB.batch(["mails", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("mail limits", () => {
  it("allows 3 link mails an hour to one address, from any Mac", async () => {
    for (const n of [1, 2, 3]) expect((await join(mac(n), "sam@example.com")).state).toBe("waiting");
    expect(await join(mac(4), "sam@example.com")).toEqual({ state: "busy" });
    expect(sent).toBe(3);
    expect(await status(mac(4))).toEqual({ state: "busy" });  // the app sees "Mail is busy"
    await call("/v1/start", { device: mac(1) });  // Send again over the limit
    expect(await status(mac(1))).toMatchObject({ state: "waiting", mail: 1 });  // its mail is still out
    clock += hour;
    expect((await join(mac(4), "sam@example.com")).state).toBe("waiting");
  });

  it("allows 3 an hour and 5 a day from one Mac, Send again included", async () => {
    await join(mac(1), "sam@example.com");
    await call("/v1/start", { device: mac(1) });
    await join(mac(1), "kim@example.com");
    expect(await call("/v1/start", { device: mac(1) })).toMatchObject({ json: { state: "busy" } });
    clock += hour;
    await join(mac(1), "lee@example.com");
    await join(mac(1), "ann@example.com");
    clock += hour;
    expect(await join(mac(1), "bo@example.com")).toEqual({ state: "busy" });
    expect(sent).toBe(5);
    clock += 24 * hour;
    expect((await join(mac(1), "bo@example.com")).state).toBe("waiting");
  });

  it("starts at the same time cannot pass the limit", async () => {
    const codes = await Promise.all([1, 2, 3, 4, 5].map(async (n) => (await call("/v1/open", { device: mac(n) })).json.code));
    const answers = await Promise.all(codes.map((code) => call("/v1/start", { body: { code, email: "sam@example.com", turnstile: "person" } })));
    expect(answers.filter((a) => a.json.state === "waiting")).toHaveLength(3);
    expect(sent).toBe(3);
  });
});

describe("bot check", () => {
  it("refuses a page start without a person and keeps the page code", async () => {
    const code = (await call("/v1/open", { device: mac(1) })).json.code;
    expect(await call("/v1/start", { body: { code, email: "sam@example.com", turnstile: "bot" } })).toEqual({ status: 400, json: { error: "bot" } });
    expect(await call("/v1/start", { body: { code, email: "sam@example.com" } })).toEqual({ status: 400, json: { error: "bot" } });
    expect((await call("/v1/start", { body: { code, email: "sam@example.com", turnstile: "person" } })).json.state).toBe("waiting");
    expect(sent).toBe(1);
  });

  it("asks Cloudflare with the secret and the token only, and needs success for getmypod.app", async () => {
    let body = "";
    const answer = (json: object, status = 200) => (async (_: RequestInfo | URL, init?: RequestInit) => {
      body = String(init?.body);
      return new Response(JSON.stringify(json), { status });
    }) as typeof fetch;
    expect(await turnstile("sec", answer({ success: true, hostname: "getmypod.app" }))("tok")).toBe(true);
    expect(new URLSearchParams(body).toString()).toBe("secret=sec&response=tok");
    expect(await turnstile("sec", answer({ success: true, hostname: "evil.example" }))("tok")).toBe(false);
    expect(await turnstile("sec", answer({ success: false, hostname: "getmypod.app" }))("tok")).toBe(false);
    expect(await turnstile("sec", answer({ success: true, hostname: "getmypod.app" }, 500))("tok")).toBe(false);
    expect(await turnstile("sec", (async () => { throw new Error("timeout"); }) as typeof fetch)("tok")).toBe(false);
    let asked = false;
    const never = (async () => { asked = true; return new Response("{}"); }) as typeof fetch;
    expect(await turnstile(undefined, never)("tok")).toBe(false);
    expect(asked).toBe(false);
  });
});
