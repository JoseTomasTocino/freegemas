from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "media" / "fuentelcd.ttf"
OUT = ROOT / "x16" / "src" / "time_font.h"
CHARS = "0123456789:"
CELL_W, CELL_H = 12, 18

font = ImageFont.truetype(str(FONT), 62)
fg_masks = []
edge_masks = []
for ch in CHARS:
    canvas = Image.new("L", (48, 80), 0)
    ImageDraw.Draw(canvas).text((0, 0), ch, font=font, fill=255)
    # The Windows original renders this 62px font at scale 2; the X16
    # scene is ~0.195 of that, i.e. 12x18 pixels for a digit cell.  The
    # fuentelcd ink starts at y=10, so keep that row: cropping at y=10 while
    # drawing at y=-10 used to remove the top of every LED digit.
    glyph = canvas.crop((0, 10, 31, 54)).resize((CELL_W, CELL_H), Image.Resampling.LANCZOS)
    px = glyph.load()
    fg, edge = [], []
    for y in range(CELL_H):
        fg_row = edge_row = 0
        for x in range(CELL_W):
            a = px[x, y]
            bit = 0x8000 >> x
            if a >= 160:
                fg_row |= bit
            elif a >= 32:
                edge_row |= bit
        fg.append(fg_row)
        edge.append(edge_row)
    fg_masks.append(fg)
    edge_masks.append(edge)

lines = [
    "/* Generated from media/fuentelcd.ttf by tools/build_time_font.py.",
    " * The original 62 px LCD font is rendered at 2x and then reduced to the",
    " * X16 scene's 12x18 cell; fg is the solid ink and edge is anti-aliasing. */",
    "#ifndef TIME_FONT_H",
    "#define TIME_FONT_H",
    "#include <stdint.h>",
    "static const uint16_t time_glyphs[11][18] = {",
]
for glyph in fg_masks:
    lines.append("  { " + ", ".join(f"0x{v:04x}" for v in glyph) + " },")
lines += ["};", "static const uint16_t time_edge[11][18] = {"]
for glyph in edge_masks:
    lines.append("  { " + ", ".join(f"0x{v:04x}" for v in glyph) + " },")
lines += ["};", "#endif", ""]
OUT.write_text("\n".join(lines), encoding="ascii")
print(f"wrote {OUT}")
