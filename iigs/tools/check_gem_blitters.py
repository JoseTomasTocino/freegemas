"""Execute generated A16 blitters in a small verifier against masked source rows.

Checks every palette/gem/row and every whole-sprite alignment, including writes
outside the sprite rectangle. This verifies emitted instructions and addresses;
the emulator regression separately exercises real 65816 execution and bank loads.
"""
import re
from pathlib import Path

from build_iigs_assets import GEN, MEDIA, GEM_NAMES, GLYPH, PREVIEW_BOARD
from shr_art import build


def table(name):
    text = (GEN / 'gem_data.s').read_text(encoding='utf-8')
    body = text.split('\n' + name + '\n', 1)[1]
    body = re.split(r'\n\S', body, maxsplit=1)[0]
    return bytes(int(h, 16) for h in re.findall(r'\$([0-9A-Fa-f]{2})', body))


def word(data, offset):
    return int.from_bytes(data[offset:offset+2], 'little')


def execute(code, pc, screen, x, cache=b'', y=0):
    accumulator = 0
    for _ in range(1000):
        opcode = code[pc]; pc += 1
        if opcode == 0x6B:
            return
        if opcode in (0xA9, 0x29, 0x09, 0xB9):
            operand = word(code, pc); pc += 2
            if opcode == 0xA9: accumulator = operand
            elif opcode == 0x29: accumulator &= operand
            elif opcode == 0x09: accumulator |= operand
            else:
                offset = operand + y - 0xB400
                assert 0 <= offset < len(cache)-1
                accumulator = word(cache, offset)
        elif opcode in (0xBF, 0x9F):
            address = int.from_bytes(code[pc:pc+3], 'little'); pc += 3
            offset = address + x - 0x012000
            assert 0 <= offset < len(screen)-1
            if opcode == 0xBF: accumulator = word(screen, offset)
            else: screen[offset:offset+2] = accumulator.to_bytes(2, 'little')
        else:
            raise AssertionError(f'Unexpected opcode {opcode:02X} at {pc-1:04X}')
    raise AssertionError('Blitter did not return')


def main():
    sampled = build(MEDIA, GEM_NAMES, GLYPH, PREVIEW_BOARD)
    original = bytes((i*73+19) & 255 for i in range(32000))
    cache = bytes((i*37+41) & 255 for i in range(18304))
    rows = (GEN / 'gem_rasters.bin').read_bytes()
    for palette in range(16):
        for gem in range(7):
            for row in range(20):
                actual = bytearray(original); expected = bytearray(original)
                destination = 40*160+49
                for x in range(0,12,2):
                    offset = gem*240+row*12+x
                    value = (word(original,destination+x) & word(sampled['masks'],offset)) | word(sampled['tiles'],palette*1680+offset)
                    expected[destination+x:destination+x+2] = value.to_bytes(2,'little')
                execute(rows, word(rows,(palette*140+gem*20+row)*2), actual,destination)
                assert actual == expected, (palette,gem,row)
    offsets = table('gemFastOffset'); banks = table('gemFastBank')
    codes = [(GEN / f'gem_fast{i}.bin').read_bytes() for i in range(3)]
    for alignment in range(22):
        for gem in range(7):
            actual = bytearray(original); expected = bytearray(original)
            y0 = 15+alignment; destination = y0*160+49
            background = (y0-14)*104+1
            for row in range(20):
                raster = (alignment+row)%22
                palette = min(15,raster*16//20) if raster<20 else 0
                for x in range(0,12,2):
                    offset = gem*240+row*12+x
                    value = (word(cache,background+row*104+x) & word(sampled['masks'],offset)) | word(sampled['tiles'],palette*1680+offset)
                    dest = destination+row*160+x
                    expected[dest:dest+2] = value.to_bytes(2,'little')
            slot = (alignment*7+gem)*2
            execute(codes[word(banks,slot)//2],word(offsets,slot),actual,destination,cache,background)
            assert actual == expected, (alignment,gem)
    print('Verified 2240 masked rows and 154 whole-sprite alignments; all writes exact.')


if __name__ == '__main__':
    main()
