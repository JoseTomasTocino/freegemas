"""Source-sampled SHR artwork and masked gem rasters (no invented gem outlines).

Sixteen raster palettes preserve the source gem facets at their aligned grid
positions. Moving stones select colours for each destination scanline.
"""
from collections import Counter
import os
from PIL import Image, ImageDraw, ImageFilter

PANEL = (17, 34, 85)
CYAN = (68, 204, 187)


def hardware(c):
    return tuple(max(0, min(15, round(v / 17))) * 17 for v in c[:3])


def distance(a, b):
    return sum((x-y)**2 for x, y in zip(a, b))


def particle_rasters(media):
    """Original particle alpha, shrinking in four 8x8 masked frames."""
    result=bytearray()
    for phase,size in enumerate((8,6,4,2)):
        src=Image.open(media / ('partc1.png' if phase%2==0 else 'partc2.png')).convert('RGBA')
        small=src.resize((size,size),Image.Resampling.BOX)
        im=Image.new('RGBA',(8,8)); im.paste(small,((8-size)//2,(8-size)//2))
        for y in range(8):
            for x in range(0,8,4):
                mask=colour=0
                for xx in range(4):
                    visible=im.getpixel((x+xx,y))[3]>=64
                    mask=(mask<<4)|(0 if visible else 15)
                    colour=(colour<<4)|(1 if visible else 0)
                # Pixel words are stored in screen byte order.
                result += bytes((mask>>8,mask&255,colour>>8,colour&255))
    return bytes(result)


def source_gems(media, names, style='classic'):
    gems = []
    for name in names:
        src = Image.open(media / (name + '.png')).convert('RGBA')
        src.putdata([(r, g, b, a if max(r, g, b) >= 18 else 0)
                     for r, g, b, a in src.getdata()])
        if style=='source':
            small=src.resize((24,20),Image.Resampling.LANCZOS)
            small.putalpha(src.getchannel('A').resize((24,20),Image.Resampling.BOX))
            threshold=245 if name=='gemWhite' else 200
            highlight=Image.new('L',src.size)
            if name=='gemWhite':
                light=src.convert('L'); soft=light.filter(ImageFilter.GaussianBlur(2))
                highlight.putdata([255 if 12<=x<53 and 12<=y<53 and min(src.getpixel((x,y))[:3])>205
                                   and light.getpixel((x,y))-soft.getpixel((x,y))>3 else 0
                                   for y in range(src.height) for x in range(src.width)])
            else:
                highlight.putdata([255 if min(r,g,b)>=threshold and max(r,g,b)>=245 and a>=96 else 0
                                   for r,g,b,a in src.getdata()])
            highlight=highlight.resize((24,20),Image.Resampling.BOX)
            for y in range(20):
                for x in range(24):
                    alpha=small.getpixel((x,y))[3]
                    if alpha>=96 and highlight.getpixel((x,y))>=40:
                        small.putpixel((x,y),(255,255,255,alpha))
                    elif name=='gemWhite':
                        colour=small.getpixel((x,y))
                        small.putpixel((x,y),tuple(min(238,c) for c in colour[:3])+(alpha,))
        else:
            small=src.resize((24,20),Image.Resampling.BOX)
        gems.append(small)
    return gems


def compose(media, glyphs, time_panel, panel=PANEL):
    im = Image.open(media / 'board.png').convert('RGB').resize((320, 200), Image.Resampling.LANCZOS)
    menu = Image.open(media / 'stateMainMenu/mainMenuBackground.png').convert('RGB').resize((320,200), Image.Resampling.LANCZOS)
    # The playable cells start at x96, but the original outer rim starts at
    # x88. Preserve that eight-pixel rim when replacing the sidebar background.
    im.paste(menu.crop((0,28,88,200)), (0,28))
    board = Image.open(media / 'board.png').convert('RGB').crop((240,40,760,560))
    im.paste(board.resize((208,176), Image.Resampling.BOX), (96,14))
    draw = ImageDraw.Draw(im)

    def text(caption, x, y, colour=(238,238,255)):
        for ch in caption:
            for yy, bits in enumerate(glyphs[ch]):
                for xx in range(5):
                    if bits & (16 >> xx): draw.point((x+xx,y+yy), fill=colour)
            x += 6

    text('Score', 7 + (77-29)//2, 30, (153,187,255))
    for filename, box in [('scoreBackground.png',(7,41,84,55))] + (
            [('timeBackground.png',(7,77,84,101))] if time_panel else []):
        art = Image.open(media / filename).convert('RGBA').resize((box[2]-box[0],box[3]-box[1]), Image.Resampling.LANCZOS)
        im.paste(art, box[:2], art)
        ImageDraw.Draw(im).rectangle((box[0]+1,box[1]+1,box[2]-2,box[3]-2), fill=panel)
    if time_panel: text('Time left', 7 + (77-53)//2, 62, (153,187,255))
    for caption, icon, y, tint in [('Show hint','iconHint.png',136,(204,85,221)),
                                  ('Reset game','iconRestart.png',151,(51,238,102)),
                                  ('Exit','iconExit.png',179,(255,51,51))]:
        art = Image.open(media / 'buttonBackground.png').convert('RGBA').resize((78,14), Image.Resampling.LANCZOS)
        im.paste(art,(7,y),art)
        ic = Image.open(media / icon).convert('RGBA').resize((12,12),Image.Resampling.LANCZOS)
        coloured = Image.new('RGBA',ic.size,(*tint,255)); coloured.putalpha(ic.getchannel('A'))
        im.paste(coloured,(10,y+1),coloured)
        text(caption,20+(64-(len(caption)*6-1))//2,y+4)
    return im


def committed_flat(preview_board):
    """Exact committed scenes/colours/opaque spans, adapted to the fast blitter."""
    import committed_art as original
    base=Image.open(original.MEDIA/'board.png').convert('RGB').resize((320,200),Image.Resampling.LANCZOS)
    menu=Image.open(original.MEDIA/'stateMainMenu/mainMenuBackground.png').convert('RGB')
    palettes,scb,context=original.build_palettes(base,menu)
    packed=[original.build_scene(context,True),original.build_scene(context,False)]
    from hud_art import polish_sidebar
    packed=[polish_sidebar(scene,palettes,original.GLYPH,i==0) for i,scene in enumerate(packed)]
    palettes=palettes+[palettes[-1]]*(16-len(palettes))
    masks=bytearray([255]*1680); tiles=bytearray(1680)
    for gem,record in enumerate(original.build_tiles()):
        pos=0
        for y in range(20):
            header=record[pos]; pos+=1
            span=header>>4; pad=header&15
            offset=gem*240+y*12+pad
            tiles[offset:offset+span]=record[pos:pos+span]
            masks[offset:offset+span]=bytes(span)
            pos+=span
        assert pos==len(record)
    preview=Image.new('RGB',(320,200))
    for y in range(200):
        for x in range(320):
            value=packed[0][y*160+x//2]
            preview.putpixel((x,y),palettes[scb[y]][value>>4 if x%2==0 else value&15])
    for cell,gem in enumerate(preview_board):
        x0=98+(cell%8)*26; y0=15+(cell//8)*22
        for y in range(20):
            for x in range(24):
                offset=(gem-1)*240+y*12+x//2
                if masks[offset]: continue
                value=tiles[offset]
                preview.putpixel((x0+x,y0+y),palettes[scb[y0+y]][value>>4 if x%2==0 else value&15])
    return dict(palettes=palettes,scb=scb,packed=packed,tiles=bytes(tiles)*16,
                masks=bytes(masks),preview=preview,reference=preview.copy(),gem_rmse=0)


def build(media, names, glyphs, preview_board, style=None):
    style=style or os.environ.get('IIGS_ART_STYLE','flat')
    assert style in ('flat','classic','source')
    if style=='flat': return committed_flat(preview_board)
    source=style=='source'
    gems = source_gems(media,names,style)
    panel=(0,0,0) if source else PANEL
    scenes = [compose(media,glyphs,True,panel),compose(media,glyphs,False,panel)]
    # Fit the colours needed by each *raster row* of all seven source gems.
    # Sixteen SCB palettes repeat along the aligned 22-pixel board rows. This
    # keeps different facet/shadow colours across a stone, instead of reducing
    # every gem to the same two inks throughout its height.
    fixed = [(0,0,0),(255,255,255),(34,221,68),(0,85,170),(119,102,85),(68,51,51),(85,68,51)]
    if source: fixed=fixed[:6]
    adaptive_slots=list(range(6,14))+[15] if source else list(range(7,14))
    fixed_slots=dict(enumerate(fixed)); fixed_slots[14]=CYAN
    if not source: fixed_slots[15]=PANEL
    def make_palette(centres):
        palette=[(0,0,0)]*16
        for slot,colour in fixed_slots.items(): palette[slot]=colour
        for slot,colour in zip(adaptive_slots,centres): palette[slot]=colour
        return palette
    scb=[]
    for y in range(200):
        row=(y-15)%22
        scb.append(min(15,row*16//20) if 15<=y<190 and row<20 else 0)
    palettes = []
    for group in range(16):
        samples=[]
        for y in range(200):
            if scb[y]!=group: continue
            if not source: samples += [scenes[0].getpixel((x,y)) for x in range(0,320,2)]
            row=(y-15)%22
            if 15<=y<190 and row<20:
                samples += [g.getpixel((x,row))[:3] for g in gems for x in range(24)
                            if g.getpixel((x,row))[3]>=96]*6
        if not samples: samples=[(0,0,0)]
        counts=Counter(hardware(c) for c in samples)
        anchors=list(fixed_slots.values())
        residual=[c for c in samples if min(distance(c,p) for p in anchors)>500] or samples
        im=Image.new('RGB',(len(residual),1)); im.putdata(residual)
        q=im.quantize(colors=len(adaptive_slots),method=Image.Quantize.MEDIANCUT); qp=q.getpalette()
        centres=[hardware(qp[i*3:i*3+3] or qp[:3]) for i in range(len(adaptive_slots))]
        for _ in range(5):
            sums=[[0,0,0,0] for _ in adaptive_slots]
            allcol=make_palette(centres)
            for c,n in counts.items():
                slot=min(range(16),key=lambda i:distance(c,allcol[i]))
                if slot in adaptive_slots:
                    v=sums[adaptive_slots.index(slot)]
                    for k in range(3): v[k]+=c[k]*n
                    v[3]+=n
            centres=[hardware(tuple(v[k]/v[3] for k in range(3))) if v[3] else centres[i]
                     for i,v in enumerate(sums)]
        palettes.append(make_palette(centres))
    if source:
        # Keep a crystal's ramp in the same slots in every raster palette.
        # Fit the approved RGB source separately for each hue, rather than
        # letting a global cluster replace a red highlight with a gold ink.
        palettes=[]
        for group in range(16):
            ramps=[]
            for gi,gem in enumerate(gems):
                pixels=[gem.getpixel((x,y))[:3] for y in range(20) if min(15,y*16//20)==group
                        for x in range(24) if gem.getpixel((x,y))[3]>=160
                        and (gi!=0 or min(gem.getpixel((x,y))[:3])<250)]
                if not pixels: pixels=[c[:3] for c in gem.getdata() if c[3]>=160]
                image=Image.new('RGB',(len(pixels),1)); image.putdata(pixels)
                fitted=image.quantize(colors=2,method=Image.Quantize.MEDIANCUT).getpalette()
                colours=[hardware(fitted[:3]),hardware(fitted[3:6] or fitted[:3])]
                ramps.append(sorted(colours,key=lambda c:c[0]*.2126+c[1]*.7152+c[2]*.0722))
            w,r,p,o,g,y,b=ramps
            w=[tuple(min(204,c) for c in w[0]),tuple(min(221,c) for c in w[1])]
            palettes.append([(0,0,0),(255,255,255),g[1],(0,85,170),
                             (119,102,85),(68,51,51),w[0],r[0],r[1],p[0],p[1],
                             o[0],y[1],g[0],b[1],w[1]])
    maps = [{c:min(range(16),key=lambda i:distance(c,p[i])) for c in
             set(scenes[0].getdata()) | set(scenes[1].getdata())} for p in palettes]

    def packed_scene(im):
        data = bytearray(32000)
        # Keep sampled wood and blue backgrounds in fixed slots so adaptive
        # gem colours cannot create raster bands across the background.
        for y in range(200):
            pal=palettes[scb[y]]; mapping=maps[scb[y]]
            row=[]
            for x in range(320):
                c=im.getpixel((x,y))
                textured=96<=x<304 and 14<=y<190
                if textured:
                    slot=min((0,4,5) if source else (0,4,5,6),key=lambda i:distance(c,pal[i]))
                elif x<96 and c[2]>c[0]*1.8 and c[0]<120:
                    slot=min((3,0) if source else (3,15),key=lambda i:distance(c,pal[i]))
                else: slot=mapping[c]
                row.append(slot)
            for x in range(0,320,2): data[y*160+x//2]=(row[x]<<4)|row[x+1]
        return bytes(data)

    masks=bytearray(); tiles=bytearray()
    for g in gems:
        for y in range(20):
            for x in range(0,24,2):
                masks.append((0xF0 if g.getpixel((x,y))[3]<96 else 0) |
                             (0x0F if g.getpixel((x+1,y))[3]<96 else 0))
    errors=[]
    for bank,pal in enumerate(palettes):
        for gi,g in enumerate(gems):
            for y in range(20):
                row=[]
                for x in range(24):
                    c=g.getpixel((x,y))
                    inks=((0,1,6,15),(0,1,7,8),(0,1,9,10),(0,1,4,5,11,12),
                          (0,1,2,13),(0,1,11,12),(0,1,3,14))[gi] if source else range(16)
                    if source and gi==0:
                        inks=(1,) if min(c[:3])>=250 else (0,6,15)
                    slot=0 if c[3]<96 else min(inks,key=lambda i:distance(c[:3],pal[i]))
                    row.append(slot)
                    if c[3]>=96 and scb[15+y]==bank: errors.append(distance(c[:3],pal[slot]))
                for x in range(0,24,2): tiles.append((row[x]<<4)|row[x+1])

    packed=[packed_scene(im) for im in scenes]
    def render(data):
        im=Image.new('RGB',(320,200))
        for y in range(200):
            for x in range(320):
                b=data[y*160+x//2]; im.putpixel((x,y),palettes[scb[y]][(b>>4) if x%2==0 else (b&15)])
        return im
    preview=render(packed[0]); reference=scenes[0].copy()
    for cell,gem in enumerate(preview_board):
        x0=98+(cell%8)*26; y0=15+(cell//8)*22
        reference.paste(gems[gem-1],(x0,y0),gems[gem-1])
        for y in range(20):
            bank=scb[y0+y]
            for x in range(24):
                off=(gem-1)*240+y*12+x//2
                if masks[off] & (0xF0 if x%2==0 else 0x0F): continue
                b=tiles[bank*1680+off]; slot=(b>>4) if x%2==0 else (b&15)
                preview.putpixel((x0+x,y0+y),palettes[bank][slot])
    return dict(palettes=palettes,scb=scb,packed=packed,tiles=bytes(tiles),
                masks=bytes(masks),preview=preview,reference=reference,
                gem_rmse=(sum(errors)/len(errors)/3)**.5)
