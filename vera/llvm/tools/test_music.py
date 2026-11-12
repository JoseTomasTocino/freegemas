"""Stream the shipped MUSIC.PCM through the real 65C02 player.

Instrumented model only: the VERA FIFO drain is simulated per frame, and the
bytes the player queues are compared with the generated PCM.  This is not a
listening test and says nothing about real hardware timing.
"""
from test_mos import Machine, VERA

MUSIC = (VERA / 'generated/music.pcm').read_bytes()

def signed_samples(data):
    return [x if x < 128 else x - 256 for x in data]

# Cover every possible alignment of music and each effect. Both emulator
# mixers double the PCM bus after applying VERA's volume lookup (13 = 38/64).
music_samples = signed_samples(MUSIC)
for name in ('select', 'fall', 'match1', 'match2', 'match3'):
    effect = signed_samples((VERA / f'generated/{name}.pcm').read_bytes())
    lo = min(music_samples) + min(effect)
    hi = max(music_samples) + max(effect)
    assert -128 <= lo <= hi <= 127, f'{name}: signed mixer overflow'
    assert lo * 256 * 38 * 2 >= -32768 * 64, f'{name}: output clips low'
    assert hi * 256 * 38 * 2 <= 32767 * 64, f'{name}: output clips high'


def call(m, name, arg=0):
    pc, sp = m.cpu.pc, m.cpu.sp
    m.cpu.a = arg
    m.cpu.stPushWord(0x02FE)
    m.cpu.pc = m.sym[name]
    m.until(lambda: m.cpu.pc == 0x02FF)
    assert m.cpu.sp == sp and not m.mem.aux_read and not m.mem.aux_write
    m.cpu.pc = pc


def tick(m):
    """One VSYNC: drain what VERA plays, then run the player's tick.

    Returns how many new bytes the player queued.
    """
    if m.mem.reg[28]:
        samples = round(m.mem.reg[28] * 48828.125 / 128 / 60)
        del m.mem.pcm_fifo[:samples]
    before = len(m.mem.pcm_writes)
    call(m, 'music_tick')
    return len(m.mem.pcm_writes) - before


def check_port(m, saved):
    assert (m.mem.addr[:], m.mem.inc[:], m.mem.ctrl) == saved, 'graphics port disturbed'


def started(slot, frames=1200):
    m = Machine(slot)
    m.boot_game(1)
    assert m.value('music_ready') == 1, 'MUSIC.PCM must be installed'
    assert m.value('ready') == 1, 'sound effects must be installed'
    m.mem.addr[:] = [0x12345, 0x18010]
    m.mem.inc[:] = [320, 40]
    m.mem.ctrl = 3
    saved = (m.mem.addr[:], m.mem.inc[:], m.mem.ctrl)
    # frame_pump() may already have started the engine inside start_game, so
    # rewind explicitly before measuring the stream from its first byte.
    call(m, 'music_stop')
    m.mem.pcm_writes.clear()
    m.mem.pcm_fifo.clear()
    m.mem.pcm_resets = 0
    reads = m.read_calls
    for _ in range(frames):
        tick(m)
        check_port(m, saved)
    got = bytes(m.mem.pcm_writes)
    assert m.mem.pcm_resets == 1, 'engine start must reset the FIFO exactly once'
    assert got == MUSIC[:len(got)], 'queued stream differs from MUSIC.PCM'
    assert m.read_calls > reads, 'streaming must read MUSIC.PCM from disk'
    assert m.value('music_on') == 1 and m.value('music_fd') == 1
    return m, saved, len(got)


for slot in (2, 4):
    m, saved, pos = started(slot)

    # OFF stops, closes the file and queues nothing more while remaining silent.
    m.mem.ram[0x3F2] = 0
    assert tick(m) == 0
    assert m.value('music_on') == 0 and m.value('music_fd') == 0
    for _ in range(20):
        assert tick(m) == 0
        check_port(m, saved)
    assert not (m.mem.reg[27] & 15) and not m.mem.reg[28], 'OFF must mute and stop'
    assert not m.mem.reg[27] & 0x40, 'OFF must release the PCM restart line'

    # ON starts the stream again from its first byte.
    m.mem.pcm_writes.clear()
    m.mem.pcm_fifo.clear()
    m.mem.ram[0x3F2] = 1
    pos = 0
    assert tick(m) == 1024
    assert bytes(m.mem.pcm_writes) == MUSIC[:1024], 'ON must replay from the start'
    assert m.mem.reg[28] == 21 and m.mem.reg[27] & 15 == 13
    pos = 1024

    # Sound OFF must not stop the music.
    m.mem.ram[0x3F3] = 0
    for _ in range(4):
        n = tick(m)
        assert bytes(m.mem.pcm_writes[-n:]) == MUSIC[pos:pos + n]
        pos += n

    # EFFECTS: the next queued samples are music plus the effect, sample by sample.
    m.mem.ram[0x3F3] = 1
    effect = (VERA / 'generated/match2.pcm').read_bytes()
    call(m, 'sound_play', 3)
    base = pos
    for _ in range(24):
        n = tick(m)
        chunk = bytes(m.mem.pcm_writes[-n:])
        for i, value in enumerate(chunk):
            index = pos + i
            source = MUSIC[index]
            mixed = (source + effect[index - base]) & 255 if index - base < len(effect) else source
            assert value == mixed, (slot, index - base, value, mixed)
        pos += n
    assert pos > base + len(effect), 'the whole effect must have been queued'
    assert m.value('effect_remaining') == 0, 'effect must end by itself'

    # R restarts the song from the top.
    call(m, 'music_stop')
    call(m, 'music_restart')
    m.mem.pcm_writes.clear()
    m.mem.pcm_fifo.clear()
    pos = 0
    assert tick(m) == 1024, ('tick', len(m.mem.pcm_writes), m.value('music_on'),
                             m.value('music_fd'), len(m.mem.pcm_fifo), m.mem.pcm_resets,
                             m.value('music_ready'), hex(m.value('mli_status')),
                             m.value('disk_open'), m.value('disk_epoch_value'))
    assert bytes(m.mem.pcm_writes) == MUSIC[:1024], 'restart must rewind the stream'

    # Esc returns to the title with both audio paths silent.
    m.mem.ram[0xC000] = 0x9B
    m.until(lambda: m.cpu.pc == 0x2000)
    assert not (m.mem.reg[27] & 15) and not m.mem.reg[28], 'Esc must mute the output'
    assert m.value('music_on') == 0 and m.value('music_fd') == 0
    assert m.value('effect_remaining') == 0
    m.return_loader()
    print(f'PASS slot {slot}: {len(MUSIC)} bytes stream byte-exact, disk reads, '
          f'loop start, OFF/ON, effect mixing, restart, Esc silence', flush=True)

# Loop: run past the end of the file and confirm the stream wraps without a gap.
m = Machine(2)
m.boot_game(1)
call(m, 'music_stop')
m.mem.pcm_writes.clear()
m.mem.pcm_fifo.clear()
pos = 0
frames = len(MUSIC) // 133 + 8
for _ in range(frames):
    pos += tick(m)
queued = bytes(m.mem.pcm_writes)
assert len(queued) > len(MUSIC), (len(queued), len(MUSIC))
assert queued[:len(MUSIC)] == MUSIC, 'first pass differs from the file'
assert queued[len(MUSIC):] == MUSIC[:len(queued) - len(MUSIC)], 'loop must wrap cleanly'
print(f'PASS loop: {len(queued) - len(MUSIC)} bytes after the wrap match MUSIC.PCM again',
      flush=True)
