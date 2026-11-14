#!/usr/bin/env python3
"""Create the BASIC stub PRG that loads the resident loader and jumps to it."""
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "hostfs"

# 10 SYS 2061
basic = bytearray([0x0B, 0x08, 0x0A, 0x00, 0x9E])
basic += b"2061"
basic += bytes([0x00, 0x00, 0x00])

code = bytearray()
code += bytes([0xA9, 0x00])              # LDA #0
code += bytes([0xA2, 0x00])              # LDX #0
code += bytes([0x9D, 0x00, 0x9E])        # STA $9E00,X
code += bytes([0xE8])                    # INX
code += bytes([0xD0, 0xFA])              # BNE loop
code += bytes([0xA9, 0x06])              # LDA #6 (name length)
ldx_at = len(code) + 1
code += bytes([0xA2, 0x00])              # LDX #<name
ldy_at = len(code) + 1
code += bytes([0xA0, 0x00])              # LDY #>name
code += bytes([0x20, 0xBD, 0xFF])        # JSR SETNAM
code += bytes([0xA9, 0x01])              # LDA #1
code += bytes([0xA2, 0x08])              # LDX #8
code += bytes([0xA0, 0x01])              # LDY #1 (header load)
code += bytes([0x20, 0xBA, 0xFF])        # JSR SETLFS
code += bytes([0xA9, 0x00])              # LDA #0 (system RAM)
code += bytes([0xA2, 0x00])              # LDX #0
code += bytes([0xA0, 0x01])              # LDY #1
code += bytes([0x20, 0xD5, 0xFF])        # JSR LOAD
code += bytes([0x4C, 0x00, 0x20])        # JMP $2000

name_addr = 0x080D + len(code)
code[ldx_at] = name_addr & 0xFF
code[ldy_at] = name_addr >> 8
code += b"loader"

assert 0x0801 + len(basic) == 0x080D
assert 0x080D + len(code) - 6 == name_addr

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "boot.prg").write_bytes(bytes([0x01, 0x08]) + basic + code)
print(f"boot.prg: code {len(code)} bytes, name at ${name_addr:04x}")
