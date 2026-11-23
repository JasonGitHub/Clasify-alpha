// CLA-175: writes the hashes of the launch page's inline scripts and styles into src/launch-hashes.ts,
// so a new page from the website thread drops in with no hand edits. No packages: Node only.
//   node scripts/csp-hashes.mjs
// The Worker sends the page's CSP itself (src/launch.ts): with all its style hashes it is longer than
// the 2000 characters a public/_headers line may have, and Cloudflare drops a longer line.
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const html = readFileSync(new URL("../public/launch/index.html", import.meta.url), "utf8");
const hash = (s) => `'sha256-${createHash("sha256").update(s, "utf8").digest("base64")}'`;
const inline = (tag) => [...html.matchAll(new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, "g"))].map((m) => hash(m[1]));
const unique = (list) => [...new Set(list)];
const scripts = unique(inline("script"));
const styles = unique([...inline("style"), ...[...html.matchAll(/<[a-z][^>]*\sstyle="([^"]*)"/g)].map((m) => hash(m[1]))]);
const list = (name, items) => `export const ${name} = [\n${items.map((h) => `  "${h}",`).join("\n")}\n];\n`;
writeFileSync(new URL("../src/launch-hashes.ts", import.meta.url),
  "// Written by scripts/csp-hashes.mjs from public/launch/index.html. Do not edit by hand (CLA-175).\n\n" +
  "/** The inline <script> elements of the launch page. */\n" + list("launchScripts", scripts) +
  "\n/** The <style> elements and style=\"...\" attributes of the launch page. */\n" + list("launchStyles", styles));
console.log(`src/launch-hashes.ts: ${scripts.length} script hashes, ${styles.length} style hashes`);
