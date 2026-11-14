"""Verify the shipped PSG stream on both slots, including disk-free playback."""
from test_mos import Machine, VERA

SOURCE = (VERA / 'generated/music_pure_gained.psg').read_bytes()

def call(m, name, arg=0):
    pc, sp = m.cpu.pc, m.cpu.sp
    m.cpu.a = arg
    m.cpu.stPushWord(0x02FE)
    m.cpu.pc = m.sym[name]
    m.until(lambda: m.cpu.pc == 0x02FF)
    assert m.cpu.sp == sp and not m.mem.aux_read and not m.mem.aux_write and not m.mem.altzp
    m.cpu.pc = pc

for slot in (2, 4):
    m = Machine(slot)
    m.files.pop('MUSIC.PCM')  # PSG and effects must not depend on PCM music.
    m.mem.ram[0x3F4] = 0xA5
    m.mem.ram[0x3F2] = 2
    m.mem.ram[0x3F3] = 1
    m.boot_game(1)
    for i, b in enumerate(SOURCE):
        page = 8 + (i >> 8)
        at = (page << 8 | (i & 255)) if page < 0xC0 else (page + 0x10) * 256 + (i & 255)
        assert m.mem.aux[at] == b, (slot, i, hex(at))
    call(m, 'music_stop')
    call(m, 'music_restart')
    m.mem.addr[:] = [0x12345, 0x18010]
    m.mem.inc[:] = [320, 40]
    m.mem.ctrl = 3
    saved = (m.mem.addr[:], m.mem.inc[:], m.mem.ctrl)
    reads = m.read_calls
    shadow = bytearray(64)
    shadow[3::4] = bytes([128])*16
    pos = frames = 0
    while SOURCE[pos] != 255:
        count = SOURCE[pos]; pos += 1
        for _ in range(count):
            reg, value = SOURCE[pos:pos+2]; pos += 2
            shadow[reg] = value
        call(m, 'psg_tick')
        assert m.mem.vram[0x1F9C0:0x1FA00] == shadow, (slot, frames)
        assert (m.mem.addr, m.mem.inc, m.mem.ctrl) == saved
        frames += 1
    assert m.read_calls == reads
    call(m, 'psg_tick')  # loop marker resets the chip and replays frame zero
    first = bytearray(64); first[3::4] = bytes([128])*16
    for i in range(SOURCE[0]):
        reg, value = SOURCE[1+i*2:3+i*2]
        first[reg] = value
    assert m.mem.vram[0x1F9C0:0x1FA00] == first
    # PCM effects share the game tick but must not trigger disk I/O or stop PSG.
    call(m, 'sound_play', 0)
    previous_psg_writes = len(m.mem.psg_writes)
    tail_pending = False
    tail_verified = False
    for _ in range(12):
        if m.mem.reg[28]:
            del m.mem.pcm_fifo[:134]
        had_tail = tail_pending and bool(m.mem.pcm_fifo)
        call(m, 'music_tick')
        if had_tail:
            assert m.mem.reg[28] == 21 and m.mem.pcm_fifo, 'effect tail was cut off'
            tail_verified = True
        tail_pending = m.value('effect_remaining', 2) == 0 and bool(m.mem.pcm_fifo)
    assert tail_verified
    assert len(m.mem.psg_writes) > previous_psg_writes
    assert m.read_calls == reads
    call(m, 'music_stop')
    assert not any(m.mem.vram[0x1F9C2:0x1FA00:4])
    limited = Machine(slot)
    limited.mem.aux_present = False
    limited.mem.ram[0x3F4] = 0xA5
    limited.mem.ram[0x3F2] = 2
    limited.mem.ram[0x3F3] = 1
    limited.boot_game(1)
    assert not limited.value('psg_ready')
    call(limited, 'sound_play', 0)
    call(limited, 'music_tick')
    assert limited.mem.reg[28] == 21, 'effects must still work without auxiliary RAM'
    print(f'PASS slot {slot}: {frames} PSG frames match, AUX preload, no playback disk reads, port preservation', flush=True)
