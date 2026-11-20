// Build VERA-ready visual assets from the original Freegemas PNG resources.
// Requires ffmpeg (available in the development environment) only to decode PNG.
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import zlib from "node:zlib"

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, "..", "..")
const media = path.join(root, "media")
const out = path.join(here, "..", "generated")
fs.mkdirSync(out, { recursive: true })

const readPng = (file) => {
  const probe = spawnSync("ffmpeg", ["-v", "error", "-i", file, "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { encoding: null, maxBuffer: 16 * 1024 * 1024 })
  if (probe.status !== 0) throw new Error(`Could not decode ${file}: ${probe.stderr}`)
  const size = spawnSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", file], { encoding: "utf8" })
  if (size.status !== 0) throw new Error(`Could not probe ${file}`)
  const [width, height] = size.stdout.trim().split(",").map(Number)
  return { width, height, data: new Uint8Array(probe.stdout) }
}
const readPngScaled = (file, width, height, filter="lanczos") => {
  const scaled = spawnSync("ffmpeg", ["-v", "error", "-i", file, "-vf", `scale=${width}:${height}:flags=${filter}`, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { encoding: null, maxBuffer: 4 * 1024 * 1024 })
  if (scaled.status !== 0) throw new Error(`Could not scale ${file}: ${scaled.stderr}`)
  return { width, height, data: new Uint8Array(scaled.stdout) }
}
const tintIcon = (file, rgb) => {
  const icon = readPngScaled(file, 16, 16)
  for (let p = 0; p < icon.data.length; p += 4) if (icon.data[p + 3]) {
    icon.data[p] = rgb[0]; icon.data[p + 1] = rgb[1]; icon.data[p + 2] = rgb[2]
  }
  return icon
}
const makeSyncIcon = (rgb) => {
  const icon = image(16, 16)
  const pixel = (x,y) => { const p=(y*16+x)*4; icon.data[p]=rgb[0]; icon.data[p+1]=rgb[1]; icon.data[p+2]=rgb[2]; icon.data[p+3]=255 }
  /* Two bold, opposing arrows designed directly for a 16px target. */
  for (let x=4;x<=11;x++) { pixel(x,4); pixel(x,5); pixel(x,10); pixel(x,11) }
  for (const [x,y] of [[11,2],[12,3],[13,4],[12,5],[11,6],[4,8],[3,9],[2,10],[3,11],[4,12]]) { pixel(x,y); if (x>0) pixel(x-1,y) }
  return icon
}

const renderButtonText = (caption, width = 78, height = 17) => {
  const filter = `drawtext=fontfile='media/fuenteNormal.ttf':text='${caption}':fontsize=13:fontcolor=white:shadowcolor=black@0.45:shadowx=1:shadowy=1:x=16+(w-16-text_w)/2:y=0`
  const rendered = spawnSync("ffmpeg", ["-v", "error", "-f", "lavfi", "-i", `color=c=black@0.0:s=${width}x${height},format=rgba`, "-vf", filter, "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"], { encoding: null, maxBuffer: 1024 * 1024 })
  if (rendered.status !== 0) throw new Error(`Could not render button text: ${rendered.stderr}`)
  return { width, height, data: new Uint8Array(rendered.stdout) }
}

const image = (width, height) => ({ width, height, data: new Uint8Array(width * height * 4) })
const crop = (src, x0, y0, width, height) => {
  const dst = image(width, height)
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const si = ((y0 + y) * src.width + x0 + x) * 4
    dst.data.set(src.data.subarray(si, si + 4), (y * width + x) * 4)
  }
  return dst
}
const put = (dst, src, dx, dy, dw = src.width, dh = src.height) => {
  for (let y = 0; y < dh; y++) for (let x = 0; x < dw; x++) {
    const sx = Math.min(src.width - 1, Math.floor(x * src.width / dw))
    const sy = Math.min(src.height - 1, Math.floor(y * src.height / dh))
    const si = (sy * src.width + sx) * 4
    const di = ((dy + y) * dst.width + dx + x) * 4
    if (dx + x < 0 || dy + y < 0 || dx + x >= dst.width || dy + y >= dst.height || src.data[si + 3] === 0) continue
    dst.data.set(src.data.subarray(si, si + 4), di)
  }
}
const putAlpha = (dst, src, dx, dy, dw = src.width, dh = src.height) => {
  for (let y = 0; y < dh; y++) for (let x = 0; x < dw; x++) {
    const sx = Math.min(src.width - 1, Math.floor(x * src.width / dw)), sy = Math.min(src.height - 1, Math.floor(y * src.height / dh))
    const si = (sy * src.width + sx) * 4, tx = dx + x, ty = dy + y
    if (tx < 0 || ty < 0 || tx >= dst.width || ty >= dst.height) continue
    const a = src.data[si + 3]; if (!a) continue
    const di = (ty * dst.width + tx) * 4
    for (let c = 0; c < 3; c++) dst.data[di + c] = (src.data[si + c] * a + dst.data[di + c] * (255 - a) + 127) / 255
    dst.data[di + 3] = 255
  }
}

// Tiny temporary text renderer: it is only for the generated visual reference.
// The game will use VERA tile glyphs, not this bitmap font.
const glyph = {
  A:[14,17,17,31,17,17,17], B:[30,17,17,30,17,17,30], C:[14,17,16,16,16,17,14], D:[30,17,17,17,17,17,30], E:[31,16,16,30,16,16,31], F:[31,16,16,30,16,16,16], G:[14,17,16,23,17,17,15],
  H:[17,17,17,31,17,17,17], I:[31,4,4,4,4,4,31], J:[7,2,2,2,2,18,12], K:[17,18,20,24,20,18,17], L:[16,16,16,16,16,16,31],
  M:[17,27,21,21,17,17,17], N:[17,25,21,19,17,17,17], O:[14,17,17,17,17,17,14], P:[30,17,17,30,16,16,16], Q:[14,17,17,17,21,18,13],
  R:[30,17,17,30,20,18,17], S:[15,16,16,14,1,1,30], T:[31,4,4,4,4,4,4], U:[17,17,17,17,17,17,14], V:[17,17,17,17,17,10,4],
  W:[17,17,17,21,21,27,17], X:[17,10,4,4,4,10,17], Y:[17,10,4,4,4,4,4], Z:[31,1,2,4,8,16,31],
  ':':[0,4,4,0,4,4,0], '.':[0,0,0,0,0,4,4], ' ':[0,0,0,0,0,0,0], '0':[14,17,19,21,25,17,14],
  '1':[4,12,4,4,4,4,14], '2':[14,17,1,2,4,8,31], '3':[30,1,1,14,1,1,30],
  '4':[2,6,10,18,31,2,2], '5':[31,16,16,30,1,1,30], '6':[14,16,16,30,17,17,14],
  '7':[31,1,2,4,8,8,8], '8':[14,17,17,14,17,17,14], '9':[14,17,17,15,1,1,14], '?':[14,17,1,2,4,0,4]
}
Object.assign(glyph, {
  a:[0,0,14,1,15,17,15], b:[16,16,30,17,17,17,30],
  c:[0,0,14,16,16,17,14], d:[1,1,15,17,17,17,15],
  f:[6,8,28,8,8,8,8], h:[16,16,30,17,17,17,17],
  j:[2,0,6,2,2,18,12], k:[16,16,18,20,24,20,18],
  q:[0,0,15,17,15,1,1], u:[0,0,17,17,17,19,13],
  v:[0,0,17,17,17,10,4], w:[0,0,17,17,21,21,10],
  z:[0,0,31,2,4,8,31],
  e:[0,0,14,17,31,16,14], g:[0,0,15,17,15,1,14],
  i:[4,0,12,4,4,4,14], l:[12,4,4,4,4,4,14],
  m:[0,0,26,21,21,21,21], n:[0,0,30,17,17,17,17],
  o:[0,0,14,17,17,17,14], p:[0,0,30,17,30,16,16],
  r:[0,0,22,25,16,16,16], s:[0,0,15,16,14,1,30],
  t:[4,4,31,4,4,5,2], x:[0,0,17,10,4,10,17],
  y:[0,0,17,17,15,1,14]
})
const text = (dst, str, x, y, rgb, scale = 1, advance = 6) => {
  for (const ch of str) {
    const rows = glyph[ch] || glyph[' ']
    for (let yy = 0; yy < 7; yy++) for (let xx = 0; xx < 5; xx++) if (rows[yy] & (16 >> xx)) {
      for (let py = 0; py < scale; py++) for (let px = 0; px < scale; px++) {
        const tx = x + xx * scale + px, ty = y + yy * scale + py
        if (tx >= 0 && ty >= 0 && tx < dst.width && ty < dst.height) dst.data.set([...rgb, 255], (ty * dst.width + tx) * 4)
      }
    }
    x += advance * scale
  }
}

const rgbaToPng = (img) => {
  const raw = Buffer.alloc((img.width * 4 + 1) * img.height)
  for (let y = 0; y < img.height; y++) {
    raw[y * (img.width * 4 + 1)] = 0
    raw.set(img.data.subarray(y * img.width * 4, (y + 1) * img.width * 4), y * (img.width * 4 + 1) + 1)
  }
  const chunk = (kind, data) => { const b = Buffer.alloc(data.length + 12); b.writeUInt32BE(data.length, 0); b.write(kind, 4); data.copy(b, 8); b.writeUInt32BE(crc32(b.subarray(4, 8 + data.length)), 8 + data.length); return b }
  const head = Buffer.alloc(13); head.writeUInt32BE(img.width, 0); head.writeUInt32BE(img.height, 4); head[8] = 8; head[9] = 6
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), chunk("IHDR", head), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))])
}
const crc32 = (buf) => { let c = 0xffffffff; for (const b of buf) { c ^= b; for (let n = 0; n < 8; n++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)) } return (c ^ 0xffffffff) >>> 0 }

const base = image(320, 240)
put(base, readPngScaled(path.join(media, "board.png"), 320, 240), 0, 0)
const menuBackground = readPngScaled(path.join(media, "stateMainMenu", "mainMenuBackground.png"), 320, 240)
/* The board artwork's pale cloud becomes a conspicuous patch below TIME
 * LEFT at RGB444. Use the menu's blue backdrop for the left HUD instead.
 * Preserve the baked-in logo, and feather the join just below its glow. */
for (let y = 36; y < 240; ++y) for (let x = 0; x < 88; ++x) {
  const p = (y * 320 + x) * 4, blend = Math.min(1, (y - 36) / 16)
  for (let c = 0; c < 3; ++c)
    base.data[p + c] = Math.round(base.data[p + c] * (1 - blend) + menuBackground.data[p + c] * blend)
}
const boardOnly = { width: base.width, height: base.height, data: base.data.slice() }
put(base, readPng(path.join(media, "scoreBackground.png")), 7, 50, 77, 17)
put(base, readPng(path.join(media, "timeBackground.png")), 7, 92, 77, 28)
for (const [x, y, label, icon, rgb] of [[7,168,"Show hint","iconHint.png",[204,85,221]],[7,187,"Reset game","iconRestart.png",[51,238,102]],[7,215,"Exit","iconExit.png",[255,51,51]]]) {
  put(base, readPng(path.join(media, "buttonBackground.png")), x, y, 78, 17)
  putAlpha(base, icon === "iconRestart.png" ? makeSyncIcon(rgb) : tintIcon(path.join(media, icon), rgb), x + 3, y + 1)
  const labelWidth = label.length * 5
  text(base, label, x + 16 + Math.floor((62 - labelWidth) / 2), y + 5, [235, 241, 255], 1, 5)
}
text(base, "Score", 22, 39, [165, 180, 255])
// Score digits are rendered by the game and right-aligned at runtime.
text(base, "Time left", 13, 82, [165, 180, 255])
// Time digits are rendered by the game in Time Trial mode.
// Keep Layer 0 pristine. Gems live in hardware sprites at runtime.
const background = { width: base.width, height: base.height, data: base.data.slice() }
const endlessBackground = { width: background.width, height: background.height, data: background.data.slice() }
for (let y = 78; y < 126; ++y) for (let x = 7; x < 85; ++x) {
  const p = (y * 320 + x) * 4
  endlessBackground.data.set(boardOnly.data.subarray(p, p + 4), p)
}

// Title is deliberately a separate disk asset. It is not linked into the
// $0800 game image: the runtime will stream it into VERA only while in menu.
const title = image(320, 240)
put(title, menuBackground, 0, 0)
/* The source logo lives in a 714x422 canvas with a very broad, faint white
 * matte. Crop to the meaningful glow before scaling; otherwise the actual
 * lettering becomes tiny and the matte quantizes into a pale rectangle. */
const logo = readPng(path.join(media, "stateMainMenu", "mainMenuLogo.png"))
putAlpha(title, logo, 34, 0, 284, 168)
const titleGemNames = ["gemWhite.png", "gemRed.png", "gemPurple.png", "gemOrange.png", "gemGreen.png", "gemYellow.png", "gemBlue.png"]
const titleGems = titleGemNames.map(name => {
  const gem = readPng(path.join(media, name))
  /* Original gem PNGs have an opaque black matte, not alpha transparency. */
  for (let p = 0; p < gem.data.length; p += 4)
    if (gem.data[p] < 18 && gem.data[p + 1] < 18 && gem.data[p + 2] < 18) gem.data[p + 3] = 0
  return gem
})
for (const [y, label] of [[144,"Timetrial mode"],[161,"Endless mode"],[178,"How to play?"],[195,"Options"],[212,"Exit"]])
  text(title, label, 160 - label.length * 3, y, [255, 255, 255], 1)

const howto = image(320, 240)
put(howto, readPngScaled(path.join(media, "howtoScreen.png"), 320, 240), 0, 0)
text(howto, "How to play", 156, 20, [255,255,255], 2, 6)
const helpLines = [
  "The objective is to swap one", "gem with an adjacent gem to", "form a horizontal or vertical", "chain of three or more gems.", "",
  "Select the first gem and then", "select an adjacent gem. A", "correct move swaps them and", "removes the matching chain.", "",
  "Longer chains give bonus", "points. Falling gems can form", "cascades, which also give", "bonus points."
]
for (let i=0;i<helpLines.length;i++) text(howto, helpLines[i], 124, 55+i*10, [255,255,255])
text(howto, "Press any button to go back", 12, 222, [255,255,255])

const options = image(320, 240)
put(options, menuBackground,0,0)
text(options,"Music:",106,60,[255,255,255],2,6)
text(options,"Sound:",106,77,[255,255,255],2,6)
for (const [y,label] of [[94,"Fullscreen: On"],[111,"Back"]]) text(options,label,160-label.length*6,y,[255,255,255],2,6)
text(options,"High score",130,151,[255,255,255],1,6)
// Record rows are drawn at runtime, centered using the wider saved score.
const portCredit = "Freegemas Apple II VERA port by anomixer 2026"
if ([...portCredit].some(ch => !glyph[ch])) throw new Error("Missing port credit glyph")
text(options,portCredit,Math.floor((320-(portCredit.length*6-1))/2),222,[255,255,255])

const names = ["gemWhite.png", "gemRed.png", "gemPurple.png", "gemOrange.png", "gemGreen.png", "gemYellow.png", "gemBlue.png"]
const gems = names.map(name => readPng(path.join(media, name)))
const selector = readPng(path.join(media, "selector.png"))
// Deterministic board chosen for preview only. Gameplay owns the real board.
const previewBoard = [5,4,6,2,3,6,1,3,1,1,6,2,2,6,5,5,4,3,5,4,5,2,6,2,3,2,5,3,4,5,3,2,5,4,4,3,3,5,1,4,4,2,2,5,2,2,3,3,2,4,4,6,1,5,3,6,1,3,3,6,1,4,5,6]
for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) put(base, gems[previewBoard[y * 8 + x] - 1], 97 + x * 26, 17 + y * 26, 24, 24)

// Palette 64..255 is exclusively for gem colours; the UI needs enough tones
// for the original blue gradients and pink logo without looking muddy.
// original red/purple/orange/green hues instead of quantizing them to UI ink.
const gemBins = new Map(), accentBins = new Map()
const boardColors = new Map(), uiColors = new Map()
const addRgbColor = (bins, r, g, b) => {
  const key = (r << 16) | (g << 8) | b
  bins.set(key, (bins.get(key) || 0) + 1)
}
const addColor = (bins, r, g, b) => { const key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4); bins.set(key, (bins.get(key) || 0) + 1) }
for (let y = 0; y < 240; ++y) for (let x = 0; x < 320; ++x) {
  const p = (y * 320 + x) * 4, r = background.data[p], g = background.data[p+1], b = background.data[p+2]
  if (x >= 94 && x < 307 && y >= 16 && y < 232) addRgbColor(boardColors, r, g, b)
  else if ((r < g && g < b) || Math.max(r,g,b) < 48) addRgbColor(uiColors, r, g, b)
}
/* Give the warm board and blue HUD their own representative ramps, rather
 * than letting frequency-only bins discard intermediate brown shades.
 * Keep fractional source channels until rounding final RGB444 centers. */
const gameRamp = (bins, count) => {
  const describe = items => {
    const weight = items.reduce((sum,p) => sum+p.w, 0), mean = [0,0,0], variance = [0,0,0]
    for (const p of items) for (let c=0;c<3;++c) mean[c] += p.c[c]*p.w/weight
    for (const p of items) for (let c=0;c<3;++c) variance[c] += (p.c[c]-mean[c])**2*p.w
    return {items,mean,axis:variance.indexOf(Math.max(...variance)),error:variance.reduce((a,b)=>a+b,0)}
  }
  const boxes = [describe([...bins].map(([key,w])=>({w,c:[key>>16,(key>>8)&255,key&255]})))]
  while (boxes.length < count) {
    let split=-1,error=-1
    for(let i=0;i<boxes.length;++i) if(boxes[i].items.length>1 && boxes[i].error>error){split=i;error=boxes[i].error}
    if(split<0)break
    const box=boxes.splice(split,1)[0], items=box.items.sort((a,b)=>a.c[box.axis]-b.c[box.axis])
    const half=items.reduce((sum,p)=>sum+p.w,0)/2;let weight=0,cut=1
    for(let i=0;i<items.length-1;++i){weight+=items[i].w;cut=i+1;if(weight>=half)break}
    boxes.push(describe(items.slice(0,cut)),describe(items.slice(cut)))
  }
  const pack = rgb => {const c=rgb.map(v=>Math.max(0,Math.min(15,Math.round(v/17))));return(c[0]<<8)|(c[1]<<4)|c[2]}
  const colors = new Set(boxes.map(box=>pack(box.mean))), candidates = new Map()
  for(const [key,w] of bins){const color=pack([key>>16,(key>>8)&255,key&255]);candidates.set(color,(candidates.get(color)||0)+w)}
  const channels = key => [key>>8,(key>>4)&15,key&15]
  /* Adjacent RGB centroids often round to the same RGB444 color. Recover
   * those wasted slots with the most underrepresented source shades. */
  while(colors.size<count){
    let chosen=-1,best=-1
    for(const [key,w] of candidates) if(!colors.has(key)){
      const c=channels(key),error=Math.min(...[...colors].map(color=>{const q=channels(color);return c.reduce((sum,v,i)=>sum+(v-q[i])**2,0)}))*w
      if(error>best){best=error;chosen=key}
    }
    if(chosen<0)break
    colors.add(chosen)
  }
  return [...colors]
}
/* Reserve saturated UI colours before the large blue background histogram
 * consumes the palette: game logo plus the three button icons. */
for (let y = 0; y < 36; y++) for (let x = 0; x < 88; x++) {
  const p = (y * 320 + x) * 4, r = background.data[p], g = background.data[p + 1], b = background.data[p + 2]
  if (Math.max(r,g,b) >= 64 && Math.max(r,g,b) - Math.min(r,g,b) >= 32) addColor(accentBins, r, g, b)
}
for (const name of ["iconHint.png","iconRestart.png","iconExit.png"]) {
  const icon = readPng(path.join(media, name))
  for (let p = 0; p < icon.data.length; p += 4) if (icon.data[p + 3] > 32) {
    const r=icon.data[p],g=icon.data[p+1],b=icon.data[p+2]
    if (Math.max(r,g,b) >= 64 && Math.max(r,g,b) - Math.min(r,g,b) >= 32) addColor(accentBins,r,g,b)
  }
}
for (const g of gems) for (let i = 0; i < g.data.length; i += 4) if (g.data[i + 3] && (g.data[i] >= 18 || g.data[i + 1] >= 18 || g.data[i + 2] >= 18)) addColor(gemBins, g.data[i], g.data[i + 1], g.data[i + 2])
const palette = [0]
for (const key of [0xC5D,0x3E6,0xF33]) if (!palette.includes(key)) palette.push(key)
const sortedAccents = [...accentBins.entries()].sort((a,b)=>b[1]-a[1])
/* Runtime drawing uses these exact slots. Reserve them before quantizing the
 * scene so changing the cursor/score ink cannot recolour logo pixels. */
for (const [key] of sortedAccents) { if (!palette.includes(key)) palette.push(key); if (palette.length === 10) break }
palette.push(0x0FF) // index 10: cyan cursor/LCD ink
palette.push(0xFFF) // index 11: white game-over ink
palette.push(0x000) // index 12: score-popup outline, not transparent
for (const [key] of sortedAccents) { if (!palette.includes(key)) palette.push(key); if (palette.length === 21) break }
for (const key of [...gameRamp(boardColors,26), ...gameRamp(uiColors,17)]) palette.push(key)
while (palette.length < 64) palette.push(0)
for (const [key] of [...gemBins.entries()].sort((a, b) => b[1] - a[1])) { palette.push(key); if (palette.length === 256) break }
while (palette.length < 256) palette.push(0)
/* Frequency-only palettes spend almost every slot on blue background bins,
 * discarding low-area logo/glow/gem hues. Weighted median cut covers the full
 * gamut, followed by Lloyd refinement in the actual RGB444 colour space. */
const titleBins = new Map()
const menuColor=(r,g,b,weight)=>{
  const key=(Math.round(r/17)<<8)|(Math.round(g/17)<<4)|Math.round(b/17)
  titleBins.set(key,(titleBins.get(key)||0)+weight)
}
for(let i=0;i<title.data.length;i+=4){const r=title.data[i],g=title.data[i+1],b=title.data[i+2];menuColor(r,g,b,r>g*1.3&&r>90?3:1)}
for(const img of [howto,options])for(let i=0;i<img.data.length;i+=4)menuColor(img.data[i],img.data[i+1],img.data[i+2],0.2)
for(const gem of titleGems)for(let i=0;i<gem.data.length;i+=4)if(gem.data[i+3])menuColor(gem.data[i],gem.data[i+1],gem.data[i+2],4)
const channels=key=>[key>>8,(key>>4)&15,key&15]
const samples=[...titleBins].map(([key,w])=>({key,w,c:channels(key)}))
const describe=items=>{
  const weight=items.reduce((s,p)=>s+p.w,0),mean=[0,0,0],variance=[0,0,0]
  for(const p of items)for(let c=0;c<3;c++)mean[c]+=p.c[c]*p.w/weight
  for(const p of items)for(let c=0;c<3;c++)variance[c]+=(p.c[c]-mean[c])**2*p.w
  const axis=variance.indexOf(Math.max(...variance))
  return {items,mean,axis,error:variance.reduce((a,b)=>a+b,0)}
}
const boxes=[describe(samples.filter(p=>p.key!==0&&p.key!==0xFFF))]
while(boxes.length<253){
  let idx=-1,best=-1
  for(let i=0;i<boxes.length;i++)if(boxes[i].items.length>1&&boxes[i].error>best){idx=i;best=boxes[i].error}
  if(idx<0)break
  const box=boxes.splice(idx,1)[0],items=box.items.sort((a,b)=>a.c[box.axis]-b.c[box.axis]||a.key-b.key)
  const half=items.reduce((s,p)=>s+p.w,0)/2;let sum=0,cut=1
  for(let i=0;i<items.length-1;i++){sum+=items[i].w;cut=i+1;if(sum>=half)break}
  boxes.push(describe(items.slice(0,cut)),describe(items.slice(cut)))
}
const pack=c=>(Math.max(0,Math.min(15,Math.round(c[0])))<<8)|(Math.max(0,Math.min(15,Math.round(c[1])))<<4)|Math.max(0,Math.min(15,Math.round(c[2])))
const titlePalette=[0,0,...boxes.map(box=>pack(box.mean))]
while(titlePalette.length<255)titlePalette.push(0)
titlePalette.push(0xFFF)
const refine=()=>{
  const centers=titlePalette.map(channels),sums=centers.map(()=>[0,0,0,0])
  for(const p of samples){let best=1,error=Infinity;for(let i=1;i<256;i++){const d=p.c.reduce((s,c,a)=>s+(c-centers[i][a])**2,0);if(d<error){error=d;best=i}}
    for(let c=0;c<3;c++)sums[best][c]+=p.c[c]*p.w;sums[best][3]+=p.w}
  for(let i=2;i<255;i++)if(sums[i][3])titlePalette[i]=pack(sums[i].slice(0,3).map(c=>c/sums[i][3]))
}
for(let pass=0;pass<3;pass++)refine()
/* Original menuHighlight.png is white. Keep its runtime marker ink stable
 * instead of borrowing whichever colour quantization leaves at index 255. */
titlePalette[255] = 0xFFF
const titleNearest = (r,g,b) => { let best=1,bestD=Infinity; for(let i=1;i<256;i++){const c=titlePalette[i],dr=(c>>8)*17-r,dg=((c>>4)&15)*17-g,db=(c&15)*17-b,d=dr*dr+dg*dg+db*db;if(d<bestD){bestD=d;best=i}} return best }
const titleGemSprites = new Uint8Array(7 * 32 * 32)
for (let g=0;g<7;g++) {
  const scaled=readPngScaled(path.join(media,titleGemNames[g]),26,26,"area")
  for(let y=0;y<26;y++)for(let x=0;x<26;x++){
    const p=(y*26+x)*4
    if(scaled.data[p+3]>=128 && Math.max(scaled.data[p],scaled.data[p+1],scaled.data[p+2])>=18)
      titleGemSprites[g*1024+(y+3)*32+x+3]=titleNearest(scaled.data[p],scaled.data[p+1],scaled.data[p+2])
  }
}
const nearest = (r, g, b, first = 1, last = 63) => { let best = first, bestD = Infinity; for (let i = first; i <= last; i++) { const c = palette[i], dr = (c >> 8) * 17 - r, dg = ((c >> 4) & 15) * 17 - g, db = (c & 15) * 17 - b, d = dr * dr + dg * dg + db * db; if (d < bestD) { bestD = d; best = i } } return best }
const indexImage = (img, transparent = false, first = 1, last = 63) => { const dst = new Uint8Array(img.width * img.height); for (let p = 0; p < dst.length; p++) { const i = p * 4; dst[p] = transparent && img.data[i + 3] === 0 ? 0 : nearest(img.data[i], img.data[i + 1], img.data[i + 2], first, last) } return dst }
const indexGameScene = (img) => {
  const dst = indexImage(img), width = img.width
  let current = new Float32Array((width + 2) * 3), next = new Float32Array(current.length)
  /* Smooth the blue backdrop and warm board with RGB444 error diffusion;
   * keep logo, HUD, button edges and the thin checkerboard grid sharp. */
  for (let y = 0; y < img.height; ++y) {
    const step = y & 1 ? -1 : 1
    for (let x = step === 1 ? 0 : width - 1; x >= 0 && x < width; x += step) {
      const p = y * img.width + x, q = p * 4, e = (x + 1) * 3
      const hud = x < 88 && y >= 36
      const board = x >= 94 && x < 307 && y >= 16 && y < 232 &&
        (x-96)%26 !== 0 && (y-16)%26 !== 0
      if (!hud && !board) continue
      if ([0,1,2].some(c => img.data[q + c] !== boardOnly.data[q + c])) continue
      const rgb = [0,1,2].map(c => Math.max(0, Math.min(255, img.data[q + c] + current[e + c])))
      /* The board can share warm gem shadow tones without changing sprites. */
      const index = nearest(...rgb, 1, board ? 255 : 63), color = channels(palette[index]).map(c => c * 17)
      dst[p] = index
      for (let c = 0; c < 3; ++c) {
        const error = rgb[c] - color[c]
        current[e + step * 3 + c] += error * 7 / 16
        next[e - step * 3 + c] += error * 3 / 16
        next[e + c] += error * 5 / 16
        next[e + step * 3 + c] += error / 16
      }
    }
    current = next; next = new Float32Array(current.length)
  }
  return dst
}
const scene = indexGameScene(background)
const endlessScene = indexGameScene(endlessBackground)
/* Serpentine error diffusion suppresses visible RGB444 gradient contours.
 * Exact white menu glyphs stay exact white; no runtime palette mutation. */
const titleIndexImage = (img, dither=false) => {
  const dst=new Uint8Array(img.width*img.height)
  let current=new Float32Array((img.width+2)*3),next=new Float32Array(current.length)
  for(let y=0;y<img.height;y++){
    const step=y&1?-1:1
    for(let x=step===1?0:img.width-1;x>=0&&x<img.width;x+=step){
      const p=y*img.width+x,q=p*4,e=(x+1)*3
      const rgb=[0,1,2].map(c=>Math.max(0,Math.min(255,img.data[q+c]+(dither?current[e+c]:0))))
      const white=img.data[q]===255&&img.data[q+1]===255&&img.data[q+2]===255
      const index=white?255:titleNearest(...rgb);dst[p]=index
      if(white||!dither)continue
      const color=channels(titlePalette[index]).map(c=>c*17)
      for(let c=0;c<3;c++){
        const error=rgb[c]-color[c]
        current[e+step*3+c]+=error*7/16
        next[e-step*3+c]+=error*3/16;next[e+c]+=error*5/16;next[e+step*3+c]+=error/16
      }
    }
    current=next;next=new Float32Array(current.length)
  }
  return dst
}
const titleScene = titleIndexImage(title,true)
const howtoScene=titleIndexImage(howto,true), optionsScene=titleIndexImage(options,true)
const gemData = new Uint8Array(7 * 24 * 24)
for (let g = 0; g < 7; g++) {
  const scaled = readPngScaled(path.join(media,names[g]),24,24,"area")
  const indexed = indexImage(scaled, true, 64, 255)
  /* The source sheets use opaque black as their transparent surround. */
  for (let p = 0; p < indexed.length; ++p) {
    const q = p * 4
    if (scaled.data[q+3]<128 || (scaled.data[q] < 18 && scaled.data[q + 1] < 18 && scaled.data[q + 2] < 18)) indexed[p] = 0
  }
  gemData.set(indexed, g * 576)
}
// Hardware sprites are 32x32. Centre the 24px original gem inside a
// transparent frame so sprites can follow the original 26px board pitch.
const gemSprites = new Uint8Array(7 * 32 * 32)
for (let g = 0; g < 7; ++g) for (let y = 0; y < 24; ++y) for (let x = 0; x < 24; ++x)
  gemSprites[g * 1024 + (y + 4) * 32 + x + 4] = gemData[g * 576 + y * 24 + x]
// Legacy 4bpp prototype asset; the active game uses the 8bpp patterns above.
const sprite4 = new Uint8Array(7 * 512)
for (let g = 0; g < 7; ++g) for (let y = 0; y < 32; ++y) for (let x = 0; x < 32; x += 2) {
  const at = (px) => { const v = (px < 4 || px >= 28 || y < 4 || y >= 28) ? 0 : gemData[g * 576 + (y - 4) * 24 + px - 4]; return v ? ((v % 15) + 1) : 0 }
  sprite4[g * 512 + y * 16 + (x >> 1)] = (at(x) << 4) | at(x + 1)
}
// VERA tile memory is tile-major (8 rows x 8 columns), not image row-major.
// Tile 0 is transparent; every gem contributes a 3x3 tile block.
const tileData = new Uint8Array(64 + 7 * 9 * 64)
for (let g = 0; g < 7; g++) for (let ty = 0; ty < 3; ty++) for (let tx = 0; tx < 3; tx++) {
  const tile = 1 + g * 9 + ty * 3 + tx
  for (let py = 0; py < 8; py++) for (let px = 0; px < 8; px++) tileData[tile * 64 + py * 8 + px] = gemData[g * 576 + (ty * 8 + py) * 24 + tx * 8 + px]
}
const selectorData = image(32, 32)
// VERA sprites offer 16/32px dimensions. The original 65px selector should
// frame a 24px gem, not spill over its neighbours: centre it in a 32px canvas.
put(selectorData, selector, 4, 4, 24, 24)
const boardMap = new Uint8Array(64 * 32 * 2)
for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
  const baseTile = 1 + (previewBoard[y * 8 + x] - 1) * 9
  for (let ty = 0; ty < 3; ty++) for (let tx = 0; tx < 3; tx++) {
    const cell = (2 + y * 3 + ty) * 64 + 12 + x * 3 + tx
    boardMap[cell * 2] = baseTile + ty * 3 + tx
  }
}
const pal = Buffer.alloc(512)
// VERA palette entry is little-endian $0RGB: byte 0 is $GB, byte 1 is $0R.
for (let i = 0; i < palette.length; i++) { const c = palette[i]; pal[i * 2] = c & 0xff; pal[i * 2 + 1] = (c >> 8) & 15 }
const titlePal = Buffer.alloc(512)
for (let i = 0; i < titlePalette.length; i++) { const c = titlePalette[i]; titlePal[i * 2] = c & 0xff; titlePal[i * 2 + 1] = (c >> 8) & 15 }
const makeRle=(src)=>{const dst=[];for(let i=0;i<src.length;){let run=1;while(run<255&&i+run<src.length&&src[i+run]===src[i])run++;dst.push(run,src[i]);i+=run}return dst.length<src.length?dst:[0,0,...src]}
const gameStored = Buffer.from(makeRle(scene)), endlessStored = Buffer.from(makeRle(endlessScene))
fs.writeFileSync(path.join(out, "game_scene.idx"), scene)
fs.writeFileSync(path.join(out, "game_scene.rle"), gameStored)
fs.writeFileSync(path.join(out, "game_endless.rle"), endlessStored)
fs.writeFileSync(path.join(out, "title_scene.rle"), Buffer.from(makeRle(titleScene)))
fs.writeFileSync(path.join(out, "howto_scene.rle"), Buffer.from(makeRle(howtoScene)))
fs.writeFileSync(path.join(out, "options_scene.rle"), Buffer.from(makeRle(optionsScene)))
fs.writeFileSync(path.join(out, "title_gems_32.idx"), titleGemSprites)
fs.writeFileSync(path.join(out, "game_gems_24.idx"), gemData)
fs.writeFileSync(path.join(out, "game_gems_32.idx"), gemSprites)
const effectsDigits=new Uint8Array(10*256)
for(let n=0;n<10;n++){
  const ink=[]
  for(let r=0;r<7;r++)for(let c=0;c<5;c++)if(glyph[String(n)][r]&(16>>c))
    for(let dy=0;dy<2;dy++)for(let dx=0;dx<2;dx++)ink.push((1+r*2+dy)*16+3+c*2+dx)
  for(const p of ink)for(const d of [-1,1,-16,16])effectsDigits[n*256+p+d]=12
  for(const p of ink)effectsDigits[n*256+p]=11
}
fs.writeFileSync(path.join(out,"effects_digits_16.idx"),effectsDigits)
fs.writeFileSync(path.join(out, "game_gems_4.idx"), sprite4)
fs.writeFileSync(path.join(out, "game_tiles.idx"), tileData)
fs.writeFileSync(path.join(out, "game_board_map.bin"), boardMap)
fs.writeFileSync(path.join(out, "game_board.bin"), Buffer.from(previewBoard))
fs.writeFileSync(path.join(out, "game_selector_32.idx"), indexImage(selectorData, true))
fs.writeFileSync(path.join(out, "game_palette.bin"), pal)
fs.writeFileSync(path.join(out, "title_palette.bin"), titlePal)
fs.writeFileSync(path.join(out, "game_preview.png"), rgbaToPng(base))
fs.writeFileSync(path.join(out, "title_preview.png"), rgbaToPng(title))
const titleIndexedPreview=image(320,240)
for(let p=0;p<titleScene.length;p++){const c=titlePalette[titleScene[p]];titleIndexedPreview.data.set([(c>>8)*17,((c>>4)&15)*17,(c&15)*17,255],p*4)}
for(let g=0;g<7;g++)for(let y=0;y<32;y++)for(let x=0;x<32;x++){
  const index=titleGemSprites[g*1024+y*32+x];if(!index)continue
  const c=titlePalette[index];titleIndexedPreview.data.set([(c>>8)*17,((c>>4)&15)*17,(c&15)*17,255],((104+y)*320+69+g*26+x)*4)
}
fs.writeFileSync(path.join(out,"title_preview_indexed.png"),rgbaToPng(titleIndexedPreview))
const indexedPreview = image(320, 240)
for (let p = 0; p < scene.length; p++) { const c = palette[scene[p]]; indexedPreview.data.set([((c >> 8) & 15) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17, 255], p * 4) }
for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) {
  const g = previewBoard[y * 8 + x] - 1
  for (let py = 0; py < 24; py++) for (let px = 0; px < 24; px++) {
    const index = gemData[g * 576 + py * 24 + px]
    if (!index) continue
    const c = palette[index], p = ((17 + y * 26 + py) * 320 + 97 + x * 26 + px) * 4
    indexedPreview.data.set([((c >> 8) & 15) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17, 255], p)
  }
}
fs.writeFileSync(path.join(out, "game_preview_indexed.png"), rgbaToPng(indexedPreview))
const backgroundPreview = image(320,240)
for(let p=0;p<scene.length;++p){const c=channels(palette[scene[p]]).map(v=>v*17);backgroundPreview.data.set([...c,255],p*4)}
fs.writeFileSync(path.join(out,"game_background_preview_indexed.png"),rgbaToPng(backgroundPreview))
console.log(`Generated VERA assets: scene=${scene.length} B (${gameStored.length} B ${gameStored[0]===0&&gameStored[1]===0?'raw':'RLE'}), gems=${gemData.length} B, palette=${pal.length} B`)
