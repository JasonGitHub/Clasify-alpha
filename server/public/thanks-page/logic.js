// CLA-175: the "thank you" page's rules, shared with the tests. The page (public/launch/thanks.html)
// shows one of four states: checking, ok (paid), wait (in progress), no (not found).

/** @typedef {"checking" | "ok" | "wait" | "no"} ThanksState */

/**
 * The state for the Bought answer. Only "paid" and "pending" mean something; any other answer, an
 * error, "busy" (too many checks) or no answer is "not found", which has "Check again".
 * @param {unknown} json
 * @returns {ThanksState}
 */
export function thanksState(json) {
  const result = json && typeof json === "object" ? /** @type {Record<string, unknown>} */ (json).result : null;
  return result === "paid" ? "ok" : result === "pending" ? "wait" : "no";
}

/**
 * The Checkout session ID from the page address (?session=...), or null. The server checks it again.
 * @param {string | null} value
 */
export function sessionID(value) {
  return value && /^cs_(test|live)_[A-Za-z0-9]{10,200}$/.test(value) ? value : null;
}
