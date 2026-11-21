// CLA-172: the beta page's live parts, from GET /v1/beta: the spots count and bar, the
// Download button and "Beta N". The frozen page's look; this file only fills it in.
import { apiBase, formLine, formPath, formState, parseBeta, siteKey, view } from "./logic.js";

const api = apiBase(location.hostname);
const turnstileSiteKey = siteKey(location.hostname);

const spots = /** @type {HTMLElement} */ (document.getElementById("spots"));
const download = /** @type {HTMLAnchorElement} */ (document.querySelector(".row > a.cta"));
const version = /** @type {HTMLElement} */ (document.querySelector(".row > .bver"));
const form = /** @type {HTMLFormElement} */ (document.getElementById("wl"));
const formButton = /** @type {HTMLButtonElement} */ (form.querySelector("button"));
const formDone = /** @type {HTMLElement} */ (form.querySelector(".ok"));
const formInput = /** @type {HTMLInputElement} */ (form.querySelector("input"));
const phone = matchMedia("(max-width:700px), (hover:none) and (pointer:coarse)").matches;

const el = (/** @type {string} */ tag, /** @type {string} */ text = "") => { const e = document.createElement(tag); e.textContent = text; return e; };

/** Draws one view (logic.js). */
function draw(/** @type {import("./logic.js").View} */ v) {
  document.body.classList.toggle("full", v.full);
  document.body.classList.toggle("soon", v.soon);
  const s = v.spots;
  spots.className = s.kind === "full" ? "spots full" : "spots";
  const p = el("p");
  if (s.kind === "limited") p.append(el("b", `Limited to ${s.cap} testers.`));
  else p.append(el("b", `${s.taken} of ${s.cap}`), " beta spots taken");
  spots.replaceChildren(p);
  if (s.kind !== "limited") {
    const bar = el("div"), fill = el("i");
    bar.className = "bar";
    fill.style.width = `${s.width}%`;  // through the DOM: the CSP allows no style attribute
    bar.append(fill);
    spots.append(bar);
  }
  download.style.display = v.download ? "" : "none";
  if (v.download) download.href = v.download;
  else download.removeAttribute("href");
  version.style.display = v.version ? "" : "none";
  const b = version.querySelector("b");
  if (b && v.version) b.textContent = v.version;
  form.style.display = v.form === "none" ? "none" : "flex";
  if (v.form !== "none") kind = v.form;
  formButton.textContent = kind === "waitlist" ? "Save me a spot" : "Email me the link";
  formDone.textContent = formLine("ok", kind);
}

/** @type {import("./logic.js").FormKind} */
let kind = "link";

/** GET /v1/beta, or null: offline, an error, no answer in 5 s, or a bad answer. */
async function load() {
  try {
    const r = await fetch(api + "/v1/beta", { referrerPolicy: "no-referrer", signal: AbortSignal.timeout(5000) });
    return r.ok ? parseBeta(await r.json()) : null;
  } catch {
    return null;
  }
}

/** The bot check runs without a box, unless Cloudflare asks. A new token for each send. */
function human() {
  return new Promise((resolve) => {
    const w = /** @type {any} */ (window).turnstile;
    if (!w) return resolve(null);
    // Under the row, not in the form: an empty item in the form's flex row would add a gap.
    let box = document.querySelector(".row + .ts");
    if (box) w.remove?.(box), box.remove();
    box = document.createElement("div");
    box.className = "ts";
    form.parentElement?.after(box);
    w.render(box, {
      sitekey: turnstileSiteKey, appearance: "interaction-only",
      callback: resolve, "error-callback": () => resolve(null), "expired-callback": () => resolve(null),
    });
  });
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
  formDone.textContent = formLine(state, kind);
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
    result(token ? formState(await post(formPath[kind], { email: formInput.value.trim(), human: token })) : "bot");
  } finally {
    sending = false;
    formButton.disabled = false;
  }
});

// Until the answer comes: no count, no button, no version (never a dead link), and no
// "on its way" line yet: that line is for no answer or no public build.
draw({ ...view(null, phone), soon: false });
load().then((beta) => draw(view(beta, phone)));
