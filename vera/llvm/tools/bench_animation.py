"""Compare a repeatable swap's 65C02 wait intervals with and without audio.

The ProDOS and VSYNC implementations are models, not a measurement of actual
disk latency, emulator speed, frame rate, or hardware. Set FREEGEMAS_TEST_DISK
to an image built from the binaries under llvm/build before running.
"""
from test_mos import Machine, swap

for enabled in (0, 1):
    machine = Machine(2)
    machine.boot_game(1)
    machine.mem.ram[0x3F2] = enabled
    machine.mem.ram[0x3F3] = enabled
    swap(machine)
    intervals = sorted(machine.wait_cycles)
    print(f'audio={enabled}: n={len(intervals)}, '
          f'mean={sum(intervals) // len(intervals)}, '
          f'median={intervals[len(intervals) // 2]}, '
          f'over_frame={sum(n > 17030 for n in intervals)}, '
          f'max={max(intervals)}', flush=True)
