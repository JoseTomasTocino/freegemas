"""Player menu timing changes new games; R continues the RNG sequence."""
from test_mos import Machine, has_match, solution

for slot in (2, 4):
    boards = []
    for delay in (1000, 4000, 12000):
        m = Machine(slot)
        m.mem.ram[0x3f4] = 0xa5
        m.until(lambda: m.mem.frames >= 61)
        for _ in range(delay):
            m.step()
        m.mem.ram[0xC000] = 0x80 | 32
        m.until(lambda: m.cpu.pc == m.sym['waitvsync'] and m.mem.reg[9] == 0x71)
        m.idle_sp = m.cpu.sp
        b = bytes(m.board())
        assert not has_match(b)
        solution(b)
        boards.append(b)
        m.key(ord('R'))
        assert bytes(m.board()) != b and not has_match(m.board())
        solution(m.board())
    assert len(set(boards)) == 3
    print('PASS varying menu timing produces different valid boards; R reshuffles:', slot)
    early_boards = []
    for frame in (2, 10, 30):
        m = Machine(slot)
        m.mem.ram[0x3f4] = 0xa5
        m.until(lambda: m.mem.frames >= frame)
        m.mem.ram[0xC000] = 0x80 | 32  # Queue start during gem animation.
        m.until(lambda: m.cpu.pc == m.sym['waitvsync'] and m.mem.reg[9] == 0x71)
        b = bytes(m.board())
        assert not has_match(b)
        solution(b)
        early_boards.append(b)
    assert len(set(early_boards)) == 3
    print('PASS early start during title animation changes first board:', slot)
