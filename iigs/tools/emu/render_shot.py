"""Render an Apple IIGS Super Hi-Res frame dump to PNG.

Inputs are the raw blobs a debug session reads straight out of the machine:
  --fb   32000 bytes at $012000 (160 bytes per scanline, 2 pixels per byte)
  --pal   up to 512 bytes at $019E00 (16 palettes x 16 RGB444 words)
  --scb   200 bytes at $019D00 (one scanline control byte per row)

Usage:
  python render_shot.py --fb fb_game.bin --pal pal_game.bin --scb scb_game.bin --out shot.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image

FB_LEN = 32000
PAL_LEN = 384
SCB_LEN = 200


def rgb(word: int) -> tuple[int, int, int]:
    r = (word >> 8) & 0xF
    g = (word >> 4) & 0xF
    b = word & 0xF
    return (r * 17, g * 17, b * 17)


def render(fb: bytes, pal: bytes, scb: bytes) -> Image.Image:
    if len(fb) < FB_LEN or len(pal) < PAL_LEN or len(scb) < SCB_LEN:
        raise ValueError(f"short dump: fb={len(fb)} pal={len(pal)} scb={len(scb)}")
    needed = (max(v & 15 for v in scb[:200]) + 1) * 32
    if len(pal) < needed:
        raise ValueError(f"SCB needs {needed} palette bytes, got {len(pal)}")
    palettes = [(pal[i * 2] | (pal[i * 2 + 1] << 8)) for i in range(len(pal)//2)]
    img = Image.new("RGB", (320, 200))
    px = img.load()
    for y in range(200):
        base = (scb[y] & 0x0F) * 16
        row = y * 160
        for xb in range(160):
            v = fb[row + xb]
            px[xb * 2, y] = rgb(palettes[base + (v >> 4)])
            px[xb * 2 + 1, y] = rgb(palettes[base + (v & 0x0F)])
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fb", required=True)
    ap.add_argument("--pal", required=True)
    ap.add_argument("--scb", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--scale", type=int, default=0, help="optional integer upscale")
    a = ap.parse_args()
    img = render(Path(a.fb).read_bytes(), Path(a.pal).read_bytes(), Path(a.scb).read_bytes())
    if a.scale > 1:
        img = img.resize((320 * a.scale, 200 * a.scale), Image.NEAREST)
    img.save(a.out)
    print(f"wrote {a.out} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
