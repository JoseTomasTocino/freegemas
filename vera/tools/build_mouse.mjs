// Original handCursor.png scaled to a legible 16x16 cursor, packed as a 16x16
// 4bpp sprite. Keep its alpha and black outline; use reserved white/black ink.
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
const vera = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const source = path.resolve(vera, '..', 'media', 'handCursor.png')
const result = spawnSync('ffmpeg', ['-v', 'error', '-i', source, '-vf', 'scale=16:16:flags=area', '-frames:v', '1', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-'], { encoding: null })
if (result.status !== 0 || result.stdout.length !== 16 * 16 * 4) throw new Error('Cannot convert handCursor.png: ' + result.stderr)
const packed = Buffer.alloc(128)
for (let y = 0; y < 16; y++) for (let x = 0; x < 16; x++) {
  const p = (y * 16 + x) * 4
  if (result.stdout[p + 3] < 128) continue
  const ink = result.stdout[p] > 170 ? 11 : 12
  packed[y * 8 + (x >> 1)] |= ink << ((x & 1) ? 0 : 4)
}
fs.writeFileSync(path.join(vera, 'generated', 'mouse_hand_16.bin'), packed)
