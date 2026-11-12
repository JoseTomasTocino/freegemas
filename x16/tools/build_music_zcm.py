#!/usr/bin/env python3
"""Build music.zcm from the original 44.1 kHz stereo OGG.

Output is 8011 Hz, mono, signed 16-bit PCM (VERA audio rate 21 =
8010.86 Hz), wrapped in the standard 8-byte ZCM header.  Sixteen-bit samples
keep the orchestral track clean; the old 8-bit render had audible
quantisation hiss.  The game streams this file through the KERNAL file
channel and mixes the five 8-bit effect samples in before the FIFO.

Requires:
    python -m pip install soundfile soxr numpy
"""
from pathlib import Path
import struct
import sys

import numpy as np
import soundfile as sf
import soxr

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
SRC = ROOT.parent / "media" / "music.ogg"
OUT = ROOT / "assets" / "music.zcm"

RATE_HZ = 8010.864
VERA_RATE = 21
GAIN = 0.55             # leaves room for the effects mixed on top
FADE = 40               # ~5 ms loop-edge ramp
MAX_SIZE = 2048 * 1024 - 8192


def main() -> int:
    if not SRC.exists():
        raise SystemExit(f"missing source: {SRC}")
    data, sr = sf.read(SRC, dtype="float32", always_2d=True)
    mono = data.mean(axis=1)
    resampled = soxr.resample(mono, sr, RATE_HZ, quality="VHQ")
    pcm = np.round(resampled * GAIN * 32767.0).astype(np.int32)
    pcm = np.clip(pcm, -32768, 32767)
    if FADE and len(pcm) >= 2 * FADE:
        ramp = np.linspace(0.0, 1.0, FADE, dtype=np.float32)
        pcm[:FADE] = np.round(pcm[:FADE] * ramp).astype(np.int32)
        pcm[-FADE:] = np.round(pcm[-FADE:] * ramp[::-1]).astype(np.int32)
    raw = pcm.astype("<i2").tobytes()
    size = len(raw)
    if size == 0 or size > MAX_SIZE:
        raise SystemExit(f"PCM size out of range: {size}")
    # 16-bit mono (bit 5), volume 15, VERA rate 21.
    header = struct.pack("<HBHBBB", 0, 0, size & 0xFFFF, size >> 16, 0x2F, VERA_RATE)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(header + raw)
    print(f"music.zcm {len(header) + size} bytes ({len(pcm) / RATE_HZ:.2f}s "
          f"at {RATE_HZ:.3f} Hz, peak {int(np.abs(pcm).max())})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
