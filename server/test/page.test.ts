import { describe, expect, it } from "vitest";
import { fromConfirm, fromPeek, fromStart, opened, screen } from "../public/activate/logic.js";

const words = (s: ReturnType<typeof screen>) => [s.title, ...s.lines.map((l) => l.map((p) => (p === "@" ? s.email : p)).join(""))];

describe("activation page (card BX)", () => {
  it("opens the email step from the app and the confirm step from the mail, and nothing else", () => {
    const code = "A".repeat(43);
    expect(opened(`?d=${code}`)).toEqual({ code });
    expect(opened(`?c=${code}`)).toEqual({ token: code });
    expect(opened("?d=short")).toEqual({});
    expect(opened(`?d=${code}<script>`)).toEqual({});
    expect(opened("")).toEqual({});
  });

  it("shows the card words for each answer to the email step", () => {
    expect(words(screen("email"))).toEqual(["Join the myPod beta", "Type your email. We’ll send you a link.", "Click it, and myPod opens up."]);
    expect(words(fromStart({ state: "waiting", email: "sam@example.com", mail: 1, code: "x" }, "Sam@example.com")))
      .toEqual(["Check your mail", "We sent a link to sam@example.com.", "Click it to finish. It works for 1 hour."]);
    expect(words(fromStart({ state: "full" }, "sam@example.com")))
      .toEqual(["The beta is full", "Thanks! We saved sam@example.com.", "We’ll write to you when a spot opens."]);
    expect(words(fromStart({ state: "busy" }, "a@b.co"))).toEqual(["Mail is busy", "Many people are joining.", "Please try again later."]);
    expect(fromStart({ state: "off" }, "a@b.co").kind).toBe("off");
    expect(fromStart({ state: "active" }, "a@b.co").kind).toBe("done");
    expect(words(fromStart({ error: "code" }, "a@b.co"))).toEqual(["This page has expired", "No problem. Open myPod and", "choose “Open browser again”."]);
    expect(fromStart({ error: "email" }, "a@b.co").kind).toBe("email");
    for (const answer of [null, { error: "bot" }, { state: "locked" }]) {
      expect(words(fromStart(answer, "a@b.co"))).toEqual(["That didn’t work", "No problem, it happens."]);
    }
  });

  it("never confirms on open: peek shows the Confirm step, and the press shows the result", () => {
    expect(words(fromPeek({ email: "sam@example.com" }))).toEqual(["One more click", "Confirm sam@example.com", "to start the myPod beta."]);
    expect(words(fromPeek({ result: "expired" }))).toEqual(["This link has expired", "No problem. Open myPod and", "choose “Send again”."]);
    expect(fromPeek(null).kind).toBe("error");
    expect(words(fromConfirm({ result: "ok" }, "sam@example.com"))).toEqual(["You’re in", "Go back to myPod.", "It’s ready for you. You can close this tab."]);
    expect(words(fromConfirm({ result: "macs" }, "sam@example.com")))
      .toEqual(["Two Macs already", "This email already runs myPod on two Macs.", "Write to us at feedback@getmypod.app"]);
    expect(words(fromConfirm({ result: "off" }, "s@e.co"))).toEqual(["Activation is off", "Write to us at", "feedback@getmypod.app"]);
    expect(fromConfirm({ result: "full" }, "s@e.co").kind).toBe("full");
    expect(fromConfirm({ result: "expired" }, "s@e.co").kind).toBe("linkExpired");
    expect(fromConfirm(null, "s@e.co").kind).toBe("error");
  });
});
