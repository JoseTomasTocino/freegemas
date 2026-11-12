"""Original mode-specific dead-board handling using the built game binaries."""
from test_mos import Machine, has_match, solution, aligned

def call(m, name):
    saved_pc = m.cpu.pc
    saved_sp = m.cpu.sp
    m.cpu.stPushWord(0x02FE)
    m.cpu.pc = m.sym[name]
    m.until(lambda: m.cpu.pc == 0x02FF)
    assert m.cpu.sp == saved_sp
    m.cpu.pc = saved_pc

dead = bytes((x + 2 * y) % 7 + 1 for y in range(8) for x in range(8))
# The actual board reported in nomove.png (white/red/purple/orange/green/
# yellow/blue = 1..7), in addition to the synthetic no-move board.
reported_dead = bytes([
    1,1,2,5,2,1,1,3, 5,6,3,3,4,7,6,2,
    4,6,7,1,7,2,3,2, 4,4,2,6,3,1,3,5,
    1,5,3,5,2,2,7,5, 5,2,1,4,6,3,7,7,
    7,6,1,3,5,1,4,6, 6,2,3,3,6,1,3,6,
])
for fixture in (dead, reported_dead):
    assert not has_match(fixture)
    try:
        solution(fixture)
    except AssertionError:
        pass
    else:
        raise AssertionError('fixture must have no legal swap')

def idle(m):
    return m.cpu.pc == m.sym['waitvsync'] and m.cpu.sp == m.idle_sp and not m.value('resolving')

for slot in (2, 4):
    for mode, fixture in ((0, dead), (1, dead), (1, reported_dead)):
        m = Machine(slot)
        records = m.disk_scores()
        m.boot_game(mode)
        # Complete the initial automatic check before installing a dead board;
        # this must work during normal idle play, without scheduling it in RAM.
        m.step()
        m.until(lambda: idle(m))
        m.put('score', 12345, 4)
        m.mem.ram[m.sym['board']:m.sym['board'] + 64] = fixture
        m.mem.writes.clear()
        # Do not press keys, set scheduling flags, or call the checker directly.
        assert m.value('score', 4) == 12345
        if mode:
            m.until(lambda: bool(m.value('game_over')) and not m.value('timer_active')
                    and idle(m))
            assert bytes(m.board()) == fixture, 'move search changed the live board'
            assert len(m.endings) == 1
            assert all(m.mem.vram[0x1FC06 + i * 8] == 0 for i in range(64))
            assert m.mem.ram[0x3e8] == 1
            records[1] = max(records[1], 12345)
            assert int.from_bytes(m.mem.ram[0x3e4:0x3e8], 'little') == records[1]
            m.return_loader()
            assert m.disk_scores() == records
            print('PASS Endless auto Game Over, gem drop and high score:', slot,
                  'nomove.png' if fixture == reported_dead else 'synthetic')
        else:
            m.until(lambda: bytes(m.board()) != fixture and idle(m))
            assert not m.value('game_over') and m.value('timer_active')
            assert 0 < m.value('time_left') <= 120
            assert bytes(m.board()) != dead and not has_match(m.board())
            solution(m.board())
            aligned(m)
            assert not any(a < 76800 and a % 320 >= 96 for a in m.mem.writes)
            print('PASS Time Trial dead board drops/refills, retains score and timer:', slot)
    m = Machine(slot)
    m.boot_game()
    m.mem.ram[m.sym['board']:m.sym['board'] + 64] = dead
    m.put('time_left', 1)
    m.put('time_frames', 59)
    call(m, 'check_no_moves')
    assert m.value('game_over') and not m.value('resolving')
    assert len(m.endings) == 1
    print('PASS timeout during dead-board animation ends once:', slot)
