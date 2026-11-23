// CLA-175: the "thank you" page. Stripe sends the buyer here with ?session=<Checkout session ID>.
// It asks our server (Bought) once, and again only when the person presses "Check again".
// It never asks Stripe or any other host.
import { apiBase, parseBeta } from "../beta-page/logic.js";
import { sessionID, thanksState } from "./logic.js";

const api = apiBase(location.hostname);
const session = sessionID(new URLSearchParams(location.search).get("session"));
let checking = false;

async function check() {
  if (checking) return;
  checking = true;
  document.body.dataset.state = "checking";
  let json = null;
  if (session) {
    try {
      const r = await fetch(api + "/v1/bought", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ session }), referrerPolicy: "no-referrer", signal: AbortSignal.timeout(15000) });
      json = await r.json();
    } catch { /* no answer: not found */ }
  }
  checking = false;
  document.body.dataset.state = thanksState(json);
}

for (const a of document.querySelectorAll("[data-check]")) {
  a.addEventListener("click", (e) => { e.preventDefault(); check(); });
}

/** "Download for Mac": the server writes the newest build; if it could not, ask for it here. A buyer needs no beta seat. */
async function fillDownload() {
  const a = document.querySelector("a[data-dl]");
  if (!a || a.getAttribute("href") !== "#") return;
  let url = null;
  try {
    const r = await fetch(api + "/v1/beta", { referrerPolicy: "no-referrer", signal: AbortSignal.timeout(5000) });
    url = parseBeta(await r.json())?.url ?? null;
  } catch { /* the beta page has the download */ }
  a.setAttribute("href", url ?? "/beta");
}

fillDownload();
check();
