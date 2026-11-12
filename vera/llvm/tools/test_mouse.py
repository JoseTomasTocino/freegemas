"""Run shipped title/game binaries against the Apple Mouse firmware contract.

Uses single-byte vector offsets from AppleWin's MouseInterface.rom. Firmware
entry traps check register arguments, clamp scratch locations and ZP safety;
this is a model, not an AppleWin/hardware mouse capture.
"""
from test_mos import Machine, Memory, solution, swap, VERA, LLVM, symbols
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--disk', type=Path)
parser.add_argument('--case', help='Only one VERA,mouse,mode combination')
args = parser.parse_args()
test_disk = args.disk.read_bytes() if args.disk else None

VECTORS = bytes.fromhex('B3 C4 9B A4 C0 8A DD BC')


class MouseMemory(Memory):
    def __init__(self, vera_slot, card_slot):
        super().__init__(vera_slot)
        self.card_base = 0xC000 + card_slot * 256 if card_slot else 0
        self.card_rom = bytearray(256)
        self.card_rom[0x0C] = 0x20
        self.card_rom[0xFB] = 0xD6
        self.card_rom[0x12:0x1A] = VECTORS
        self.lc_ram = True
        self.lc_bank2 = True

    def __getitem__(self, addr):
        if addr == 0xC011:
            return 128 if self.lc_bank2 else 0
        if addr == 0xC012:
            return 128 if self.lc_ram else 0
        if addr in (0xC082, 0xC08A, 0xC083, 0xC08B):
            self.lc_ram = addr in (0xC083, 0xC08B)
            self.lc_bank2 = addr in (0xC082, 0xC083)
            return 0
        if isinstance(addr, int) and self.card_base and self.card_base <= addr < self.card_base + 256:
            return self.card_rom[addr - self.card_base]
        return super().__getitem__(addr)


class MouseMachine(Machine):
    def __init__(self, vera_slot, card_slot):
        super().__init__(vera_slot, test_disk)
        memory = MouseMemory(vera_slot, card_slot)
        memory.ram[:] = self.mem.ram
        self.mem = memory
        self.cpu.memory = memory
        self.card_slot = card_slot
        self.position = (0, 0)
        self.down = False
        self.polls = 0
        self.clamps = {}
        self.mode = 0

    def step(self):
        if self.cpu.pc in (0xFB39, 0xFC58):
            self.cpu.pc = (self.cpu.stPopWord() + 1) & 65535
            return
        base = self.mem.card_base
        if base and self.cpu.pc in [base + n for n in VECTORS]:
            operation = 0x12 + VECTORS.index(self.cpu.pc - base)
            assert self.cpu.x == base >> 8, ('firmware X', operation, self.cpu.x)
            assert self.cpu.y == self.card_slot * 16, ('firmware Y', operation, self.cpu.y)
            ram = self.mem.ram
            if operation == 0x19:
                assert not self.mem.lc_ram, 'INITMOUSE requires system ROM'
            elif operation == 0x17:
                minimum = ram[0x478] | ram[0x578] << 8
                maximum = ram[0x4F8] | ram[0x5F8] << 8
                self.clamps[self.cpu.a] = (minimum, maximum)
            elif operation == 0x12:
                self.mode = self.cpu.a
            elif operation == 0x14:
                x, y = self.position
                for address, value in ((0x478, x & 255), (0x578, x >> 8),
                                       (0x4F8, y & 255), (0x5F8, y >> 8),
                                       (0x778, 128 if self.down else 0)):
                    ram[address + self.card_slot] = value
                self.polls += 1
            ram[:192] = bytes([0xD7]) * 192
            self.cpu.x = 0xA7
            self.cpu.y = 0xB7
            self.cpu.pc = (self.cpu.stPopWord() + 1) & 65535
            return
        super().step()

    def mouse_frame(self, x, y, down=False):
        self.position = (x, y)
        self.down = down
        polls = self.polls
        self.until(lambda: self.polls > polls and self.cpu.pc == self.sym['waitvsync']
                   and self.cpu.sp == self.idle_sp and not self.value('resolving'))


for vera_slot, card_slot in ((2, 4), (2, 5), (4, 5), (2, 0), (4, 0)):
    for mode in (0, 1):
        if args.case and args.case != f'{vera_slot},{card_slot},{mode}':
            continue
        m = MouseMachine(vera_slot, card_slot)
        # Exercise the actual Intro -> Title -> Time Trial/Endless loader path.
        m.until(lambda: m.mem.frames >= 361)
        if card_slot:
            suffix='4' if vera_slot==4 else ''
            title_sym=symbols(LLVM/f'build/title{suffix}.bin.elf')
            option_sym=symbols(LLVM/f'build/option{suffix}.bin.elf')
            howto_sym=symbols(LLVM/f'build/howto{suffix}.bin.elf')
            def menu_frame(sym,x,y,down=False):
                m.position=(x,y);m.down=down;polls=m.polls
                # INIT polls before Options finishes caching/drawing values.
                # Wait for steady menu polls before inspecting hand attributes.
                m.until(lambda:m.polls>=polls+3)
                for _ in range(4000):m.step()
                hand=m.mem.vram[0x1FC00+64*8:0x1FC08+64*8]
                assert ((hand[0]<<5)|((hand[1]&15)<<13))==0x1F040,'menu hand address'
                assert hand[1]&128 and hand[6:8]==bytes([12,0x50]),'menu hand format'
            menu_frame(title_sym,160,195)
            m.down=True
            m.until(lambda:m.cpu.pc==0x3000 and m.mem.reg[9]==0)
            menu_frame(option_sym,150,66) # Release incoming title click.
            menu_frame(option_sym,150,66,True)
            assert m.mem.ram[0x3F2]==2,'mouse music toggle PCM to PSG'
            menu_frame(option_sym,150,66,True)
            assert m.mem.ram[0x3F2]==2,'held click must not repeat toggle'
            menu_frame(option_sym,150,66)
            menu_frame(option_sym,150,66,True)
            assert m.mem.ram[0x3F2]==0,'mouse music toggle PSG to OFF'
            menu_frame(option_sym,150,66)
            menu_frame(option_sym,150,66,True)
            assert m.mem.ram[0x3F2]==1,'mouse music toggle OFF to PCM'
            menu_frame(option_sym,150,83)
            menu_frame(option_sym,150,83,True)
            assert m.mem.ram[0x3F3]==0,'mouse sound toggle'
            menu_frame(option_sym,150,117)
            m.down=True
            m.until(lambda:m.cpu.pc==0x3000 and m.mem.reg[9]==0)
            menu_frame(title_sym,160,178)
            m.down=True
            m.until(lambda:m.cpu.pc==0x3000 and m.mem.reg[9]==0)
            menu_frame(howto_sym,160,210)
            m.down=True
            m.until(lambda:m.cpu.pc==0x3000 and m.mem.reg[9]==0)
            menu_frame(title_sym,160,145+mode*17)
            m.down=True
            m.until(lambda:m.cpu.pc==m.sym['waitvsync'] and m.mem.reg[9]==0x71)
        else:
          if mode:
              cleared = m.mem.keys_cleared
              m.mem.ram[0xC000] = 0x8A
              m.until(lambda: m.mem.keys_cleared > cleared)
              for _ in range(3000):m.step()
          m.mem.ram[0xC000] = 0xA0
          m.until(lambda: m.cpu.pc == m.sym['waitvsync'] and m.mem.reg[9] == 0x71)
        m.idle_sp = m.cpu.sp
        assert m.mem.ram[0x3F1] == mode
        if card_slot:
            # mouse_init preserves the Language Card selection it inherited
            # (the model boots in ProDOS's RAM-read bank 2 state).
            assert m.mem.lc_ram and m.mem.lc_bank2, 'mouse init must restore LC state'
            assert m.clamps == {0: (0, 319), 1: (0, 239)}
            assert m.mode == 1 and m.value('mouse_slot') == card_slot
            ax, ay, bx, by = solution(m.board())
            m.mouse_frame(105 + ax * 26, 25 + ay * 26)
            hand=m.mem.vram[0x1FC00+64*8:0x1FC08+64*8]
            assert ((hand[0]<<5)|((hand[1]&15)<<13)) == 0x1F040
            assert not hand[1]&128 and hand[6:8] == bytes([12,0x50])
            assert m.mem.vram[0x1F040:0x1F0C0] == (VERA/'generated/mouse_hand_16.bin').read_bytes(), 'hand pattern must survive PCM preload'
            assert (m.value('cursor_x'), m.value('cursor_y')) == (ax, ay)
            m.mouse_frame(105 + ax * 26, 25 + ay * 26, True)
            assert m.value('selected') == 1
            m.mouse_frame(105 + ax * 26, 25 + ay * 26, True)
            assert m.value('selected') == 1, 'held button must not double-select'
            m.mouse_frame(105 + ax * 26, 25 + ay * 26)
            before = bytes(m.board())
            m.mouse_frame(105 + bx * 26, 25 + by * 26, True)
            assert bytes(m.board()) != before and not m.value('selected')
            m.mouse_frame(0,0)
            ax,ay,bx,by=solution(m.board())
            m.mouse_frame(105+ax*26,25+ay*26,True)
            before=bytes(m.board())
            m.mouse_frame(105+bx*26,25+by*26,True)
            assert bytes(m.board())!=before and not m.value('selected'),'held drag must swap'
            after=bytes(m.board())
            m.mouse_frame(105+bx*26,25+by*26,True)
            assert bytes(m.board())==after and not m.value('selected'),'drag must fire once'
            m.mouse_frame(0, 0)
            m.mouse_frame(105 + 3 * 26, 25 + 3 * 26)
            m.key(21)
            m.mouse_frame(105 + 3 * 26, 25 + 3 * 26)
            assert (m.value('cursor_x'), m.value('cursor_y')) == (4, 3), 'stationary mouse must not undo keyboard input'
            m.mouse_frame(30,176,True)
            assert m.value('hint_used') == 1
            assert m.mem.vram[0x1FC06+65*8] == 12
            assert (m.value('cursor_x'),m.value('cursor_y')) == (4,3), 'HUD hint click must preserve board cursor'
            m.mouse_frame(30,195)
            m.mouse_frame(30,195,True)
            assert m.value('score',4) == 0 and m.value('time_left') == 120
            assert m.mem.vram[0x1FC06+64*8] == 12, 'reset must restore mouse pointer'
            m.mouse_frame(30,223)
            m.position=(30,223);m.down=True
            m.until(lambda:m.cpu.pc==0x3000 and m.mem.reg[9]==0)
        else:
            assert m.value('mouse_slot') == 0
            assert m.mem.vram[0x1FC06+64*8] == 0
            swap(m)
        print(f'PASS mode {mode}, VERA {vera_slot}, mouse: {card_slot or "none"}: menus, drag/input, hand, HUD, firmware/ZP', flush=True)
