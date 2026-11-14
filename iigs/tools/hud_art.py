"""Pixel-aligned sidebar and LCD masks; no resampled font edge fragments."""
from pathlib import Path
from PIL import Image, ImageDraw
SCORE_Y, SCORE_H, SCORE_W = 44, 9, 7
TIME_Y, TIME_H, TIME_W = 82, 14, 11
HUD_CENTER = 45


def lcd_masks(width, height, thickness):
    segments=('abcdef','bc','abdeg','abcdg','bcfg','acdfg','acdefg','abc','abcdefg','abcdfg')
    middle=(height-thickness)//2
    masks={}
    for ch in '0123456789:':
        rows=[[0]*width for _ in range(height)]
        def rect(x0,y0,x1,y1):
            for y in range(y0,y1):
                for x in range(x0,x1): rows[y][x]=1
        if ch==':':
            x=(width-thickness)//2
            rect(x,middle//2,x+thickness,middle//2+thickness)
            rect(x,height-middle//2-thickness,x+thickness,height-middle//2)
        else:
            for segment in segments[int(ch)]:
                if segment in 'agd':
                    y={'a':0,'g':middle,'d':height-thickness}[segment]
                    rect(thickness,y,width-thickness,y+thickness)
                else:
                    x=width-thickness if segment in 'bc' else 0
                    y0,y1=(thickness,middle) if segment in 'bf' else (middle+thickness,height-thickness)
                    rect(x,y0,x+thickness,y1)
        masks[ch]=rows
    return masks,width,height


def bounds(masks):
    pairs=[]
    for ch in '0123456789:':
        xs=[x for row in masks[ch] for x,value in enumerate(row) if value]
        pairs.append((min(xs),max(xs)))
    return pairs


def string_origin(value,masks,pitch):
    ink=dict(zip('0123456789:',bounds(masks)))
    leading=ink[value[0]][0]; trailing=ink[value[-1]][1]
    width=(len(value)-1)*pitch+trailing-leading+1
    return HUD_CENTER-width//2-leading


def polish_sidebar(packed, palettes, glyphs, time_panel):
    grid=[[(packed[y*160+x//2]>>(4 if x%2==0 else 0))&15 for x in range(320)] for y in range(200)]
    for y,row in enumerate(grid):
        bg = 11 if y < 28 else 12
        row[:96]=[bg]*96; row[308:]=[bg]*12
        if y<14 or y>=190: row[96:308]=[11 if y < 28 else 12]*212
    def rect(x0,y0,x1,y1,colour):
        for y in range(y0,y1): grid[y][x0:x1]=[colour]*(x1-x0)
    def text(value,x,y,colour=1,scale_y=1):
        for ch in value:
            for yy,bits in enumerate(glyphs[ch]):
                for xx in range(5):
                    if bits&(16>>xx): rect(x+xx,y+yy*scale_y,x+xx+1,y+(yy+1)*scale_y,colour)
            x+=6
    def plaque(x,y,w,h):
        rect(x,y,x+w,y+h,1); rect(x+1,y+1,x+w-1,y+h-1,15)
        for xx,yy in ((x,y),(x+w-1,y),(x,y+h-1),(x+w-1,y+h-1)): grid[yy][xx]=12
    # Use the original in-game wordmark, not the menu-logo alpha crop whose
    # faint outer pixels produced a bright patch at the upper-right S.
    logo=Image.open(Path(__file__).resolve().parents[2]/'media/board.png').convert('RGB')
    logo=logo.resize((320,200),Image.Resampling.LANCZOS).crop((0,0,88,28))
    palette=palettes[0]; choices=(0,1,11,12,14,15)
    for y in range(28):
        for x in range(88):
            colour=logo.getpixel((x,y))
            grid[y][x]=min(choices,key=lambda i:sum((colour[k]-palette[i][k])**2 for k in range(3)))
    text('SCORE',31,30,14); plaque(7,41,77,15)
    if time_panel:
        text('TIME LEFT',19,66,14); plaque(7,77,77,24)
    hint_icon=('.....y......','..y.....y...','...a...a....','..ayyya.....',
               '.aywwwwya...','.aywwwwya...','..aywwya....','...awwa.....',
               '...aywa.....','....aa......','............','............')
    reset_icon=Image.new('1',(9,9),0)
    reset_draw=ImageDraw.Draw(reset_icon)
    reset_draw.arc((0,0,8,8),45,315,fill=1,width=2)
    reset_draw.polygon(((6,0),(8,1),(6,3)),fill=1)
    exit_icon=('1111000','1001000','1001010','1001111','1001010','1001000','1111000')
    for caption,y in zip(('SHOW HINT','RESET GAME','EXIT'),(136,151,179)):
        plaque(7,y,78,14)
        if caption=='SHOW HINT':
            for yy,line in enumerate(hint_icon):
                for xx,value in enumerate(line):
                    if value!='.':
                        grid[y+1+yy][10+xx]={'a':5,'y':7,'w':1}[value]
        elif caption=='RESET GAME':
            for yy in range(9):
                for xx in range(9):
                    if reset_icon.getpixel((xx,yy)):
                        grid[y+2+yy][10+xx]=13
        else:
            for yy,line in enumerate(exit_icon):
                for xx,value in enumerate(line):
                    if value=='1': grid[y+3+yy][11+xx]=14
        width=len(caption)*6-1
        text(caption,21+(62-width)//2,y+3)
    data=bytes((grid[y][x]<<4)|grid[y][x+1] for y in range(200) for x in range(0,320,2))
    assert all(data[y*160+48:y*160+154]==packed[y*160+48:y*160+154] for y in range(14,190))
    return data
