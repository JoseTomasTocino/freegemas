"""Exercise Title EXIT and save-before-QUIT for both slots."""
from test_mos import Machine

class QuitMachine(Machine):
    quit = False

    def step(self):
        if self.cpu.pc in (0xFB39, 0xFC58):
            self.cpu.pc = (self.cpu.stPopWord() + 1) & 65535
            return
        if self.cpu.pc == 0xBF00:
            sp = self.cpu.sp
            ret = self.mem.ram[0x100 + sp + 1] | self.mem.ram[0x100 + sp + 2] << 8
            if self.mem.ram[ret + 1] == 0x65:
                p = int.from_bytes(self.mem.ram[ret + 2:ret + 4], 'little')
                assert self.mem.ram[p:p + 7] == bytes([4, 0, 0, 0, 0, 0, 0])
                assert self.mem.reg[9] == 0
                self.quit = True
                return
        super().step()

for slot in (2, 4):
    m = QuitMachine(slot)
    m.until(lambda: m.mem.frames >= 361)
    m.mem.ram[0x3e0:0x3e8] = (12345).to_bytes(4, 'little') + (67890).to_bytes(4, 'little')
    m.mem.ram[0x3e8] = 1
    for key in (10, 10, 10, 10, 32):
        cleared = m.mem.keys_cleared
        m.mem.ram[0xC000] = key | 128
        m.until(lambda: m.mem.keys_cleared > cleared)
        for _ in range(3000):
            m.step()
            if m.quit:
                break
    m.until(lambda: m.quit)
    assert m.disk_scores() == [12345, 67890]
    assert m.write_calls == 1 and not m.mem.ram[0x3e8]
    print('PASS Title EXIT saves records and calls ProDOS QUIT:', slot)
