#!/usr/bin/env python3
"""Execute shipped 65C02 images against an instrumented VERA/MLI model.

Requires py65 (pip install py65). This supplements, not replaces, AppleWin.
Uses a private in-memory HDV copy: test scores never alter the user's disk.
"""
from pathlib import Path
import subprocess
import os
from collections import Counter
from py65.devices.mpu65c02 import MPU

LLVM=Path(__file__).resolve().parents[1]
VERA=LLVM.parent
NM=Path('C:/dev/llvm-mos-sdk/install/bin/llvm-nm.exe')

def symbols(file):
    result={}
    for line in subprocess.check_output([str(NM),str(file)],text=True).splitlines():
        fields=line.split()
        if len(fields)==3: result[fields[2]]=int(fields[0],16)
    return result

def entry(disk,name):
    block=2
    while block:
        page=disk[block*512:(block+1)*512]
        for i in range(1 if block==2 else 0,13):
            e=page[4+i*39:4+(i+1)*39]
            if e[0] and bytes(e[1:1+(e[0]&15)]).decode('ascii')==name:
                return e[0]>>4,e[17]|e[18]<<8,int.from_bytes(e[21:24],'little')
        block=page[2]|page[3]<<8
    raise AssertionError(f'Missing {name}')

def scene_pixels(file):
    data=file.read_bytes()
    if data[:2]==bytes(2): pixels=data[2:]
    else:
        pixels=bytearray()
        for i in range(0,len(data),2):pixels.extend(bytes([data[i+1]])*data[i])
    assert len(pixels)==76800
    return pixels

def file_blocks(disk,storage,key,size):
    """Block list backing one ProDOS file, following its index level(s)."""
    if storage==1:return [key]
    index=[disk[key*512+i]|disk[key*512+256+i]<<8 for i in range(256)]
    if storage==2:return index[:(size+511)//512]
    return [disk[sub*512+i]|disk[sub*512+256+i]<<8
            for sub in index[:(size+511)//512//256+1] for i in range(256)]

def read_catalog(disk):
    """Name -> storage type, key block, EOF and content for the boot volume."""
    files={};block=2;seen=set()
    while block and block not in seen:
        seen.add(block);page=disk[block*512:(block+1)*512]
        for i in range(1 if block==2 else 0,13):
            e=page[4+i*39:4+(i+1)*39]
            if not e[0]:continue
            name=bytes(e[1:1+(e[0]&15)]).decode('ascii','replace')
            storage,key,size=e[0]>>4,e[17]|e[18]<<8,int.from_bytes(e[21:24],'little')
            blocks=file_blocks(disk,storage,key,size)
            data=bytearray()
            for b in blocks:data+=disk[b*512:(b+1)*512]
            files[name]=dict(storage=storage,key=key,eof=size,blocks=blocks,data=data[:size])
        block=page[2]|page[3]<<8
    return files

class Memory:
    def __init__(self,slot):
        self.ram=bytearray(65536);self.vram=bytearray(131072)
        self.aux=bytearray(65536);self.aux_read=False;self.aux_write=False;self.aux_present=True
        self.altzp=False;self.lc_read=False;self.lc_write=False
        self.base=0xC000+slot*256;self.addr=[0,0];self.inc=[0,0];self.ctrl=0
        self.reg=bytearray(32);self.writes=Counter();self.keys_cleared=0;self.frames=0
        self.psg_writes=[]
        # YM2151 device-select window ($C0A0/$C0C0) next to the VERA card.
        self.fm_base=0xC0A0 if slot==2 else 0xC0C0
        self.fm_present=False;self.fm_select=0;self.fm_regs=bytearray(256)
        self.fm_busy=0;self.fm_writes=[]
        self.pcm_fifo=bytearray();self.pcm_writes=[];self.pcm_resets=0
        self.pcm_clocked=False
    def __getitem__(self,a):
        if isinstance(a,slice): return self.ram[a]
        if a==0xC08B:self.lc_read=True;self.lc_write=True;return 0
        if a==0xC081:self.lc_read=False;self.lc_write=True;return 0
        if a==0xC082:self.lc_read=False;self.lc_write=False;return 0
        if a>=0xD000 and self.altzp and self.lc_read:return self.aux[a]
        if self.base<=a<self.base+32:
            r=a-self.base;port=self.ctrl&1
            if r<3:
                return (self.addr[port]>>(r*8))&255 if r<2 else ((self.addr[port]>>16)|([0,1,2,4,8,16,32,64,128,256,512,40,80,160,320,640].index(self.inc[port])<<4))
            if r in (3,4):
                port=r-3;v=self.vram[self.addr[port]&0x1FFFF];self.addr[port]=(self.addr[port]+self.inc[port])&0x1FFFF;return v
            if r==5:return self.ctrl
            if r==7:
                # VSYNC pulse per wait, not wall-clock, plus bit 3: the audio-low
                # flag both emulators compute from the live FIFO depth (<1024).
                return 1 | (8 if len(self.pcm_fifo) < 1024 else 0)
            if r==27:return (self.reg[r]&63)|(128 if len(self.pcm_fifo)>=4095 else 0)|(64 if not self.pcm_fifo else 0)
            return self.reg[r]
        if self.fm_base<=a<self.fm_base+2:
            if a==self.fm_base:return self.fm_select
            if not self.fm_present:return 0xFF     # empty device-select: open bus
            # BUSY asserts after the timer reset and clears on later reads.
            status=0x80 if self.fm_busy else 0
            if self.fm_busy:self.fm_busy-=1
            return status
        if a==0xC010:self.ram[0xC000]&=127;self.keys_cleared+=1
        if 0xC200<=a<0xC220 or 0xC400<=a<0xC420:return 0 # empty other slot
        if 0x0200<=a<0xC000 and self.aux_read:return self.aux[a]
        return self.ram[a]
    def __setitem__(self,a,v):
        if isinstance(a,slice):self.ram[a]=v;return
        v&=255
        if self.base<=a<self.base+32:
            r=a-self.base;p=self.ctrl&1
            if r<3:
                shift=r*8;mask=255 if r<2 else 1
                self.addr[p]=(self.addr[p]&~(mask<<shift))|((v&mask)<<shift)
                if r==2:self.inc[p]=[0,1,2,4,8,16,32,64,128,256,512,40,80,160,320,640][v>>4]
            elif r in (3,4):
                p=r-3;address=self.addr[p]&0x1FFFF;self.vram[address]=v;self.writes[address]+=1
                if 0x1F9C0<=address<0x1FA00:self.psg_writes.append((self.frames,address,v))
                self.addr[p]=(address+self.inc[p])&0x1FFFF
            elif r==5:self.ctrl=v
            else:
                if r==27 and v&128:self.pcm_fifo.clear();self.pcm_resets+=1
                if r==29:
                    assert len(self.pcm_fifo)<4095,'PCM FIFO overflow'
                    self.pcm_fifo.append(v);self.pcm_writes.append(v)
                self.reg[r]=v
                if r==7:
                    # Clearing VSYNC (bit 0) marks a waited frame; clearing the
                    # audio-low flag (bit 3) is not a frame and must not drain.
                    if not v&1:return
                    self.frames+=1
                    if self.reg[28] and not self.pcm_clocked:
                        samples=round(self.reg[28]*48828.125/128/60)
                        stride=(1,2,2,4)[(self.reg[27]>>4)&3]
                        del self.pcm_fifo[:samples*stride]
            return
        if self.fm_base<=a<self.fm_base+2:
            if a==self.fm_base:self.fm_select=v;return
            self.fm_writes.append((self.frames,self.fm_select,v))
            self.fm_regs[self.fm_select]=v
            if self.fm_select==0x14 and v&0x30:self.fm_busy=8
            return
        if a==0xC010:self.ram[0xC000]&=127;self.keys_cleared+=1
        elif a==0xC002:self.aux_read=False
        elif a==0xC003:self.aux_read=self.aux_present
        elif a==0xC004:self.aux_write=False
        elif a==0xC005:self.aux_write=self.aux_present
        elif a==0xC008:self.altzp=False
        elif a==0xC009:self.altzp=True
        elif a>=0xD000 and self.altzp and self.lc_write:self.aux[a]=v
        elif a==0xC000:pass # 80STORE off, not keyboard input
        elif 0xC200<=a<0xC220 or 0xC400<=a<0xC420:return
        elif 0x0200<=a<0xC000 and self.aux_write:self.aux[a]=v
        else:self.ram[a]=v

class Machine:
    def __init__(self,slot=2,disk=None):
        self.mem=Memory(slot);self.cpu=MPU(memory=self.mem,pc=0x2000)
        self.disk=bytearray(disk or Path(os.environ.get('FREEGEMAS_TEST_DISK',str(VERA/'freegemas.hdv'))).read_bytes())
        system=(LLVM/'build/freegemas.sys').read_bytes()
        if int.from_bytes(system[:2],'little')==0x2000:system=system[4:]
        self.mem.ram[0x2000:0x2000+len(system)]=system
        self.mem.ram[0xBF30]=0x70;self.write_calls=0;self.read_calls=0;self.fail_write=False
        self.files=read_catalog(self.disk);self.opened={};self.next_ref=1
        self.quit_params=None
        # Fixed seed only in the test fixture, for repeatable cascade coverage.
        self.mem.ram[0x3EA:0x3EC]=(0xBEEF).to_bytes(2,'little')
        self.sym=symbols(LLVM/f'build/freegemas{4 if slot==4 else ""}.bin.elf')
        self.endings=[]
        self.wait_cycles=[];self.last_wait=0
    def step(self):
        if self.cpu.pc==0xBF00:
            # Real JSR return address precedes inline MLI command + parameter ptr.
            low=self.cpu.stPop();high=self.cpu.stPop();ret=low|high<<8
            cmd=self.mem.ram[ret+1];p=int.from_bytes(self.mem.ram[ret+2:ret+4],'little')
            status=self.mli(cmd,p)
            # Deliberately clobber ALL compiler ZP state and X/Y like a system call.
            self.mem.ram[:192]=bytes([0xDA])*192
            self.cpu.x=0xAA;self.cpu.y=0xBB;self.cpu.a=status
            # Carry marks a failed call; READ's informational EOF code does not.
            self.cpu.p=(self.cpu.p&~1)|(1 if status not in (0,0x42) else 0)
            self.cpu.pc=(ret+4)&65535
        else:
            if self.cpu.pc==self.sym.get('waitvsync'):
                if self.last_wait and self.value('resolving'):self.wait_cycles.append(self.cpu.processorCycles-self.last_wait)
                self.last_wait=self.cpu.processorCycles
            if self.cpu.pc==self.sym.get('show_game_over'):
                self.endings.append((self.value('score',4),self.mem.ram[self.sym['resolving']],has_match(self.board())))
            self.cpu.step()
    def mli(self,cmd,p):
        """Minimal ProDOS 8 MLI: block I/O plus the file-level calls used by
        the resident loader (GET_PREFIX/OPEN/READ/WRITE/SET_MARK/GET_EOF/
        CLOSE/QUIT).  Files come from the boot volume catalog."""
        q=self.mem.ram[p:p+8]
        if cmd in (0x80,0x81):
            dest=q[2]|q[3]<<8;block=q[4]|q[5]<<8
            if cmd==0x80:
                self.read_calls+=1;self.mem.ram[dest:dest+512]=self.disk[block*512:(block+1)*512]
            else:
                self.write_calls+=1
                if self.fail_write:return 0x27
                self.disk[block*512:(block+1)*512]=self.mem.ram[dest:dest+512]
            return 0
        if cmd==0xC7:                                   # GET_PREFIX
            buf=q[1]|q[2]<<8;prefix=b'/FREEGEMAS'
            self.mem.ram[buf]=len(prefix);self.mem.ram[buf+1:buf+1+len(prefix)]=prefix
            return 0
        if cmd==0xC8:                                   # OPEN
            ptr=q[1]|q[2]<<8;length=self.mem.ram[ptr]
            path=bytes(self.mem.ram[ptr+1:ptr+1+length]).decode('ascii','replace')
            name=path.rsplit('/',1)[-1].upper()
            if name not in self.files:return 0x46
            ref=self.next_ref;self.next_ref+=1;self.opened[ref]=[name,0];self.mem.ram[p+5]=ref
            return 0
        if cmd==0xCC:                                   # CLOSE
            self.opened.pop(q[1],None);return 0
        if cmd==0xCE:                                   # SET_MARK
            entry_=self.opened.get(q[1])
            if not entry_:return 0x2D
            entry_[1]=q[2]|q[3]<<8|q[4]<<16;return 0
        if cmd==0xCA:                                   # READ
            entry_=self.opened.get(q[1])
            if not entry_:return 0x2D
            dest=q[2]|q[3]<<8;count=q[4]|q[5]<<8;start=entry_[1]
            chunk=bytes(self.files[entry_[0]]['data'][start:start+count])
            self.mem.ram[dest:dest+len(chunk)]=chunk;entry_[1]=start+len(chunk)
            self.mem.ram[p+6]=len(chunk)&255;self.mem.ram[p+7]=len(chunk)>>8
            self.read_calls+=1
            return 0 if len(chunk)==count else 0x42
        if cmd==0xCB:                                   # WRITE
            entry_=self.opened.get(q[1])
            if not entry_:return 0x2D
            self.write_calls+=1
            if self.fail_write:return 0x27
            src=q[2]|q[3]<<8;count=q[4]|q[5]<<8;start=entry_[1]
            f=self.files[entry_[0]]
            f['data'][start:start+count]=self.mem.ram[src:src+count]
            f['eof']=max(f['eof'],start+count);entry_[1]=start+count
            self.mem.ram[p+6]=count&255;self.mem.ram[p+7]=count>>8
            self.write_back(entry_[0])
            return 0
        if cmd==0xD1:                                   # GET_EOF
            entry_=self.opened.get(q[1])
            if not entry_:return 0x2D
            size=self.files[entry_[0]]['eof']
            self.mem.ram[p+2]=size&255;self.mem.ram[p+3]=(size>>8)&255;self.mem.ram[p+4]=size>>16
            return 0
        if cmd==0x65:                                   # QUIT
            self.quit_params=list(q);return 0
        raise AssertionError(f'unknown MLI command ${cmd:02X} at parameter block ${p:04X}')
    def write_back(self,name):
        """Mirror a written file into its data blocks so disk_scores() agrees."""
        f=self.files[name]
        for i,block in enumerate(f['blocks']):
            chunk=f['data'][i*512:(i+1)*512]
            if chunk:self.disk[block*512:block*512+len(chunk)]=chunk
    def until(self,predicate,limit=12_000_000):
        for n in range(limit):
            if predicate():return n
            self.step()
        raise AssertionError(f'timeout PC=${self.cpu.pc:04X}, frames={self.mem.frames}')
    def boot_game(self,mode=0):
        self.mem.ram[0x3F0]=0xA5;self.mem.ram[0x3F1]=mode
        self.until(lambda:self.cpu.pc==self.sym['waitvsync'] and self.mem.reg[9]==0x71)
        self.idle_sp=self.cpu.sp
        expected=scene_pixels(VERA/('generated/game_endless.rle' if mode else 'generated/game_scene.rle'))
        for y in range(240):
            for x in range(320):
                if (7<=x<84 and 50<=y<67) or (31<=x<79 and 98<=y<113):continue
                assert self.mem.vram[y*320+x]==expected[y*320+x],('game background load mismatch',x,y)
        assert all(1<=gem<=7 for gem in self.board())
        assert self.mem.vram[0x12C00:0x14800]==(VERA/'generated/game_gems_32.idx').read_bytes()
        assert self.mem.vram[0x1FA18:0x1FA1A]==bytes(2),'popup outline ink must be reserved black'
        assert not any(self.mem.vram[0x1B800:0x1B840]),'mask tile zero must be transparent'
        assert not any(self.mem.vram[0x1A900:0x1B800]),'mask must not cover the playing board'
        for y in range(2):
            for x in range(40):
                tile=0x1B800+(1+y*40+x)*64
                for row in range(8):
                    source=(y*8+row)*320+x*8
                    assert self.mem.vram[tile+row*8:tile+row*8+8]==self.mem.vram[source:source+8]
    def key(self,key):
        clears=self.mem.keys_cleared;self.mem.ram[0xC000]=key|128
        self.until(lambda:self.mem.keys_cleared>clears and self.cpu.pc==self.sym['waitvsync'] and self.cpu.sp==self.idle_sp and not self.value('resolving'))
    def value(self,name,length=1):
        a=self.sym[name];return int.from_bytes(self.mem.ram[a:a+length],'little')
    def put(self,name,value,length=1):
        a=self.sym[name];self.mem.ram[a:a+length]=value.to_bytes(length,'little')
    def board(self):return self.mem.ram[self.sym['board']:self.sym['board']+64]
    def return_loader(self):
        self.cpu.pc=0x2000;self.mem.ram[0x3F0]=0
        self.until(lambda:self.cpu.pc==0x3000)
        assert self.cpu.sp==255,'segment transfer must reset hardware stack'
        assert self.mem.vram[:76800]==scene_pixels(VERA/'generated/title_scene.rle'),'raw/RLE scene upload differs from generated pixels'
    def disk_scores(self):
        storage,key,size=entry(self.disk,'HISCORE.DAT');assert storage==1 and size==12
        data=self.disk[key*512:key*512+12];assert data[:4]==b'FGH\x01'
        return [int.from_bytes(data[i:i+4],'little') for i in (4,8)]

def has_match(b):
    return any(b[y*8+x] and b[y*8+x]==b[y*8+x+1]==b[y*8+x+2] for y in range(8) for x in range(6)) or any(b[y*8+x] and b[y*8+x]==b[(y+1)*8+x]==b[(y+2)*8+x] for y in range(6) for x in range(8))
def solution(b):
    for y in range(8):
        for x in range(8):
            for dx,dy in ((1,0),(0,1)):
                if x+dx>=8 or y+dy>=8:continue
                test=bytearray(b);a=y*8+x;c=(y+dy)*8+x+dx;test[a],test[c]=test[c],test[a]
                if has_match(test):return x,y,x+dx,y+dy
    raise AssertionError('no solution')
def move(m,x,y):
    for name,target,left,right in (('cursor_x',x,8,21),('cursor_y',y,11,10)):
        while m.value(name)!=target:m.key(left if m.value(name)>target else right)
def swap(m,last_second=False):
    ax,ay,bx,by=solution(m.board());move(m,ax,ay);m.key(32);move(m,bx,by)
    if last_second:m.put('time_left',1);m.put('time_frames',58)
    before=bytes(m.board());frame=m.mem.frames;m.key(32)
    assert bytes(m.board())!=before and not has_match(m.board())
    return m.mem.frames-frame

def aligned(m):
    for i,gem in enumerate(m.board()):
        a=m.mem.vram[0x1FC00+i*8:0x1FC08+i*8]
        pattern=(a[0]<<5)|((a[1]&15)<<13)
        assert pattern==0x12C00+(gem-1)*1024,(i,gem,hex(pattern))
        assert a[6]==8 and (a[2]|a[3]<<8)==93+(i%8)*26 and (a[4]|a[5]<<8)==13+(i//8)*26

def test(slot):
    m=Machine(slot);m.boot_game()
    board_bitmap=bytes(m.mem.vram[:76800]);attrs=bytes(m.mem.vram[0x1FC00:0x1FE00])
    m.mem.writes.clear();m.key(21)
    assert bytes(m.mem.vram[:76800])==board_bitmap,'cursor touched bitmap'
    assert bytes(m.mem.vram[0x1FC00:0x1FE00])==attrs,'cursor rewrote gems'
    graphics_writes=sum(n for a,n in m.mem.writes.items() if not 0x1F9C0<=a<0x1FA00)
    assert graphics_writes<=24,'cursor update excessive'
    print(f'PASS slot {slot}: cursor only ({graphics_writes} graphics VRAM bytes, PSG excluded)')
    m.mem.writes.clear();before=bytes(m.board());m.key(32);m.key(32)
    assert bytes(m.board())==before and not any(a<76800 for a in m.mem.writes)
    print(f'PASS slot {slot}: invalid/same-cell swap leaves board and bitmap unchanged')
    # At the start of falling, matched sprites may be hidden but every
    # survivor must remain visible while the board was being refilled.
    original_step=m.step;checked_survivors=[0]
    def check_fall_entry():
        if m.cpu.pc==m.sym['animate_fall'] and m.value('resolving'):
            old=m.mem.ram[m.sym['before_fall']:m.sym['before_fall']+64]
            marked=set()
            for y in range(8):
                for x in range(8):
                    i=y*8+x
                    if x<6 and old[i]==old[i+1]==old[i+2]:marked.update((i,i+1,i+2))
                    if y<6 and old[i]==old[i+8]==old[i+16]:marked.update((i,i+8,i+16))
            for i in range(64):
                if i not in marked and any(j%8==i%8 and j//8>i//8 for j in marked):
                    assert m.mem.vram[0x1FC06+i*8]&12, ('survivor hidden before fall',i)
                    checked_survivors[0]+=1
        original_step()
    m.step=check_fall_entry
    m.mem.writes.clear();swap(m)
    m.step=original_step
    assert checked_survivors[0], 'fixture must check survivors above a match'
    assert m.value('score',4)>0
    # HUD writes permitted, no board bitmap writes, and gems stay enabled/aligned.
    board_writes=sum(n for address,n in m.mem.writes.items() if address<76800 and address%320>=96)
    assert not board_writes,f'{board_writes} board bitmap writes during cascade'
    aligned(m)
    bitmap_after=bytes(m.mem.vram[:76800]);frame=m.mem.frames
    m.until(lambda:m.mem.frames>=frame+55)
    assert all(m.mem.vram[0x1FC06+i*8]==0 for i in range(68,120)),'effects did not expire'
    assert all(m.mem.vram[y*320+96:(y+1)*320]==bitmap_after[y*320+96:(y+1)*320] for y in range(240))
    print(f'PASS slot {slot}: swap/cascade score={m.value("score",4)}, zero board redraw, effects expire')
    print(f'  Animation CPU cycles between waits: average={sum(m.wait_cycles)//len(m.wait_cycles)}, maximum={max(m.wait_cycles)} (1MHz frame budget ~17000)')
    cascades=0
    for turn in range(12):
        try:solution(m.board())
        except AssertionError:m.key(ord('R'))
        m.mem.writes.clear();duration=swap(m);aligned(m)
        cascades+=duration>31
        assert not any(a<76800 and a%320>=96 for a in m.mem.writes)
    assert cascades,'stress fixture must exercise multi-cascade moves'
    print(f'PASS slot {slot}: 12 more swaps, {cascades} multi-cascade moves, artwork/position agree with logical board')
    trial=int.from_bytes(m.mem.ram[0x3E0:0x3E4],'little');m.return_loader();assert m.disk_scores()[0]==trial
    restart=Machine(slot,m.disk);restart.boot_game(1)
    assert int.from_bytes(restart.mem.ram[0x3E0:0x3E4],'little')==trial
    swap(restart);endless=restart.value('score',4);restart.return_loader()
    assert restart.disk_scores()==[trial,endless]
    cold=Machine(slot,restart.disk);cold.boot_game();assert list(int.from_bytes(cold.mem.ram[i:i+4],'little') for i in (0x3E0,0x3E4))==[trial,endless]
    cold.mem.ram[0x3E8]=1;cold.fail_write=True;cold.return_loader();assert cold.mem.ram[0x3E8]==1
    cold.fail_write=False;cold.return_loader();assert cold.mem.ram[0x3E8]==0
    print(f'PASS slot {slot}: separate records, cold reload, failed-write retry; MLI clobbered ZP throughout')
    end=Machine(slot);end.boot_game();swap(end,last_second=True)
    assert end.value('game_over') and end.endings and all(score>0 and not resolving and not match for score,resolving,match in end.endings)
    assert all(end.mem.vram[0x1FC06+i*8]==0 for i in range(64))
    end.key(ord('R'));assert not end.value('game_over') and end.value('score',4)==0
    zero_rows=(14,17,19,21,25,17,14)
    assert all(end.mem.vram[(55+row)*320+75+col]==10
               for row,bits in enumerate(zero_rows) for col in range(5)
               if bits&(16>>col)), 'reset score zero must be visible'
    assert all(end.mem.vram[(98+row*2+py)*320+47+px]==10
               for row in (1,2,4,5) for py in range(2) for px in range(2)), 'reset timer colon must be visible'
    assert all(end.mem.vram[0x1FC06+i*8]==8 for i in range(64))
    print(f'PASS slot {slot}: last-second move finishes before Game Over, R restores game')
    hint=Machine(slot);hint.boot_game()
    hx,hy,_,_=solution(hint.board())
    move(hint, hx+1 if hx<7 else hx-1, hy);hint.key(32)
    def cursor_attrs():
        return bytes(hint.mem.vram[0x1FC00+66*8:0x1FC00+68*8])
    cursor=cursor_attrs()
    state=[hint.value(n) for n in ('cursor_x','cursor_y','selected','select_x','select_y')]
    hx,hy,_,_=solution(hint.board())
    hint.mem.writes.clear();hint.key(ord('H'))
    assert cursor==cursor_attrs()
    assert state==[hint.value(n) for n in ('cursor_x','cursor_y','selected','select_x','select_y')]
    assert not any(a<76800 for a in hint.mem.writes),'hint must not redraw bitmap'
    attrs=hint.mem.vram[0x1FC00+65*8:0x1FC00+66*8]
    assert attrs[6]==12 and int.from_bytes(attrs[2:4],'little')==93+hx*26
    assert int.from_bytes(attrs[4:6],'little')==13+hy*26
    def complete_hint(stage):
        attr=hint.mem.vram[0x1FC00+65*8:0x1FC00+66*8]
        pattern=(attr[0]<<5)|((attr[1]&15)<<13)
        assert pattern==0x1CC40+stage*1024
        edge=2-stage
        for row in range(32):
            # AppleWin VERA: one lookup clock/slot, one clock/pixel plus
            # one fetch clock/4 pixels in 8bpp. Check actual active sprites
            # ahead of the hint, including overlapping 32px gem rows.
            cost=66+40
            for gemslot in range(64):
                a=hint.mem.vram[0x1FC00+gemslot*8:0x1FC08+gemslot*8]
                sy=int.from_bytes(a[4:6],'little')
                width=8<<((a[7]>>4)&3);height=8<<((a[7]>>6)&3)
                if a[6]&12 and sy<=13+hy*26+row<sy+height:
                    cost+=width+(width+3)//4
            assert cost<801, ('hint scanline truncated',row,cost)
            for col in range(32):
                border=(edge<=row<=31-edge and edge<=col<=31-edge
                        and (row in (edge,31-edge) or col in (edge,31-edge)))
                assert bool(hint.mem.vram[pattern+row*32+col])==border
    complete_hint(0)
    for stage in (1,2):
        expected=((0x1CC40+stage*1024)>>5)&255
        hint.until(lambda:hint.mem.vram[0x1FC00+65*8]==expected)
        complete_hint(stage)
    frames=hint.mem.frames
    hint.until(lambda:hint.mem.frames>=frames+41)
    assert hint.mem.vram[0x1FC06+65*8]==0
    assert cursor==cursor_attrs()
    hint.key(32);swap(hint)
    assert hint.value('score',4)==0
    print(f'PASS slot {slot}: all hint borders/stages fit scanline budget, preserve cursor/selection, expire, suppress initial points')

if __name__=='__main__':
    import sys
    for slot in (list(map(int,sys.argv[1:])) or (2,4)):test(slot)
    import build_hdv
    data=bytearray((VERA/'freegemas.hdv').read_bytes());_,key,_=entry(data,'HISCORE.DAT')
    expected=b'FGH\x01'+(12345).to_bytes(4,'little')+(67890).to_bytes(4,'little')
    data[key*512:key*512+12]=expected
    assert build_hdv.saved_scores(data)==expected
    print('PASS HDV rebuild preserves records across directory blocks')
