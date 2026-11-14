"""Gem-first SHR palette study; leaves the playable game assets unchanged.

Each scanline uses black, white, and two source-fitted colours per gem: exactly
16 inks for all seven gems together. This intentionally spends the whole palette
on crystals, so it is a visual study, not a drop-in replacement for the wood/UI.
"""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw
from build_iigs_assets import MEDIA, GEM_NAMES, GLYPH, PREVIEW_BOARD
from shr_art import build, hardware, distance


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=Path('iigs/merlin32/build/evidence/gloss-study'))
    args = parser.parse_args(); args.output.mkdir(parents=True, exist_ok=True)
    current = build(MEDIA, GEM_NAMES, GLYPH, PREVIEW_BOARD)
    gems = []; glints = []
    for name in GEM_NAMES:
        source = Image.open(MEDIA / (name+'.png')).convert('RGBA')
        source.putdata([(r,g,b,a if max(r,g,b)>=18 else 0) for r,g,b,a in source.getdata()])
        small = source.resize((24,20),Image.Resampling.LANCZOS)
        small.putalpha(source.getchannel('A').resize((24,20),Image.Resampling.BOX))
        gems.append(small)
        # Preserve the original subpixel white reflection lines instead of
        # averaging them entirely into the crystal's body colour.
        threshold = 245 if name=='gemWhite' else 200
        highlight = Image.new('L',source.size)
        highlight.putdata([255 if min(r,g,b)>=threshold and max(r,g,b)>=245 and a>=96 else 0
                           for r,g,b,a in source.getdata()])
        glints.append(highlight.resize((24,20),Image.Resampling.BOX))
    palettes = []
    for group in range(16):
        palette = [(0,0,0),(255,255,255)]
        for gem in gems:
            pixels = [gem.getpixel((x,y))[:3] for y in range(20) if min(15,y*16//20)==group
                      for x in range(24) if gem.getpixel((x,y))[3]>=96] or [(0,0,0)]
            image = Image.new('RGB',(len(pixels),1)); image.putdata(pixels)
            fitted = image.quantize(colors=2,method=Image.Quantize.MEDIANCUT).getpalette()
            palette += [hardware(fitted[:3]),hardware(fitted[3:6] or fitted[:3])]
        assert len(palette)==16
        palettes.append(palette)
    strips = [Image.new('RGB',(224,20)) for _ in range(3)]
    indexed_gems = []
    for gi,gem in enumerate(gems):
        indexed = []
        for y in range(20):
            old_bank = current['scb'][15+y]; palette = palettes[min(15,y*16//20)]
            for x in range(24):
                xx = gi*32+x; colour = gem.getpixel((x,y))
                if colour[3]<96:
                    indexed.append(0); continue
                offset = gi*240+y*12+x//2
                packed = current['tiles'][old_bank*1680+offset]
                slot = packed>>4 if x%2==0 else packed&15
                strips[0].putpixel((xx,y),current['palettes'][old_bank][slot])
                slot = min((0,1,2+gi*2,3+gi*2),key=lambda i:distance(colour[:3],palette[i]))
                if glints[gi].getpixel((x,y))>=40: slot=1
                indexed.append(slot)
                strips[1].putpixel((xx,y),palette[slot])
                strips[2].putpixel((xx,y),colour[:3])
        indexed_gems.append(indexed)
    comparison = Image.new('RGB',(936,430),(23,25,31)); draw = ImageDraw.Draw(comparison)
    for i,label in enumerate(('CURRENT','GEM-FIRST STUDY / 16 COLORS PER SCANLINE','SOURCE RESAMPLED / RGB REFERENCE')):
        draw.text((20,12+i*140),label,fill='white')
        comparison.paste(strips[i].resize((896,96),Image.Resampling.NEAREST),(20,36+i*140))
    comparison.save(args.output/'comparison.png')
    for y in range(20):
        colours=set(strips[1].crop((0,y,224,y+1)).getdata())
        assert len(colours)<=16 and all(channel%17==0 for colour in colours for channel in colour)
    # A native-resolution board-only preview with the same 16-ink raster budget.
    board = Image.new('RGB',(208,176))
    for cell,gem in enumerate(PREVIEW_BOARD):
        x0=2+(cell%8)*26; y0=1+(cell//8)*22
        for y in range(20):
            palette=palettes[min(15,y*16//20)]
            for x in range(24): board.putpixel((x0+x,y0+y),palette[indexed_gems[gem-1][y*24+x]])
    board.resize((624,634),Image.Resampling.NEAREST).save(args.output/'board.png')
    (args.output/'palettes.json').write_text(json.dumps(palettes),encoding='utf-8')
    print(args.output/'comparison.png')
    print(args.output/'board.png')


if __name__ == '__main__':
    main()
