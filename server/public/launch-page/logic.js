// CLA-175: the launch page's wiring rules, shared by the Worker (src/launch.ts) and wire.js, so the
// server fill and the page cannot differ. The design (public/launch/index.html) never holds them.

/** The links that download the current build ("Try it first", in the hero, the nav and the price section). */
export const downloadSelector = 'a[href="#download"]';

/** Where "Try it first" goes when the build is unknown or the beta is full: the beta page. */
export const betaPage = "/beta";

/**
 * Where "Try it first" goes, from the beta answer (logic.js parseBeta): the current build's DMG
 * while the beta has room, else the beta page (it has the waitlist). Null: no answer yet.
 * @param {import("../beta-page/logic.js").Beta | null | undefined} beta
 * @returns {string | null}
 */
export function downloadHref(beta) {
  if (beta === undefined) return null;
  return beta && beta.url && !beta.full ? beta.url : betaPage;
}

/** The Buy links ("Buy myPod" in the price section). The hero's "Buy myPod" only scrolls there (#buy). */
export const buySelector = 'a[href="#checkout"]';

/** Stripe's hosted payment page. Buy's answer goes nowhere else. */
export const checkoutPrefix = "https://checkout.stripe.com/";

/**
 * What a Buy answer means: the payment page's address, or why there is none. "sales": sales are
 * stopped (or Stripe failed); "busy": too many presses from this network; "other": no answer.
 * @param {number | null} status
 * @param {unknown} json
 * @returns {{ url: string } | { error: "sales" | "busy" | "other" }}
 */
export function buyResult(status, json) {
  const body = /** @type {Record<string, unknown> | null} */ (json && typeof json === "object" ? json : null);
  if (status === 200 && typeof body?.url === "string" && body.url.startsWith(checkoutPrefix)) return { url: body.url };
  if (body?.error === "sales" || body?.error === "busy") return { error: body.error };
  return { error: "other" };
}
