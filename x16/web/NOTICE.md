# Third-party notices — x16/web

This page plays the repository's own Commander X16 build. Nothing in this
directory is a game binary; the site build copies `x16/hostfs/` and downloads
the emulator.

## x16-emulator (WebAssembly release r49)

- Upstream: https://github.com/X16Community/x16-emulator
- Release: https://github.com/X16Community/x16-emulator/releases/tag/r49
  (`x16emu_wasm-r49.zip`, SHA-256
  `9711036cf5b33504815b278fa872b8ec20aef9cb609fd7b17f3685d91312628f`)
- Licence: **2-clause BSD**, © 2019 Michael Steil —
  see `emulator-license.txt` (reproduced in full).
- Fetched by `assemble.mjs` at build time into `x16/web/dist/emulator/`
  (`x16emu.js`, `x16emu.wasm`, `x16emu.data`). The archive is never committed;
  `build-cache/` is gitignored.

`x16emu.data` contains the X16 ROM, so the ROM licences apply as well:

## x16-rom

- Upstream: https://github.com/X16Community/x16-rom
- Licence terms: reproduced in `rom-license.md`. The Commodore KERNAL and
  Microsoft BASIC parts are used under the X16 project's licence for X16
  context; the additions are 2-clause BSD.

## Game

The Commander X16 game (`boot.prg`, `loader`, the overlays, scene chunks,
PCM effects and `music.zcm`) is built from this repository's `x16/` sources and
is covered by the repository `LICENSE`. The page (HTML/CSS/JS) is part of
`x16/` and follows the same licence.
