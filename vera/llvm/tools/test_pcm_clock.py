"""Clock the 8-bit PCM FIFO against real CPU cycles.

The model normally drains one VSYNC worth per frame; here every instruction
advances a fractional 8010.86 Hz clock so the rendered byte stream can be
compared with MUSIC.PCM (and with the mixed effect) exactly.  Instrumented
65C02/VERA model only, not a hardware or listening test.
"""
from test_mos import Machine, VERA

MUSIC = (VERA / 'generated/music.pcm').read_bytes()
MATCH2 = (VERA / 'generated/match2.pcm').read_bytes()


def call(m, name, arg=0):
    pc, sp = m.cpu.pc, m.cpu.sp
    m.cpu.a = arg
    m.cpu.stPushWord(0x02FE)
    m.cpu.pc = m.sym[name]
    m.until(lambda: m.cpu.pc == 0x02FF)
    assert m.cpu.sp == sp
    m.cpu.pc = pc


def clocked(slot):
    """Boot with the PCM FIFO driven by CPU cycles instead of VSYNC frames."""
    m = Machine(slot)
    m.boot_game(1)
    # frame_pump() may already have started the engine inside start_game;
    # rewind so the rendered stream starts at the first byte of MUSIC.PCM.
    call(m, 'music_stop')
    m.mem.pcm_clocked = True
    m.mem.pcm_writes.clear()
    m.mem.pcm_fifo.clear()
    m.mem.pcm_resets = 0
    rendered = bytearray()
    phase = [0]

    def advance(cycles):
        rate = m.mem.reg[28]
        if not rate:
            return
        # 8-bit mono: rate * 25e6 / 512 / 128 Hz against a 1.023 MHz CPU.
        phase[0] += cycles * rate * 25_000_000
        period = 1_023_000 * 512 * 128
        while phase[0] >= period:
            phase[0] -= period
            if m.mem.pcm_fifo:
                rendered.append(m.mem.pcm_fifo[0])
                del m.mem.pcm_fifo[:1]

    def step():
        before = m.cpu.processorCycles
        original_step()
        advance(m.cpu.processorCycles - before)

    original_step = m.step
    m.step = step
    return m, rendered, advance


def drain(m, rendered, advance, written):
    """Play everything queued so far, honouring the CPU-cycle clock."""
    guard = 0
    while len(rendered) < written or m.mem.pcm_fifo:
        advance(20_000)
        written = max(written, len(m.mem.pcm_writes))
        guard += 1
        assert guard < 100_000, 'clock never drained the FIFO'


for slot in (2, 4):
    # Pure music: byte-for-byte, including a 230 ms CPU gap that starves the
    # FIFO (the player must refill in order, not skip or duplicate samples).
    m, rendered, advance = clocked(slot)
    # Verify the real compiled clock conversion across zero, fractional,
    # multiple and capped frame counts, including the carried remainder.
    for acc in (0, 133513, 133514, 2 * 133514 + 123, 256 * 133514):
        m.put('clock_acc', acc, 4)
        m.put('clock_active', 1)
        call(m, 'music_frames_elapsed')
        expected = min(acc // 133514, 255)
        assert m.cpu.a == expected
        assert m.value('clock_acc', 4) == acc - expected * 133514
    m.put('clock_acc', 0, 4)
    m.put('clock_active', 0)
    for frame in range(80):
        call(m, 'music_tick')
        advance(230_000 if frame % 7 == 3 else 17_000)
    drain(m, rendered, advance, len(m.mem.pcm_writes))
    assert rendered == MUSIC[:len(rendered)], (slot, len(rendered))
    assert len(rendered) > 8000, len(rendered)

    # Effects ride on the same stream: sample by sample the rendered byte is
    # music plus match2 for its exact length, then music alone again.
    m2, rendered2, advance2 = clocked(slot)
    for _ in range(20):
        call(m2, 'music_tick')
    base = len(m2.mem.pcm_writes)
    call(m2, 'sound_play', 3)   # SFX_MATCH2
    for _ in range(80):
        call(m2, 'music_tick')
        if m2.value('effect_remaining', 2) == 0:
            break
    drain(m2, rendered2, advance2, len(m2.mem.pcm_writes))
    assert len(rendered2) >= base + len(MATCH2), (slot, len(rendered2), base)
    for i, value in enumerate(rendered2):
        want = MUSIC[i]
        if base <= i < base + len(MATCH2):
            want = (want + MATCH2[i - base]) & 255
        assert value == want, (slot, i, value, want)
    assert m2.value('effect_remaining', 2) == 0
    assert not m2.mem.psg_writes, 'PCM playback must not touch the PSG'
    print(f'PASS slot {slot}: {len(rendered2)} clocked samples exact, '
          f'{len(MATCH2)} mixed effect samples', flush=True)
