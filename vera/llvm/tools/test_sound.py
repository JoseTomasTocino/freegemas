"""Original PCM effects preloaded into VERA VRAM, played through the 65C02 mixer.

Instrumented model only: bytes are compared, never listened to.
"""
from test_mos import Machine, VERA

NAMES = ('select', 'fall', 'match1', 'match2', 'match3')
# SFX_* -> preloaded sample index.
SFX = ((0, 'select'), (5, 'fall'), (2, 'match1'), (3, 'match2'), (4, 'match3'))


def call(m, name, arg=0):
    pc, sp = m.cpu.pc, m.cpu.sp
    m.cpu.a = arg
    m.cpu.stPushWord(0x02FE)
    m.cpu.pc = m.sym[name]
    m.until(lambda: m.cpu.pc == 0x02FF)
    assert m.cpu.sp == sp
    m.cpu.pc = pc


def tick(m):
    if m.mem.reg[28]:
        samples = round(m.mem.reg[28] * 48828.125 / 128 / 60)
        del m.mem.pcm_fifo[:samples]
    call(m, 'music_tick')


def samples_table(m):
    table = m.sym['samples']
    rows = []
    for i in range(5):
        at = table + i * 6
        offset = int.from_bytes(m.mem.ram[at:at + 4], 'little')
        length = int.from_bytes(m.mem.ram[at + 4:at + 6], 'little')
        rows.append((offset, length))
    return rows


for slot in (2, 4):
    m = Machine(slot)
    m.boot_game(1)
    assert m.value('ready') == 1, 'all original samples must load'

    rows = samples_table(m)
    total = 0
    for index, (offset, length) in enumerate(rows):
        want = (VERA / 'generated' / f'{NAMES[index]}.pcm').read_bytes()
        assert length == len(want), (slot, index, length, len(want))
        assert offset == 0x14800 + total, (slot, index, hex(offset))
        assert bytes(m.mem.vram[offset:offset + length]) == want, (slot, NAMES[index])
        total += length
    assert 0x14800 + total <= 0x19000, 'PCM pool must stay below the cursor patterns'

    # The sound option gates playback: OFF queues nothing at all.
    m.mem.ram[0x3F3] = 0
    call(m, 'sound_play', 2)
    assert m.value('effect_remaining', 2) == 0
    m.mem.ram[0x3F3] = 1

    # Each effect starts at its own sample and lasts exactly its file length.
    for sfx, name in SFX:
        call(m, 'sound_play', sfx)
        index = NAMES.index(name)
        assert m.value('effect_source', 4) == rows[index][0], (slot, name)
        assert m.value('effect_remaining', 2) == rows[index][1], (slot, name)

    # A newer effect replaces the old one instead of mixing both.
    call(m, 'sound_play', 2)
    call(m, 'sound_play', 4)
    assert m.value('effect_source', 4) == rows[4][0]
    assert m.value('effect_remaining', 2) == rows[4][1]

    # Unknown effect numbers are ignored.
    before = (m.value('effect_source', 4), m.value('effect_remaining', 2))
    for sfx in (1, 6, 7, 8, 255):
        call(m, 'sound_play', sfx)
    assert (m.value('effect_source', 4), m.value('effect_remaining', 2)) == before

    # Staging reads VRAM through port 0; the graphics port and both address
    # ports come back untouched, and the music stream keeps the only open file.
    for _ in range(8):
        tick(m)
    m.mem.addr[:] = [0x12345, 0x18010]
    m.mem.inc[:] = [320, 40]
    m.mem.ctrl = 3
    saved = (list(m.mem.addr), list(m.mem.inc), m.mem.ctrl)
    psg = bytes(m.mem.vram[0x1F9C0:0x1FA00])
    m.mem.vram[0x1F9C0:0x1FA00] = bytes([0xA5]) * 64
    epoch = m.value('disk_epoch_value')
    call(m, 'sound_play', 3)
    for _ in range(30):
        tick(m)
    assert (list(m.mem.addr), list(m.mem.inc), m.mem.ctrl) == saved, 'graphics port disturbed'
    assert m.value('disk_epoch_value') == epoch, 'a cached effect must not reopen files'
    assert m.value('disk_size', 4) == 1012224, 'the music stream owns the only open file'
    assert m.mem.vram[0x1F9C0:0x1FA00] == bytes([0xA5]) * 64, 'PSG registers untouched'
    m.mem.vram[0x1F9C0:0x1FA00] = psg
    assert m.value('effect_remaining', 2) == 0, 'effect must drain by itself'

    # Esc stops everything before handing back to the loader.
    call(m, 'sound_stop')
    assert m.value('effect_remaining', 2) == 0
    m.mem.ram[0xC000] = 0x9B
    m.until(lambda: m.cpu.pc == 0x2000)
    assert not m.mem.reg[28] and not m.mem.pcm_fifo
    m.return_loader()
    print(f'PASS slot {slot}: five original PCM streams byte-exact in VRAM, '
          f'{total} bytes, OFF/ON, replacement, drain, silent Esc', flush=True)
