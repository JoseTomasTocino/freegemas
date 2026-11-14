# Freegemas for Commander X16

English | [繁體中文](README-tw.md)

A Commander X16 port of Freegemas, compiled to 65C02 code with the
[LLVM-MOS SDK](https://github.com/llvm-mos/llvm-mos-sdk). It reuses the
Apple //e VERA artwork and the original `media/` assets, but runs natively on
the X16: VERA at `$9F20`, KERNAL I/O, and the X16 keyboard/joystick APIs.

The game is split into a resident loader at `$2000` and overlays at `$3000`
for the intro, title, How to Play, Options, and the game. Graphics use a
320x240 8bpp VERA bitmap plus hardware sprites. Music is a **ZCM stream**:
8,011 Hz mono signed 16-bit PCM streamed from `hostfs/music.zcm` through the
KERNAL `MACPTR` block read. The five short sound effects are signed 16-bit PCM
samples preloaded in banked RAM and mixed into the same VERA FIFO.

## Requirements

- Windows with PowerShell 7 (`pwsh`), Python 3 with NumPy, and the
  LLVM-MOS SDK. Pass `-Sdk <llvm-mos-sdk>/bin`, or set `LLVM_MOS_SDK` to that
  directory.
- The tracked `assets/music.zcm` (2,024,422 bytes, 126.35 s). A normal build
  copies it into `hostfs/` and needs no audio conversion.
- The tracked `generated/` inputs (palettes, sprites, scenes and PCM effects)
  consumed by `tools/build_assets.py`.
- Commander X16 emulator **r49 (Pyrite) or newer** for running the built
  `hostfs/` directory. The R49 `kbdbuf_get` extapi (A=18, `$FEAB`) is used
  for keyboard input.
- 512 KiB of banked RAM: scene chunks use banks 30-39, effects banks 24-28, and
  the HUD cache bank 20. The music never has to be loaded into banked RAM.

`ffmpeg` is not needed; the effect builder uses Python with `soundfile` and
`soxr`. The music regeneration path is described below.

## Build

From this directory:

```powershell
cd x16
.\build.ps1 -Sdk C:\path\to\llvm-mos-sdk\install\bin
```

Or from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File .\x16\build.ps1
```

The build creates:

- `hostfs/` — the runnable HostFS directory (programs, scenes, PCM effects and
  `music.zcm`).
- `build/` — disposable `.bin`, `.map` and intermediate files.

`build.ps1` removes and recreates both output directories, so a clean build
does not inherit a previous `hiscore.dat`.

## Run

```powershell
x16emu.exe `
  -prg x16\hostfs\boot.prg `
  -run `
  -capture `
  -fsroot x16\hostfs `
  -scale 2
```

Add `-capture` to let x16emu receive the mouse, or press `Ctrl+M` after the
window opens. The game paints its own pointer, so the host cursor is hidden.

To capture the audio output as a WAV file, add `-wav x16\out.wav`.
HostFS names are lower-case and case-sensitive.

## Browser web player

A standalone browser player is in [`web/`](web/). It uses the official
x16-emulator WebAssembly r49 build and the same generated `hostfs/` files, so it
runs the actual X16 KERNAL and `boot.prg` in the browser. The build produces a
static `dist/` directory that can be hosted anywhere:

```powershell
cd x16\web
.\build.ps1
python -m http.server 8123 --directory .\dist
```

Then open <http://127.0.0.1:8123/> (add `?auto=1` to boot immediately). See
[`web/README.md`](web/README.md) for requirements, the pinned emulator
checksum, offline caching and the session-only high-score note.

## Controls

- **Title:** arrow keys or the mouse move the pointer; Space, Enter or a left
  click opens an item.
- **How to Play:** any key or a left click returns to the title.
- **Options:** arrow keys or the mouse select; Space or a left click toggles
  Music (ZCM/Off), Sound (On/Off), or selects Back; Esc returns to the title.
- **Game:** arrow keys or the mouse move the cursor; Space/left click selects
  a gem, then an adjacent click/arrow key swaps it. Click the on-screen
  Show hint, Reset game and Exit buttons with the mouse. `H` shows a hint,
  `R` restarts the game, and Esc returns to the title.
- **Game Over:** `R` restarts; Esc returns to the title and saves a pending
  high score.

The same directions and the A/B buttons work through the X16 keyboard
joystick mapping (arrows, `X`/`Ctrl` and `Z`/`Alt` for A/B). The port polls
joystick 0.

## Sprite layers and mouse pointer

Slot 0 belongs to the KERNAL mouse driver and is never used by the game. The
sprite map is: gems **1-64**, mouse hand **65**, hint **66**, cursor **67**,
selection **68**, floating digits **69-88**, particles **89-120**, and the menu
pointer **127**. Gems use VERA z-depth 2 (between layer 0 and layer 1);
overlays and the hand use z-depth 3 (in front of layer 1). At equal z-depth the
sprite at the **lower** attribute address is rendered in front, so the hand at
65 stays above the cursor at 67 and selection at 68. The old hand slot 126 put
the glove behind the cursor frame at 66. Slot 126 would also be late enough
for the hint to lose part of its border to VERA's scanline sprite-clock budget,
so the hint stays at 66. Title gems use z-depth 2 as well, leaving the menu
pointer at slot 127, z-depth 3, visible on top. The menu pointer uses sprite
palette offset 15 with private entries 251/252 (white and black); otherwise it
would inherit the title palette's index 15, which is dark red.

The slot constants are in [effects.h](src/effects.h#L8), and the VERA
attribute writes are in [effects.c](src/effects.c#L36-L41) and
[main.c](src/main.c#L331-L340).

## Music and audio path

- `media/music.ogg` is decoded and downmixed to mono, resampled to
  **8,010.864 Hz** with `soxr` VHQ, scaled by `0.55`, and stored as signed
  16-bit PCM inside a ZCM container. The eight-byte header is
  `00 00 00 <24-bit sample count> 2F 15`: geometry `0x2F` means 16-bit mono and
  VERA rate `21`. The resulting `assets/music.zcm` is 2,024,422 bytes and
  repeats smoothly at a 40-sample fade at each end.
- `music.c` opens the ZCM once after startup I/O and reads it with `MACPTR`,
  skipping the header, so the 2 MB track is never resident in banked RAM. The
  sample clock starts after a **2,048-byte prefill** (about 128 ms), then feeds
  the number of VSYNCs that actually elapsed, not one frame per loop. A VSYNC
  consumes **267.03 bytes** at 8,010.864 Hz; the feeder uses the VERA
  audio-low flag to top up before empty and allows at most eight 510-byte
  catch-up chunks per frame. At EOF it drains the pending FIFO data, closes
  the stream and silences the channel.
- The five effects are built from the original OGGs by
  `tools/build_effects.py`: soxr VHQ to 8,010.864 Hz, mono, peak-normalised,
  and stored as little-endian signed 16-bit PCM. Each effect is preloaded at
  `$A000` in its own bank (24-28), so a 4,806-byte match effect no longer
  crosses the `$BFFF` bank boundary and truncates MATCH3. `mix_effect16()` in
  `music.c` performs a full 16-bit add and clip in the music RAM buffer;
  `pcm_copy` writes only whole 16-bit pairs and retains unsent bytes for the
  next call. VERA uses 16-bit mono at volume 10 (`0x2A`).
- The effect stage is **512 bytes / 256 samples at `$1000`**. A catch-up call
  can request **510 bytes / 255 samples**, so the old 320-byte (160-sample)
  stage mixed only the first part of that call and left the rest music-only.
  `sound_stage()` now loads a fresh slice for every feed call. The old code also
  returned a one-sample leftover after a 512-byte load, leaving most of the
  next 255-sample run without effect data. Both paths produced the chopped,
  intermittent match sound; the fresh-slice path removes them.
- The fall sound is started **before** the 16-frame fall animation, so the
  landing cue is heard while the gems move rather than after they have already
  settled.
- The X16 scene patch also removes the decorative dark-blue `88:88` ghost from
  the timer panel and flattens the hard gradient rule across Show hint/Reset/
  Exit. The timer is drawn with a **12×18 glyph cell generated from
  `media/fuentelcd.ttf` at the original 62 px size**, with separate solid and
  anti-alias-bit masks (`time_glyphs` and `time_edge`). It is right-aligned to
  x=75, uses the original LCD ink colour index 10 with a dark blue anti-alias
  index 5, and no longer uses the heavy binary glyph masks that made the
  foreground look artificially bold against the LED ghost.
- **The audio-noise causes found so far are fixed.** `pcm_read` had two
  `beq pcm_read_done` branches more than 127 bytes from their target. The
  assembler encoded the truncated offset as `B7`, so whenever a read consumed
  exactly the remaining count, the 65C02 jumped *backwards* to `$3142` and
  executed `FF AD 44` as a Rockwell `BBS7`. That was the source of
  `Warning: encountered Rockwell instruction BBS at $00:3143`; it also entered
  the tail of `pcm_open_fail` and corrupted the read state. The two branches
  are now local `bne` plus `jmp`; the warning is gone in post-fix captures.
  Separately, `MACPTR` returns the byte count in **X (low) and Y (high)**, not
  X only. The earlier code wrote `lda #0; sta pcm_read_hi`, shortening every
  full 267/510-byte read to 11/0 bytes and shifting the 16-bit stream. Both X
  and Y are now preserved. `pcm_copy` writes complete 16-bit pairs and
  `music.c` retains the unsent tail; the effects are signed 16-bit PCM.
  The WAV measurements after these fixes are listed under “Validation status”;
  the earlier claim of a 1.0 correlation was wrong and has been removed.
- Music On/Off is the Options setting. The stream is opened even when music is
  off but its samples are zeroed, so the same 16-bit effect mixer is used in
  both modes; with Music Off only effects are audible. `R` resets the board and
  effects but **keeps the stream open** (reopening the HostFS channel during
  play corrupts later reads); Escape/Exit stops it and removes the VSYNC IRQ.
- Keyboard input uses `kbdbuf_get`, so the KERNAL channel used for music never
  redirects keyboard reads. The game accepts both upper- and lower-case `H`
  and `R`.

To regenerate the music and effect assets:

```powershell
python .\tools\build_music_zcm.py
python .\tools\build_effects.py
```

Both builders require Python with `soundfile`, `soxr` and NumPy. The music
builder rewrites `assets/music.zcm`; the effect builder rewrites the five
16-bit `hostfs/*.pcm` files. Then run `.\build.ps1` to rebuild
`hostfs/`; `build.ps1` also calls both builders.

## High scores and files

High scores are stored in two little-endian `uint32` values in
`hostfs/hiscore.dat`, wrapped in a 12-byte `FGH` version-1 header. The file
is saved when returning to the title after a game over, and when exiting from
the title. A fresh build has no seeded high score.

The loader reads all assets by lower-case HostFS filename, so the directory
can be copied as-is to another HostFS root.

## Validation status

Validated in **x16emu r49 (Pyrite)**, Windows, with WAV captures and screenshots
only. There is **no real Commander X16 hardware** here and **no human-ear
listening**; audio statements below are envelope/peak/zero-run/spectral
measurements, not a listening test.

- **Mouse:** with `-capture`, synthetic relative host motion moved the game’s
  pointer (title screenshots), a left click started Timetrial, and in-game
  motion moved the cursor between cells. Clicking a valid adjacent pair
  produced a real in-game match: score changed from 0 to 15 and the board
  cleared/refilled. This is native x16emu mouse/KERNAL validation only.
- **Sprite order:** a forced overlap of the hand and the cursor/selection frame
  showed the glove on top, and the shifted hint slot 66 rendered its full green
  border. This was a native test build with the same attribute values as the
  normal build; it is not a real-hardware test.
- **Music:** after the two out-of-range branch fixes, a 61.7-second native WAV
  capture had no `BBS`/Rockwell warning. After the load period, music ran for
  about 54 seconds; the longest zero run in that interval was **0.389 ms**,
  maximum absolute sample **0.291**, no samples at or above 0.999, and 1-second
  spectral flatness stayed around 0.08-0.18 with no broadband burst. A separate
  24.3-second normal title-to-Timetrial capture had 11 seconds of music after
  loading with no dropouts. The old 30-second explosion is not present in these
  captures.
- **Effects:** a 19.7-second native WAV calling the same
  `sound_play(SFX_MATCH1)` entry point used by gem clearing (music silenced)
  contained twelve match effects, each about 0.30 seconds, peak **0.191**, no
  clipping, and no truncated fragment. In a separate music-plus-match capture,
  after the music had started there was no zero run longer than **2 ms**. The
  actual in-game scoring match above was **not
  recorded to WAV in the same run**; the effect WAV is a separate direct-path
  capture, not a human-ear test.
- Boot, intro, title, Timetrial and gameplay loading, timer countdown, board
  interaction, and the mouse/selection path were exercised in native x16emu.
- The timer uses the antialiased 12×18 `fuentelcd.ttf` masks; the native
  screenshot shows thin LCD strokes and no bold ghost silhouette.
- Earlier checks (not re-run this pass) covered Game Over, high-score write and
  readback, Title Exit to BASIC, and overlay-to-overlay bitmap cleanliness.

Not verified here:

- the complete 126.35-second track to EOF (the longest capture was 61.7 s);
- real hardware PCM level, music/effect balance, timing, and joystick mapping;
- current browser runtime behaviour. The `web/` build was regenerated from the
  current `hostfs/`, but a fresh headless-browser interaction run was not
  completed in this pass. Earlier browser checks reached the title and
  Timetrial; do not treat browser mouse/audio as newly verified.

The two concrete audio bugs fixed in this pass are the shortened `MACPTR`
return count (`X` and `Y` are both consumed now) and the mis-encoded
out-of-range `beq` that jumped into `FF AD 44` (`BBS7`). The latter is the
source of the Rockwell warning and of the corrupted read state that preceded
the old 30-second failure.
