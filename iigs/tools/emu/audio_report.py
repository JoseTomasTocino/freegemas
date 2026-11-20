"""Analyse a GSSquared SDL "disk" audio capture (raw S16LE, 2ch, 44100 Hz).

The emulator is started with SDL_AUDIODRIVER=disk and
SDL_AUDIO_DISK_OUTPUT_FILE=<file>, which writes raw interleaved S16LE:
176400 bytes per second (44100 * 2ch * 2 bytes). No header.

Reported per window: peak, RMS, and how many samples hit the clipping
threshold. Windows with RMS below --quiet are reported as silence runs,
which is how "music stopped" bugs are spotted.

Use --from/--to (seconds) for a fine-grained look at one moment, e.g. the
first music start.
"""

from __future__ import annotations

import argparse
import struct
import sys
from array import array
from pathlib import Path

BYTES_PER_SEC = 44100 * 2 * 2


def load(path: Path) -> array:
    data = path.read_bytes()
    a = array("h")
    a.frombytes(data[: len(data) // 2 * 2])
    if sys.byteorder == "big":
        a.byteswap()
    return a


def windows(samples: array, rate: int, frames_per_window: int):
    """Yield (start_seconds, end_seconds, peak, rms) over the left channel."""
    step = frames_per_window * 2  # interleaved stereo
    n = len(samples)
    for start in range(0, n - step + 1, step):
        peak = 0
        acc = 0
        for i in range(start, start + step, 2):
            v = samples[i]
            if v < 0:
                v = -v
            if v > peak:
                peak = v
            acc += v * v
        rms = (acc / frames_per_window) ** 0.5
        yield start / (rate * 2), (start + step) / (rate * 2), peak, rms


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("file")
    ap.add_argument("--rate", type=int, default=44100)
    ap.add_argument("--window", type=float, default=0.1, help="analysis window in seconds")
    ap.add_argument("--clip", type=int, default=32000, help="clipping threshold")
    ap.add_argument("--quiet", type=int, default=200, help="silence threshold (RMS)")
    ap.add_argument("--from", dest="t_from", type=float, default=0.0)
    ap.add_argument("--to", dest="t_to", type=float, default=None)
    ap.add_argument("--per-second", action="store_true")
    a = ap.parse_args()

    samples = load(Path(a.file))
    dur = len(samples) / 2 / a.rate
    print(f"file {a.file}  dur {dur:.2f} s  samples/chan {len(samples) // 2}")

    t_from = a.t_from
    t_to = dur if a.t_to is None else min(a.t_to, dur)
    start_idx = int(t_from * a.rate) * 2
    end_idx = int(t_to * a.rate) * 2
    seg = samples[start_idx:end_idx]

    clip = sum(1 for i in range(0, len(seg), 2) if abs(seg[i]) >= a.clip)
    peak = max((abs(seg[i]) for i in range(0, len(seg), 2)), default=0)
    print(f"window {t_from:.2f}..{t_to:.2f} s: peak {peak}; |x|>={a.clip}: {clip}")

    frames = max(1, int(a.window * a.rate))
    quiet: list[tuple[float, float]] = []
    run_start = None
    loud_rms = []
    for s, e, pk, rms in windows(seg, a.rate, frames):
        s += t_from
        e += t_from
        if rms < a.quiet:
            if run_start is None:
                run_start = s
            run_end = e
        else:
            if run_start is not None:
                quiet.append((run_start, run_end))
                run_start = None
            loud_rms.append(rms)
        if a.per_second and abs(s - round(s)) < 1e-9:
            print(f"  t={s:7.2f}  peak {pk:6d}  rms {rms:8.1f}")
    if run_start is not None:
        quiet.append((run_start, run_end))

    if loud_rms:
        loud_rms.sort()
        med = loud_rms[len(loud_rms) // 2]
        p90 = loud_rms[int(len(loud_rms) * 0.9)]
        print(f"sound windows {len(loud_rms)}, rms median {med:.0f}, p90 {p90:.0f}")
    if quiet:
        print(f"quiet windows ({len(quiet)}):")
        merged: list[list[float]] = []
        for s, e in quiet:
            if merged and s - merged[-1][1] < 0.05:
                merged[-1][1] = e
            else:
                merged.append([s, e])
        for s, e in merged:
            print(f"  quiet {s:6.2f} .. {e:6.2f}  ({e - s:.2f} s)")


if __name__ == "__main__":
    main()
