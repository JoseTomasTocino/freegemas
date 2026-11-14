// Build the standalone Freegemas Commander X16 web player.
//
//   node x16/web/build.mjs
//   node x16/web/build.mjs --out <dir>
//
// It copies the static page, downloads/verifies the pinned official WebAssembly
// emulator (or uses x16/web/build-cache/x16emu_wasm-r49.zip offline), and copies
// every file in x16/hostfs into the emulator's virtual game directory. The
// result is a static directory that can be served by any HTTP server.

import { copyFileSync, existsSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { assembleX16 } from "./assemble.mjs";

const here = dirname(fileURLToPath(import.meta.url));

function arg(name, fallback) {
  const i = process.argv.indexOf("--" + name);
  return i >= 0 ? process.argv[i + 1] : fallback;
}

const out = resolve(arg("out", join(here, "dist")));

const pageFiles = [
  ["index.html", "index.html"],
  ["app.js", "app.js"],
  ["style.css", "style.css"],
  ["favicon.png", "favicon.png"],
  ["NOTICE.md", "NOTICE.md"],
  ["emulator-license.txt", "emulator-license.txt"],
  ["rom-license.md", "rom-license.md"],
];

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

const manifest = [];
for (const [from, to] of pageFiles) {
  const src = join(here, from);
  if (!existsSync(src)) throw new Error(`missing web page file ${src}`);
  const dst = join(out, to);
  mkdirSync(dirname(dst), { recursive: true });
  copyFileSync(src, dst);
  manifest.push([to, statSync(dst).size]);
}

for (const [path, size] of await assembleX16(out, {
  cacheDir: join(here, "build-cache"),
})) {
  manifest.push([path, size]);
}

writeFileSync(join(out, ".nojekyll"), "");

// The page is static and must work at any mount point, so every local
// reference is relative. Check them rather than discovering a 404 after deploy.
function localRefs(html) {
  const refs = [];
  for (const m of html.matchAll(/(?:src|href)="([^"]+)"/g)) {
    const ref = m[1];
    if (/^(?:[a-z]+:|\/\/|#|data:)/i.test(ref)) continue;
    refs.push(ref.split(/[?#]/)[0]);
  }
  return refs;
}

for (const htmlFile of ["index.html"]) {
  const html = readFileSync(join(out, htmlFile), "utf8");
  for (const ref of localRefs(html)) {
    const candidates = [join(out, dirname(htmlFile), ref), join(out, ref)];
    if (!candidates.some((p) => existsSync(p))) {
      throw new Error(`${htmlFile}: local reference "${ref}" does not exist in the site`);
    }
  }
}

// The runtime fetches the names in this manifest; fail the build if any file
// would be missing after assembly.
const manifestPath = join(out, "game", "manifest.json");
const { resources } = JSON.parse(readFileSync(manifestPath, "utf8"));
for (const name of resources) {
  if (!existsSync(join(out, "game", name))) throw new Error(`missing game/${name}`);
}
if (!existsSync(join(out, "emulator", "x16emu.js"))) throw new Error("missing emulator/x16emu.js");

manifest.sort((a, b) => a[0].localeCompare(b[0]));
const total = manifest.reduce((n, [, size]) => n + size, 0);
for (const [path, size] of manifest) console.log(`  ${String(size).padStart(8)}  ${path}`);
console.log(`${out}: ${manifest.length} files, ${total} bytes`);
