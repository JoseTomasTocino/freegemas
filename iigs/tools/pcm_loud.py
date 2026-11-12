"""Raise the streamed music bed without raising its peak.

The IIGS DOC plays 8-bit waves as ``data * volume / 8`` and the desktop
GSSquared ES5503 model has no main-volume stage, so the music bed lands about
20 dB below the system beep even with the oscillator volume at its maximum
($FF).  The wave table has no headroom left either: MUSIC.PCM peaks at +-123
already, but its RMS is only 34/127 (27 % of the table range) because the track
is a bed with quiet body and loud transients.

So "louder" can only mean more body under the same ceiling.  ``boost()``
applies a linear drive and then a peak limiter with an instant attack and a
slow release, which lifts the quiet parts by exactly ``drive`` and pins the loud
parts at full scale.  Because the peak stays at 127, neither the desktop mix
(data*vol/8) nor the web mix (51x hotter) gains any new clipping risk.

Usage: python iigs/tools/pcm_loud.py <pcm> [--drive 2.0] [--force]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

RATE = 11186          # DOC playback rate, see build_iigs_sounds.py
DRIVE = 2.0           # +6 dB on everything the limiter is not holding down
RELEASE_MS = 80.0     # gain recovery after a transient; long enough to stay smooth
CEILING = 127.0       # u8 sample range is -127..127 around the $80 centre


def boost(pcm: bytes | bytearray, drive: float = DRIVE, rate: int = RATE) -> bytearray:
    """Return ``pcm`` driven by ``drive`` and peak-limited back into +-127."""
    x = (np.frombuffer(bytes(pcm), dtype=np.uint8).astype(np.float64) - 128.0)
    x *= drive / CEILING
    level = np.abs(x)

    release = float(np.exp(-1.0 / (rate * RELEASE_MS / 1000.0)))
    env = np.empty_like(level)
    e = 0.0
    for i in range(level.size):
        v = level[i]
        e = v if v > e else e * release
        env[i] = e
    np.maximum(env, 1.0, out=env)

    y = np.rint(x / env * CEILING) + 128.0
    return bytearray(np.clip(y, 1.0, 255.0).astype(np.uint8).tobytes())


def stats(pcm: bytes | bytearray) -> tuple[float, int]:
    x = np.frombuffer(bytes(pcm), dtype=np.uint8).astype(np.int16) - 128
    return float(np.sqrt(np.mean(x.astype(np.float64) ** 2))), int(np.abs(x).max())


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 1
    path = Path(argv[0])
    drive = DRIVE
    force = False
    rest = argv[1:]
    while rest:
        arg = rest.pop(0)
        if arg == "--drive":
            drive = float(rest.pop(0))
        elif arg == "--force":
            force = True
        else:
            print(f"unknown argument {arg}", file=sys.stderr)
            return 1

    before = path.read_bytes()
    rms0, peak0 = stats(before)
    # A file that is already loud means somebody is about to boost it twice.
    if rms0 > 0.45 * CEILING and not force:
        print(f"{path}: already boosted (rms {rms0:.1f}); pass --force to re-boost",
              file=sys.stderr)
        return 2

    after = boost(before, drive)
    rms1, peak1 = stats(after)
    path.write_bytes(after)
    print(f"{path}: rms {rms0:.1f} -> {rms1:.1f} (+{20 * np.log10(rms1 / rms0):.1f} dB), "
          f"peak {peak0} -> {peak1}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
