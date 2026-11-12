"""Loading messages must clear old native text on every segment transfer."""
from test_mos import Machine

for slot in (2, 4):
    m = Machine(slot)
    m.mem.ram[0x3f4] = 0xa5  # Return from a menu rather than cold boot.
    m.mem.ram[0x400:0x800] = bytes([0xC1]) * 1024
    m.until(lambda: m.cpu.pc == 0x3000)
    expected = bytes(c | 128 for c in b'LOADING TITLE...')
    assert m.mem.ram[0x400:0x400 + len(expected)] == expected
    for row in range(24):
        start = 0x400 + (row & 7) * 128 + (row >> 3) * 40
        offset = len(expected) if row == 0 else 0
        assert m.mem.ram[start + offset:start + 40] == bytes([0xA0]) * (40 - offset)
    print('PASS stale text cleared before LOADING TITLE:', slot)
