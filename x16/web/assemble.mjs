// Assemble the Freegemas Commander X16 web player.
//
//   import { assembleX16 } from "./x16/web/assemble.mjs";
//   await assembleX16("x16/web/dist", { cacheDir: "x16/web/build-cache" });
//
// The emulator is the official X16Community WebAssembly release r49. It is
// downloaded once into `cacheDir` (gitignored) and checksum-verified. The game
// files are the generated x16/hostfs directory, copied under the lower-case
// names the X16 asset layer asks HostFS for.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateRawSync } from "node:zlib";

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, "..", "..");

export const EMULATOR_ARCHIVE = "x16emu_wasm-r49.zip";
export const EMULATOR_URL =
  "https://github.com/X16Community/x16-emulator/releases/download/r49/" + EMULATOR_ARCHIVE;
export const EMULATOR_SHA256 =
  "9711036cf5b33504815b278fa872b8ec20aef9cb609fd7b17f3685d91312628f";

// The three files the Emscripten loader needs. The release archive also
// carries the upstream `webassembly/` demo page, which is not used here.
const EMULATOR_FILES = ["x16emu.js", "x16emu.wasm", "x16emu.data"];

// Files that are local test state, not part of a fresh distribution.
const IGNORED_GAME_FILES = new Set(["hiscore.dat", ".ds_store", "thumbs.db"]);

/* Minimal read-only ZIP reader: the release archive is a plain deflate ZIP and
 * Node has zlib, so the site build does not need unzip/tar (or a dependency). */
function readZip(buffer) {
  let eocd = -1;
  const lowest = Math.max(0, buffer.length - 22 - 0xffff);
  for (let i = buffer.length - 22; i >= lowest; --i) {
    if (buffer.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("not a ZIP archive (no end-of-central-directory record)");

  const entries = buffer.readUInt16LE(eocd + 10);
  const start = buffer.readUInt32LE(eocd + 16);
  const files = new Map();
  let cursor = start;
  for (let i = 0; i < entries; ++i) {
    if (buffer.readUInt32LE(cursor) !== 0x02014b50) throw new Error("corrupt central directory");
    const method = buffer.readUInt16LE(cursor + 10);
    const compressedSize = buffer.readUInt32LE(cursor + 20);
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const localOffset = buffer.readUInt32LE(cursor + 42);
    const name = buffer.toString("utf8", cursor + 46, cursor + 46 + nameLength);
    const dataStart = localOffset + 30
      + buffer.readUInt16LE(localOffset + 26)
      + buffer.readUInt16LE(localOffset + 28);
    const raw = buffer.subarray(dataStart, dataStart + compressedSize);
    files.set(name, method === 0 ? Buffer.from(raw) : inflateRawSync(raw));
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return files;
}

function sha256(buffer) {
  return createHash("sha256").update(buffer).digest("hex");
}

/** Download (once) and verify the pinned emulator archive; return its bytes. */
export async function emulatorArchive(cacheDir) {
  mkdirSync(cacheDir, { recursive: true });
  const archivePath = join(cacheDir, EMULATOR_ARCHIVE);
  if (existsSync(archivePath) && sha256(readFileSync(archivePath)) === EMULATOR_SHA256) {
    return readFileSync(archivePath);
  }
  console.log(`  downloading ${EMULATOR_URL}`);
  let response;
  try {
    response = await fetch(EMULATOR_URL, { redirect: "follow", signal: AbortSignal.timeout(180000) });
  } catch (problem) {
    throw new Error(
      `cannot download ${EMULATOR_URL}: ${problem.message}\n` +
      `for an offline build put the archive at ${archivePath}`);
  }
  if (!response.ok) {
    throw new Error(`cannot download ${EMULATOR_URL}: HTTP ${response.status}\n` +
      `for an offline build put the archive at ${archivePath}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (sha256(bytes) !== EMULATOR_SHA256) {
    throw new Error(`emulator archive checksum mismatch (${sha256(bytes)})`);
  }
  writeFileSync(archivePath, bytes);
  return bytes;
}

/** Copy the emulator and the game files into `outDir` and report what was written. */
export async function assembleX16(outDir, options = {}) {
  const cacheDir = options.cacheDir || join(here, "build-cache");
  const distDir = options.distDir || join(repoRoot, "x16", "hostfs");
  const zip = readZip(await emulatorArchive(cacheDir));

  const written = [];
  const emulatorDir = join(outDir, "emulator");
  mkdirSync(emulatorDir, { recursive: true });
  for (const name of EMULATOR_FILES) {
    const bytes = zip.get(name);
    if (!bytes) throw new Error(`${EMULATOR_ARCHIVE} does not contain ${name}`);
    writeFileSync(join(emulatorDir, name), bytes);
    written.push([`emulator/${name}`, bytes.length]);
  }

  const gameDir = join(outDir, "game");
  mkdirSync(gameDir, { recursive: true });
  const resources = [];
  const sourceNames = readdirSync(distDir)
    .filter((name) => !IGNORED_GAME_FILES.has(name.toLowerCase()))
    .filter((name) => statSync(join(distDir, name)).isFile())
    .sort();
  for (const name of sourceNames) {
    const source = join(distDir, name);
    if (!existsSync(source)) {
      throw new Error(`missing game file ${source} — run x16/build.ps1 first`);
    }
    const lower = name.toLowerCase();
    if (!/^[a-z0-9][a-z0-9._-]*$/.test(lower)) {
      throw new Error(`HostFS file name is not lower-case/simple: ${name}`);
    }
    if (resources.includes(lower)) {
      throw new Error(`duplicate HostFS name after lower-casing: ${name}`);
    }
    writeFileSync(join(gameDir, lower), readFileSync(source));
    resources.push(lower);
    written.push([`game/${lower}`, statSync(source).size]);
  }
  if (!resources.includes("boot.prg")) {
    throw new Error("x16/hostfs does not contain boot.prg — run x16/build.ps1 first");
  }
  const manifest = JSON.stringify({ resources }, null, 2) + "\n";
  writeFileSync(join(gameDir, "manifest.json"), manifest);
  written.push(["game/manifest.json", Buffer.byteLength(manifest)]);

  return written;
}
