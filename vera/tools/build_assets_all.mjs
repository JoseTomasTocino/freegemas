// Rebuild every checked-in VERA input from the original media/ tree.
//
// The individual converters remain the source of truth; this wrapper gives
// people and CI one command so `vera/generated/` cannot silently drift.
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, "..", "..")
const generated = path.resolve(here, "..", "generated")
const build = path.resolve(here, "..", "llvm", "build")
const python = process.env.PYTHON || (process.platform === "win32" ? "python" : "python3")

fs.mkdirSync(generated, { recursive: true })
fs.mkdirSync(build, { recursive: true })

const steps = [
  [process.execPath, [path.join(here, "build_assets.mjs")]],
  [process.execPath, [path.join(here, "build_mouse.mjs")]],
  [process.execPath, [path.join(here, "build_sound.mjs")]],
  [python, [path.join(here, "build_music_pcm.py")]],
]

for (const [command, args] of steps) {
  console.log(`==> ${path.basename(command)} ${args.map((arg) => path.basename(arg)).join(" ")}`)
  const result = spawnSync(command, args, { cwd: root, stdio: "inherit" })
  if (result.error) throw result.error
  if (result.status !== 0) process.exit(result.status ?? 1)
}

console.log("VERA assets regenerated in vera/generated/")
