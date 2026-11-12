"""Build the five X16 sound effects as 16-bit mono PCM at 8010.864 Hz.

The old assets were 8-bit samples derived from the original OGGs; at their low
peak level that left only a few effective bits and made every effect sound
sandy.  The X16 build now keeps 16-bit effects and mixes them into the 16-bit
music stream, so this script resamples the original OGGs with a proper
anti-alias filter, normalises them, and stores little-endian signed 16-bit
samples.  The sample counts match the original Apple II/VERA lengths so game
timing is unchanged.
"""
from pathlib import Path

import numpy as np
import soundfile as sf
import soxr

RATE = 8010.864
# Effect name -> (source OGG, retained sample count, target peak)
EFFECTS = {
    "select": ("select.ogg", 1100, 0.34),
    "fall": ("fall.ogg", 1431, 0.24),
    "match1": ("match1.ogg", 2403, 0.34),
    "match2": ("match2.ogg", 2403, 0.34),
    "match3": ("match3.ogg", 2403, 0.34),
}

ROOT = Path(__file__).resolve().parents[1]
MEDIA = ROOT.parent / "media"
OUT = ROOT / "hostfs"


def load_mono(path: Path) -> tuple[np.ndarray, int]:
    data, rate = sf.read(path, dtype="float32", always_2d=True)
    return data.mean(axis=1), rate


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (source, samples, peak) in EFFECTS.items():
        audio, rate = load_mono(MEDIA / source)
        audio = soxr.resample(audio, rate, RATE, quality="VHQ")
        if len(audio) < samples:
            audio = np.pad(audio, (0, samples - len(audio)))
        audio = audio[:samples].astype(np.float64)

        # Very short fades avoid start/end clicks without changing the body.
        fade = min(32 if name == "fall" else 16, samples // 8)
        if fade:
            ramp = np.linspace(0.0, 1.0, fade, endpoint=False)
            audio[:fade] *= ramp
            audio[-fade:] *= ramp[::-1]

        top = float(np.max(np.abs(audio)))
        if top > 1e-9:
            audio *= peak / top
        pcm = np.clip(np.rint(audio * 32767.0), -32768, 32767).astype("<i2")
        path = OUT / f"{name}.pcm"
        path.write_bytes(pcm.tobytes())
        print(f"{path.name}: {len(pcm)} samples, {len(pcm) * 2} bytes, "
              f"peak {float(np.max(np.abs(pcm)))/32768.0:.3f}")


if __name__ == "__main__":
    main()
