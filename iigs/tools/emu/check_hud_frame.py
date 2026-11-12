"""Compare actual HUD pixels with centered LCD text, including erased margins."""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hud_art import lcd_masks, string_origin


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('directory',type=Path); parser.add_argument('name')
    args=parser.parse_args(); root=args.directory
    fb=(root/f'fb_{args.name}.bin').read_bytes()
    state=json.loads((root/f'hud_{args.name}.json').read_text(encoding='utf-8-sig'))
    cases=[('score',str(state['score']),lcd_masks(7,9,1),44,(8,42,83,55)),
           ('time',f"{state['time']//60}:{state['time']%60:02}",lcd_masks(11,14,2),82,(8,78,83,100))]
    for label,text,(masks,width,height),y0,box in cases:
        x0=string_origin(text,masks,width+1); expected=set()
        for i,ch in enumerate(text):
            for y,row in enumerate(masks[ch]):
                for x,bit in enumerate(row):
                    if bit: expected.add((x0+i*(width+1)+x,y0+y))
        actual=set(); errors=[]
        for y in range(box[1],box[3]):
            for x in range(box[0],box[2]):
                value=(fb[y*160+x//2]>>(4 if x%2==0 else 0))&15
                if value==14: actual.add((x,y))
                elif value!=15: errors.append((x,y,value))
        assert not errors,f'{label}: unexpected edge/background pixels {errors[:8]}'
        assert actual==expected,f'{label} {text}: {len(actual^expected)} wrong/missing/stale pixels'
        left=min(x for x,y in actual); right=max(x for x,y in actual)
        assert abs((left+right)/2-45)<=.5
        print(f'{label} {text}: exact LCD pixels, ink bounds x{left}..{right}, centered.')


if __name__=='__main__': main()
