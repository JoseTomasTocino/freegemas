"""Check cold-boot instructions, timeout and key skip on both slots."""
from test_mos import Machine

for slot in (2, 4):
    for skip in (False, True):
        m = Machine(slot)
        card=5 if skip else 0
        if card:
            m.mem.ram[0xC000+card*256+0x0C]=0x20
            m.mem.ram[0xC000+card*256+0xFB]=0xD6
        m.mem.ram[0x3f0] = 0xff  # Real cold RAM need not contain zero.
        row18 = 0x400 + 2 * 128 + 2 * 40
        m.until(lambda: m.mem.ram[row18:row18 + 3] == b'\xc8\xc9\xd4')
        mouse_text=b'MOUSE: SLOT 5' if card else b'MOUSE: NONE'
        assert m.mem.ram[0x700:0x700+len(mouse_text)]==bytes(c|128 for c in mouse_text)
        if card:
            m.mem.ram[0xC000+card*256+0x0C]=0
            m.mem.ram[0xC000+card*256+0xFB]=0
        assert m.mem.ram[0x480:0x480 + 16] == bytes(c | 128 for c in b'BY ANOMIXER 2026')
        if skip:
            m.until(lambda: m.mem.frames >= 1)
            m.mem.ram[0xC000] = 0x80 | 32
        m.until(lambda: m.mem.reg[9] == 0x51)
        assert (m.mem.frames < 300) if skip else (m.mem.frames == 300)
        expected = bytes(c | 128 for c in b'LOADING TITLE...')
        assert m.mem.ram[0x400:0x400 + len(expected)] == expected
        for row in range(1, 24):
            start = 0x400 + (row & 7) * 128 + (row >> 3) * 40
            assert m.mem.ram[start:start + 40] == bytes([0xA0]) * 40
        print('PASS boot instructions:', slot, 'key skip' if skip else '5-second timeout')
