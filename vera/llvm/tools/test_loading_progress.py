"""Native game asset meter: monotonic real block counts, both modes/slots."""
from test_mos import Machine, entry

for slot,mode in ((2,0),(2,1),(4,0),(4,1)):
    m=Machine(slot);percent=[];original=m.step
    def step():
        if m.cpu.pc==m.sym['loading_draw']:percent.append(m.cpu.a)
        original()
    m.step=step;m.boot_game(mode)
    from test_mos import VERA
    scene = 'game_endless.rle' if mode else 'game_scene.rle'
    files = ['game_gems_32.idx', 'select.pcm', 'fall.pcm',
             'match1.pcm', 'match2.pcm', 'match3.pcm', scene]
    total = sum((VERA.joinpath('generated', name).stat().st_size + 511) // 512
                for name in files)
    # LLVM may fold loading_total's constant low byte; do not interpret its
    # optimized symbol as an unconditionally materialized uint16 object.
    assert m.value('loading_done',2)==total,(m.value('loading_done',2),total)
    assert percent[0]==0 and percent[-1]==100 and len(percent)>30
    assert percent==sorted(percent),percent
    assert not m.value('loading_active')
    assert bytes(m.mem.ram[0x480:0x49B])==bytes(x|128 for x in b'[####################] 100%')
    assert bytes(m.mem.ram[0x500:0x528])==bytes(x|128 for x in b'GAME START'+b' '*30),'GAME START must replace PREPARING BOARD below the meter'
    print(f'PASS slot {slot} mode {mode}: {total} real asset blocks, monotonic 0..100%, full native text bar',flush=True)
