import { env } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { handle } from "../src/activation";
import { noMail } from "../src/mailer";
import { waitPerHour } from "../src/waitlist";

// CLA-172: POST /v1/waitlist from the beta page.

const page = "https://getmypod.app";
let clock = 1_000_000;
const hour = 60 * 60_000;

async function join(body: unknown, origin = page) {
  const request = new Request("https://api.example/v1/waitlist", { method: "POST", headers: { Origin: origin }, body: JSON.stringify(body) });
  const response = await handle(request, env, { now: () => clock, mailer: noMail, human: async (t: string) => t === "person" });
  return { status: response.status, result: ((await response.json()) as { result: string }).result, headers: response.headers };
}
const accounts = async () =>
  (await env.DB.prepare("SELECT * FROM accounts ORDER BY email").all<Record<string, unknown>>()).results;

beforeEach(async () => {
  clock = 1_000_000;
  await env.DB.batch(["page_tries", "mails", "swaps", "macs", "accounts"].map((t) => env.DB.prepare(`DELETE FROM ${t}`)));
});

describe("POST /v1/waitlist", () => {
  it("puts a new address on the waitlist with its time only", async () => {
    const answer = await join({ email: "  Sam@Example.com ", human: "person" });
    expect(answer).toMatchObject({ status: 200, result: "ok" });
    expect(answer.headers.get("Access-Control-Allow-Origin")).toBe(page);
    expect(await accounts()).toEqual([{ id: expect.any(String), email: "sam@example.com", state: "waitlist", off: 0, created_at: clock, confirmed_at: null, invited_at: null, invite_id: null }]);
    // The try keeps only a hash of the address.
    const tries = (await env.DB.prepare("SELECT * FROM page_tries").all<{ kind: string; key_hash: string }>()).results;
    expect(tries).toEqual([{ kind: "wait", key_hash: expect.stringMatching(/^[0-9a-f]{64}$/), at: clock }]);
  });

  it("answers ok for a known address and changes nothing", async () => {
    await env.DB.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES ('a1', 'kim@example.com', 'active', 5)").run();
    expect((await join({ email: "kim@example.com", human: "person" })).result).toBe("ok");
    expect((await join({ email: "KIM@example.com", human: "person" })).result).toBe("ok");
    expect(await accounts()).toEqual([{ id: "a1", email: "kim@example.com", state: "active", off: 0, created_at: 5, confirmed_at: null, invited_at: null, invite_id: null }]);
  });

  it("checks the bot token first, and fails closed", async () => {
    expect((await join({ email: "not an address", human: "robot" })).result).toBe("bot");
    expect((await join({ email: "sam@example.com" })).result).toBe("bot");
    expect((await join({ email: "sam@example.com", human: 5 })).result).toBe("bot");
    for (const body of ["nonsense", null, 5, [{ email: "sam@example.com", human: "person" }]]) {
      expect((await join(body)).result, JSON.stringify(body)).toBe("bot");
    }
    expect(await accounts()).toEqual([]);
  });

  it("refuses a bad address", async () => {
    for (const email of [undefined, "", "sam", "sam@example", "a b@example.com", `${"x".repeat(250)}@example.com`, 42]) {
      expect((await join({ email, human: "person" })).result, String(email)).toBe("bad");
    }
    expect(await accounts()).toEqual([]);
  });

  it("allows 3 tries an hour per address; more are \"ok\" and write nothing", async () => {
    for (let i = 0; i < waitPerHour; i++) expect((await join({ email: "sam@example.com", human: "person" })).result).toBe("ok");
    const tries = async () => (await env.DB.prepare("SELECT COUNT(*) AS n FROM page_tries").first<{ n: number }>())?.n;
    expect(await tries()).toBe(waitPerHour);
    expect((await join({ email: "sam@example.com", human: "person" })).result).toBe("ok");  // already on the list
    expect(await tries()).toBe(waitPerHour);
    expect((await accounts()).map((a) => a.email)).toEqual(["sam@example.com"]);
    expect((await join({ email: "kim@example.com", human: "person" })).result).toBe("ok");  // another address
    clock += hour;
    expect((await join({ email: "sam@example.com", human: "person" })).result).toBe("ok");
  });

  it("stops at WAIT_DAY tries a day for all addresses, and forgets old tries", async () => {
    const perDay = Number(env.WAIT_DAY);
    await env.DB.batch([...Array(perDay)].map((_, i) =>
      env.DB.prepare("INSERT INTO page_tries (kind, key_hash, at) VALUES ('wait', ?, ?)").bind(`h${i}`, clock - 1000)));
    expect((await join({ email: "sam@example.com", human: "person" })).result).toBe("busy");
    expect(await accounts()).toEqual([]);
    clock += 24 * hour;
    expect((await join({ email: "sam@example.com", human: "person" })).result).toBe("ok");
    clock += 2 * 24 * hour + 1;
    await join({ email: "kim@example.com", human: "person" });
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM page_tries").first<{ n: number }>())?.n).toBe(1);  // older than 2 days: gone
  });
});

describe("POST /v1/waitlist with an invite id (Jason OK 20:29 JST 11-23)", () => {
  const inviteOf = async (email: string) =>
    (await env.DB.prepare("SELECT invite_id FROM accounts WHERE email = ?").bind(email).first<{ invite_id: string | null }>())?.invite_id;

  it("keeps a valid invite id on the new account, in lower case", async () => {
    expect((await join({ email: "sam@example.com", human: "person", invite: "Jason_01" })).result).toBe("ok");
    expect(await inviteOf("sam@example.com")).toBe("jason_01");
  });

  it("ignores an invite id that is not valid", async () => {
    for (const [n, invite] of [["a", ""], ["b", "has space"], ["c", "x".repeat(33)], ["d", "é"], ["e", "a/b"], ["f", 5], ["g", null], ["h", ["x"]]] as const) {
      expect((await join({ email: `${n}@example.com`, human: "person", invite })).result).toBe("ok");
      expect(await inviteOf(`${n}@example.com`), String(invite)).toBeNull();
    }
  });

  it("sets the invite id once and never changes it", async () => {
    await join({ email: "sam@example.com", human: "person", invite: "first" });
    clock += 2 * hour;
    await join({ email: "sam@example.com", human: "person", invite: "second" });
    expect(await inviteOf("sam@example.com")).toBe("first");
    // A known account without one does not get one later.
    await env.DB.prepare("INSERT INTO accounts (id, email, state, created_at) VALUES ('a1', 'kim@example.com', 'waitlist', 5)").run();
    await join({ email: "kim@example.com", human: "person", invite: "late" });
    expect(await inviteOf("kim@example.com")).toBeNull();
  });
});
