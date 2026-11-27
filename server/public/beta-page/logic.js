// CLA-172: what the beta page shows for the answer of GET /v1/beta. Pure functions, so the
// server tests check them. page.js draws them; the look is the frozen page's.

/** @typedef {{ taken: number, cap: number, full: boolean, build: number | null, url: string | null }} Beta */
/** @typedef {{ kind: "limited" | "bar" | "full", taken: number, cap: number, width: number }} Spots */

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
export const barFrom = 18;
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

/** @typedef {"waitlist" | "link"} FormKind */
/** @typedef {"loading" | "open" | "full" | "soon"} PageState */
/**
 * What the page shows: the body class that picks the layout (with the CSS phone query), and the
 * live parts. The server writes it into the page (src/page.ts) and page.js draws it, through
 * the same `edits`, so the two cannot differ.
 * @typedef {{ state: PageState, kind: FormKind, download: string | null, version: string, spotsClass: string, spots: string }} Fill
 */

/** The body classes of the four states; exactly one is on. */
export const pageStates = /** @type {const} */ (["loading", "open", "full", "soon"]);

/**
 * The count line and the bar. The bar is an SVG whose width is an attribute, so the CSP needs
 * no style attribute, and the server can write it.
 * @param {Spots} s
 */
export function spotsHTML(s) {
  if (s.kind === "limited") return `<p><b>Limited to ${s.cap} testers.</b></p>`;
  const width = `${Number(s.width.toFixed(2))}%`;
  return `<p><b>${s.taken} of ${s.cap}</b> beta spots taken</p><div class="bar"><svg width="100%" height="8" aria-hidden="true">`
    + `<defs><linearGradient id="bf" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#86c3fb"/><stop offset=".49" stop-color="#4a98ec"/>`
    + `<stop offset=".51" stop-color="#3083e3"/><stop offset="1" stop-color="#2a76d8"/></linearGradient></defs>`
    + `<rect width="${width}" height="8" rx="4" fill="url(#bf)"/></svg></div>`;
}

/**
 * @param {PageState} state
 * @param {FormKind} kind
 * @param {string | null} download
 * @param {string} version
 * @param {Spots} spots
 * @returns {Fill}
 */
function make(state, kind, download, version, spots) {
  return { state, kind, download, version, spotsClass: spots.kind === "full" ? "spots full" : "spots", spots: spotsHTML(spots) };
}

/**
 * The page before the answer: the open state, invisible (body.loading), so the rows keep their
 * final size. No link: the button gets its href only from an answer. This is the static page.
 * @returns {Fill}
 */
export function loadingFill() {
  return make("loading", "link", null, "Beta", { kind: "bar", taken: 0, cap: defaultCap, width: 0 });
}

/**
 * The page for an answer of GET /v1/beta; `beta` is null with no answer, an error or a bad answer.
 * - open: the Download button (desktop) or "Email me the link" (phone, by CSS), "Beta N", the count.
 * - full: the waitlist form on every screen.
 * - soon: no answer, or no public build: "The download is on its way", no button, no form.
 * @param {Beta | null} beta
 * @returns {Fill}
 */
export function fill(beta) {
  if (!beta) return make("soon", "link", null, "", { kind: "limited", taken: 0, cap: defaultCap, width: 0 });
  const { taken, cap } = beta;
  if (beta.full) return make("full", "waitlist", null, "", { kind: "full", taken: cap, cap, width: 100 });
  /** @type {Spots} */
  const spots = taken < barFrom ? { kind: "limited", taken, cap, width: 0 } : { kind: "bar", taken, cap, width: Math.min(100, (taken / cap) * 100) };
  if (!beta.build || !beta.url) return make("soon", "link", null, "", spots);
  return make("open", "link", beta.url, `Beta ${beta.build}`, spots);
}

/**
 * The changes one fill makes to the page, for both the server (HTMLRewriter) and page.js (DOM).
 * `value` null removes the attribute; `classes` swaps the state class and keeps the others.
 * @param {Fill} f
 * @returns {{ selector: string, attr?: string, value?: string | null, text?: string, html?: string, state?: PageState }[]}
 */
export function edits(f) {
  return [
    { selector: "body", state: f.state },
    { selector: ".row > a.cta", attr: "href", value: f.download },
    { selector: ".row > .bver b", text: f.version },
    { selector: "#wl button", text: f.kind === "waitlist" ? "Save me a spot" : "Email me the link" },
    { selector: "#wl .ok", text: formLine("ok", f.kind) },
    { selector: "#spots", attr: "class", value: f.spotsClass },
    { selector: "#spots", html: f.spots },
  ];
}

/**
 * The body class after a state change: the other state classes go, the rest stays.
 * @param {string} classes
 * @param {PageState} state
 */
export function withState(classes, state) {
  /** @type {readonly string[]} */
  const states = pageStates;
  return [...classes.split(/\s+/).filter((c) => c && !states.includes(c)), state].join(" ");
}

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

/**
 * An invite id (getmypod.app/beta?invite=<id>, Jason OK 20:29 JST 11-23): lower case a-z, 0-9, _ and -,
 * 1 to 32 characters, after lower-casing. Anything else is null and ignored. The server uses the same rule.
 * @param {unknown} value
 * @returns {string | null}
 */
export function inviteID(value) {
  if (typeof value !== "string") return null;
  const id = value.toLowerCase();
  return /^[a-z0-9_-]{1,32}$/.test(id) ? id : null;
}

/**
 * CLA-193: the short links (Jason OK 22:25 and 22:27 JST 11-25). Two kinds of link, each with its
 * own key, so they cannot collide:
 * - getmypod.app/r/<name> for any Reddit name: letters, digits and _, 2 to 21 characters. Key "r/<name>",
 *   lower case.
 * - getmypod.app/<word> for the plain words below. Key "<word>". The one list: add a word here.
 */
export const linkWords = /** @type {const} */ (["hn", "x"]);

/**
 * A short link key ("hn", "r/ipodclassic"), after lower-casing, or null for anything else.
 * @param {unknown} value
 * @returns {string | null}
 */
export function linkKey(value) {
  if (typeof value !== "string") return null;
  const key = value.toLowerCase();
  if (/^r\/[a-z0-9_]{2,21}$/.test(key)) return key;
  return /** @type {readonly string[]} */ (linkWords).includes(key) ? key : null;
}

/** Where a Download press from a short link is counted (CLA-193). */
export const linkDownloadPath = "/v1/link-download";

/**
 * The page address without its ?from= (CLA-193). The rest of the query and the hash stay.
 * @param {string} path
 * @param {string} search
 * @param {string} hash
 */
export function withoutFrom(path, search, hash) {
  const query = new URLSearchParams(search);
  query.delete("from");
  const rest = query.toString();
  return path + (rest ? "?" + rest : "") + hash;
}

/**
 * The invite welcome card (Jason OK 02:19 JST 11-24): which one a page with `invite` (inviteID's
 * result) and the page state shows. None without a valid id or while the page loads; "full" for a
 * full beta; else "open". The card never shows the id, and an invite does not skip the spots limit.
 * @param {string | null} invite
 * @param {string} classes the body's classes
 * @returns {"open" | "full" | null}
 */
export function inviteCard(invite, classes) {
  const state = classes.split(/\s+/);
  if (!invite || state.includes("loading")) return null;
  return state.includes("full") ? "full" : "open";
}

/**
 * What a form sends: the email, the bot check's token, and the invite id when there is one. Both
 * forms bring it (the waitlist and "Email me the link"; Jason picked B, 20:50 JST 11-23).
 * @param {string} email
 * @param {string} human
 * @param {string | null} invite
 */
export function formBody(email, human, invite) {
  return invite ? { email, human, invite } : { email, human };
}

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
 * The answer of POST /v1/vote. See `voteKept` for which answers keep the vote. "bot": the bot
 * check failed or could not run (CLA-198), so the vote did not count.
 * @param {unknown} answer
 * @returns {"ok" | "busy" | "bad" | "bot" | "offline"}
 */
export function voteState(answer) {
  const r = answer && typeof answer === "object" ? /** @type {{ result?: unknown }} */ (answer).result : undefined;
  return r === "ok" || r === "busy" || r === "bad" || r === "bot" ? r : "offline";
}

/**
 * Whether the vote stays on. "busy" means this network already voted for this item today
 * (the same person after clearing the browser, or a second person in one office): the vote
 * is counted, so the button stays on. "bad", "bot" and no answer give the button back, so the
 * person can press again.
 * @param {"ok" | "busy" | "bad" | "bot" | "offline"} state
 */
export function voteKept(state) {
  return state === "ok" || state === "busy";
}

export const voteWords = { idle: "I’d love this", voted: "Thanks, noted" };

/**
 * GET /v1/votes: each open item's share in whole percent. Unknown items and bad numbers are
 * dropped. Null when nothing is left (offline, no votes yet, or a bad answer).
 * @param {unknown} answer
 * @returns {Map<VoteItem, number> | null}
 */
export function parseShares(answer) {
  const s = answer && typeof answer === "object" ? /** @type {{ shares?: unknown }} */ (answer).shares : undefined;
  if (!s || typeof s !== "object" || Array.isArray(s)) return null;
  /** @type {readonly string[]} */
  const known = Object.values(voteItems);
  /** @type {Map<VoteItem, number>} */
  const out = new Map();
  for (const [item, p] of Object.entries(s)) {
    if (known.includes(item) && Number.isInteger(p) && p >= 0 && p <= 100) out.set(/** @type {VoteItem} */ (item), p);
  }
  return out.size ? out : null;
}

/**
 * The cards' order: the highest share first; a tie keeps the page's order. Items with no share
 * keep their place after the others. `top` is the first item only when it leads alone.
 * @param {readonly VoteItem[]} page
 * @param {Map<VoteItem, number>} shares
 */
export function ranked(page, shares) {
  const share = (/** @type {VoteItem} */ i) => shares.get(i) ?? -1;
  const order = [...page].sort((a, b) => share(b) - share(a) || page.indexOf(a) - page.indexOf(b));
  const top = order.length > 1 && share(order[0]) > share(order[1]) ? order[0] : null;
  return { order, top };
}

/** The "Which color first?" pick after a More colors vote: one per browser. */
export const colorItems = /** @type {const} */ (["color-pink", "color-blue", "color-green", "color-red"]);
/** @typedef {typeof colorItems[number]} ColorItem */
export const colorStore = "mypod.color";
/**
 * The stored pick, or null for anything else.
 * @param {string | null} raw
 * @returns {ColorItem | null}
 */
export function colorFrom(raw) {
  return colorItems.find((c) => c === raw) ?? null;
}

/** The label on the card that leads alone. */
export const topWords = "most wanted";

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
