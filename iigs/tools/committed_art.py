# Original artwork generator retained from commit 4acf440.
#!/usr/bin/env python3
"""Build the IIGS SHR scene and game assets from the original Freegemas media.

The original 800x600 Windows layout maps to the IIGS 320x200 SHR screen by
x/2.5 and y/3 (320-mode pixels are 0.833 as wide as they are tall, so the
result keeps the original 4:3 proportions).

Outputs (iigs/merlin32/generated/):
  gem_data.s       12 scanline palettes, SCB table, gem tiles, LCD digit masks,
                   board tables (cellgem/celloff/gemoff)
  scene_tt.bin     320x200 4bpp Time Trial scene, exactly 16000 bytes
  scene_end.bin    Endless variant (no "Time left" header/panel)
  preview_tt.png   2x preview of the packed Time Trial scene
  gs2_offsets.json emulator automation data (find patterns, board, legal swaps)

Board cells retain source-aligned wood shading using the per-scanline palettes.
The cached scene supplies exact pixels to blankCell in main.s after a move. HUD digit areas are flattened to the panel mid colour so the runtime
erase is a plain fill. Ghost LCD digits in the panel art are removed for the
same reason (they conflict with incremental digit redraw at this resolution).

This generator is deliberately independent: edit it, rerun it, and do not
hand-edit the generated assembly or scene binaries.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
MEDIA = ROOT / "media"
GEN = ROOT / "iigs" / "merlin32" / "generated"

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
SCORE_PANEL = (7, 41, 77, 14)
TIME_PANEL = (7, 77, 77, 24)
BUTTONS = [                    # (label, icon file, y)
    ("Show hint", "iconHint.png", 136),
    ("Reset game", "iconRestart.png", 151),
    ("Exit", "iconExit.png", 179),
]
SCORE_DIGIT_Y, SCORE_RIGHT, SCORE_SLOTS = 42, 79, 6
TIME_DIGIT_Y, TIME_RIGHT, TIME_SLOTS = 78, 76, 5
SCORE_FONT_SIZE, SCORE_DIGIT_H = 33, 8
TIME_FONT_SIZE, TIME_DIGIT_H = 62, 15

# Fixed palette slot semantics on board scanlines (0..13); 14/15 are per-region
# extras. Slot 13 stays reserved for the green hint frame drawn by the game.
S_BLACK, S_WHITE, S_WOOD, S_WOODD, S_WOODL, S_BLUE, S_HINT = 0, 1, 9, 10, 11, 12, 13

LAVENDER = (160, 169, 255)     # original score/time header colour
CYAN = (78, 193, 190)          # original score/time digit colour
HINT_GREEN = (51, 238, 102)
PANEL_MID = (16, 32, 80)       # flat colour used inside the HUD panels ($125)
ACCENTS = [                    # (bright, dark) extra pair per button group
    ((192, 80, 208), (112, 48, 112)),   # hint: purple $C5D / $737
    ((48, 224, 96), (32, 128, 48)),     # reset: green $3E6 / $283
    ((240, 48, 48), (128, 32, 32)),     # exit: red $F33 / $822
]

GEM_NAMES = ["gemWhite", "gemRed", "gemPurple", "gemOrange", "gemGreen", "gemYellow", "gemBlue"]
GEM_DARK_LO, GEM_DARK_HI = 0.10, 0.90   # luminance percentiles -> black/white tones

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

BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


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


def quant(px, allowed, x, y):
    """allowed: list of (rgb, slot). Straight nearest-colour pick.

    Ordered (Bayer) dithering between the two nearest slots was tried on the
    ART screens and measured worse than plain nearest-colour: the 13 k-means
    centres per zone already sit close to the source colours, so toggling
    between slot N and slot N+1 adds a visible cross-hatch over the smooth
    gradient without buying any accuracy. Measured against the resized source
    (mean channel error in RGB444 steps / high-frequency energy):
        title  dither 0.19 steps, hf 4.08   ->  nearest 0.15 steps, hf 3.19
        howto  dither 0.29 steps, hf 5.56   ->  nearest 0.22 steps, hf 4.15
    The game scene keeps its own Bayer ramp in build_scene (the diagonal rays
    there are drawn, not sampled from a photo), so BAYER is still used."""
    return min(allowed, key=lambda e: dist(px, e[0]))[1]


# ---------------------------------------------------------------------------
# Palette construction
# ---------------------------------------------------------------------------
# Slot map shared by every game-screen zone (the runtime blitter, digit eraser
# and hint frame hard-code these nibbles):
#   0 black        1 white        2..8 gem bodies (gem 1..7)
#   9/10/11 wood tones            12 blue background / logo ink
#   13 hint green  14/15 zone extras (logo tones, HUD accent, button accent)
BLACK = (0, 0, 0)
WHITE = (255, 255, 255)
MENU_AMBER = (255, 214, 0)

LABEL_BLUE = (150, 180, 255)   # "Score" / "Time left" header text
PANEL_FILL = (16, 46, 82)      # HUD plaque interior == the digit erase colour
CYAN = (78, 193, 190)          # LCD digits (slot 14 on the HUD rows)
HINT_GREEN = (51, 238, 102)    # hint frame (slot 13 on every row)
PANEL_EDGE = (95, 150, 210)    # plaque/button border (slot 12 on every zone)
LOGO_TONES = [(243, 69, 196), (195, 40, 158), (105, 8, 104)]

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
ZONE_KIND = [""] * SCREEN_H


def lighten(c, f):
    return tuple(min(255, int(v + (255 - v) * f)) for v in c)


def gem_bodies():
    """One vivid body colour per gem: the dominant k-means cluster of each
    source gem, slightly brightened so it still reads on the dark wood."""
    bodies = []
    for name in GEM_NAMES:
        im = Image.open(MEDIA / f"{name}.png").convert("RGBA").resize((GEM_W, GEM_H), Image.LANCZOS)
        px = [(r, g, b) for r, g, b, a in
              (im.getpixel((x, y)) for y in range(GEM_H) for x in range(GEM_W))
              if a >= 128 and r + g + b >= 30]
        cs = kmeans(px, 5)
        counts = [sum(1 for p in px if dist(p, q) == min(dist(p, c) for c in cs)) for q in cs]
        body = cs[max(range(len(cs)), key=lambda i: counts[i])]
        bodies.append(tuple(min(255, int(v * 1.10)) for v in body))
    return bodies


def build_palettes(base_rgb, menu_rgb):
    """Return (palettes, scb, ctx). The art is only used as a colour source: the
    board, plaques, buttons and logo are drawn procedurally so no area depends
    on ordered dithering between two far-apart palette entries."""
    board_px = [base_rgb.getpixel((x, y))
                for y in range(BOARD_Y + 2, BOARD_Y + BOARD_H - 2)
                for x in range(BOARD_X + 2, BOARD_X + BOARD_W - 2)]
    wood_deep, wood_dark, wood_mid, wood_light = kmeans(board_px, 4)
    gems = gem_bodies()

    palettes = []
    scb = [0] * SCREEN_H
    for zi, (y0, y1, kind) in enumerate(ZONES):
        for y in range(y0, y1 + 1):
            scb[y] = zi
            ZONE_KIND[y] = kind
        x0, x1 = (0, 6) if kind == "logo" else (0, 3)

        def row_blue(y):
            px = [base_rgb.getpixel((x, y)) for x in range(x0, x1 + 1)]
            return tuple(int(sum(p[i] for p in px) / len(px)) for i in range(3))

        # Keep three source-fitted wood shades in slots 9..11. Slot 12 is the
        # backdrop ink (and a logo shade in the top band), leaving a fourth
        # wood tone in plain bands for more texture.
        # Fit each SCB band locally so wood lighting changes smoothly down the
        # original board instead of collapsing to a two-colour checker.
        wood_rows = range(max(BOARD_Y + 2, y0 - 1), min(BOARD_Y + BOARD_H - 2, y1 + 2))
        wood_samples = [base_rgb.getpixel((x, y)) for y in wood_rows
                        for x in range(BOARD_X + 2, BOARD_X + BOARD_W - 2, 2)]
        row_wood = kmeans(wood_samples, 4) if wood_samples else (wood_deep, wood_dark, wood_mid, wood_light)
        p = [BLACK, WHITE] + gems + [row_wood[2], row_wood[0], row_wood[3], row_blue(y1), HINT_GREEN]
        if kind == "logo":
            p[11] = (0, 68, 136)               # match the darker game-screen backdrop
            p[12] = LOGO_TONES[0]              # no rays on the logo band
            p += [LOGO_TONES[1], LOGO_TONES[2]]
        elif kind == "label":
            p[12] = (0, 68, 136)
            p += [LABEL_BLUE, PANEL_FILL]
        elif kind == "digits":
            p[12] = (0, 68, 136)
            p += [CYAN, PANEL_FILL]
        elif kind == "plain":
            p[12] = (0, 68, 136)
            p += [row_wood[1], PANEL_FILL]
        else:
            k = int(kind[-1])
            p[12] = (0, 68, 136)
            p += [ACCENTS[k][0], PANEL_FILL]
        assert len(p) == 16, (kind, len(p))
        palettes.append(p)
    assert len(palettes) <= 16
    return palettes, scb, {"wood": (wood_deep, wood_dark, wood_mid, wood_light),
                           "gems": gems, "base": base_rgb, "palettes": palettes, "scb": scb}


# ---------------------------------------------------------------------------
# Scene composition
# ---------------------------------------------------------------------------
BUTTON_LABEL_SLOT = 1          # white button captions
BUTTON_ICON_SLOT = 14          # per-button accent colour
LABEL_SLOT = 14                # coloured zone-14 header text


def draw_text_grid(grid, s, x, y, slot_value):
    """5x7 glyphs straight into the slot grid (no palette quantisation)."""
    for ch in s:
        rows = GLYPH.get(ch)
        if rows is None:
            rows = GLYPH.get(ch.upper(), [0] * 7)
        for yy in range(7):
            bits = rows[yy]
            for xx in range(5):
                if bits & (16 >> xx) and 0 <= y + yy < SCREEN_H and 0 <= x + xx < SCREEN_W:
                    grid[y + yy][x + xx] = slot_value
        x += 6


def text_w(s):
    return 6 * len(s) - 1


def plaque(grid, x0, y0, x1, y1, fill, edge):
    """Rounded rectangle: 1px border in `edge`, interior in `fill`, corners cut
    so the plaque reads as a rounded plaque instead of a hard box."""

    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x == x0 or x == x1) and (y == y0 or y == y1):
                continue
            if x == x0 or x == x1 or y == y0 or y == y1:
                grid[y][x] = edge
            else:
                grid[y][x] = fill


def build_scene(ctx, time_panel):
    palettes, scb = ctx["palettes"], ctx["scb"]
    base = ctx["base"]
    wood_deep, wood_dark, wood_mid, wood_light = ctx["wood"]
    grid = [[0] * SCREEN_W for _ in range(SCREEN_H)]

    # Background uses the blue ink in slot 12; slot 11 is a third wood tone.
    zstart = {}
    for y0, y1, kind in ZONES:
        for y in range(y0, y1 + 1):
            zstart[y] = (y0, y1 - y0 + 1)
    for y in range(SCREEN_H):
        y0, span = zstart[y]
        frac = (y - y0 + 0.5) / span
        thr = int(frac * 16)
        # the logo band keeps its dedicated blue background and logo tones
        if ZONE_KIND[y] == "logo":
            for x in range(SCREEN_W):
                grid[y][x] = 11
            continue
        for x in range(SCREEN_W):
            grid[y][x] = 12 if BAYER[y % 4][x % 4] < thr else 15

    # Logo band (rows 0..27): quantise the pink wordmark to three logo tones
    # plus white/black -- no dithering, so the wordmark stays crisp.
    logo_choices = [(BLACK, 0), (WHITE, 1), (LOGO_TONES[0], 12),
                    (LOGO_TONES[1], 14), (LOGO_TONES[2], 15)]
    mark = [(x, y) for y in range(0, 28) for x in range(0, 96)
            if base.getpixel((x, y))[0] > base.getpixel((x, y))[2] + 36]
    if mark:
        bx0, bx1 = min(p[0] for p in mark) - 2, max(p[0] for p in mark) + 2
        by0, by1 = min(p[1] for p in mark) - 2, max(p[1] for p in mark) + 2
        for y in range(max(0, by0), min(28, by1 + 1)):
            for x in range(max(0, bx0), min(96, bx1 + 1)):
                c = base.getpixel((x, y))
                grid[y][x] = min(logo_choices, key=lambda e: dist(c, e[0]))[1]

    # Board: retain the source wood and cell shading. The cached scene is also
    # the exact restoration image used after gem moves, so textured cells need
    # no separate runtime redraw path.
    BOARD_EXT_W = 212
    errors = [[0.0, 0.0, 0.0] for _ in range(BOARD_EXT_W + 2)]
    next_errors = [[0.0, 0.0, 0.0] for _ in range(BOARD_EXT_W + 2)]
    previous_bank = -1
    for y in range(BOARD_Y, BOARD_Y + BOARD_H):
        if scb[y] != previous_bank:
            errors = [[0.0, 0.0, 0.0] for _ in range(BOARD_EXT_W + 2)]
            next_errors = [[0.0, 0.0, 0.0] for _ in range(BOARD_EXT_W + 2)]
            previous_bank = scb[y]
        gy = y - BOARD_Y
        for x in range(BOARD_X, BOARD_X + BOARD_EXT_W):
            gx = x - BOARD_X
            if gx < 2 or gx >= BOARD_EXT_W - 2 or gy < 2 or gy >= BOARD_H - 2:
                grid[y][x] = 0
            else:
                if ZONE_KIND[y] == "logo":
                    candidates = (9, 10)
                else:
                    candidates = (9, 10, 11, 14) if ZONE_KIND[y] == "plain" else (9, 10, 11)
                pos = gx + 1
                source = base.getpixel((x, y))
                colour = tuple(max(0, min(255, source[k] + errors[pos][k])) for k in range(3))
                slot = min(candidates, key=lambda i: dist(colour, palettes[scb[y]][i]))
                grid[y][x] = slot
                chosen = palettes[scb[y]][slot]
                # Diffuse palette error only through the static board artwork;
                # preserve the two-pixel rim and 1px cell grid as crisp lines.
                if (gx % CELL_W >= 2 and gy % CELL_H >= 2):
                    error = [colour[k] - chosen[k] for k in range(3)]
                    for k in range(3):
                        errors[pos + 1][k] += error[k] * 7 / 16
                        next_errors[pos - 1][k] += error[k] * 3 / 16
                        next_errors[pos][k] += error[k] * 5 / 16
                        next_errors[pos + 1][k] += error[k] / 16
        errors, next_errors = next_errors, [[0.0, 0.0, 0.0] for _ in range(BOARD_EXT_W + 2)]

    # Left HUD column.
    draw_text_grid(grid, "Score", PANEL_X + (PANEL_W - text_w("Score")) // 2, 30, LABEL_SLOT)
    plaque(grid, PANEL_X, 41, PANEL_X + PANEL_W - 1, 54, 15, 1)
    if time_panel:
        draw_text_grid(grid, "Time left", PANEL_X + (PANEL_W - text_w("Time left")) // 2, 62,
                       LABEL_SLOT)
        plaque(grid, PANEL_X, 77, PANEL_X + PANEL_W - 1, 100, 15, 1)

    for label, icon, by in BUTTONS:
        plaque(grid, PANEL_X, by, PANEL_X + BTN_W - 1, by + BTN_H - 1, 15, 1)
        ic = Image.open(MEDIA / icon).convert("RGBA").resize((12, 12), Image.LANCZOS)
        for yy in range(12):
            for xx in range(12):
                if ic.getpixel((xx, yy))[3] >= 128:
                    grid[by + 1 + yy][PANEL_X + 3 + xx] = BUTTON_ICON_SLOT
        draw_text_grid(grid, label, PANEL_X + 13 + (BTN_W - 14 - text_w(label)) // 2, by + 4,
                       BUTTON_LABEL_SLOT)

    out = bytearray(SCREEN_W * SCREEN_H // 2)
    for y in range(SCREEN_H):
        for x in range(0, SCREEN_W, 2):
            out[y * BPR + x // 2] = (grid[y][x] << 4) | grid[y][x + 1]
    return bytes(out)


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


def build_art_screen(img, scb):
    """Quantise a 320x200 RGB image to one 16-colour palette per SCB zone.

    Slots 0/1/2 are forced to black/white/amber on every zone so the runtime
    text blitter (slot 1) and the menu highlight (slot 2) look identical on any
    scanline; the remaining 13 slots come from k-means over the zone's pixels.
    Returns (packed 32000-byte screen, 12x16 RGB palette list)."""
    zones = screen_zones(scb)
    palettes = [None] * 12
    allowed_by_zone = [None] * 12
    for y0, y1, idx in zones:
        if palettes[idx] is not None:
            continue
        samples = [img.getpixel((x, y)) for y in range(y0, y1 + 1)
                   for x in range(0, SCREEN_W, 4)]
        centres = kmeans(samples, 13, iters=10) if samples else [(0, 0, 0)] * 13
        pal = [BLACK, WHITE, MENU_AMBER] + list(centres)
        palettes[idx] = pal
        allowed_by_zone[idx] = [(c, i) for i, c in enumerate(pal)]
    for idx in range(12):
        if palettes[idx] is None:
            palettes[idx] = [BLACK, WHITE, MENU_AMBER] + [(0, 0, 0)] * 13
            allowed_by_zone[idx] = [(c, i) for i, c in enumerate(palettes[idx])]

    out = bytearray(SCREEN_W * SCREEN_H // 2)
    for y in range(SCREEN_H):
        allowed = allowed_by_zone[scb[y]]
        row = y * BPR
        for x in range(0, SCREEN_W, 2):
            a = quant(img.getpixel((x, y)), allowed, x, y)
            b = quant(img.getpixel((x + 1, y)), allowed, x + 1, y)
            out[row + x // 2] = (a << 4) | b
    return bytes(out), palettes


def art_palette_bytes(palettes):
    data = bytearray()
    for p in palettes:
        for c in p:
            data += word_bytes([rgb444(c)])
    return bytes(data)


def build_title_image():
    """Menu art with the Freegemas logo composited where StateMainMenu::draw
    puts it (x=86 of 800, y=0), scaled by the same 2/5 and 1/3 factors the rest
    of the port uses."""
    bg = Image.open(MEDIA / "stateMainMenu" / "mainMenuBackground.png").convert("RGB")
    bg = bg.resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
    logo = Image.open(MEDIA / "stateMainMenu" / "mainMenuLogo.png").convert("RGBA")
    lw = max(1, round(logo.width * SCREEN_W / 800))
    lh = max(1, round(logo.height * SCREEN_H / 600))
    logo = logo.resize((lw, lh), Image.LANCZOS)
    bg.paste(logo, (round(86 * SCREEN_W / 800), 0), logo)
    return bg


def build_howto_image():
    return Image.open(MEDIA / "howtoScreen.png").convert("RGB").resize(
        (SCREEN_W, SCREEN_H), Image.LANCZOS)


# ---------------------------------------------------------------------------
# Gem tiles: variable-span records, hdr = span_bytes<<4 | pad_bytes
# ---------------------------------------------------------------------------
def build_tiles():
    """Variable-span gem records: header byte = span_bytes<<4 | pad_bytes,
    then span bytes of packed pixels. Three tones per gem: slot 0 black
    outline, slot 1 white glint, slot 1+gem body colour (the palette supplies
    the body, so a gem looks the same on every scanline zone). Transparent
    pixels outside the span are skipped by the blitter (the scene wood shows
    through)."""
    tiles = []
    for gi, name in enumerate(GEM_NAMES, start=1):
        im = Image.open(MEDIA / f"{name}.png").convert("RGBA").resize((GEM_W, GEM_H), Image.LANCZOS)
        col = [[im.getpixel((x, y)) for x in range(GEM_W)] for y in range(GEM_H)]
        shape = [[col[y][x][3] >= 128 and sum(col[y][x][:3]) >= 30 for x in range(GEM_W)]
                 for y in range(GEM_H)]
        body_px = [col[y][x][:3] for y in range(GEM_H) for x in range(GEM_W) if shape[y][x]]

        outline = [[False] * GEM_W for _ in range(GEM_H)]
        for y in range(GEM_H):
            for x in range(GEM_W):
                if shape[y][x] and (x == 0 or y == 0 or x == GEM_W - 1 or y == GEM_H - 1
                                    or not shape[y][x - 1] or not shape[y][x + 1]
                                    or not shape[y - 1][x] or not shape[y + 1][x]):
                    outline[y][x] = True

        inner = [(x, y) for y in range(GEM_H) for x in range(GEM_W)
                 if shape[y][x] and not outline[y][x]]
        inside = set(inner)

        def rim_dist(x, y):
            """1 when a 4-neighbour is outside the body, 2 one step further in."""
            for d, rng in ((1, ((1, 0), (-1, 0), (0, 1), (0, -1))),
                           (2, ((2, 0), (-2, 0), (0, 2), (0, -2), (1, 1), (-1, 1), (1, -1), (-1, -1)))):
                for dx, dy in rng:
                    if (x + dx, y + dy) not in inside:
                        return d
            return 3
        ys = [p[1] for p in inner] or [0]
        y_split = min(ys) + (max(ys) - min(ys) + 1) * 0.55   # glint lives up top
        lums = sorted(lum(col[y][x][:3]) for x, y in inner)
        cut = lums[int(len(lums) * 0.96)] if lums else 255

        def neighbours_ok(x, y):
            n = 0
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < GEM_W and 0 <= ny < GEM_H and shape[ny][nx] and not outline[ny][nx]:
                    n += 1
            return n >= 2

        glint = [[False] * GEM_W for _ in range(GEM_H)]
        for x, y in inner:
            if y <= y_split and lum(col[y][x][:3]) >= cut and neighbours_ok(x, y):
                glint[y][x] = True
        # Source luminance decides how far inside the body a pixel sits; the
        # two in-between tones are ordered-dithered against white/black so a
        # 16-colour palette still reads as a rounded, glossy stone instead of a
        # flat silhouette (the tile values stay 0/1/1+gi, so nothing else has
        # to change).
        shine = {p: lum(col[p[1]][p[0]][:3]) for p in inner}
        vals_l = sorted(shine.values()) or [0]
        lo_t, hi_t = vals_l[int(len(vals_l) * 0.06)], vals_l[int(len(vals_l) * 0.94)]
        if not any(map(any, glint)) and inner:
            # flat gems (the pearl) still get one specular pixel so shading reads
            gx, gy = inner[0]
            glint[gy][gx] = True

        rec = bytearray()
        for y in range(GEM_H):
            vals = []
            for x in range(GEM_W):
                if not shape[y][x]:
                    vals.append(None)
                elif outline[y][x]:
                    vals.append(0)
                elif glint[y][x]:
                    vals.append(1)
                else:
                    t = 0.5 if hi_t <= lo_t else (shine[(x, y)] - lo_t) / (hi_t - lo_t)
                    hi_lit = 1 if (x + y) & 1 == 0 else 1 + gi
                    lo_lit = 0 if (x + y) & 1 == 0 else 1 + gi
                    if rim_dist(x, y) <= 2 and t > 0.74:
                        vals.append(hi_lit)        # 50 % white over body
                    elif rim_dist(x, y) <= 2 and t < 0.34:
                        vals.append(lo_lit)        # 50 % black over body
                    else:
                        vals.append(1 + gi)
            xs = [x for x, v in enumerate(vals) if v is not None]
            if not xs:
                rec.append(0x0C)          # fully transparent row: pad 12 bytes
                continue
            x0, x1 = xs[0], xs[-1]
            x0e = x0 & ~1
            x1e = min(GEM_W, (x1 + 2) & ~1)
            rec.append((((x1e - x0e) // 2) << 4) | (x0e // 2))
            for x in range(x0e, x1e, 2):
                lv = vals[x] if vals[x] is not None else 0
                rv = vals[x + 1] if vals[x + 1] is not None else 0
                rec.append((lv << 4) | rv)
        tiles.append(bytes(rec))
    return tiles


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

    base_img = Image.open(MEDIA / "board.png").convert("RGB").resize((SCREEN_W, SCREEN_H), Image.LANCZOS)
    menu_img = Image.open(MEDIA / "stateMainMenu" / "mainMenuBackground.png").convert("RGB")
    palettes, scb, ctx = build_palettes(base_img, menu_img)

    title_scene, title_pals = build_art_screen(build_title_image(), scb)
    howto_scene, howto_pals = build_art_screen(build_howto_image(), scb)
    scene_tt = build_scene(ctx, True)
    scene_end = build_scene(ctx, False)
    assert len(scene_tt) == SCREEN_W * SCREEN_H // 2 == len(scene_end)
    (GEN / "title_scene.bin").write_bytes(title_scene)
    (GEN / "howto_scene.bin").write_bytes(howto_scene)
    (GEN / "scene_tt.bin").write_bytes(scene_tt)
    (GEN / "scene_end.bin").write_bytes(scene_end)

    tiles = build_tiles()
    masks_s, cellw_s, h_s = build_digit_masks(MEDIA / "fuentelcd.ttf", SCORE_FONT_SIZE, SCORE_DIGIT_H)
    masks_t, cellw_t, h_t = build_digit_masks(MEDIA / "fuentelcd.ttf", TIME_FONT_SIZE, TIME_DIGIT_H)

    celloff = [(BOARD_Y + r * CELL_H) * BPR + (BOARD_X + c * CELL_W) // 2
               for r in range(8) for c in range(8)]
    gemoff = []
    off = 0
    for t in tiles:
        gemoff.append(off)
        off += len(t)

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
    add("gemtiles", b"".join(tiles))
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

    # Emit the assembly with running byte offsets for the automation JSON.
    lines = [
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
    (GEN / "gem_data.s").write_text("\n".join(lines) + "\n", encoding="utf-8")

    # Preview PNG from the packed scene, plus the runtime-drawn gems and HUD
    # digits so the tile record and mask encodings are verified visually.
    def save_preview(path, packed, pals):
        im = Image.new("RGB", (SCREEN_W, SCREEN_H))
        for y in range(SCREEN_H):
            pal = pals[scb[y]]
            for x in range(SCREEN_W):
                b = packed[y * BPR + x // 2]
                im.putpixel((x, y), pal[b >> 4 if x % 2 == 0 else b & 15])
        im.resize((SCREEN_W * 2, SCREEN_H * 2), Image.NEAREST).save(path)

    save_preview(GEN / "preview_title.png", title_scene, title_pals)
    save_preview(GEN / "preview_howto.png", howto_scene, howto_pals)

    prev = Image.new("RGB", (SCREEN_W, SCREEN_H))
    for y in range(SCREEN_H):
        p = palettes[scb[y]]
        for x in range(SCREEN_W):
            b = scene_tt[y * BPR + x // 2]
            prev.putpixel((x, y), p[b >> 4 if x % 2 == 0 else b & 15])
    for idx, gem in enumerate(PREVIEW_BOARD):
        tile = tiles[gem - 1]
        ptr = 0
        for row in range(GEM_H):
            hdr = tile[ptr]
            ptr += 1
            span, pad = hdr >> 4, hdr & 15
            for i in range(span):
                b = tile[ptr + i]
                for nib, slot in ((0, b >> 4), (1, b & 15)):
                    abs_off = celloff[idx] + 161 + row * BPR + pad + i
                    px_x = (abs_off % BPR) * 2 + nib
                    px_y = abs_off // BPR
                    prev.putpixel((px_x, px_y), palettes[scb[px_y]][slot])
            ptr += span

    def blit_digit(masks, cellw, rows, ch, x, y, slot):
        for yy in range(rows):
            for xx in range(cellw):
                if masks[ch][yy][xx]:
                    prev.putpixel((x + xx, y + yy), palettes[scb[y + yy]][slot])

    for i, ch in enumerate("12345"):
        blit_digit(masks_s, cellw_s, h_s, ch, SCORE_RIGHT + 1 - (5 - i) * (cellw_s + 1), SCORE_DIGIT_Y, 14)
    for i, ch in enumerate("2:00"):
        blit_digit(masks_t, cellw_t, h_t, ch, TIME_RIGHT + 1 - (4 - i) * (cellw_t + 1), TIME_DIGIT_Y, 14)
    prev.resize((SCREEN_W * 2, SCREEN_H * 2), Image.NEAREST).save(GEN / "preview_tt.png")

    pal0 = bytes(pal_bytes[:16])
    meta = {
        "find_pattern": list(pal0),
        "find_pattern_scb": list(bytes(scb[:16])),
        "sections": offsets,
        "section_total": pos,
        "preview_board": PREVIEW_BOARD,
        "legal_swaps": swaps,
        "scene": {"tt": "SCENE4.RAW", "endless": "SCENE4E.RAW", "bytes": len(scene_tt)},
        "art": {"title": "TITLE.RAW", "howto": "HOWTO.RAW", "bytes": len(title_scene)},
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

    print(f"palettes: {len(palettes)}  gem tiles: {sum(len(t) for t in tiles)}B  "
          f"data total: {pos}B")
    print("wood", ctx["wood"], "gems", ctx["gems"])
    print(f"score pitch {cellw_s + 1}  time pitch {cellw_t + 1}  legal swaps: {len(swaps)}")
    print(f"wrote scene_tt/scene_end/title/howto ({len(scene_tt)}B each), gem_data.s, gs2_offsets.json")


if __name__ == "__main__":
    raise SystemExit("Use build_iigs_assets.py; this module preserves the committed artwork functions.")
