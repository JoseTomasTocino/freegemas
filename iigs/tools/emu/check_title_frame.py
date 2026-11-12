"""Verify all seven native title jewels and surrounding restored background."""
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import committed_art
from build_iigs_assets import GEN
root=Path(sys.argv[1]); actual=(root/'fb_title_small.bin').read_bytes()
expected=bytearray((GEN/'title_scene.bin').read_bytes())
for gem,record in enumerate(committed_art.build_tiles()):
    pos=0
    for y in range(20):
        header=record[pos];pos+=1
        span=header>>4;pad=header&15
        for x in range(span):
            value=record[pos];pos+=1
            a,b=value>>4,value&15
            value=((a+1 if 2<=a<=8 else a)<<4)|(b+1 if 2<=b<=8 else b)
            expected[(88+y)*160+35+gem*13+pad+x]=value
errors=[]
for y in range(88,115):
    for x in range(60,264):
        offset=y*160+x//2;shift=4 if x%2==0 else 0
        if (actual[offset]>>shift)&15 != (expected[offset]>>shift)&15:errors.append((x,y))
assert not errors,f'Title jewels/background mismatch: {len(errors)} pixels, {errors[:8]}'
print('Native title: seven aligned jewels and surrounding background exact.')
