// The activation page (card BX). It reads ?d= or ?c=, removes it from the address bar at once,
// and keeps the code, the token and the email in memory only. It never confirms on open,
// because some mail programs open links by themselves.
import { fromConfirm, fromPeek, fromStart, opened, screen } from "./logic.js";

const api = "https://api.getmypod.app";
// The Turnstile widget for getmypod.app (managed). The site key is public.
const turnstileSiteKey = "0x4AAAAAAGIRWYxmCoZOyxc0";

const gray = 'fill="none" stroke="#9aa4ae"';
const icons = {
  mail: '<rect x="14" y="26" width="82" height="58" rx="9" fill="none" stroke="#3f8fd8" stroke-width="10"/><path d="M18 32l37 28 37-28" fill="none" stroke="#3f8fd8" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>',
  check: '<path d="M28 52l20 20L82 30" fill="none" stroke="#34c759" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>',
  people: `<circle cx="40" cy="40" r="15" ${gray} stroke-width="9"/><circle cx="72" cy="40" r="15" ${gray} stroke-width="9"/><path d="M14 92c0-18 12-28 26-28s26 10 26 28M50 74c6-7 13-10 22-10 14 0 24 10 24 28" ${gray} stroke-width="9" stroke-linecap="round"/>`,
  clock: `<circle cx="55" cy="55" r="38" ${gray} stroke-width="10"/><path d="M55 34v22l14 9" ${gray} stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>`,
  power: `<circle cx="55" cy="58" r="34" ${gray} stroke-width="10" stroke-dasharray="168 46" stroke-dashoffset="-23" stroke-linecap="round" transform="rotate(-90 55 58)"/><path d="M55 16v36" stroke="#9aa4ae" stroke-width="10" stroke-linecap="round"/>`,
  macs: `<rect x="10" y="22" width="56" height="40" rx="6" ${gray} stroke-width="9"/><rect x="44" y="48" width="56" height="40" rx="6" fill="#f6f5f1" stroke="#9aa4ae" stroke-width="9"/>`,
  cross: `<path d="M32 32l46 46M78 32L32 78" ${gray} stroke-width="12" stroke-linecap="round"/>`,
};

const start = opened(location.search);
history.replaceState(null, "", location.pathname);  // the code or token leaves the address bar and the history
let code = start.code ?? "";
let email = "";
let retry = () => {};

const view = document.getElementById("view");
const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text) e.textContent = text; return e; };

function show(s) {
  view.replaceChildren();
  if (s.icon) {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "icon"); svg.setAttribute("viewBox", "0 0 110 110"); svg.setAttribute("aria-hidden", "true");
    svg.innerHTML = icons[s.icon];
    view.append(svg);
  }
  view.append(el("h1", "", s.title));
  const text = el("p", "text");
  s.lines.forEach((parts, i) => {
    if (i) text.append(document.createElement("br"));
    for (const part of parts) text.append(part === "@" ? el("b", "", s.email) : part);
  });
  view.append(text);
  if (s.kind === "email") view.append(form());
  if (s.kind === "confirm") view.append(button("Confirm", () => confirm(s.email)));
  if (s.kind === "sent") view.append(links([["Send again", () => send(email)], ["Use another email", () => show(screen("email"))]]));
  if (s.kind === "error") view.append(links([["Try again", () => retry()]]));
  document.title = `${s.title} · myPod`;
}

function form() {
  const f = el("form", "row");
  const input = el("input", "field");
  Object.assign(input, { type: "email", name: "email", required: true, autocomplete: "email", maxLength: 254, value: email });
  input.setAttribute("aria-label", "Email");
  const go = el("button", "button", "Send link");
  f.append(input, go);
  f.addEventListener("submit", (e) => { e.preventDefault(); go.disabled = true; send(input.value.trim().toLowerCase()); });  // as the server stores it
  const box = el("div");
  box.append(f, el("p", "note", "One email per person. No password."));
  queueMicrotask(() => input.focus());
  return box;
}
const button = (label, act) => { const b = el("button", "button", label); b.addEventListener("click", () => { b.disabled = true; act(); }); return b; };
function links(items) {
  const row = el("div", "links");
  for (const [label, act] of items) {
    const b = el("button", "link", label);
    b.addEventListener("click", () => { for (const other of row.children) other.disabled = true; act(); });
    row.append(b);
  }
  return row;
}

async function post(path, body) {
  try {
    const r = await fetch(api + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body), referrerPolicy: "no-referrer" });
    return await r.json();
  } catch { return null; }
}

/** The bot check runs without a box, unless Cloudflare asks. A new token for each send. */
function human() {
  return new Promise((resolve) => {
    const box = document.getElementById("turnstile");
    if (!window.turnstile) return resolve(null);
    window.turnstile.remove?.(box);
    window.turnstile.render(box, {
      sitekey: turnstileSiteKey, appearance: "interaction-only",
      callback: resolve, "error-callback": () => resolve(null), "expired-callback": () => resolve(null),
    });
  });
}

// One send at a time: each one uses up the page code, so a second click would get "code".
let sending = false;
async function send(address) {
  if (sending) return;
  sending = true;
  try { await sendOnce(address); } finally { sending = false; }
}
async function sendOnce(address) {
  email = address;
  retry = () => send(address);
  if (!code) return show(screen("pageExpired"));
  const token = await human();
  if (!token) return show(screen("error"));
  const answer = await post("/v1/start", { code, email: address, turnstile: token });
  if (typeof answer?.code === "string") code = answer.code;  // the old code is used up
  else if (answer?.error === "code") code = "";
  const next = fromStart(answer, address);
  if (next.email) email = next.email;
  show(next);
}

async function peek(token) {
  retry = () => peek(token);
  show(fromPeek(await post("/v1/peek", { token })));
  // The Confirm button needs the token; the next screen keeps it in this closure only.
  confirm = async (address) => { retry = () => confirm(address); show(fromConfirm(await post("/v1/confirm", { token }), address)); };
}
let confirm = async (_address) => {};

if (start.token) peek(start.token);
else if (start.code) show(screen("email"));
else show(screen("pageExpired"));
