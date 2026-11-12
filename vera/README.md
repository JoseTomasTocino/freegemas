# Freegemas for Apple //e VERA

English | [繁體中文](README-tw.md)

An Apple //e VERA port of Freegemas, compiled to 65C02 code with LLVM-MOS. Graphics use a 320×240 8bpp bitmap, persistent hardware gem sprites, and a top-edge mask. A small resident ProDOS loader loads the title, game, instructions, and options as separate programs.

The build produces a bootable 2,048 KB disk image at `vera/freegemas.hdv`; that generated image is not checked in.

## Requirements and build

You need Node.js, Python/NumPy, ffmpeg/ffprobe, CMake, the LLVM-MOS SDK, and Cadius. Put Cadius on `PATH` or pass `-DCADIUS_EXECUTABLE=/path/to/cadius`.

The packager also needs the ProDOS system files `PRODOS#FF0000` and `CLOCK.SYSTEM#FF0000`. They are not part of this repository; copy them from a ProDOS distribution you are licensed to use into `vera/assets/prodos-system/`, or point `-DVERA_PRODOS_DIR` at a directory containing them.

Run from the repository root:

```powershell
node vera\tools\build_assets.mjs
cmake -S vera\llvm -B vera\llvm\build `
  -DLLVM_MOS_SDK=C:\path\to\llvm-mos-sdk\install `
  -DCADIUS_EXECUTABLE=C:\path\to\cadius.exe `
  -DVERA_PRODOS_DIR=C:\path\to\prodos-system
cmake --build vera\llvm\build --target disk --parallel 4
```

Set `LLVM_MOS_SDK` to the SDK root (the directory containing `bin/`), or pass `-DLLVM_MOS_SDK=...`. Assets come from the original `media/` directory. The build produces VERA slot 2 and slot 4 programs and packages them into `vera/freegemas.hdv`.

Use a 128 KB Apple IIe with VERA-enabled AppleWin or compatible hardware. PCM music streams from disk through a small main-RAM ring; PSG mode preloads the original arrangement into auxiliary RAM, and effects are preloaded into VERA VRAM. Example for VERA-enabled AppleWin:

```powershell
AppleWin.exe -s2 vera -s7 hdc -h1 vera\freegemas.hdv
```

Close or unmount the image before rebuilding if AppleWin has it locked.

## Install from ProDOS files

The HDV volume is named `FREEGEMAS`. To install on another ProDOS volume or in a subdirectory, copy all files from the HDV into the target volume or directory except `PRODOS`. Keep the `FREEGEMAS` marker file with the game files, set the ProDOS prefix to that location, and launch `FREEGEM.SYSTEM`. The loader and game open their programs, scenes, graphics, music, sound effects, and `HISCORE.DAT` by filename, so their block allocation can differ from the packaged HDV. Newly generated file entries include the local build date and time in ProDOS format.

Direct HDV boot and the game-to-title return were verified in AppleWin with the previous template-based image. The new Cadius-generated HDV has been built and its ProDOS catalog checked; booting this newly packaged image still needs verification. File-level installation on VeraSD was confirmed with the earlier image, including persistent high-score writes to `HISCORE.DAT`.

Startup checks for VERA in slot 2 or 4. If neither is detected, it still shows the full text introduction, author, URL, mouse status, and controls. It displays `STATUS: VERA NOT DETECTED` and `STOPPED: VERA REQUIRED IN SLOT 2 OR 4`, then halts without entering the title or game. Keys cannot bypass this stop.

## Controls

- Title: arrow keys select; Space/Enter opens an item. Mouse hover selects an item, and clicking opens it.
- How to Play: press any key or click to return to the title.
- Options: arrow keys select; Space/Enter or a click cycles Music through PCM, PSG, and Off, toggles Sound, or activates Back. Esc returns to the title. Fullscreen is always ON.
- Game: arrow keys move the board cursor; Space selects/swaps gems. With a mouse, click two adjacent gems, or hold the first gem and drag to an adjacent gem to attempt a swap. Each drag triggers only once.
- H shows a hint, R restarts, and Esc returns to the title. Show Hint, Reset Game, and Exit can also be clicked.
- Title EXIT saves pending high scores and returns to the ProDOS Bitsy Bye file menu.

Apple Mouse Cards are detected in slots 4 and 5. With VERA in slot 4, put the Mouse Card in slot 5. All graphical pages use the original hand-shaped pointer. Keyboard controls remain available.

The startup introduction shows ANOMIXER 2026, controls, and the detected mouse slot (or `MOUSE: NONE`). Press any key or wait approximately five seconds to continue; returning from a game does not replay it.

## Gameplay and high scores

Time Trial starts with a two-minute countdown. Endless hides the time panel. The port includes matches, cascades, scoring, hint penalties, sparkle effects, floating score text, and Game Over animations. A move already in progress finishes its cascades before a timed Game Over.

With no legal moves, Endless ends the game. Time Trial drops the old gems off-screen and supplies a new playable board, retaining the score and countdown. R instead starts a fresh game.

Gems remain hardware sprites after landing; ordinary moves do not redraw the whole bitmap. Only affected sprites and changed HUD digits are updated. During a match, surviving gems remain visible while the board is refilled; falling sprite destinations are prepared from the bottom up.

Options displays separate Time Trial and Endless high scores. Pending records are saved to `HISCORE.DAT` when returning through the loader. Closing the emulator before returning to the menu can lose unsaved scores. Disk rebuilds preserve valid existing records. Audio settings currently last only for the running session.

A freshly built image starts with both high scores set to zero.

## Audio and loading

Sound effects come from the original `select.ogg`, `fall.ogg`, and `match1–3.ogg`. They are converted to signed 8-bit mono VERA PCM at rate 21 (8010.86 Hz) with the original gains, and the whole set totals 9,740 bytes. The five streams are preloaded into VERA VRAM starting at `$14800`, so playback needs no disk reads and no auxiliary RAM.

In PCM music mode, a single VERA PCM FIFO carries both music and effects, mixed in software. Music peaks at 61 and effects at 37, so the signed sum cannot wrap. PCM volume 13 (38/64) leaves headroom for the doubled VERA bus in the current apple2ts and AppleWin mixers, including simultaneous effects; this reduces overall playback volume by about 4.5 dB compared with volume 15. Effects replace each other but add on top of music. Effect staging preserves VERA graphics address and control state.

PCM mode streams the complete recorded track. `MUSIC.PCM` is 1,012,224 bytes (1,977 ProDOS blocks, 126.35 seconds). `tools/build_music_pcm.py` renders it with ffmpeg (linear-interp resample to 8,011 Hz, attenuation to about 0.48 full scale, 40-sample fade); the original track already peaks near full scale, so boosting it only pushed the limiter into hard clipping. The limiter at 0.70 is now a safety ceiling that never engages. The game streams it from disk through a 1 KB ring buffer, keeping the FIFO about 1,024 bytes deep and topping it up with 133/134 samples per VSYNC. A frame that overruns its VSYNC returns from `waitvsync` without waiting, so those feeds would fall behind the samples VERA drains in real time; while the audio-low flag (ISR bit 3, FIFO below 1,024) still reports a shallow queue, the tick keeps paying 128-sample catch-up chunks (`MUSIC_CATCHUP`) until the target depth is back, to reduce FIFO underruns; a stall longer than the available buffer can still cause one. Long CPU-bound loops (the board scan, board generation) call `frame_pump()`, which pays the audio work in place when a VSYNC latch is already set. The number of samples actually queued is also the machine's real-time reference: `music_frames_elapsed()` turns it into whole VSYNC ticks (`133514` thousandths of a sample per frame) and the Time Trial countdown adds those ticks, so the two-minute timer now advances at wall-clock speed instead of once per loop iteration (a 1.6-frame cascade used to tick only 1.6 times for 2 frames of music). One SET_MARK per loop and sequential MLI reads up to 1 KB keep disk traffic low; short reads fall back to a 512-byte read. The track loops forever.

Falling-gem animation reuses precomputed easing offsets, and effect staging uses a 65C02 copy loop. The music clock avoids division in the per-frame path. In one instrumented 65C02 model swap, mean cycles between animation waits with music and effects enabled fell from 30,661 to 23,335; 18 of 30 intervals still exceeded a 17,030-cycle frame. These figures exclude real disk and emulator timing and are not a guarantee of 60 FPS.

PSG mode uses the original `music_pure_gained.psg` arrangement, loaded from `MUSIC.PSG` into auxiliary RAM at game startup. PSG playback and the preloaded PCM effects perform no music or effect disk reads during gameplay. Startup, resetting the scene, changing screens, and saving scores can still access the disk. The YM2151 probe is informational; no FM music path is used.

The user confirmed PCM audio, PSG playback, and falling-gem behavior in Apple2TS using the final test image. AppleWin and physical hardware have not been revalidated for this build.

Music cycles through PCM, PSG, and Off; PCM effects have a separate ON/OFF setting. Music plays only during gameplay; R restarts it and Esc mutes, closes the file, and hands the disk back to the loader. Sound OFF does not stop the music.

After the game binary starts, `LOADING GAME...` shows an asset meter for gems, scene, and the five effects; it reaches 100% when the board is ready, with `GAME START` underneath. `MUSIC.PCM` is not part of that meter because it streams during play. The game binary itself loads with the text-only message.

## Project layout

- `llvm/src/`: loader, title/menu programs, game, graphics, mouse, and audio drivers.
- `llvm/tools/build_hdv.py`: ProDOS disk packager.
- `assets/prodos-system/`: optional local location for user-supplied ProDOS system files; ignored by Git.
- `tools/build_assets.mjs`: original-media conversion for VERA graphics.
- `tools/build_mouse.mjs`: original hand-cursor conversion.
- `generated/`: palette, sprite, scene, and audio inputs needed for builds.

## Audio conversion experiments

`tools/build_music_pcm.py` and `tools/build_sound.mjs` are the only audio converters in the build now. Earlier WAV-to-PSG, MIDI, and YM2151 experiments (with their historical filenames) are documented in [music-conversion-research.md](docs/music-conversion-research.md); those historical conversion tools and `MUSIC.VZM` are no longer part of the build; the previously approved PSG asset is retained. Listening previews and analysis outputs go in `llvm/build/`.

## Regression tests

```powershell
python -m pip install py65 numpy
python -u vera\llvm\tools\test_mos.py
python -u vera\llvm\tools\test_sound.py
python -u vera\llvm\tools\test_music.py
python -u vera\llvm\tools\test_psg_music.py
python -u vera\llvm\tools\test_pcm_clock.py
python -u vera\llvm\tools\test_mouse.py
python -u vera\llvm\tools\test_vera_detect.py
```

Tests execute compiled 65C02 binaries against instrumented VERA, ProDOS, and Mouse Card firmware models. Coverage includes both VERA slots, cascades, local updates, hints, timing, high scores, audio streams, menus, and mouse swaps/drags. Private in-memory disk copies keep synthetic scores out of the delivered image. Model tests supplement, but do not replace, AppleWin and hardware testing.

`test_music.py` streams the whole 1,012,224-byte `MUSIC.PCM` byte-exactly on both slots, then checks disk reads, loop point, OFF/ON, effect mixing sample by sample, R restart, and silent Esc. `test_sound.py` verifies the five effects byte-exactly in VRAM, their table offsets, OFF/ON, replacement, drain, port preservation, and that an effect never reopens the disk. `test_pcm_clock.py` drains the FIFO per CPU cycle at 8,010.86 Hz and compares the rendered stream with the source PCM, including a 230 ms starvation gap and a mixed effect window.

The model also emulates the file-level ProDOS MLI calls the resident loader uses (`GET_PREFIX` `$C7`, `OPEN` `$C8`, `READ` `$CA`, `WRITE` `$CB`, `SET_MARK` `$CE`, `GET_EOF` `$D1`, `CLOSE` `$CC`, `QUIT` `$65`) on top of block reads/writes (`$80`/`$81`), so the full cold-boot, title and in-game paths run in the harness again. `test_loading_progress.py` counts the 186 asset blocks the disk actually carries. All of these are still model runs, not AppleWin or hardware verification.
