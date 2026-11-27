// CLA-172: the beta page's live parts, from GET /v1/beta: the spots count and bar, the
// Download button and "Beta N". The frozen page's look; this file only fills it in.
import { apiBase, edits, linkDownloadPath, linkKey, withoutFrom, fill, formBody, formLine, formPath, formState, inviteCard, inviteID, parseBeta, siteKey, withState, votedFrom, voteItems, parseShares, ranked, topWords, colorFrom, colorStore, voteKept, voteState, votesStore, voteWords, withLimit, withVote, humanWait } from "./logic.js";

const api = apiBase(location.hostname);
const turnstileSiteKey = siteKey(location.hostname);
/** The invite id in the address (?invite=), or null. Both forms send it. */
const invite = inviteID(new URLSearchParams(location.search).get("invite"));
/** CLA-193: the short link's key (?from=), kept in memory only. The address loses ?from= at once,
 * so it shows /beta. No cookie, no storage. */
const from = linkKey(new URLSearchParams(location.search).get("from"));
if (new URLSearchParams(location.search).has("from")) {
  try { history.replaceState(history.state, "", withoutFrom(location.pathname, location.search, location.hash)); } catch { /* the address keeps it; the page is the same */ }
}

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

/** The bot check runs without a box, unless Cloudflare asks. A new token for each send (a token is
 * single-use); null after an error, an expired token, or no answer in `humanWait` (a challenge the
 * person ignores). `place` puts the box on the page: by default under the email row. */
async function human(/** @type {(box: HTMLElement) => void} */ place = (box) => form.parentElement?.after(box)) {
  const w = /** @type {any} */ (window).turnstile;
  if (!w) return null;
  // Under the row, not in the form: an empty item in the form's flex row would add a gap.
  const box = document.createElement("div");
  box.className = "ts";
  place(box);
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
    result(token ? formState(await post(formPath[kind()], formBody(formInput.value.trim(), token, invite))) : "bot");
  } finally {
    sending = false;
    formButton.disabled = false;
  }
});

// The server writes the answer into the page when it has it at once (src/page.ts). If not, the
// page comes as body.loading: the rows at their final size but invisible, the button with no
// link, so nothing moves and there is never a dead link. Then this asks once.
if (document.body.classList.contains("loading")) load().then((beta) => { draw(fill(beta)); welcome(); });
else welcome();

/** The invite welcome card, once, after the page has its state. A filled page comes with the card
 * already shown (src/page.ts), so it is there in the first picture; this then only wires it. The
 * loading page shows it here. Everything else is inert while it shows, so focus stays on its one
 * button. Esc or the button closes it; "Join the waitlist" then puts focus in the email field,
 * else focus goes back where it was. */
function welcome() {
  const card = document.getElementById("inv");
  const kind = card && !card.hidden ? (card.classList.contains("full") ? "full" : "open") : inviteCard(invite, document.body.className);
  const button = /** @type {HTMLAnchorElement | null} */ (card?.querySelector(kind === "full" ? "a.if" : "a.io") ?? null);
  if (!card || !kind || !button || location.hash === "#inv") return;  // #inv: closed by its link before this ran
  const back = document.activeElement;
  const others = [...document.body.children].filter((n) => n !== card && n.tagName !== "SCRIPT");
  const shut = (/** @type {HTMLElement | null} */ next) => {
    card.hidden = true;
    document.documentElement.classList.remove("inv");
    for (const n of others) /** @type {HTMLElement} */ (n).inert = false;
    document.removeEventListener("keydown", key);
    if (next && next !== document.body) next.focus();
    else button.blur();
  };
  const key = (/** @type {KeyboardEvent} */ e) => { if (e.key === "Escape") shut(back instanceof HTMLElement ? back : null); };
  card.classList.add(kind);
  for (const n of others) /** @type {HTMLElement} */ (n).inert = true;
  document.documentElement.classList.add("inv");
  card.hidden = false;
  document.addEventListener("keydown", key);
  button.addEventListener("click", (e) => {
    e.preventDefault();  // the link to #inv is only for a page without page.js
    shut(kind === "full" ? formInput : back instanceof HTMLElement ? back : null);
  }, { once: true });
  // No ring on open (the design); Tab or a key shows it, as for any button.
  button.focus(/** @type {FocusOptions} */ ({ focusVisible: false }));
}

// Votes (CLA-172): one per item per browser. The vote shows at once; "ok" or "busy" keeps it.
// CLA-198: each vote sends a fresh bot check token. No token or "bot" gives the button back, unsaved.
const store = {
  get() { try { return localStorage.getItem(votesStore); } catch { return null; } },
  set(/** @type {string} */ v) { try { localStorage.setItem(votesStore, v); } catch { /* private mode: the vote still counts once on the server */ } },
};
const voted = votedFrom(store.get());

// The ranking (Jason 08:11 JST 11-28): the open cards sort by their share of the votes, the leader
// goes in the big slot next to the built card. The % bars show only after this browser voted.
const next = document.querySelector(".next");
const cards = /** @type {HTMLElement[]} */ ([...document.querySelectorAll(".next .sc[data-v]")]);
const pageOrder = cards.map((c) => /** @type {import("./logic.js").VoteItem} */ (c.dataset.v));
async function loadShares(/** @type {boolean} */ fresh) {
  try {
    const r = await fetch(api + "/v1/votes", { referrerPolicy: "no-referrer", signal: AbortSignal.timeout(5000), cache: fresh ? "no-store" : "default" });
    return r.ok ? parseShares(await r.json()) : null;
  } catch {
    return null;
  }
}
function rank(/** @type {Map<import("./logic.js").VoteItem, number>} */ shares, /** @type {boolean} */ show) {
  const big = next?.querySelector(".soon2"), grid = next?.querySelector(".vgrid"), idea = grid?.querySelector(".idea");
  if (!big || !grid) return;
  const { order, top } = ranked(pageOrder, shares);
  order.forEach((item, at) => {
    const card = cards[pageOrder.indexOf(item)];
    if (at === 0) big.append(card); else grid.insertBefore(card, idea ?? null);
    const sx = card.querySelector(".sx");
    let label = /** @type {HTMLElement | null} */ (card.querySelector(".sl"));
    if (item === top && !label && sx) { label = document.createElement("p"); label.className = "sl"; sx.prepend(label); }
    if (label) {
      label.dataset.was ??= label.textContent ?? "";
      if (item === top) label.textContent = topWords;
      else if (label.dataset.was) label.textContent = label.dataset.was;
      else label.remove();
    }
    const row = /** @type {HTMLElement | null} */ (card.querySelector(".vr"));
    const p = shares.get(item);
    if (!row || p === undefined) return;
    /** @type {HTMLElement} */ (row.querySelector("i")).style.width = `${p}%`;  // CSSOM: allowed by the CSP
    /** @type {HTMLElement} */ (row.querySelector("b")).textContent = `${p}%`;
    row.hidden = !show;
  });
  const note = /** @type {HTMLElement | null} */ (next?.querySelector(".rk"));
  if (note) note.hidden = false;
}
loadShares(false).then((s) => { if (s) rank(s, voted.size > 0); });

// "Which color first?" (Jason 08:20 JST 11-28): shows under More colors once this browser voted
// for it. One pick per browser, sent like a vote (bot check, one a day per network); no take-back.
const colors = /** @type {HTMLElement | null} */ (document.querySelector(".fu"));
const colorStored = {
  get() { try { return colorFrom(localStorage.getItem(colorStore)); } catch { return null; } },
  set(/** @type {string} */ v) { try { localStorage.setItem(colorStore, v); } catch { /* private mode */ } },
};
function showColors() {
  if (!colors) return;
  colors.hidden = false;
  const kept = colorStored.get();
  for (const t of colors.querySelectorAll("button")) {
    t.classList.toggle("on", t.dataset.c === kept);
    t.setAttribute("aria-pressed", String(t.dataset.c === kept));
  }
}
if (voted.has("more-colors")) showColors();
for (const t of colors?.querySelectorAll("button") ?? []) {
  t.addEventListener("click", async () => {
    const item = colorFrom(t.dataset.c ?? null);
    if (!item || colorStored.get() || colors?.querySelector(".on")) return;  // one pick, no take-back
    t.classList.add("on");
    t.setAttribute("aria-pressed", "true");
    const token = await human((box) => (t.closest(".next") ?? document.body).append(box));
    if (token && voteKept(voteState(await post("/v1/vote", { item, human: token })))) colorStored.set(item);
    else { t.classList.remove("on"); t.setAttribute("aria-pressed", "false"); }
  });
}
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
    // The box goes at the end of the section (a block), not in a card's flex column.
    const token = await human((box) => (b.closest(".next") ?? document.body).append(box));
    if (token && voteKept(voteState(await post("/v1/vote", { item, human: token })))) {
      store.set(withVote(store.get(), item));
      if (item === "more-colors") showColors();
      const s = await loadShares(true);  // with this vote in it
      if (s) rank(s, true);
    } else show(false);
  });
}

// CLA-193: a Download press after a short link counts once for its link. The download never waits
// for it: no preventDefault, the answer is never read, and an error is dropped. text/plain needs no
// preflight; keepalive lets it finish if the page goes away.
const download = document.querySelector(".row > a.cta");
if (from && download) {
  download.addEventListener("click", () => {
    if (!download.getAttribute("href")) return;  // no build link yet: nothing downloads
    fetch(api + linkDownloadPath, { method: "POST", body: JSON.stringify({ link: from }), keepalive: true, referrerPolicy: "no-referrer" }).catch(() => {});
  });
}
