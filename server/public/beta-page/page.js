// CLA-172: the beta page's live parts, from GET /v1/beta: the spots count and bar, the
// Download button and "Beta N". The frozen page's look; this file only fills it in.
import { apiBase, edits, fill, formLine, formPath, formState, parseBeta, siteKey, withState, votedFrom, voteItems, voteKept, voteState, votesStore, voteWords, withLimit, withVote, humanWait } from "./logic.js";

const api = apiBase(location.hostname);
const turnstileSiteKey = siteKey(location.hostname);

const form = /** @type {HTMLFormElement} */ (document.getElementById("wl"));
const formButton = /** @type {HTMLButtonElement} */ (form.querySelector("button"));
const formDone = /** @type {HTMLElement} */ (form.querySelector(".ok"));
const formInput = /** @type {HTMLInputElement} */ (form.querySelector("input"));

/** Draws one fill (logic.js) with the same edits the server makes. The layout comes from the
 * body class and the CSS (the phone query too), so this never sets a display by itself. */
function draw(/** @type {import("./logic.js").Fill} */ f) {
  for (const e of edits(f)) {
    const node = /** @type {HTMLElement | null} */ (document.querySelector(e.selector));
    if (!node) continue;
    if (e.state) node.className = withState(node.className, e.state);
    else if (e.attr) e.value == null ? node.removeAttribute(e.attr) : node.setAttribute(e.attr, e.value);
    else if (e.html !== undefined) node.innerHTML = e.html;  // logic.js markup: numbers only, no outside text
    else if (e.text !== undefined) node.textContent = e.text;
  }
}

/** The form's kind follows the state: the waitlist when full, else "Email me the link". */
const kind = () => /** @type {import("./logic.js").FormKind} */ (document.body.classList.contains("full") ? "waitlist" : "link");

/** GET /v1/beta, or null: offline, an error, no answer in 5 s, or a bad answer. */
async function load() {
  try {
    const r = await fetch(api + "/v1/beta", { referrerPolicy: "no-referrer", signal: AbortSignal.timeout(5000) });
    return r.ok ? parseBeta(await r.json()) : null;
  } catch {
    return null;
  }
}

/** The bot check runs without a box, unless Cloudflare asks. A new token for each send; null after
 * an error, an expired token, or no answer in `humanWait` (a challenge the person ignores). */
async function human() {
  const w = /** @type {any} */ (window).turnstile;
  if (!w) return null;
  // Under the row, not in the form: an empty item in the form's flex row would add a gap.
  const box = document.createElement("div");
  box.className = "ts";
  form.parentElement?.after(box);
  /** @type {Promise<string | null>} */
  const token = new Promise((resolve) => {
    try {
      w.render(box, {
        sitekey: turnstileSiteKey, appearance: "interaction-only",
        callback: resolve, "error-callback": () => resolve(null), "expired-callback": () => resolve(null),
      });
    } catch {
      resolve(null);
    }
  });
  const result = await withLimit(token, humanWait, null);
  try { w.remove?.(box); } catch { /* already gone */ }
  box.remove();
  return result;
}

/** POST, or null with no answer in 10 s. */
async function post(/** @type {string} */ path, /** @type {object} */ body) {
  try {
    const r = await fetch(api + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
      referrerPolicy: "no-referrer", signal: AbortSignal.timeout(10000) });
    return await r.json();
  } catch {
    return null;
  }
}

/** Shows one state: "ok" in place of the field and the button, the others under them. */
function result(/** @type {import("./logic.js").FormState} */ state) {
  formDone.textContent = formLine(state, kind());
  form.classList.toggle("done", state === "ok");
  formDone.style.display = state === "ok" ? "" : "block";
  form.dataset.state = state;
}

let sending = false;
form.addEventListener("submit", async (e) => {
  e.preventDefault();
  if (sending) return;  // one send at a time
  if (!formInput.checkValidity()) return result("bad");
  sending = true;
  formButton.disabled = true;
  try {
    const token = await human();
    result(token ? formState(await post(formPath[kind()], { email: formInput.value.trim(), human: token })) : "bot");
  } finally {
    sending = false;
    formButton.disabled = false;
  }
});

// The server writes the answer into the page when it has it at once (src/page.ts). If not, the
// page comes as body.loading: the rows at their final size but invisible, the button with no
// link, so nothing moves and there is never a dead link. Then this asks once.
if (document.body.classList.contains("loading")) load().then((beta) => draw(fill(beta)));

// Votes (CLA-172): one per item per browser. The vote shows at once; "ok" or "busy" keeps it.
const store = {
  get() { try { return localStorage.getItem(votesStore); } catch { return null; } },
  set(/** @type {string} */ v) { try { localStorage.setItem(votesStore, v); } catch { /* private mode: the vote still counts once on the server */ } },
};
const voted = votedFrom(store.get());
for (const b of document.querySelectorAll(".next button.vb")) {
  const title = b.parentElement?.querySelector("h3")?.textContent ?? "";
  const item = /** @type {Record<string, import("./logic.js").VoteItem>} */ (voteItems)[title];
  const label = b.querySelector("span");
  if (!item || !label) continue;
  const show = (/** @type {boolean} */ on) => {
    b.classList.toggle("on", on);
    b.setAttribute("aria-pressed", String(on));
    label.textContent = on ? voteWords.voted : voteWords.idle;
  };
  show(voted.has(item));
  b.addEventListener("click", async () => {
    if (b.classList.contains("on")) return;  // one vote per item: no take-back, no second send
    show(true);
    if (voteKept(voteState(await post("/v1/vote", { item })))) store.set(withVote(store.get(), item));
    else show(false);
  });
}
