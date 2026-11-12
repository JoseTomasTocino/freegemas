#!/usr/bin/env python3
"""Build the IIGS SHR scene and game assets from the original Freegemas media.

The original 800x600 Windows layout maps to the IIGS 320x200 SHR screen by
x/2.5 and y/3 (320-mode pixels are 0.833 as wide as they are tall, so the
result keeps the original 4:3 proportions).

Outputs (iigs/merlin32/generated/):
  gem_data.s       16 game palettes, art/game SCB tables, compiled gem row offsets, LCD digit masks,
                   board tables (cellgem/celloff/gemoff)
  scene_tt.bin     320x200 4bpp Time Trial scene, exactly 32000 bytes
  scene_end.bin    Endless variant (no "Time left" header/panel)
  preview_tt.png   2x preview of the packed Time Trial scene
  gs2_offsets.json emulator automation data (find patterns, board, legal swaps)

Game artwork is sampled from media/ through shr_art.py. A cached pristine
board restores damage rectangles exactly. GEMS.RAW contains native A16/X16
row blitters compiled for all sixteen SCB palettes, loaded into a locked bank.
HUD panel interiors stay flat for incremental digit redraw.

This generator is deliberately independent: edit it, rerun it, and do not
hand-edit the generated assembly or scene binaries.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from PIL import ImageFilter
from shr_art import build as build_sampled_game, particle_rasters, committed_flat
from hud_art import lcd_masks, bounds, string_origin, SCORE_Y, SCORE_H, SCORE_W, TIME_Y, TIME_H, TIME_W

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "media"
GEN = Path(os.environ.get('IIGS_ASSET_DIR',str(ROOT / 'iigs' / 'merlin32' / 'generated')))

# ---------------------------------------------------------------------------
# Layout (original coords divided by 2.5 horizontally, 3 vertically)
# ---------------------------------------------------------------------------
SCREEN_W, SCREEN_H = 320, 200
BPR = 160                      # bytes per scanline (2 pixels per byte)
BOARD_X, BOARD_Y = 96, 14      # top-left of the 8x8 board
CELL_W, CELL_H = 26, 22
GEM_W, GEM_H = 24, 20          # gem art inside the cell
BOARD_W, BOARD_H = CELL_W * 8, CELL_H * 8   # 208 x 176
PANEL_X, PANEL_W = 7, 77       # left panel column
BTN_W, BTN_H = 78, 14
BUTTONS = [                    # (label, icon file, y)
    ("Show hint", "iconHint.png", 136),
    ("Reset game", "iconRestart.png", 151),
    ("Exit", "iconExit.png", 179),
]
SCORE_DIGIT_Y, SCORE_RIGHT, SCORE_SLOTS = SCORE_Y, 64, 5
TIME_DIGIT_Y, TIME_RIGHT, TIME_SLOTS = TIME_Y, 68, 4
SCORE_FONT_SIZE, SCORE_DIGIT_H = 33, 8
TIME_FONT_SIZE, TIME_DIGIT_H = 62, 15

GEM_NAMES = ["gemWhite", "gemRed", "gemPurple", "gemOrange", "gemGreen", "gemYellow", "gemBlue"]

# Valid no-match preview board, kept in sync with vera/tools/build_assets.mjs.
PREVIEW_BOARD = [
    5, 4, 6, 2, 3, 6, 1, 3,
    1, 1, 6, 2, 2, 6, 5, 5,
    4, 3, 5, 4, 5, 2, 6, 2,
    3, 2, 5, 3, 4, 5, 3, 2,
    5, 4, 4, 3, 3, 5, 1, 4,
    4, 2, 2, 5, 2, 2, 3, 3,
    2, 4, 4, 6, 1, 5, 3, 6,
    1, 3, 3, 6, 1, 4, 5, 6,
]

# 5x7 glyph table (row bits, MSB = left pixel), shared with the VERA generator.
GLYPH = {
    "A": [14, 17, 17, 31, 17, 17, 17], "B": [30, 17, 17, 30, 17, 17, 30],
    "C": [14, 17, 16, 16, 16, 17, 14], "D": [30, 17, 17, 17, 17, 17, 30],
    "E": [31, 16, 16, 30, 16, 16, 31], "F": [31, 16, 16, 30, 16, 16, 16],
    "G": [14, 17, 16, 23, 17, 17, 15], "H": [17, 17, 17, 31, 17, 17, 17],
    "I": [31, 4, 4, 4, 4, 4, 31], "J": [7, 2, 2, 2, 2, 18, 12],
    "K": [17, 18, 20, 24, 20, 18, 17], "L": [16, 16, 16, 16, 16, 16, 31],
    "M": [17, 27, 21, 21, 17, 17, 17], "N": [17, 25, 21, 19, 17, 17, 17],
    "O": [14, 17, 17, 17, 17, 17, 14], "P": [30, 17, 17, 30, 16, 16, 16],
    "Q": [14, 17, 17, 17, 21, 18, 13], "R": [30, 17, 17, 30, 20, 18, 17],
    "S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4],
    "U": [17, 17, 17, 17, 17, 17, 14], "V": [17, 17, 17, 17, 17, 10, 4],
    "W": [17, 17, 17, 21, 21, 27, 17], "X": [17, 10, 4, 4, 4, 10, 17],
    "Y": [17, 10, 4, 4, 4, 4, 4], "Z": [31, 1, 2, 4, 8, 16, 31],
    "a": [0, 0, 14, 1, 15, 17, 15], "b": [16, 16, 30, 17, 17, 17, 30],
    "c": [0, 0, 14, 16, 16, 17, 14], "d": [1, 1, 15, 17, 17, 17, 15],
    "e": [0, 0, 14, 17, 31, 16, 14], "f": [6, 8, 28, 8, 8, 8, 8],
    "g": [0, 0, 15, 17, 15, 1, 14], "h": [16, 16, 30, 17, 17, 17, 17],
    "i": [4, 0, 12, 4, 4, 4, 14], "j": [2, 0, 6, 2, 2, 18, 12],
    "k": [16, 16, 18, 20, 24, 20, 18], "l": [12, 4, 4, 4, 4, 4, 14],
    "m": [0, 0, 26, 21, 21, 21, 21], "n": [0, 0, 30, 17, 17, 17, 17],
    "o": [0, 0, 14, 17, 17, 17, 14], "p": [0, 0, 30, 17, 30, 16, 16],
    "q": [0, 0, 15, 17, 15, 1, 1], "r": [0, 0, 22, 25, 16, 16, 16],
    "s": [0, 0, 15, 16, 14, 1, 30], "t": [4, 4, 31, 4, 4, 5, 2],
    "u": [0, 0, 17, 17, 17, 19, 13], "v": [0, 0, 17, 17, 17, 10, 4],
    "w": [0, 0, 17, 17, 21, 21, 10], "x": [0, 0, 17, 10, 4, 10, 17],
    "y": [0, 0, 17, 17, 15, 1, 14], "z": [0, 0, 31, 2, 4, 8, 31],
    " ": [0, 0, 0, 0, 0, 0, 0],
    "0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14],
    "2": [14, 17, 1, 2, 4, 8, 31], "3": [31, 2, 4, 2, 1, 17, 14],
    "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 30, 1, 1, 17, 14],
    "6": [6, 8, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8],
    "8": [14, 17, 17, 14, 17, 17, 14], "9": [14, 17, 17, 15, 1, 2, 12],
    ":": [0, 0, 4, 0, 0, 4, 0], "!": [4, 4, 4, 4, 4, 0, 4],
    "-": [0, 0, 0, 31, 0, 0, 0], ".": [0, 0, 0, 0, 0, 0, 4],
    ",": [0, 0, 0, 0, 0, 4, 8], "/": [1, 2, 2, 4, 8, 8, 16],
    "'": [4, 4, 8, 0, 0, 0, 0], "?": [14, 17, 1, 2, 4, 0, 4],
}

# Runtime text font: ASCII 32..90 (space, punctuation, digits, A-Z), 8 bytes
# per glyph (7 rows + blank). Emitted at the end of gem_data so the existing
# section offsets (scbtab/gemoff/cellgem/...) do not move.
TEXT_FIRST, TEXT_LAST = 32, 122   # space..z; lowercase reuses the uppercase cells
TEXT_ROW_BYTES = 8


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def dist(a, b):
    return (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2


def rgb444(c):
    return ((c[0] >> 4) << 8) | ((c[1] >> 4) << 4) | (c[2] >> 4)


def kmeans(pixels, k, iters=14):
    """Deterministic k-means over a list of RGB tuples; returns centres sorted
    by luminance."""
    if not pixels:
        return [(0, 0, 0)] * k
    order = sorted(range(len(pixels)), key=lambda i: lum(pixels[i]))
    centers = [tuple(pixels[order[int((i + 0.5) * len(order) / k)]]) for i in range(k)]
    for _ in range(iters):
        sums = [[0, 0, 0, 0] for _ in range(k)]
        for c in pixels:
            best, bd = 0, 1 << 30
            for i, ct in enumerate(centers):
                d = dist(c, ct)
                if d < bd:
                    bd, best = d, i
            s = sums[best]
            s[0] += c[0]
            s[1] += c[1]
            s[2] += c[2]
            s[3] += 1
        centers = [
            (round(s[0] / s[3]), round(s[1] / s[3]), round(s[2] / s[3])) if s[3] else centers[i]
            for i, s in enumerate(sums)
        ]
    return sorted(centers, key=lum)


# ---------------------------------------------------------------------------
# Palette construction
# ---------------------------------------------------------------------------
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
MENU_AMBER = (255, 214, 0)


# Scanline zones. Each zone gets one palette; widths are chosen so no plaque,
# button or logo band is split across two palettes.
ZONES = [
    (0, 27, "logo"),
    (28, 40, "label"),
    (41, 54, "digits"),
    (55, 76, "label"),
    (77, 100, "digits"),
    (101, 135, "plain"),
    (136, 149, "btn0"),
    (150, 164, "btn1"),
    (165, 178, "plain"),
    (179, 192, "btn2"),
    (193, 199, "plain"),
]


# ---------------------------------------------------------------------------
# Scene composition
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Full-screen art screens (title, how to play)
# ---------------------------------------------------------------------------


def screen_zones(scb):
    """Contiguous row ranges per SCB palette index, in screen order."""
    zones = []
    for y in range(SCREEN_H):
        if not zones or zones[-1][2] != scb[y]:
            zones.append([y, y, scb[y]])
        else:
            zones[-1][1] = y
    return [(a, b, i) for a, b, i in zones]


def build_art_screen(img, scb, gem_colours=None, gem_from_y=77, gem_mask=None,
                     palette_source=None, palette_y_pad=0, fit_rgb444=False,
                     ordered_blue_dither=False, dither_mask=None):
    """Quantise a 320x200 RGB image to one 16-colour palette per SCB zone.

    Slots 0/1/2 are forced to black/white/amber on every zone so the runtime
    text blitter (slot 1) and the menu highlight (slot 2) look identical on any
    scanline. Optional overlapping sample rows and RGB444 fitting smooth
    dedicated art palettes. The title uses a wide palette sample across its
    scanline bands so the background remains visually consistent around its
    logo.
    Returns (packed 32000-byte screen, 12x16 RGB palette list)."""
    zones = screen_zones(scb)
    palettes = [None] * 12
    allowed_by_zone = [None] * 12
    for y0, y1, idx in zones:
        if palettes[idx] is not None:
            continue
        source = palette_source or img
        sample_y0 = max(0, y0 - palette_y_pad)
        sample_y1 = min(SCREEN_H - 1, y1 + palette_y_pad)
        sample_step = 2 if fit_rgb444 else 4
        samples = [source.getpixel((x, y)) for y in range(sample_y0, sample_y1 + 1)
                   for x in range(0, SCREEN_W, sample_step)]
        jewel_zone=gem_colours is not None and y0>=gem_from_y
        count=6 if jewel_zone else 13
        centres = kmeans(samples, count, iters=10) if samples else [(0, 0, 0)] * count
        pal = [BLACK, WHITE, MENU_AMBER] + (list(gem_colours) if jewel_zone else []) + list(centres)
        if fit_rgb444:
            pal = [tuple((v >> 4) * 17 for v in colour) for colour in pal]
        palettes[idx] = pal
        allowed_by_zone[idx] = [(c, i) for i, c in enumerate(pal)
                                if not jewel_zone or i < 3 or i >= 10]
    for idx in range(12):
        if palettes[idx] is None:
            palettes[idx] = [BLACK, WHITE, MENU_AMBER] + [(0, 0, 0)] * 13
            allowed_by_zone[idx] = [(c, i) for i, c in enumerate(palettes[idx])]

    out = bytearray(SCREEN_W * SCREEN_H // 2)
    indices = bytearray(SCREEN_W * SCREEN_H)
    bayer4 = ((0, 8, 2, 10), (12, 4, 14, 6),
              (3, 11, 1, 9), (15, 7, 13, 5))
    for y in range(SCREEN_H):
        allowed = allowed_by_zone[scb[y]]
        for x in range(SCREEN_W):
            def choices(px):
                if (gem_colours is not None and gem_mask is not None and
                        y >= gem_from_y and gem_mask.getpixel((px, y))):
                    pal = palettes[scb[y]]
                    return [(c, i) for i, c in enumerate(pal) if i < 2 or 3 <= i <= 9]
                return allowed

            source_pixel = img.getpixel((x, y))
            protected = dither_mask is not None and dither_mask.getpixel((x, y)) >= 128
            is_blue = (not protected and source_pixel[2] > source_pixel[0] * 1.15 and
                       source_pixel[2] > source_pixel[1] * 1.05)
            if ordered_blue_dither and is_blue:
                # A fixed Bayer pattern spreads palette steps evenly across
                # every menu screen, avoiding the irregular clusters and
                # silhouette breaks caused by error diffusion.
                offset = (bayer4[y & 3][x & 3] - 7.5) * 2
                adjusted = tuple(max(0, min(255, source_pixel[k] + offset))
                                 for k in range(3))
            else:
                adjusted = source_pixel
            allowed_pixel = choices(x)
            if ordered_blue_dither and is_blue:
                # UI inks are intentionally reserved for crisp text and
                # selection markers; never let background error land on
                # white, black, amber, or magenta logo clusters.
                first_art_slot = 10 if gem_colours is not None and y >= gem_from_y else 3
                allowed_pixel = [(colour, index) for colour, index in allowed_pixel
                                 if index >= first_art_slot and colour[2] > colour[0] * 1.10
                                 and colour[2] > colour[1] * 0.90]
            slot = min(allowed_pixel, key=lambda entry: dist(adjusted, entry[0]))[1]
            indices[y * SCREEN_W + x] = slot
    for y in range(SCREEN_H):
        row = y * BPR
        for x in range(0, SCREEN_W, 2):
            out[row + x // 2] = (indices[y * SCREEN_W + x] << 4) | indices[y * SCREEN_W + x + 1]
    return bytes(out), palettes


def art_palette_bytes(palettes):
    data = bytearray()
    for p in palettes:
        for c in p:
            data += word_bytes([rgb444(c)])
    return bytes(data)


def build_title_image():
    """Menu art and logo where StateMainMenu::draw
    puts it (x=86 of 800, y=0), scaled by the same 2/5 and 1/3 factors the rest
    of the port uses."""
    bg = Image.open(MEDIA / "stateMainMenu" / "mainMenuBackground.png").convert("RGB")
    bg = bg.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
    logo = Image.open(MEDIA / "stateMainMenu" / "mainMenuLogo.png").convert("RGBA")
    # The source logo includes broad translucent bloom. At IIgs SHR resolution
    # it quantises into a bright blotch above the final S, so keep only the
    # stronger logo pixels before downsampling.
    rgba = logo.load()
    for y in range(logo.height):
        for x in range(logo.width):
            r, g, b, alpha = rgba[x, y]
            if alpha < 128 or (r > 220 and g > 220 and b > 220 and alpha < 250):
                rgba[x, y] = (r, g, b, 0)
    lw = max(1, round(logo.width * SCREEN_W / 800))
    lh = max(1, round(logo.height * SCREEN_H / 600))
    logo = logo.resize((lw, lh), Image.LANCZOS)
    logo_x = round(86 * SCREEN_W / 800)
    bg.paste(logo, (logo_x, 0), logo)
    protect = Image.new('L', (SCREEN_W, SCREEN_H), 0)
    protect.paste(logo.getchannel('A').point(lambda alpha: 255 if alpha else 0), (logo_x, 0))
    return bg, protect


def build_options_image():
    return Image.open(MEDIA / "stateMainMenu" / "mainMenuBackground.png").convert("RGB").resize(
        (SCREEN_W, SCREEN_H), Image.LANCZOS)


def build_howto_image(gem_source):
    """Use the same flat gem rasters as gameplay in both tutorial diagrams."""
    img = Image.open(MEDIA / "howtoScreen.png").convert("RGB").resize(
        (SCREEN_W, SCREEN_H), Image.LANCZOS)
    palette_source = img.copy()
    # Cell origins in the 320x200 tutorial image. Replace each illustrated gem
    # with the complete 24x20 game raster. Pixels use the same per-row palette
    # bank as an in-game gem at y=15, so both its width and hue stay intact.
    examples = [
        (23, 47, 1), (49, 47, 2), (75, 47, 6),
        (23, 69, 2), (49, 69, 7), (75, 69, 2),
        (23, 129, 1), (49, 129, 7), (75, 129, 6),
        (23, 150, 2), (49, 150, 2), (75, 150, 2),
    ]
    px = img.load()
    gem_mask = Image.new('1', (SCREEN_W, SCREEN_H), 0)
    mask_px = gem_mask.load()
    # Key out the old glossy gem silhouettes (the PNGs use an opaque black
    # matte) before drawing the game rasters, otherwise their bevels peek out
    # around the transparent corners of the smaller flat sprites.
    old_gem_names = ["gemWhite", "gemRed", "gemPurple", "gemOrange",
                     "gemGreen", "gemYellow", "gemBlue"]
    blue_origin = blue_bg = None
    for x0, y0, gem in examples:
        ox, oy = x0 - 1, y0 - 1
        old = Image.open(MEDIA / f"{old_gem_names[gem - 1]}.png").convert('RGB')
        old_mask = Image.new('L', old.size, 0)
        old_px, old_mask_px = old.load(), old_mask.load()
        for oy in range(old.height):
            for ox in range(old.width):
                if max(old_px[ox, oy]) >= 24:
                    old_mask_px[ox, oy] = 255
        old_mask = old_mask.resize((25, 22), Image.LANCZOS)
        # The source How-to art bakes a colored aura outside the old matte-keyed
        # gem silhouette. Expand the cleanup mask so no glow survives beside
        # the sharper gameplay raster.
        old_mask = old_mask.filter(ImageFilter.MaxFilter(13 if gem == 7 else 9))
        ring = []
        for yy in range(oy - 2, oy + 24):
            for xx in range(ox - 2, ox + 27):
                if ox <= xx < ox + 25 and oy <= yy < oy + 22:
                    continue
                if not (0 <= xx < SCREEN_W and 0 <= yy < SCREEN_H):
                    continue
                r, g, b = px[xx, yy]
                if 25 < r < 145 and 12 < g < 110 and 8 < b < 90 and r >= g >= b:
                    ring.append((r, g, b))
        fill = tuple(sorted(c[i] for c in ring)[len(ring) // 2] for i in range(3)) if ring else (68, 52, 44)
        if gem == 7:
            blue_origin, blue_bg = (x0, y0), fill
        old_mask_px = old_mask.load()
        for y in range(22):
            for x in range(25):
                if old_mask_px[x, y] >= 96:
                    if gem == 7 and y0 + y >= 148:
                        continue  # keep the selected-row border below this gem
                    px[ox + x, oy + y] = fill
    for x0, y0, gem in examples:
        for y in range(20):
            bank = gem_source['scb'][15 + y]
            palette = gem_source['palettes'][bank]
            for x in range(24):
                off = (gem - 1) * 240 + y * 12 + x // 2
                shift = 4 if x % 2 == 0 else 0
                mask = gem_source['masks'][off]
                transparency = (mask >> shift) & 15
                if transparency:
                    continue
                colour = gem_source['tiles'][bank * 1680 + off]
                index = (colour >> shift) & 15
                px[x0 + x, y0 + y] = palette[index]
                mask_px[x0 + x, y0 + y] = 1
    if blue_origin is not None:
        bx, by = blue_origin
        # Clear the old blue gem's cyan aura outside the new opaque raster.
        # Its source glow is baked into howtoScreen.png and is not part of the
        # actual game gem tile.
        for y in range(max(0, by - 5), min(SCREEN_H, by + 20)):
            for x in range(max(0, bx - 5), min(SCREEN_W, bx + 29)):
                if mask_px[x, y]:
                    continue
                r, g, b = px[x, y]
                if r < 90 and g > r + 24 and b > r + 32 and abs(g - b) < 90:
                    px[x, y] = blue_bg
    # Redraw the swap arrows as clean foreground strokes. The source arrows
    # were antialiased into the original glossy gems, so thresholding them left
    # colored flecks when those gems were replaced by the flat game rasters.
    scale = 4
    layer = Image.new('RGBA', (SCREEN_W * scale, SCREEN_H * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    def bezier(points, steps=32):
        p0, p1, p2, p3 = points
        result = []
        for i in range(steps + 1):
            t = i / steps
            u = 1 - t
            x = u**3*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t**3*p3[0]
            y = u**3*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t**3*p3[1]
            result.append((round(x*scale), round(y*scale)))
        return result

    arrows = [
        (bezier([(43,77),(38,74),(36,66),(40,63)]),
         bezier([(40,63),(42,60),(45,60),(47,61)]),
         [(49,61),(44,58),(45,64)]),
        (bezier([(77,59),(82,62),(85,68),(82,71)]),
         bezier([(82,71),(80,74),(76,75),(74,75)]),
         [(71,75),(76,72),(76,78)]),
    ]
    for first, second, head in arrows:
        path = first + second[1:]
        draw.line(path, fill=(8, 10, 16, 255), width=24, joint='curve')
        draw.line(path, fill=(250, 250, 250, 255), width=14, joint='curve')
        head_px = [(x*scale, y*scale) for x, y in head]
        draw.polygon(head_px, fill=(8, 10, 16, 255))
        tip, left, right = head
        inner = [(tip[0]*scale, tip[1]*scale),
                 (round((left[0]*0.8+tip[0]*0.2)*scale), round((left[1]*0.8+tip[1]*0.2)*scale)),
                 (round((right[0]*0.8+tip[0]*0.2)*scale), round((right[1]*0.8+tip[1]*0.2)*scale))]
        draw.polygon(inner, fill=(250, 250, 250, 255))
    layer = layer.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
    img = Image.alpha_composite(img.convert('RGBA'), layer).convert('RGB')
    arrow_mask = layer.getchannel('A')
    for y in range(50, 84):
        for x in range(34, 96):
            if arrow_mask.getpixel((x, y)):
                mask_px[x, y] = 0
    return img, gem_mask, palette_source


def sample_howto_gem_colours(gem_source):
    """Pick one stable body colour per gem for the tutorial's 16-colour art."""
    colours = []
    for gem in range(7):
        pixels = []
        for y in range(20):
            bank = gem_source['scb'][15 + y]
            palette = gem_source['palettes'][bank]
            for x in range(24):
                off = gem * 240 + y * 12 + x // 2
                shift = 4 if x % 2 == 0 else 0
                if (gem_source['masks'][off] >> shift) & 15:
                    continue
                colour = gem_source['tiles'][bank * 1680 + off]
                rgb = palette[(colour >> shift) & 15]
                hi, lo = max(rgb), min(rgb)
                lum = sum(rgb) / 3
                if (gem == 0 and 100 <= lum <= 245) or (gem != 0 and hi - lo >= 24 and 35 <= lum <= 235):
                    pixels.append(rgb)
        if not pixels:
            pixels = [gem_source['palettes'][0][1]]
        colours.append(tuple(round(sum(c[i] for c in pixels) / len(pixels)) for i in range(3)))
    return colours


# ---------------------------------------------------------------------------
# Gem tiles: variable-span records, hdr = span_bytes<<4 | pad_bytes
# ---------------------------------------------------------------------------


def build_digit_masks(font_path, size, target_h):
    font = ImageFont.truetype(str(font_path), size)
    chars = "0123456789:"
    scaled = {}
    for ch in chars:
        img = Image.new("L", (size * 2, size * 2), 0)
        d = ImageDraw.Draw(img)
        d.text((size // 2, size // 2), ch, fill=255, font=font)
        bb = img.getbbox()
        crop = img.crop(bb)
        w = max(1, round(crop.width * target_h / crop.height))
        scaled[ch] = crop.resize((w, target_h), Image.LANCZOS)
    cellw = max(im.width for im in scaled.values())
    masks = {}
    for ch, im in scaled.items():
        canvas = Image.new("L", (cellw, target_h), 0)
        canvas.paste(im, ((cellw - im.width) // 2, 0))
        bits = [[1 if canvas.getpixel((x, y)) >= 100 else 0
                 for x in range(cellw)] for y in range(target_h)]
        masks[ch] = bits
    return masks, cellw, target_h


# ---------------------------------------------------------------------------
# Board checks
# ---------------------------------------------------------------------------
def find_runs(board):
    runs = []
    for r in range(8):
        run = 1
        for c in range(1, 8):
            if board[r * 8 + c] == board[r * 8 + c - 1]:
                run += 1
            else:
                if run >= 3:
                    runs.append((r, c - run, r, c - 1))
                run = 1
        if run >= 3:
            runs.append((r, 8 - run, r, 7))
    for c in range(8):
        run = 1
        for r in range(1, 8):
            if board[r * 8 + c] == board[(r - 1) * 8 + c]:
                run += 1
            else:
                if run >= 3:
                    runs.append((r - run, c, r - 1, c))
                run = 1
        if run >= 3:
            runs.append((8 - run, c, 7, c))
    return runs


def legal_swaps(board):
    swaps = []
    for r in range(8):
        for c in range(8):
            for dr, dc in ((0, 1), (1, 0)):
                r2, c2 = r + dr, c + dc
                if r2 >= 8 or c2 >= 8:
                    continue
                b = list(board)
                a, i, j = b[r * 8 + c], r2 * 8 + c2, r * 8 + c
                b[i], b[j] = b[j], b[i]
                if find_runs(b):
                    swaps.append([min(i, j), max(i, j)])
    return swaps


# ---------------------------------------------------------------------------
# Emission
# ---------------------------------------------------------------------------
def byte_lines(data):
    return ["         db " + ",".join(f"${v:02X}" for v in data[o:o + 16])
            for o in range(0, len(data), 16)]


def word_bytes(values):
    out = bytearray()
    for v in values:
        out += bytes((v & 0xFF, (v >> 8) & 0xFF))
    return bytes(out)


def emit_masks(masks, cellw, height, ptr_label, data_label, sections):
    chars = "0123456789:"
    offsets, data = [], bytearray()
    for ch in chars:
        offsets.append(len(data))
        for row in masks[ch]:
            b = 0
            nbits = 0
            acc = []
            for bit in row:
                b = (b << 1) | bit
                nbits += 1
                if nbits == 8:
                    acc.append(b)
                    b, nbits = 0, 0
            while nbits:
                b <<= 1
                nbits += 1
                if nbits == 8:
                    acc.append(b)
                    b, nbits = 0, 0
            data += bytes(acc)
    sections[ptr_label] = word_bytes(offsets)
    sections[data_label] = bytes(data)
    return cellw, height


def main():
    GEN.mkdir(parents=True, exist_ok=True)

    assert not find_runs(PREVIEW_BOARD), "preview board must not start with a match"
    swaps = legal_swaps(PREVIEW_BOARD)
    assert swaps, "preview board must have at least one legal swap"

    scb = [next(i for i,(a,b,_kind) in enumerate(ZONES) if a<=y<=b) for y in range(SCREEN_H)]
    # Title gets its own evenly-spaced scanline banks. The first five palettes
    # cover the logo band; palettes 5..11 start at the falling-gem baseline so
    # their fixed gem inks stay correct throughout the title animation.
    title_edges = (0, 18, 36, 54, 72, 88, 104, 120, 136, 152, 168, 184, 200)
    title_scb = [next(i for i, (a, b) in enumerate(zip(title_edges, title_edges[1:]))
                      if a <= y < b) for y in range(SCREEN_H)]
    howto_edges = (0, 20, 41, 57, 73, 89, 105, 121, 137, 153, 169, 185, 200)
    howto_scb = [next(i for i, (a, b) in enumerate(zip(howto_edges, howto_edges[1:]))
                      if a <= y < b) for y in range(SCREEN_H)]
    options_scb = title_scb[:]
    sampled = build_sampled_game(MEDIA, GEM_NAMES, GLYPH, PREVIEW_BOARD)
    palettes = sampled['palettes']
    game_scb = sampled['scb']

    title_source=sampled if os.environ.get('IIGS_ART_STYLE','flat')=='flat' else committed_flat(PREVIEW_BOARD)
    menu_background = build_options_image()
    title_img, title_logo_mask = build_title_image()
    title_scene, title_pals = build_art_screen(
        title_img, title_scb, title_source['palettes'][0][2:9],
        gem_from_y=88, palette_y_pad=100, fit_rgb444=True, ordered_blue_dither=True,
        dither_mask=title_logo_mask)
    howto_gem_colours = sample_howto_gem_colours(title_source)
    howto_img, howto_gem_mask, howto_palette_source = build_howto_image(title_source)
    howto_dither_mask = howto_gem_mask.convert('L')
    howto_scene, howto_pals = build_art_screen(
        howto_img, howto_scb, howto_gem_colours, gem_from_y=41,
        gem_mask=howto_gem_mask, palette_source=howto_palette_source,
        palette_y_pad=100, fit_rgb444=True, ordered_blue_dither=True,
        dither_mask=howto_dither_mask)
    options_scene, options_pals = build_art_screen(
        menu_background, options_scb, palette_y_pad=100,
        fit_rgb444=True, ordered_blue_dither=True)
    scene_tt, scene_end = sampled['packed']
    assert len(scene_tt) == SCREEN_W * SCREEN_H // 2 == len(scene_end)
    (GEN / "title_scene.bin").write_bytes(title_scene)
    (GEN / "howto_scene.bin").write_bytes(howto_scene)
    (GEN / "options_scene.bin").write_bytes(options_scene)
    (GEN / "scene_tt.bin").write_bytes(scene_tt)
    (GEN / "scene_end.bin").write_bytes(scene_end)

    masks_s, cellw_s, h_s = lcd_masks(SCORE_W,SCORE_H,1)
    masks_t, cellw_t, h_t = lcd_masks(TIME_W,TIME_H,2)

    celloff = [(BOARD_Y + r * CELL_H) * BPR + (BOARD_X + c * CELL_W) // 2
               for r in range(8) for c in range(8)]
    gemoff = []
    off = 0
    for _ in GEM_NAMES:
        gemoff.append(off)
        off += 40                # twenty compiled row pointers

    sections = {}
    order = []

    def add(label, data):
        order.append((label, data))

    pal_bytes = bytearray()
    for p in palettes:
        for c in p:
            pal_bytes += word_bytes([rgb444(c)])
    add("gempals", bytes(pal_bytes))
    add("scbtab", bytes(scb))
    add("gemoff", word_bytes(gemoff))
    add("cellgem", word_bytes(PREVIEW_BOARD))
    add("celloff", word_bytes(celloff))
    add("dgtSh", bytes([h_s]))
    add("dgtSpitch", bytes([cellw_s + 1]))
    cw_s = emit_masks(masks_s, cellw_s, h_s, "dgtSptr", "dgtSdata", sections)
    add("dgtSptr", sections["dgtSptr"])
    add("dgtSdata", sections["dgtSdata"])
    add("dgtTh", bytes([h_t]))
    add("dgtTpitch", bytes([cellw_t + 1]))
    emit_masks(masks_t, cellw_t, h_t, "dgtTptr", "dgtTdata", sections)
    add("dgtTptr", sections["dgtTptr"])
    add("dgtTdata", sections["dgtTdata"])
    for prefix,masks in (('dgtS',masks_s),('dgtT',masks_t)):
        ink=bounds(masks)
        add(prefix+'left',word_bytes([pair[0] for pair in ink]))
        add(prefix+'right',word_bytes([pair[1] for pair in ink]))
    # Compile each distinct masked raster row into native A16/X16 code.
    # A 4480-byte offset table precedes deduplicated RTL-terminated row bodies.
    row_pointers = bytearray(); code = bytearray(); compiled = {}
    for bank in range(16):
        for gem in range(7):
            for y in range(20):
                row = b''.join(sampled['masks'][gem*240+y*12+x:gem*240+y*12+x+2] +
                               sampled['tiles'][bank*1680+gem*240+y*12+x:bank*1680+gem*240+y*12+x+2]
                               for x in range(0,12,2))
                if row not in compiled:
                    compiled[row] = 4480 + len(code)
                    for x in range(6):
                        mask = row[x*4:x*4+2]; colour = row[x*4+2:x*4+4]
                        dest = (0x012000+x*2).to_bytes(3,'little')
                        if mask == b'\xff\xff': continue
                        if mask == b'\0\0': code += b'\xa9' + colour
                        else: code += b'\xbf' + dest + b'\x29' + mask + b'\x09' + colour
                        code += b'\x9f' + dest
                    code += b'\x6b'  # RTL: caller preserves DB and A16/X16.
                row_pointers += compiled[row].to_bytes(2,'little')
    # Whole visible gems bypass the twenty per-row dispatches. Three additional
    # locked banks hold long-store native blitters for each raster alignment.
    fast_banks = [bytearray()]; fast_offsets = []; fast_ids = []; fast_dedup = {}
    for alignment in range(22):
        for gem in range(7):
            body = bytearray()
            for y in range(20):
                row = (alignment+y)%22
                bank = min(15,row*16//20) if row<20 else 0
                for x in range(6):
                    off=gem*240+y*12+x*2
                    mask=sampled['masks'][off:off+2]
                    colour=sampled['tiles'][bank*1680+off:bank*1680+off+2]
                    dest=(0x012000+y*160+x*2).to_bytes(3,'little')
                    if mask == b'\0\0': body += b'\xa9'+colour
                    else:
                        body += b'\xb9'+(0xB400+y*104+x*2).to_bytes(2,'little')
                        if mask != b'\xff\xff': body += b'\x29'+mask+b'\x09'+colour
                    body += b'\x9f'+dest
            body += b'\x6b'
            key=bytes(body)
            if key not in fast_dedup:
                if len(fast_banks[-1])+len(body)>65536: fast_banks.append(bytearray())
                fast_dedup[key]=(len(fast_banks)-1,len(fast_banks[-1]))
                fast_banks[-1] += body
            bank,off=fast_dedup[key]; fast_ids.append(bank*2); fast_offsets.append(off)
    assert len(fast_banks)<=3
    while len(fast_banks)<3: fast_banks.append(bytearray())
    assert len(fast_banks[-1])<=0xB400, 'title composite cache must not overwrite sprite code'
    for bank,body in enumerate(fast_banks):
        (GEN / f'gem_fast{bank}.bin').write_bytes(body + bytes(65536-len(body)))
    add("gemFastOffset",word_bytes(fast_offsets))
    add("gemFastBank",word_bytes(fast_ids))
    add("gemFastAlign",word_bytes([((y-15)%22)*14 for y in range(200)]))
    raster = row_pointers + code
    title_base=len(raster); title_pointers=bytearray(); title_code=bytearray()
    for gem in range(7):
        for y in range(20):
            record=bytearray()
            for x in range(0,12,2):
                offset=gem*240+y*12+x
                record+=title_source['masks'][offset:offset+2]
                for value in title_source['tiles'][offset:offset+2]:
                    a,b=value>>4,value&15
                    record.append(((a+1 if 2<=a<=8 else a)<<4)|(b+1 if 2<=b<=8 else b))
            key=bytes(record)
            if key not in compiled:
                compiled[key]=title_base+280+len(title_code)
                for x in range(6):
                    mask=record[x*4:x*4+2]; colour=record[x*4+2:x*4+4]
                    dest=(0x012000+x*2).to_bytes(3,'little')
                    if mask==b'\xff\xff': continue
                    if mask==b'\0\0': title_code+=b'\xa9'+colour
                    else: title_code+=b'\xbf'+dest+b'\x29'+mask+b'\x09'+colour
                    title_code+=b'\x9f'+dest
                title_code+=b'\x6b'
            title_pointers+=compiled[key].to_bytes(2,'little')
    raster+=title_pointers+title_code
    assert len(row_pointers) == 4480 and len(raster) <= 0xB400
    (GEN / 'gem_rasters.bin').write_bytes(raster)
    add('titleGemOff',word_bytes([title_base+i*40 for i in range(7)]))
    add('titleCacheRows',word_bytes([max(0,y-88)*102 for y in range(200)]))
    add('titleRiseY',word_bytes([88+round(112*((30-step)/30)**3) for step in range(31)]))
    add("gameScb", bytes(game_scb))
    add("gamePalOfs", word_bytes([p*280 for p in game_scb]))
    add("cellBgOff", word_bytes([r*22*104+c*13 for r in range(8) for c in range(8)]))
    add("cellGemY", word_bytes([15+r*22 for r in range(8) for c in range(8)]))
    add("cellGemX", word_bytes([49+c*13 for r in range(8) for c in range(8)]))
    add("screenRows", word_bytes([y*160 for y in range(200)]))
    add("boardRows", word_bytes([y*104 for y in range(176)]))
    add("fxStar", particle_rasters(MEDIA))
    txt, txt_off = bytearray(), {}
    for code in range(TEXT_FIRST, TEXT_LAST + 1):
        ch = chr(code)
        rows = GLYPH.get(ch)
        if rows is None and "a" <= ch <= "z":
            rows = GLYPH.get(ch.upper())   # uppercase-only 5x7 cell set
        rows = rows if rows is not None else [0] * 7
        txt_off[ch] = len(txt) // TEXT_ROW_BYTES
        txt += bytes([r & 0x1F for r in rows] + [0])
    add("txtglyphs", bytes(txt))
    # Art-screen palettes are appended last so every existing section offset
    # (cellgem, celloff, gempals, ...) stays put for the automation anchors.
    add("titlepals", art_palette_bytes(title_pals))
    add("howtopals", art_palette_bytes(howto_pals))
    add("optionspals", art_palette_bytes(options_pals))
    add("titleScb", bytes(title_scb))
    add("howtoScb", bytes(howto_scb))
    add("optionsScb", bytes(options_scb))

    # Emit the assembly with running byte offsets for the automation JSON.
    lines = [
        f"gfxBytes equ {len(raster)}",
        "* GENERATED by iigs/tools/build_iigs_assets.py -- do not edit by hand.",
        f"* {len(palettes)} scanline palettes (RGB444 $0RGB words), SCB, gem tiles,",
        "* LCD digit masks and board tables for the 320x200 scene port.",
        f"* Score digit cell {cellw_s}px pitch {cellw_s + 1}; time digit cell {cellw_t}px pitch {cellw_t + 1}.",
    ]
    offsets = {}
    pos = 0
    for label, data in order:
        offsets[label] = pos
        pos += len(data)
        lines.append(label)
        lines += byte_lines(data)

    # Match VERA's 16x16 area-filtered hand cursor. SHR has no sprite layer,
    # so emit packed per-pixel keep/ink planes for the runtime software cursor.
    hand = Image.open(MEDIA / "handCursor.png").convert("RGBA").resize(
        (16, 16), Image.Resampling.BOX)
    hand_keep = bytearray(128)
    hand_ink = bytearray(128)
    for y in range(16):
        for x in range(16):
            r, _g, _b, a = hand.getpixel((x, y))
            index = y * 8 + x // 2
            shift = 4 if x % 2 == 0 else 0
            if a < 128:
                hand_keep[index] |= 0x0F << shift
            elif r > 170:
                hand_ink[index] |= 0x01 << shift  # white, palette index 1
            # Dark opaque pixels are black (index 0); mask already paints them.
    lines += ["* VERA-matched 16x16 hand cursor from media/handCursor.png.",
              "dPtrKeep"] + byte_lines(hand_keep)
    lines += ["dPtrVal"] + byte_lines(hand_ink)
    (GEN / "gem_data.s").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # Preview PNG from the packed scene, plus the runtime-drawn gems and HUD
    # digits so the tile record and mask encodings are verified visually.
    def save_preview(path, packed, pals, preview_scb=scb):
        im = Image.new("RGB", (SCREEN_W, SCREEN_H))
        for y in range(SCREEN_H):
            pal = pals[preview_scb[y]]
            for x in range(SCREEN_W):
                b = packed[y * BPR + x // 2]
                im.putpixel((x, y), pal[b >> 4 if x % 2 == 0 else b & 15])
        im.resize((SCREEN_W * 2, SCREEN_H * 2), Image.NEAREST).save(path)

    save_preview(GEN / "preview_title.png", title_scene, title_pals, title_scb)
    save_preview(GEN / "preview_howto.png", howto_scene, howto_pals, howto_scb)
    save_preview(GEN / "preview_options.png", options_scene, options_pals, options_scb)

    prev = sampled['preview']
    sampled['reference'].save(GEN / 'reference_tt.png')

    def blit_digit(masks, cellw, rows, ch, x, y, slot):
        for yy in range(rows):
            for xx in range(cellw):
                if masks[ch][yy][xx]:
                    prev.putpixel((x + xx, y + yy), palettes[game_scb[y + yy]][slot])

    for value,masks,width,height,y in [('12345',masks_s,cellw_s,h_s,SCORE_DIGIT_Y),('2:00',masks_t,cellw_t,h_t,TIME_DIGIT_Y)]:
        start=string_origin(value,masks,width+1)
        for i,ch in enumerate(value): blit_digit(masks,width,height,ch,start+i*(width+1),y,14)
    prev.resize((SCREEN_W * 2, SCREEN_H * 2), Image.NEAREST).save(GEN / "preview_tt.png")

    pal0 = bytes(pal_bytes[:16])
    meta = {
        "find_pattern": list(pal0),
        "find_pattern_scb": list(bytes(game_scb[:16])),
        "find_pattern_art_scb": list(bytes(scb[:16])),
        "gem_fast_files": ["GEMS0.RAW", "GEMS1.RAW", "GEMS2.RAW"],
        "gem_rasters": {"file": "GEMS.RAW", "bytes": len(raster), "row_table_bytes": 4480,
                        "format": "16 palettes x 7 gems x 20 uint16 offsets; native A16/X16 long-store RTL rows"},
        "sections": offsets,
        "section_total": pos,
        "preview_board": PREVIEW_BOARD,
        "legal_swaps": swaps,
        "scene": {"tt": "SCENE4.RAW", "endless": "SCENE4E.RAW", "bytes": len(scene_tt)},
        "art": {"title": "TITLE.RAW", "howto": "HOWTO.RAW", "options": "OPTIONS.RAW", "bytes": len(title_scene)},
        "layout": {
            "screen": [SCREEN_W, SCREEN_H], "bpr": BPR,
            "board": [BOARD_X, BOARD_Y, BOARD_W, BOARD_H],
            "cell": [CELL_W, CELL_H], "gem": [GEM_W, GEM_H],
            "score_digit_y": SCORE_DIGIT_Y, "score_right": SCORE_RIGHT,
            "score_slots": SCORE_SLOTS, "score_pitch": cellw_s + 1,
            "time_digit_y": TIME_DIGIT_Y, "time_right": TIME_RIGHT,
            "time_slots": TIME_SLOTS, "time_pitch": cellw_t + 1,
            "buttons": [{"label": l, "x": PANEL_X, "y": by, "w": BTN_W, "h": BTN_H}
                        for l, _icon, by in BUTTONS],
            "font": {"first": TEXT_FIRST, "last": TEXT_LAST,
                     "rows": TEXT_ROW_BYTES, "advance": 6},
        },
    }
    (GEN / "gs2_offsets.json").write_text(json.dumps(meta, indent=1), encoding="utf-8")

    print(f"palettes: {len(palettes)}  compiled gem rasters: {len(raster)}B  "
          f"data total: {pos}B")
    if os.environ.get('IIGS_ART_STYLE','flat')=='flat':
        print('Artwork: committed 4acf440 flat scenes and original gem spans.')
    else:
        print(f"aligned opaque gem RGB RMSE: {sampled['gem_rmse']:.2f}; compiled masked rows")
    print(f"score pitch {cellw_s + 1}  time pitch {cellw_t + 1}  legal swaps: {len(swaps)}")
    print(f"wrote scene_tt/scene_end/title/howto ({len(scene_tt)}B each), gem_data.s, gs2_offsets.json")


if __name__ == "__main__":
    main()
