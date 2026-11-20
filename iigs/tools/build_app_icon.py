#!/usr/bin/env python3
"""Build a classic Apple IIgs Finder icon file for Freegemas."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from PIL import Image, ImageDraw


def draw_big() -> tuple[Image.Image, Image.Image]:
    # Pixel values are the IIgs standard 640-mode colors used by Finder icons.
    image = Image.new("L", (32, 32), 0)
    mask = Image.new("L", (32, 32), 0)
    art = ImageDraw.Draw(image)
    opaque = ImageDraw.Draw(mask)

    def shape(points, color):
        art.polygon(points, fill=color)
        opaque.polygon(points, fill=15)

    # Match the game's square red gem: clipped pixel corners, black outline,
    # flat red face, and the small white glint at the upper-left.
    shape([(7, 3), (24, 3), (28, 7), (28, 24), (24, 28),
           (7, 28), (3, 24), (3, 7)], 0)
    shape([(8, 5), (23, 5), (26, 8), (26, 23), (23, 26),
           (8, 26), (5, 23), (5, 8)], 4)
    shape([(8, 5), (23, 5), (26, 8), (26, 23), (23, 26),
           (8, 26), (5, 23), (5, 8)], 7)
    shape([(23, 9), (26, 9), (26, 23), (23, 26)], 4)
    shape([(8, 23), (22, 23), (22, 26), (8, 26)], 4)
    shape([(10, 12), (15, 9), (25, 9), (25, 11), (18, 11),
           (16, 13), (10, 13)], 15)
    shape([(10, 14), (12, 12), (14, 12), (11, 15),
           (11, 20), (9, 20), (9, 16)], 15)
    return image, mask


def draw_small() -> tuple[Image.Image, Image.Image]:
    image = Image.new("L", (16, 16), 0)
    mask = Image.new("L", (16, 16), 0)
    art = ImageDraw.Draw(image)
    opaque = ImageDraw.Draw(mask)
    def shape(points, color):
        art.polygon(points, fill=color)
        opaque.polygon(points, fill=15)

    shape([(4, 1), (11, 1), (14, 4), (14, 11), (11, 14),
           (4, 14), (1, 11), (1, 4)], 0)
    shape([(4, 3), (10, 3), (12, 5), (12, 10), (10, 12),
           (4, 12), (3, 10), (3, 4)], 4)
    shape([(4, 3), (10, 3), (12, 5), (12, 10), (10, 12),
           (4, 12), (3, 10), (3, 4)], 7)
    shape([(10, 9), (12, 9), (12, 10), (10, 12)], 4)
    shape([(4, 10), (9, 10), (9, 12), (4, 12)], 4)
    shape([(6, 6), (8, 5), (11, 5), (11, 6), (9, 6),
           (8, 7), (6, 7)], 15)
    shape([(6, 8), (7, 7), (8, 7), (7, 8),
           (7, 10), (6, 10)], 15)
    return image, mask


def pack_plane(image: Image.Image) -> bytes:
    pixels = image.load()
    width, height = image.size
    output = bytearray()
    for y in range(height):
        for x in range(0, width, 2):
            output.append((pixels[x, y] << 4) | pixels[x + 1, y])
    return bytes(output)


def icon_data(image: Image.Image, mask: Image.Image) -> bytes:
    width, height = image.size
    size = ((width + 1) // 2) * height
    return (struct.pack("<4H", 0x8000, size, height, width)
            + pack_plane(image) + pack_plane(mask))


def preview_image(image: Image.Image, mask: Image.Image, size: tuple[int, int]) -> Image.Image:
    palette = [
        (0, 0, 0), (0, 0, 127), (127, 127, 0), (111, 111, 111),
        (127, 0, 0), (127, 0, 127), (255, 127, 0), (255, 127, 127),
        (0, 127, 0), (0, 127, 127), (127, 255, 0), (127, 255, 127),
        (143, 143, 143), (127, 127, 255), (255, 255, 127), (255, 255, 255),
    ]
    indexed = Image.new("P", image.size)
    indexed.frombytes(image.tobytes())
    indexed.putpalette([channel for color in palette for channel in color]
                       + [0] * (768 - len(palette) * 3))
    rgba = indexed.convert("RGBA").resize(size, Image.Resampling.NEAREST)
    alpha = mask.point(lambda p: 255 if p else 0).resize(size, Image.Resampling.NEAREST)
    rgba.putalpha(alpha)
    return rgba


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="Finder icon file output path")
    parser.add_argument("--preview", type=Path, help="optional 4x PNG preview")
    args = parser.parse_args()

    big, big_mask = draw_big()
    small, small_mask = draw_small()
    if args.preview:
        preview = Image.new("RGB", (220, 144), (40, 40, 48))
        preview.paste(preview_image(big, big_mask, (128, 128)), (8, 8))
        preview.paste(preview_image(small, small_mask, (64, 64)), (148, 48))
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        preview.save(args.preview)

    filename = b"FREEGEMAS.ICONS"
    pascal16 = bytes([len(filename)]) + filename
    boss = bytes(64)
    app_name = b"FREEGEM.S16"
    name_filter = bytes([len(app_name)]) + app_name + bytes(15 - len(app_name))
    big_bytes = icon_data(big, big_mask)
    small_bytes = icon_data(small, small_mask)
    record_length = 86 + len(big_bytes) + len(small_bytes)
    record = (struct.pack("<H", record_length) + boss + name_filter
              + struct.pack("<HH", 0x00B3, 0xDB03) + big_bytes + small_bytes)
    header = struct.pack("<IHI", 0, 1, 0) + pascal16
    args.output.parent.mkdir(parents=True, exist_ok=True)
    output = header + record + b"\0\0"
    args.output.write_bytes(output)
    print(f"wrote {args.output} ({len(output)} bytes)")


if __name__ == "__main__":
    main()
