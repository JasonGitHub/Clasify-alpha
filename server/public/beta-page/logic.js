// CLA-172: what the beta page shows for the answer of GET /v1/beta. Pure functions, so the
// server tests check them. page.js draws them; the look is the frozen page's.

/** @typedef {{ taken: number, cap: number, full: boolean, build: number | null, url: string | null }} Beta */
/** @typedef {{ kind: "limited" | "bar" | "full" | "none", taken: number, cap: number, width: number }} Spots */
/** @typedef {{ full: boolean, soon: boolean, form: "none" | "link" | "waitlist", download: string | null, version: string | null, spots: Spots }} View */

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
