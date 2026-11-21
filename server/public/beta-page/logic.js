// CLA-172: what the beta page shows for the answer of GET /v1/beta. Pure functions, so the
// server tests check them. page.js draws them; the look is the frozen page's.

/** @typedef {{ taken: number, cap: number, full: boolean, build: number | null, url: string | null }} Beta */
/** @typedef {{ kind: "limited" | "bar" | "full" | "none", taken: number, cap: number, width: number }} Spots */
/** @typedef {{ full: boolean, soon: boolean, form: "none" | "link" | "waitlist", download: string | null, version: string | null, spots: Spots }} View */

/** The live host. Any other host is a test address. */
export const liveHost = "getmypod.app";

/**
 * Where the API is: its own host on getmypod.app, the page's own origin on a test address.
 * @param {string} hostname
 */
export function apiBase(hostname) {
  return hostname === liveHost ? "https://api.getmypod.app" : "";
}

/**
 * The Turnstile site key (public): the real one on getmypod.app; on any other host, Cloudflare's
 * documented always-pass test key. That is safe: the live server's secret refuses test tokens.
 * @param {string} hostname
 */
export function siteKey(hostname) {
  return hostname === liveHost ? "0x4AAAAAAGIRWYxmCoZOyxc0" : "1x00000000000000000000AA";
}

/** Under this many taken spots the page says "Limited to N testers." with no bar. */
export const barFrom = 8;
/** The cap the page names while it has no answer. */
export const defaultCap = 25;

/**
 * The DMG link, only when it is https on exactly dl.getmypod.app with a file path (the same
 * rule as the app's BetaDownload.url and the Worker). Anything else gives null: no dead link.
 * @param {unknown} value
 * @returns {string | null}
 */
export function dmgURL(value) {
  if (typeof value !== "string") return null;
  let u;
  try { u = new URL(value); } catch { return null; }
  if (u.protocol !== "https:" || u.hostname !== "dl.getmypod.app" || u.username || u.password || u.port) return null;
  if (u.pathname.length <= 1) return null;
  return u.href;
}

/**
 * The answer, or null when it is not a good one.
 * @param {unknown} json
 * @returns {Beta | null}
 */
export function parseBeta(json) {
  if (!json || typeof json !== "object") return null;
  const j = /** @type {Record<string, unknown>} */ (json);
  const count = (/** @type {unknown} */ v) => typeof v === "number" && Number.isInteger(v) && v >= 0;
  if (!count(j.taken) || !count(j.cap) || /** @type {number} */ (j.cap) === 0) return null;
  const taken = /** @type {number} */ (j.taken), cap = /** @type {number} */ (j.cap);
  const build = count(j.build) && /** @type {number} */ (j.build) > 0 ? /** @type {number} */ (j.build) : null;
  const url = dmgURL(j.url);
  return { taken, cap, full: j.full === true || taken >= cap, build: build && url ? build : null, url: build && url ? url : null };
}

/**
 * What the page shows. `beta` is null with no answer (offline, an error, a bad answer).
 * `phone` is a phone or touch screen: it gets "Email me the link" in place of the download.
 * @param {Beta | null} beta
 * @param {boolean} phone
 * @returns {View}
 */
export function view(beta, phone) {
  // No answer, or no public build: "The download is on its way", with no button and no form.
  if (!beta) return { full: false, soon: true, form: "none", download: null, version: null, spots: { kind: "limited", taken: 0, cap: defaultCap, width: 0 } };
  const { taken, cap } = beta;
  if (beta.full) return { full: true, soon: false, form: "waitlist", download: null, version: null, spots: { kind: "full", taken: cap, cap, width: 100 } };
  const spots = taken < barFrom ? { kind: /** @type {const} */ ("limited"), taken, cap, width: 0 }
    : { kind: /** @type {const} */ ("bar"), taken, cap, width: Math.min(100, (taken / cap) * 100) };
  const version = beta.build && beta.url ? `Beta ${beta.build}` : null;
  if (!version) return { full: false, soon: true, form: "none", download: null, version: null, spots };
  if (phone) return { full: false, soon: false, form: "link", download: null, version, spots };
  return { full: false, soon: false, form: "none", download: beta.url, version, spots };
}

/** @typedef {"waitlist" | "link"} FormKind */
/** @typedef {"ok" | "busy" | "bot" | "bad" | "offline"} FormState */

/** The line each answer shows in the form. "ok" hides the field and the button. */
export const formWords = {
  ok: { waitlist: "You’re on the list. We’ll write to you.", link: "Sent. Open it on your Mac." },
  busy: "Lots of people are writing right now. Please try again in a few minutes.",
  bot: "We couldn’t check that you’re a person. Please try again.",
  bad: "Please check your email address.",
  offline: "No connection. Please try again.",
};

/**
 * One state for each answer of POST /v1/waitlist or /v1/link. No answer, or one the page does
 * not know, is "offline": the person can try again.
 * @param {unknown} answer
 * @returns {FormState}
 */
export function formState(answer) {
  const r = answer && typeof answer === "object" ? /** @type {Record<string, unknown>} */ (answer).result : undefined;
  return r === "ok" || r === "busy" || r === "bot" || r === "bad" ? r : "offline";
}

/**
 * The words for a state.
 * @param {FormState} state
 * @param {FormKind} kind
 */
export function formLine(state, kind) {
  return state === "ok" ? formWords.ok[kind] : formWords[state];
}

/** The path each form sends to. */
export const formPath = { waitlist: "/v1/waitlist", link: "/v1/link" };

/** Vote items by their card title on the page (the website thread's list). "Something else?" is a mail link, not a vote. */
export const voteItems = /** @type {const} */ ({
  "Your own music files": "local-music", "Nano": "nano", "Radio": "radio", "Like from the wheel": "like-from-wheel", "More colors": "more-colors",
});
/** @typedef {typeof voteItems[keyof typeof voteItems]} VoteItem */

/** The localStorage key for this browser's votes: one vote per item per browser. */
export const votesStore = "mypod.votes";

/**
 * The items this browser voted for, from the stored text. Anything else is dropped.
 * @param {string | null} raw
 * @returns {Set<VoteItem>}
 */
export function votedFrom(raw) {
  /** @type {readonly string[]} */
  const known = Object.values(voteItems);
  try {
    const list = JSON.parse(raw ?? "[]");
    return new Set(Array.isArray(list) ? list.filter((i) => known.includes(i)) : []);
  } catch {
    return new Set();
  }
}

/**
 * The stored text with one more vote.
 * @param {string | null} raw
 * @param {VoteItem} item
 */
export function withVote(raw, item) {
  return JSON.stringify([...votedFrom(raw).add(item)].sort());
}

/**
 * The answer of POST /v1/vote. See `voteKept` for which answers keep the vote.
 * @param {unknown} answer
 * @returns {"ok" | "busy" | "bad" | "offline"}
 */
export function voteState(answer) {
  const r = answer && typeof answer === "object" ? /** @type {{ result?: unknown }} */ (answer).result : undefined;
  return r === "ok" || r === "busy" || r === "bad" ? r : "offline";
}

/**
 * Whether the vote stays on. "busy" means this network already voted for this item today
 * (the same person after clearing the browser, or a second person in one office): the vote
 * is counted, so the button stays on. "bad" and no answer give the button back.
 * @param {"ok" | "busy" | "bad" | "offline"} state
 */
export function voteKept(state) {
  return state === "ok" || state === "busy";
}

export const voteWords = { idle: "I’d love this", voted: "Thanks, noted" };

/** How long a send waits for the bot check, a challenge the person ignores included. */
export const humanWait = 60_000;

/**
 * `promise`'s value, or `fallback` when it fails or takes longer than `ms`.
 * @template T, F
 * @param {Promise<T>} promise
 * @param {number} ms
 * @param {F} fallback
 * @returns {Promise<T | F>}
 */
export function withLimit(promise, ms, fallback) {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(fallback), ms);
    promise.then((v) => { clearTimeout(timer); resolve(v); }, () => { clearTimeout(timer); resolve(fallback); });
  });
}
