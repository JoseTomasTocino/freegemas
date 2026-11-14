#!/usr/bin/env python3
"""Build the Commander X16 asset set from the Apple //e VERA originals.

Everything is byte-for-byte the same data that the a2vera build uses, except
that the full-screen scenes are split into KERNAL-friendly chunks.  Music is
a ZSM PSG stream in the asset set and is loaded by ZSMKit at game start; the
five sound effects remain short PCM samples.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "x16" / "generated"
OUT = Path(__file__).resolve().parents[1] / "hostfs"
INC = Path(__file__).resolve().parents[1] / "src"

SCENE_CHUNK = 8000

# Same 5x7 bitmap font used by the VERA asset generator.
FONT = {
    "A": (14, 17, 17, 31, 17, 17, 17), "B": (30, 17, 17, 30, 17, 17, 30),
    "C": (14, 17, 16, 16, 16, 17, 14), "D": (30, 17, 17, 17, 17, 17, 30),
    "E": (31, 16, 16, 30, 16, 16, 31), "F": (31, 16, 16, 30, 16, 16, 16),
    "G": (14, 17, 16, 23, 17, 17, 15), "H": (17, 17, 17, 31, 17, 17, 17),
    "I": (31, 4, 4, 4, 4, 4, 31), "J": (7, 2, 2, 2, 2, 18, 12),
    "K": (17, 18, 20, 24, 20, 18, 17), "L": (16, 16, 16, 16, 16, 16, 31),
    "M": (17, 27, 21, 21, 17, 17, 17), "N": (17, 25, 21, 19, 17, 17, 17),
    "O": (14, 17, 17, 17, 17, 17, 14), "P": (30, 17, 17, 30, 16, 16, 16),
    "Q": (14, 17, 17, 17, 21, 18, 13), "R": (30, 17, 17, 30, 20, 18, 17),
    "S": (15, 16, 16, 14, 1, 1, 30), "T": (31, 4, 4, 4, 4, 4, 4),
    "U": (17, 17, 17, 17, 17, 17, 14), "V": (17, 17, 17, 17, 17, 10, 4),
    "W": (17, 17, 17, 21, 21, 27, 17), "X": (17, 10, 4, 4, 4, 10, 17),
    "Y": (17, 10, 4, 4, 4, 4, 4), "Z": (31, 1, 2, 4, 8, 16, 31),
    ":": (0, 4, 4, 0, 4, 4, 0), ".": (0, 0, 0, 0, 0, 4, 4),
    " ": (0, 0, 0, 0, 0, 0, 0), "0": (14, 17, 19, 21, 25, 17, 14),
    "1": (4, 12, 4, 4, 4, 4, 14), "2": (14, 17, 1, 2, 4, 8, 31),
    "3": (30, 1, 1, 14, 1, 1, 30), "4": (2, 6, 10, 18, 31, 2, 2),
    "5": (31, 16, 16, 30, 1, 1, 30), "6": (14, 16, 16, 30, 17, 17, 14),
    "7": (31, 1, 2, 4, 8, 8, 8), "8": (14, 17, 17, 14, 17, 17, 14),
    "9": (14, 17, 17, 15, 1, 1, 14), "?": (14, 17, 1, 2, 4, 0, 4),
    "a": (0, 0, 14, 1, 15, 17, 15), "b": (16, 16, 30, 17, 17, 17, 30),
    "c": (0, 0, 14, 16, 16, 17, 14), "d": (1, 1, 15, 17, 17, 17, 15),
    "e": (0, 0, 14, 17, 31, 16, 14), "f": (6, 8, 28, 8, 8, 8, 8),
    "g": (0, 0, 15, 17, 15, 1, 14), "h": (16, 16, 30, 17, 17, 17, 17),
    "i": (4, 0, 12, 4, 4, 4, 14), "j": (2, 0, 6, 2, 2, 18, 12),
    "k": (16, 16, 18, 20, 24, 20, 18), "l": (12, 4, 4, 4, 4, 4, 14),
    "m": (0, 0, 26, 21, 21, 21, 21), "n": (0, 0, 30, 17, 17, 17, 17),
    "o": (0, 0, 14, 17, 17, 17, 14), "p": (0, 0, 30, 17, 30, 16, 16),
    "q": (0, 0, 15, 17, 15, 1, 1), "r": (0, 0, 22, 25, 16, 16, 16),
    "s": (0, 0, 15, 16, 14, 1, 30), "t": (4, 4, 31, 4, 4, 5, 2),
    "u": (0, 0, 17, 17, 17, 19, 13), "v": (0, 0, 17, 17, 17, 10, 4),
    "w": (0, 0, 17, 17, 21, 21, 10), "x": (0, 0, 17, 10, 4, 10, 17),
    "y": (0, 0, 17, 17, 15, 1, 14), "z": (0, 0, 31, 2, 4, 8, 31),
}

OLD_CREDIT = "Freegemas Apple II VERA port by anomixer 2026"
NEW_CREDIT = "Freegemas Commander X16 port by anomixer 2026"
CREDIT_Y = 222


def palette_rgb(palette: bytes, index: int) -> tuple[int, int, int]:
    lo, hi = palette[index * 2], palette[index * 2 + 1]
    return ((hi & 0x0F) * 17, ((lo >> 4) & 0x0F) * 17, (lo & 0x0F) * 17)


def nearest_palette(palette: bytes, rgb: tuple[int, int, int]) -> int:
    best, best_d = 0, 1 << 30
    for i in range(256):
        pr, pg, pb = palette_rgb(palette, i)
        d = (pr - rgb[0]) ** 2 + (pg - rgb[1]) ** 2 + (pb - rgb[2]) ** 2
        if d < best_d:
            best, best_d = i, d
    return best


def options_credit_patch(raw: bytes, palette: bytes) -> bytes:
    """Replace the Apple II credit line with the Commander X16 one.

    The old line is removed by interpolating the background from the rows
    above and below it; the two strings are the same length, so the menu
    layout does not move.
    """
    data = bytearray(raw)
    x0 = (320 - (len(OLD_CREDIT) * 6 - 1)) // 2
    x1 = x0 + len(OLD_CREDIT) * 6
    top, bottom = CREDIT_Y - 3, CREDIT_Y + 9
    for y in range(top, bottom):
        t = (y - top) / (bottom - top - 1)
        for x in range(max(0, x0 - 2), min(320, x1 + 2)):
            a = palette_rgb(palette, data[(top - 3) * 320 + x])
            b = palette_rgb(palette, data[(bottom + 3) * 320 + x])
            data[y * 320 + x] = nearest_palette(
                palette, tuple(round(a[c] + (b[c] - a[c]) * t) for c in range(3)))
    for i, ch in enumerate(NEW_CREDIT):
        rows = FONT[ch]
        for r, bits in enumerate(rows):
            for c in range(5):
                if bits & (16 >> c):
                    data[(CREDIT_Y + r) * 320 + x0 + i * 6 + c] = 255
    return bytes(data)


def c_header(path: Path, symbol: str, data: bytes) -> None:
    lines = ["#pragma once", "#include <stdint.h>",
             f"static const uint8_t {symbol}[{len(data)}] = {{"]
    for i in range(0, len(data), 16):
        lines.append("  " + ", ".join(f"0x{b:02x}" for b in data[i:i + 16]) + ",")
    lines += ["};", ""]
    path.write_text("\n".join(lines), encoding="ascii")


def split_to(data: bytes, chunk: int, prefix: str, start: int = 0) -> int:
    n = 0
    while start < len(data):
        part = data[start:start + chunk]
        (OUT / f"{prefix}.{n}").write_bytes(part)
        start += chunk
        n += 1
    return n


def patch_game_hud(data: bytes) -> bytes:
    """Fix two HUD artefacts in the X16 game scene only.

    The shared VERA asset is left untouched.  The scene contains a decorative
    ``88:88`` ghost LED behind the timer; the runtime draws a four-character
    timer over it, so the left ghost digit used to remain visible.  The button
    background also has a hard gradient/body boundary that becomes a bright
    horizontal rule across Show hint/Reset/Exit.  Remove the ghost pixels and
    flatten the button body background while preserving the baked text/icons.
    """
    b = bytearray(data)
    assert b[:2] == b"\x00\x00" and len(b) == 2 + 320 * 240
    raw = 2

    # Remove the dark-blue ``88:88`` ghost from the timer panel.  The panel
    # body is 0x2c; the ghost is 0x2e.  Keep the panel border and labels.
    for y in range(96, 116):
        for x in range(14, 78):
            if b[raw + y * 320 + x] == 0x2E:
                b[raw + y * 320 + x] = 0x2C

    # Flatten the button body.  The hard horizontal rule is the 0x2f gradient
    # row; setting those pixels to the same 0x2c as the lower body removes it.
    # Text (0x0b/0x01), icons, and the 0x31/0x33 borders are untouched.
    for y0, y1 in ((169, 183), (188, 202), (216, 230)):
        for y in range(y0, y1 + 1):
            for x in range(8, 83):
                if b[raw + y * 320 + x] == 0x2F:
                    b[raw + y * 320 + x] = 0x2C
    return bytes(b)


def scene_chunks(data: bytes, name: str) -> int:
    return split_to(data, SCENE_CHUNK, name)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    INC.mkdir(parents=True, exist_ok=True)

    # Runtime headers embedded in the overlays (small, read-only data).
    c_header(INC / "game_palette.h", "game_palette", (SRC / "game_palette.bin").read_bytes())
    c_header(INC / "title_palette.h", "title_palette", (SRC / "title_palette.bin").read_bytes())
    c_header(INC / "effects_digits.h", "effects_digits", (SRC / "effects_digits_16.idx").read_bytes())
    c_header(INC / "title_gems.h", "title_gems", (SRC / "title_gems_32.idx").read_bytes())
    c_header(INC / "mouse_hand.h", "mouse_hand", (SRC / "mouse_hand_16.bin").read_bytes())

    (INC / "loading_data.h").write_text(
        "#pragma once\n#define LOADING_TIMED_BLOCKS 186u\n#define LOADING_ENDLESS_BLOCKS 186u\n",
        encoding="ascii",
    )

    # Game scenes are consumed through the original 512-byte block interface.
    for src, prefix in (("game_scene.rle", "game.rle"),
                        ("game_endless.rle", "endless.rle")):
        scene_chunks(patch_game_hud((SRC / src).read_bytes()), prefix)

    # Title/howto/options are copied straight into VRAM 0.  The two-byte 00 00
    # raw marker is dropped because there is no RLE decoder on this path.
    pal = (SRC / "title_palette.bin").read_bytes()
    for src, prefix in (("title_scene.rle", "title"),
                        ("howto_scene.rle", "howto"),
                        ("options_scene.rle", "options")):
        data = (SRC / src).read_bytes()[2:]
        assert len(data) == 76800, (src, len(data))
        if prefix == "options":
            data = options_credit_patch(data, pal)
        for i in range(0, len(data), 8000):
            (OUT / f"{prefix}.v{i // 8000}").write_bytes(data[i:i + 8000])

    (OUT / "gem.pat").write_bytes((SRC / "game_gems_32.idx").read_bytes())

    for name in ("select", "fall", "match1", "match2", "match3"):
        (OUT / f"{name}.pcm").write_bytes((SRC / f"{name}.pcm").read_bytes())


if __name__ == "__main__":
    main()
