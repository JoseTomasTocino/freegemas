"""Check loader detection against real-model, absent, and RAM-echo slots."""
from test_mos import Machine

message=bytes(c|128 for c in b'STATUS: VERA NOT DETECTED')
for echo in (False,True):
    m=Machine(2)
    # Move the model device out of slots 2/4. Unmapped addresses either echo
    # RAM writes or return fixed open-bus-like bytes; neither is a VERA.
    m.mem.base=0xC600
    if not echo:
        original=m.mem.__class__
        class Absent(original):
            def __getitem__(self,a):
                if isinstance(a,int) and (0xC200<=a<0xC220 or 0xC400<=a<0xC420):return 0xFF
                return super().__getitem__(a)
        m.mem.__class__=Absent
    def row(n):return 0x400+(n&7)*128+(n>>3)*40
    stopped=bytes(c|128 for c in b'STOPPED: VERA REQUIRED IN SLOT 2 OR 4')
    m.until(lambda:m.mem.ram[row(18):row(18)+len(stopped)]==stopped)
    for n,s in ((0,b'FREEGEMAS FOR APPLE II VERA'),(1,b'BY ANOMIXER 2026'),
                (2,b'HTTPS://GITHUB.COM/ANOMIXER/FREEGEMAS'),(5,b'STATUS: VERA NOT DETECTED'),
                (6,b'MOUSE: NONE'),(7,b'CONTROLS:'),(9,b'  ARROW KEYS'),(16,b'  MOUSE')):
        assert m.mem.ram[row(n):row(n)+len(s)]==bytes(c|128 for c in s),'complete intro text'
    m.mem.ram[0xC000]=0xA0 # A key must not bypass the missing-card stop.
    for _ in range(20000):m.step()
    assert m.mem.ram[row(5):row(5)+len(message)]==message
    assert m.mem.reg[9]==0 and m.mem.frames==0,'must not load graphics or wait on absent VSYNC'
    assert m.mem.ram[0x3EC]==0,'missing-card status must reach intro'
    print('PASS no VERA: halted, '+('RAM echo rejected' if echo else 'open bus rejected'))
for slot in (2,4):
    m=Machine(slot)
    m.until(lambda:m.mem.reg[9]==0x51)
    print(f'PASS VERA slot {slot}: detected and title loaded')
