"""Check settled native SHR gem pixels against the generated source rasters.

Uses the actual logical board captured by fgparitycheck. The software pointer
rectangle is excluded; every other opaque gem pixel must match, in every column.
"""
import argparse
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_iigs_assets import GEN, MEDIA, GEM_NAMES, GLYPH, PREVIEW_BOARD
from shr_art import build


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directory', type=Path)
    parser.add_argument('--gameover', action='store_true')
    args = parser.parse_args()
    if args.gameover:
        framebuffer = (args.directory / 'fb_parity_gameover.bin').read_bytes()
        background = (GEN / 'scene_tt.bin').read_bytes()
        failures = []
        for y in range(14,190):
            for x in range(96,304):
                if 104 <= x < 296 and 72 <= y < 162: continue
                offset = y*160+x//2; shift = 4 if x % 2 == 0 else 0
                if (framebuffer[offset] >> shift) & 15 != (background[offset] >> shift) & 15:
                    failures.append((x,y))
        if failures:
            raise AssertionError(f'Drop left {len(failures)} stray pixels outside the overlay: {failures[:8]}')
        print('Native game-over frame: board background exact outside the overlay.')
        return
    sampled = build(MEDIA, GEM_NAMES, GLYPH, PREVIEW_BOARD)
    framebuffer = (args.directory / 'fb_parity_game.bin').read_bytes()
    board = (args.directory / 'parity_board.bin').read_bytes()[::2]
    pointer = json.loads((args.directory / 'parity_pointer.json').read_text(encoding='utf-8-sig'))
    if os.environ.get('IIGS_ART_STYLE','flat')=='flat':
        import committed_art
        expected=bytearray((GEN/'scene_tt.bin').read_bytes())
        records=committed_art.build_tiles()
        for cell,gem in enumerate(board):
            record=records[gem-1]; pos=0
            for y in range(20):
                header=record[pos]; pos+=1
                span=header>>4; pad=header&15
                offset=(15+(cell//8)*22+y)*160+49+(cell%8)*13+pad
                expected[offset:offset+span]=record[pos:pos+span]; pos+=span
        cursor=pointer.get('cursor',0); cx=96+(cursor%8)*26; cy=14+(cursor//8)*22
        for y in range(cy,cy+22):
            for x in range(cx,cx+26):
                if y in (cy,cy+21) or x in (cx,cx+25):
                    offset=y*160+x//2
                    expected[offset]=(expected[offset]&15)|16 if x%2==0 else (expected[offset]&240)|1
        errors=[]
        for y in range(14,190):
            for x in range(96,304):
                if pointer['x']-2<=x<=pointer['x']+10 and pointer['y']-2<=y<=pointer['y']+10: continue
                offset=y*160+x//2; shift=4 if x%2==0 else 0
                if ((expected[offset]>>shift)&15)!=((framebuffer[offset]>>shift)&15): errors.append((x,y))
        assert not errors,f'Committed flat rendering mismatch: {len(errors)} pixels, {errors[:8]}'
        print('Native flat board matches committed spans/background exactly (pointer excluded).')
        return
    failures = []; checked = 0
    assert len(framebuffer) == 32000 and len(board) == 64
    for cell, gem in enumerate(board):
        assert 1 <= gem <= 7
        x0 = 98 + (cell % 8)*26; y0 = 15 + (cell // 8)*22
        for y in range(20):
            for x in range(24):
                xx = x0+x; yy = y0+y
                if pointer['x']-2 <= xx <= pointer['x']+10 and pointer['y']-2 <= yy <= pointer['y']+10:
                    continue
                offset = (gem-1)*240+y*12+x//2
                shift = 4 if x % 2 == 0 else 0
                if (sampled['masks'][offset] >> shift) & 15:
                    continue
                expected = (sampled['tiles'][sampled['scb'][yy]*1680+offset] >> shift) & 15
                actual = (framebuffer[yy*160+xx//2] >> (4 if xx % 2 == 0 else 0)) & 15
                checked += 1
                if expected != actual: failures.append((cell, x, y, expected, actual))
    if failures:
        raise AssertionError(f'{len(failures)} gem pixel mismatches: {failures[:8]}')
    print(f'Native settled frame: {checked} opaque gem pixels exact across all 64 cells.')


if __name__ == '__main__':
    main()
