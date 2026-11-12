#!/usr/bin/env python3
"""Build the Apple IIGS DOC sound effects and the streamed music track.

The Ensoniq 5503 plays 8-bit unsigned PCM straight out of its 64 KB wave RAM.
The game uploads five effect waves once at boot (see loadSounds in src/main.s)
and only reprograms oscillator registers per trigger, so each effect file must
be exactly the size of its wave table:

    SELECT.PCM   4096 bytes   DOC $0000   (table size 4 = 4K)
    FALL.PCM     4096 bytes   DOC $1000   (table size 4 = 4K)
    MATCH1.PCM  16384 bytes   DOC $2000   (table size 6 = 16K)
    MATCH2.PCM  16384 bytes   DOC $6000   (table size 6 = 16K)
    MATCH3.PCM  16384 bytes   DOC $A000   (table size 6 = 16K)

SELECT and FALL only need 4K: the source OGGs are 0.14 s and 0.18 s.  The two
4K pages that paid for that are the music buffers at $E000 and $F000, which is
how the whole 64 KB stays in use:

    MUSIC.PCM   streamed        DOC $E000 / $F000   (two 4K ping-pong buffers)

`music.ogg` is ~126 s, so it cannot sit in wave RAM at all.  MUSIC.PCM is a
plain 8-bit PCM file; the game keeps it open and reads 4K slices into main
memory while the oscillators loop the buffers (see the DOC music section of
src/main.s).  The file must therefore NOT be padded to a table size.

Sample rate: with eight oscillators enabled the DOC sample clock is
894886/10 = 89488.6 Hz; a 4K table with size 4, resolution 0 and freq 4 (or an
8K table with size 5, resolution 1 and freq 4, or a 16K table with size 6,
resolution 0 and freq 1) plays at 89488.6/8 = 11186 Hz, which is the rate used
here.  Rates are identical on all three table sizes so effects and music can
live side by side.

Two details that matter on real hardware and in GSSquared:
  * one-shot mode halts when the wave data contains $00, so a genuine negative
    peak (unsigned $00) is nudged to $01;
  * shorter than the table is fine: the tail is silence ($80) and playback stops
    at the end of the table.

Usage: python iigs/tools/build_iigs_sounds.py [output-dir]
"""
import shutil
import subprocess
import sys
from pathlib import Path

from pcm_loud import boost

RATE = 11186
GAIN = 8.0       # linear pre-gain into the limiter (+18 dB), see the SOUNDS note
MUSIC_GAIN = 2.0  # music is a bed, not the lead. 8x drove the limiter into
                  # flat-topped clipping (the "爆音" the user heard). At 2x the
                  # 99th percentile is 225 and only 0.047% of samples reach an
                  # extreme, so it stays clear without squashing dynamics.
                  # MUS_VOL in main.s ($D0) sets the final DOC level.
MUSIC_DRIVE = 2.0  # the streamed bed is quiet because the DOC has no main-volume
                   # stage here and the 8-bit table is already at its ceiling:
                   # pcm_loud.boost() lifts the body by 6 dB and limits the peaks
                   # back to +-127, so loudness rises without any clipping risk.
LIMIT = 0.98     # limiter ceiling so the boosted peak stays just under full scale
# (source ogg, output name, table bytes)
SOUNDS = [
    ("select.ogg", "SELECT.PCM", 4096),
    ("fall.ogg", "FALL.PCM", 4096),
    ("match1.ogg", "MATCH1.PCM", 16384),
    ("match2.ogg", "MATCH2.PCM", 16384),
    ("match3.ogg", "MATCH3.PCM", 16384),
]
# The music is streamed, not table-sized: no padding, no -t limit.
MUSIC = ("music.ogg", "MUSIC.PCM")


def encode(ffmpeg: Path, ogg: Path, max_sec: float | None, gain: float,
           high_quality_resample: bool = False) -> bytes:
    cmd = [ffmpeg, "-v", "error", "-y", "-i", str(ogg)]
    if max_sec is not None:
        cmd += ["-t", f"{max_sec:.3f}"]
    filters = []
    if high_quality_resample:
        # The music is the only long continuous stream. Use a longer 64-tap
        # band-limited filter for the 44.1 kHz stereo OGG -> 11.186 kHz DOC
        # conversion; SFX retain the established default resampling path.
        filters.append(
            f"aresample={RATE}:resampler=swr:filter_size=64:phase_shift=10:"
            "cutoff=0.97:linear_interp=0")
    filters.append(f"volume={gain}")
    filters.append(f"alimiter=limit={LIMIT}:attack=1:release=20")
    cmd += [
        "-ac", "1", "-ar", str(RATE),
        "-af", ",".join(filters),
        "-f", "u8", "-",
    ]
    return subprocess.run(cmd, check=True, capture_output=True).stdout


def nudge(pcm: bytearray) -> None:
    """DOC one-shot playback stops on a $00 byte; shift real zero peaks to $01."""
    for i, b in enumerate(pcm):
        if b == 0x00:
            pcm[i] = 0x01


MUSIC_BLOCK = 4096   # one ping-pong buffer; main.s switches tables on this edge
EDGE_FADE = 8        # ~0.7 ms ramp to/from $80 at both ends of every block


def edge_fade(pcm: bytearray, block: int = MUSIC_BLOCK, n: int = EDGE_FADE) -> None:
    """Ramp each block's first and last n samples to the $80 centre line.

    The DOC oscillator is stopped and restarted at every ping-pong switch (and
    GSplus zeroes the output while halted), so a block that starts or ends on a
    non-centre sample produces an audible click -- the "bo~ bo~" heard every
    0.4 s on GSplus. Keep the fade short: longer ramps carve an audible dip
    into every block, which can sound like recurring stutter on the title.
    """
    centre = 0x80
    for base in range(0, len(pcm), block):
        end = min(base + block, len(pcm))
        for i in range(n):
            head = pcm[base + i]
            pcm[base + i] = centre + int((head - centre) * i / n)
            tail = pcm[end - 1 - i]
            pcm[end - 1 - i] = centre + int((tail - centre) * i / n)


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    media = root / "media"
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        root / "iigs" / "merlin32" / "build")
    out_dir.mkdir(parents=True, exist_ok=True)

    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print("ffmpeg not found on PATH", file=sys.stderr)
        return 1

    for src, name, size in SOUNDS:
        ogg = media / src
        if not ogg.exists():
            print(f"missing {ogg}", file=sys.stderr)
            return 1
        # Trim just inside the table so no sample is cut mid-wave.
        max_sec = size / RATE - 0.02
        # The DOC mixes 8-bit waves as data*volume/8 and this emulator/board has no
        # further DOC gain, so the raw OGG levels land ~20 dB below the system beep.
        # Compensate in the asset: 8x gain into a fast limiter keeps the peak at
        # full scale while lifting the body of each effect ~8 dB.
        pcm = bytearray(encode(Path(ffmpeg), ogg, max_sec, GAIN))
        if len(pcm) > size:
            pcm = pcm[:size]
        if len(pcm) == 0:
            print(f"{ogg}: no audio decoded", file=sys.stderr)
            return 1
        # Silence-pad to the exact table length, then keep one-shot playback
        # from stopping early on a legitimate $00 sample.
        pcm = bytearray(pcm) + bytes([0x80]) * (size - len(pcm))
        nudge(pcm)
        (out_dir / name).write_bytes(pcm)
        print(f"{name}: {len(pcm)} bytes, {len(pcm) / RATE:.3f}s")

    src, name = MUSIC
    ogg = media / src
    if not ogg.exists():
        print(f"missing {ogg}", file=sys.stderr)
        return 1
    pcm = bytearray(encode(Path(ffmpeg), ogg, None, MUSIC_GAIN,
                           high_quality_resample=True))
    if len(pcm) == 0:
        print(f"{ogg}: no audio decoded", file=sys.stderr)
        return 1
    pcm = boost(pcm, MUSIC_DRIVE)
    nudge(pcm)
    edge_fade(pcm)
    (out_dir / name).write_bytes(pcm)
    print(f"{name}: {len(pcm)} bytes, {len(pcm) / RATE:.3f}s (streamed)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
