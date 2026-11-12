# Third-party components

This port builds on the original Freegemas assets and code. The game itself is
distributed under the repository's GPLv2 license.

## Build tools

- **LLVM-MOS SDK** provides the `mos-apple2e-clang` toolchain.
- **Cadius** packages the ProDOS disk image.
- **Node.js**, **Python/NumPy**, **ffmpeg**, and **ffprobe** are used by the
  asset builders.

These tools are not vendored in this directory.

## Apple system files

`PRODOS#FF0000` and `CLOCK.SYSTEM#FF0000` are needed to make the HDV bootable.
They are not included in this repository. Supply them from a ProDOS
distribution you are licensed to use, or point `-DVERA_PRODOS_DIR` at a
directory containing them.

## Audio and graphics

The VERA graphics, PCM music, and sound effects are derived from the original
Freegemas `media/` assets. The music conversion keeps the original track's
attribution and is used only with the game.
