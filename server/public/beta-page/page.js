// CLA-172: the beta page's live parts, from GET /v1/beta: the spots count and bar, the
// Download button and "Beta N". The frozen page's look; this file only fills it in.
import { parseBeta, view } from "./logic.js";

// The API: its own host on getmypod.app, the page's own origin on a test address.
export const api = location.hostname === "getmypod.app" ? "https://api.getmypod.app" : "";

const spots = /** @type {HTMLElement} */ (document.getElementById("spots"));
const download = /** @type {HTMLAnchorElement} */ (document.querySelector(".row > a.cta"));
const version = /** @type {HTMLElement} */ (document.querySelector(".row > .bver"));
const form = /** @type {HTMLFormElement} */ (document.getElementById("wl"));
const formButton = /** @type {HTMLButtonElement} */ (form.querySelector("button"));
const formDone = /** @type {HTMLElement} */ (form.querySelector(".ok"));
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
  formButton.textContent = v.form === "waitlist" ? "Save me a spot" : "Email me the link";
  formDone.textContent = v.form === "waitlist" ? "You’re on the list. We’ll write to you." : "Sent. Open it on your Mac.";
}

/** GET /v1/beta, or null: offline, an error, no answer in 5 s, or a bad answer. */
async function load() {
  try {
    const r = await fetch(api + "/v1/beta", { referrerPolicy: "no-referrer", signal: AbortSignal.timeout(5000) });
    return r.ok ? parseBeta(await r.json()) : null;
  } catch {
    return null;
  }
}

// Until the answer comes: no count, no button, no version (never a dead link), and no
// "on its way" line yet: that line is for no answer or no public build.
draw({ ...view(null, phone), soon: false });
form.addEventListener("submit", (e) => {
  e.preventDefault();  // the forms are wired in the next step (CLA-172 PR 3)
  if (!/** @type {HTMLInputElement} */ (form.querySelector("input")).checkValidity()) return;
  form.classList.add("done");
});
load().then((beta) => draw(view(beta, phone)));
