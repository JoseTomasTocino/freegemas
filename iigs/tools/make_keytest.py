#!/usr/bin/env python3
"""Generate a scripted-key regression variant of merlin32/src/main.s.

Run from iigs/merlin32:
    python ../tools/make_keytest.py '$0044,$0044,$0057,$0000' [src] [out]

The variant keeps all drawing/movement logic; only gameLoop's KBD read is
replaced by a `jsr nextKey` script reader so WASD/ESC can be tested in an
emulator whose window cannot receive automated key input.
"""
import pathlib
import sys

def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: make_keytest.py KEYS [SRC] [OUT]")
    keys = sys.argv[1]
    src_path = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "src/main.s")
    out_path = pathlib.Path(sys.argv[3] if len(sys.argv) > 3 else "src/main_keys.s")

    src = src_path.read_text()
    old = """gameLoop sep #$20
         longa off
         lda >KBD
         bmi keyDown
         rep #$20
         longa on
         brl gameLoop
"""
    repl = """gameLoop
         jsr nextKey
         beq freeze
         brl keyDown
freeze   brl freeze
"""
    tail = """nextKey
         rep #$20
         longa on
         ldx dKeyIdx
         lda keyScript,x
         inc dKeyIdx
         cmp #$0000
         rts

dKeyIdx dw 0
keyScript dw %s

""" % keys

    if old not in src:
        raise SystemExit("gameLoop block not found in %s" % src_path)
    src = src.replace("dsk ../build/FREEGEM.S16", "dsk ../build/FREEGEM_KEYTEST.S16")
    src = src.replace(old, repl)
    src = src.replace("         put ../generated/gem_data.s", tail + "         put ../generated/gem_data.s")
    out_path.write_text(src)
    print("wrote", out_path)

if __name__ == "__main__":
    main()
