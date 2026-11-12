#!/usr/bin/env python3
"""Generate a scripted-mouse regression variant of merlin32/src/main.s.

Run from iigs/merlin32:
    python ../tools/make_mousetest.py [SRC] [OUT]
    python ../tools/make_mousetest.py --ports [SRC] [OUT]

The GSSquared debug socket has no ADB device injection (only the Apple Mouse II
card implements STATE_SET), so the hardware read in `mousePoll` is replaced by a
one-event handover: the harness writes dMEvX/dMEvY (the two $C024 movement
bytes, encoded exactly like the hardware does -- bit7 button/1=up, bits 6-0
signed two's-complement delta) plus dMEvReady, and mousePoll decodes them with the
shipping code.  Everything from the signed decode, clamping, board
hit-test, hover and click handling down to the menu is the real code path; only
the two $C024/$C027 register reads are bypassed.

The variant exposes dMEvReady / dMEvX / dMEvY as extra dbgTab entries.

--ports replaces only register loads, retaining the real polling branches.
dMEvReady is then an axis mask (1=X, 2=Y, 3=X then Y), and the three debug
entries are appended after the shipping table. Run emu/fgmousecheck.ps1 against
an image packaged with this variant. The legacy mode bypasses polling and
keeps its historical debug indices for existing local scripts.
"""
import pathlib
import re
import sys

STUB = """         lda dMEvReady
         beq mpNoEv
         stz dMEvReady
         lda dMEvX
         sta dMByteX
         lda #1
         sta dMNewX
         lda dMEvY
         sta dMByteY
         lda #1
         sta dMNewY
         bra mpHave
mpNoEv   rep #$20
         longa on
         rts

"""

DATA = """dMEvReady   dw 0
dMEvX       dw 0
dMEvY       dw 0
"""

# Replace only the I/O loads, keeping the shipping polling/control flow intact.
# Ready is an axis mask: 1 = X only, 2 = Y only, 3 = X then Y. Reading a byte
# consumes that axis just as $C024 does; repeated $C027 reads do not consume it.
PORTS = """
mtStatus sep #$20
         longa off
         lda dMEvReady
         beq mtIdle
         and #1
         bne mtXReady
         lda #$82
         rts
mtXReady lda #$80
         rts
mtIdle   lda #0
         rts
mtData   sep #$20
         longa off
         lda dMEvReady
         and #1
         beq mtReadY
         lda dMEvReady
         and #$FE
         sta dMEvReady
         lda dMEvX
         rts
mtReadY  stz dMEvReady
         lda dMEvY
         rts

"""


def main() -> None:
    args = [arg for arg in sys.argv[1:] if arg != "--ports"]
    ports = "--ports" in sys.argv
    src_path = pathlib.Path(args[0] if args else "src/main.s")
    out_path = pathlib.Path(args[1] if len(args) > 1 else "src/main_mtest.s")
    src = src_path.read_text(encoding="utf-8")

    begin = src.index("mousePoll anop")
    end = src.index("mpHave   rep #$20", begin)
    block = src[begin:end]
    if ports:
        block, ns = re.subn(r"lda\s+>ADBSTAT", "jsr mtStatus", block)
        block, nd = re.subn(r"lda\s+>MOUSEDAT", "jsr mtData", block)
        if ns != 5 or nd != 4:
            raise SystemExit(f"polling loads changed: expected 5/4, got {ns}/{nd}")
        src = src[:begin] + block + src[end:]
        src = re.sub(r"^\s+END\s*$", PORTS + "         END\n", src, flags=re.MULTILINE)
    else:
        cut = re.search(r"^\s+sep\s+#\$20", block, re.MULTILINE).start()
        src = src[:begin] + block[:cut] + STUB + src[end:]

    src = src.replace("dMCell      dw $FFFF\n", "dMCell      dw $FFFF\n" + DATA)
    if ports:
        # Append rather than shifting existing indices in fgemu.ps1.
        anchor = re.search(r"^\s+adrl\s+dEmBank\s*$", src, re.MULTILINE)
        if not anchor:
            raise SystemExit("dbgTab end not found")
        src = src[:anchor.end()] + "\n         adrl dMEvReady\n         adrl dMEvX\n         adrl dMEvY\n" + src[anchor.end():]
    else:
        src = src.replace(
            "         adrl cellgem\n         adrl dHiTrial\n",
            "         adrl cellgem\n         adrl dMEvReady\n         adrl dMEvX\n"
            "         adrl dMEvY\n         adrl dHiTrial\n",
        )
    src, count = re.subn(r"dsk\s+\.\./build/FREEGEM.S16", "dsk ../build/FREEGEM_MTEST.S16", src)
    if count != 1 or "dMEvReady   dw" not in src:
        raise SystemExit("source anchors changed")
    out_path.write_text(src, encoding="utf-8", newline="\n")
    print("wrote", out_path)


if __name__ == "__main__":
    main()
