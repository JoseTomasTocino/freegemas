"""Build the streamed VERA PCM music track.

The IIGS port streams `MUSIC.PCM` (unsigned 8-bit mono) from disk while the
Ensoniq DOC ping-pongs 4 KiB tables.  VERA has one PCM FIFO and no oscillator
memory, so the VERA port uses the same idea with a signed 8-bit mono stream
(VERA's PCM samples are signed) fed from a small ring buffer that the game
refills from disk every few frames.

Sample rate: VERA PCM rate 21 gives 25e6/512/128*21 = 8010.86 Hz, so the track
is resampled to 8011 Hz.  The source OGG is already close to full scale, so the
track is attenuated rather than boosted: the mix peaks near 0.48 full scale and
the sound effects near 0.29.  That leaves room to add both in software without
wrapping, and keeps VERA's doubled (PSG + PCM) mixer from clamping on peaks.

Outputs:
  generated/music.pcm        signed 8-bit mono, shipped as MUSIC.PCM
  llvm/build/music_pcm_preview.wav  44.1 kHz preview for listening
  llvm/build/music_pcm_report.json
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
VERA = HERE.parent
MEDIA = VERA.parent / 'media'
GENERATED = VERA / 'generated'
BUILD = VERA / 'llvm' / 'build'

RATE = 8011          # VERA PCM rate 21; the hardware clock is 8010.86 Hz
MUSIC_GAIN = 0.36    # attenuate: the source OGG already peaks near full scale
MUSIC_LIMIT = 0.70   # safety ceiling only; MUSIC_GAIN keeps the limiter idle
FADE = 40            # ~5 ms loop-edge ramp at both ends


def decode(ogg):
    command = [
        'ffmpeg', '-v', 'error', '-i', str(ogg),
        '-af', (f'aresample={RATE}:resampler=swr:filter_size=64:'
                'phase_shift=10:cutoff=0.97:linear_interp=0,'
                f'volume={MUSIC_GAIN},alimiter=limit={MUSIC_LIMIT}:level=0:'
                'attack=1:release=20'),
        '-ac', '1', '-f', 's16le', 'pipe:1',
    ]
    result = subprocess.run(command, check=True, capture_output=True)
    return np.frombuffer(result.stdout, dtype='<i2').astype(np.int32)


def to_signed8(samples):
    # VERA PCM reads the FIFO byte as signed 8-bit (value << 8), so the file
    # itself must already be signed.  Round rather than truncate to keep the
    # waveform symmetric around zero.
    scaled = np.round(samples / 256.0).astype(np.int32)
    return np.clip(scaled, -128, 127).astype(np.int8)


def fade_edges(pcm):
    if FADE <= 0 or len(pcm) < 2 * FADE:
        return
    ramp = np.linspace(0.0, 1.0, FADE, dtype=np.float32)
    pcm[:FADE] = np.round(pcm[:FADE] * ramp).astype(np.int8)
    pcm[-FADE:] = np.round(pcm[-FADE:] * ramp[::-1]).astype(np.int8)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', nargs='?', type=Path, default=MEDIA / 'music.ogg')
    parser.add_argument('--output', type=Path, default=GENERATED / 'music.pcm')
    parser.add_argument('--preview', type=Path, default=BUILD / 'music_pcm_preview.wav')
    parser.add_argument('--no-preview', action='store_true')
    args = parser.parse_args()

    samples = decode(args.input)
    pcm = to_signed8(samples)
    fade_edges(pcm)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(pcm.tobytes())

    seconds = len(pcm) / RATE
    peak = int(np.abs(pcm.astype(np.int16)).max())
    rms = float(np.sqrt(np.mean(pcm.astype(np.float64) ** 2)))
    if not args.no_preview:
        args.preview.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            'ffmpeg', '-v', 'error', '-y', '-f', 's8', '-ar', str(RATE),
            '-ac', '1', '-i', str(args.output), '-ar', '44100',
            str(args.preview)], check=True)
    report = {
        'source': str(args.input),
        'rate': RATE,
        'seconds': round(seconds, 3),
        'samples': len(pcm),
        'bytes': len(pcm),
        'peak': peak,
        'rms': round(rms, 2),
        'gain': MUSIC_GAIN,
        'limit': MUSIC_LIMIT,
    }
    report_path = BUILD / 'music_pcm_report.json'
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(f'music.pcm {len(pcm)} bytes ({seconds:.2f}s at {RATE} Hz, '
          f'peak {peak}, rms {rms:.1f}) from {args.input.name}')
    if peak > 127:
        raise SystemExit('music peak overflows signed 8-bit')
    return 0


if __name__ == '__main__':
    sys.exit(main())
