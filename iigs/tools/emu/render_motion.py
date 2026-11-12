"""Render FG-Burst captures to an animation and a contact sheet."""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw
from render_shot import render

p=argparse.ArgumentParser(); p.add_argument('directory',type=Path); p.add_argument('name')
a=p.parse_args(); root=a.directory; stem='burst_'+a.name
ticks=json.loads((root/(stem+'.json')).read_text())
pal=(root/(stem+'.pal')).read_bytes(); scb=(root/(stem+'.scb')).read_bytes()
frames=[render((root/(stem+f'_{i:03}.bin')).read_bytes(),pal,scb) for i in range(len(ticks))]
durations=[max(20,round(((ticks[i+1]-ticks[i])&65535)*1000/60)) for i in range(len(ticks)-1)]+[100]
frames[0].save(root/(stem+'.gif'),save_all=True,append_images=frames[1:],duration=durations,loop=0,disposal=2)
sheet=Image.new('RGB',(960,432),'#202027'); draw=ImageDraw.Draw(sheet)
for j in range(6):
    i=min(len(frames)-1,j*(len(frames)-1)//5)
    x=(j%3)*320;y=(j//3)*216
    sheet.paste(frames[i],(x,y)); draw.text((x+4,y+201),f'{((ticks[i]-ticks[0])&65535)/60:.2f}s',fill='white')
sheet.save(root/(stem+'_sheet.png'))
print(root/(stem+'.gif')); print(root/(stem+'_sheet.png'))
