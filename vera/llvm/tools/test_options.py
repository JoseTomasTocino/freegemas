"""Check record layout using the built Options segment, without changing disk."""
from test_mos import Machine

for slot in (2, 4):
    menu = Machine(slot)
    menu.mem.ram[0x3f0] = 0xa7
    menu.mem.ram[0x3f4] = 0xa5
    menu.mem.ram[0x3f2] = 1
    menu.mem.ram[0x3f3] = 1
    menu.until(lambda: menu.mem.reg[9] == 0x11)
    for expected in (2, 0, 1):
        menu.mem.ram[0xc000] = 0xa0  # Space
        menu.until(lambda: menu.mem.ram[0x3f2] == expected)
    print('PASS Options keyboard PCM -> PSG -> Off -> PCM:', slot, flush=True)
    for scores in ((0, 0), (12345, 67890), (1, 4294967295)):
        m = Machine(slot)
        m.mem.ram[0x3f0] = 0xa7
        m.mem.ram[0x3f4] = 0xa5
        m.mem.ram[0x3e9] = 0xa5
        m.mem.ram[0x3e0:0x3e8] = b''.join(v.to_bytes(4, 'little') for v in scores)
        m.until(lambda: m.mem.reg[9] == 0x11)
        width = max(len(str(v)) for v in scores)
        x = (320 - ((11 + width) * 6 - 1)) // 2
        for n, row in enumerate((171, 185)):
            points = [i % 320 for i in range(row * 320, (row + 7) * 320)
                      if m.mem.vram[i] == 255]
            assert min(points) == x, (scores, row, x, min(points), bytes(m.mem.ram[0x3e0:0x3e8]))
            last_pixel = 3 if scores[n] % 10 == 1 else 4
            assert max(points) == x + (10 + width) * 6 + last_pixel
        print('PASS Options centered/right-aligned:', slot, scores)
