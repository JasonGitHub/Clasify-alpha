// Card BX (328-333, 349 two Macs, 350 expired page code): what the page shows for each server answer.
// Pure functions, so the server tests check them. page.js draws them.

/** @typedef {"email" | "sent" | "confirm" | "done" | "full" | "linkExpired" | "pageExpired" | "busy" | "off" | "macs" | "error"} Kind */
/** @typedef {{ kind: Kind, icon: string, title: string, lines: string[][], email?: string }} Screen */

// Each line is a list of parts; the part "@" is the address, in bold.
/** @type {Record<Kind, Omit<Screen, "kind" | "email">>} */
const screens = {
  email: { icon: "", title: "Join the myPod beta", lines: [["Type your email. We’ll send you a link."], ["Click it, and myPod opens up."]] },
  sent: { icon: "mail", title: "Check your mail", lines: [["We sent a link to ", "@", "."], ["Click it to finish. It works for 1 hour."]] },
  confirm: { icon: "", title: "One more click", lines: [["Confirm ", "@"], ["to start the myPod beta."]] },
  done: { icon: "check", title: "You are in", lines: [["Go back to myPod."], ["It’s ready for you. You can close this tab."]] },
  full: { icon: "people", title: "The beta is full", lines: [["Thanks! We saved ", "@", "."], ["We’ll write to you when a spot opens."]] },
  linkExpired: { icon: "clock", title: "This link has expired", lines: [["No problem. Open myPod and"], ["choose “Send again”."]] },
  pageExpired: { icon: "clock", title: "This page has expired", lines: [["No problem. Open myPod and"], ["choose “Open browser again”."]] },
  busy: { icon: "clock", title: "Mail is busy", lines: [["Many people are joining."], ["Please try again later."]] },
  off: { icon: "power", title: "Activation is off", lines: [["Write to us at"], ["feedback@getmypod.app"]] },
  macs: { icon: "macs", title: "Two Macs already", lines: [["This email already runs myPod on two Macs."], ["Write to us at feedback@getmypod.app"]] },
  error: { icon: "cross", title: "That didn’t work", lines: [["No problem, it happens."]] },
};

/** @param {Kind} kind @param {string} [email] @returns {Screen} */
export function screen(kind, email = "") {
  return { kind, ...screens[kind], email };
}

/** The answer to POST /v1/start. null: no connection. @param {Record<string, unknown> | null} answer @param {string} email */
export function fromStart(answer, email) {
  const address = typeof answer?.email === "string" ? answer.email : email;
  if (answer?.error === "code") return screen("pageExpired");
  if (answer?.error === "email") return screen("email");
  const kinds = /** @type {Record<string, Kind>} */ ({ waiting: "sent", active: "done", full: "full", busy: "busy", off: "off" });
  return screen(kinds[String(answer?.state)] ?? "error", address);
}

/** The answer to POST /v1/peek. @param {Record<string, unknown> | null} answer */
export function fromPeek(answer) {
  if (typeof answer?.email === "string") return screen("confirm", answer.email);
  return screen(answer?.result === "expired" ? "linkExpired" : "error");
}

/** The answer to POST /v1/confirm. @param {Record<string, unknown> | null} answer @param {string} email */
export function fromConfirm(answer, email) {
  const kinds = /** @type {Record<string, Kind>} */ ({ ok: "done", expired: "linkExpired", full: "full", macs: "macs", off: "off" });
  return screen(kinds[String(answer?.result)] ?? "error", email);
}

/** What the page opened with: ?d=CODE from the app, ?c=TOKEN from the mail. @param {string} search */
export function opened(search) {
  const query = new URLSearchParams(search);
  const ok = (/** @type {string | null} */ v) => (v && /^[A-Za-z0-9_-]{20,128}$/.test(v) ? v : null);
  const token = ok(query.get("c")), code = ok(query.get("d"));
  return token ? { token } : code ? { code } : {};
}
