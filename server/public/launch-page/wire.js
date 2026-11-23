// CLA-175: the launch page's live parts. The Worker loads this file into public/launch/index.html, so
// a new design drops in without edits: "Try it first" gets the current build (src/launch.ts writes it
// first; this file only fills what the server could not), "Buy myPod" opens Stripe's payment page,
// and the phones' "Email me the link" form sends the beta page's link mail with the same bot check
// and the invite id. The bot check's script loads only when the form is sent.
import { apiBase, formBody, formLine, formState, humanWait, inviteID, parseBeta, siteKey, withLimit } from "../beta-page/logic.js";
import { buyResult, buySelector, downloadHref, downloadSelector } from "./logic.js";

const api = apiBase(location.hostname);
const invite = inviteID(new URLSearchParams(location.search).get("invite"));

/** "Try it first" links that the server did not fill: the beta page at once, the DMG once known. */
async function fillDownloads() {
  const links = /** @type {NodeListOf<HTMLAnchorElement>} */ (document.querySelectorAll(downloadSelector));
  if (!links.length) return;
  for (const a of links) a.setAttribute("href", "/beta");
  let beta = null;
  try {
    const r = await fetch(api + "/v1/beta", { referrerPolicy: "no-referrer", signal: AbortSignal.timeout(5000) });
    beta = parseBeta(await r.json());
  } catch { /* stays on the beta page */ }
  const href = downloadHref(beta);
  if (href) for (const a of links) a.setAttribute("href", href);
}

const form = /** @type {HTMLFormElement | null} */ (document.getElementById("wl"));

/** @type {Promise<boolean> | null} */
let turnstileScript = null;

/** Loads Cloudflare's bot check once, at the first send. False: it did not load. */
function loadTurnstile() {
  turnstileScript ??= new Promise((resolve) => {
    const s = document.createElement("script");
    s.src = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
    s.async = true;
    s.onload = () => resolve(true);
    s.onerror = () => { turnstileScript = null; resolve(false); };
    document.head.append(s);
  });
  return turnstileScript;
}

/** The Turnstile token, or null (no script, an error, or no answer in time). */
async function human() {
  if (!form || !(await withLimit(loadTurnstile(), 10_000, false))) return null;
  const w = /** @type {any} */ (window).turnstile;
  if (!w) return null;
  const box = document.createElement("div");
  box.className = "ts";
  form.after(box);
  /** @type {Promise<string | null>} */
  const token = new Promise((resolve) => {
    try {
      w.render(box, { sitekey: siteKey(location.hostname), appearance: "interaction-only",
        callback: resolve, "error-callback": () => resolve(null), "expired-callback": () => resolve(null) });
    } catch {
      resolve(null);
    }
  });
  const result = await withLimit(token, humanWait, null);
  try { w.remove?.(box); } catch { /* already gone */ }
  box.remove();
  return result;
}

/** POST /v1/link, or null with no answer in 10 s. */
async function post(/** @type {object} */ body) {
  try {
    const r = await fetch(api + "/v1/link", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
      referrerPolicy: "no-referrer", signal: AbortSignal.timeout(10000) });
    return await r.json();
  } catch {
    return null;
  }
}

if (form) {
  const input = /** @type {HTMLInputElement} */ (form.querySelector("input"));
  const button = /** @type {HTMLButtonElement} */ (form.querySelector("button"));
  const line = /** @type {HTMLElement} */ (form.querySelector(".ok"));
  const result = (/** @type {import("../beta-page/logic.js").FormState} */ state) => {
    line.textContent = formLine(state, "link");
    form.classList.toggle("done", state === "ok");
    line.style.display = state === "ok" ? "" : "block";
    form.dataset.state = state;
  };
  let sending = false;
  // The design's own submit handler only draws "Sent". This one runs first (capture on the
  // document) and stops it, then really sends.
  document.addEventListener("submit", async (e) => {
    if (e.target !== form) return;
    e.preventDefault();
    e.stopPropagation();
    if (sending) return;
    if (!input.checkValidity()) return result("bad");
    sending = true;
    button.disabled = true;
    try {
      const token = await human();
      result(token ? formState(await post(formBody(input.value.trim(), token, invite))) : "bot");
    } finally {
      sending = false;
      button.disabled = false;
    }
  }, true);
}

/**
 * A Buy press that did not open the payment page. Every failure comes here, with its kind, so a
 * one-line message can be added in one place later. Today: the button only comes back.
 * @param {HTMLAnchorElement} a
 * @param {"sales" | "busy" | "other"} _kind
 */
function buyFailed(a, _kind) {
  a.removeAttribute("aria-disabled");
  a.style.opacity = "";
}

let buying = false;
for (const a of /** @type {NodeListOf<HTMLAnchorElement>} */ (document.querySelectorAll(buySelector))) {
  a.addEventListener("click", async (e) => {
    e.preventDefault();
    if (buying) return;
    buying = true;
    a.setAttribute("aria-disabled", "true");
    a.style.opacity = ".6";
    let status = null, json = null;
    try {
      const r = await fetch(api + "/v1/buy", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}",
        referrerPolicy: "no-referrer", signal: AbortSignal.timeout(15000) });
      status = r.status;
      json = await r.json().catch(() => null);
    } catch { /* no answer */ }
    buying = false;
    const result = buyResult(status, json);
    if ("url" in result) {
      location.assign(result.url);
      // Back from Stripe (the page may come from the back-forward cache): the button works again.
      addEventListener("pageshow", () => buyFailed(a, "other"), { once: true });
    } else {
      buyFailed(a, result.error);
    }
  });
}

fillDownloads();
