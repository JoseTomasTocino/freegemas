#!/usr/bin/env python3
"""Regenerate every tracked Apple IIGS build input.

`build_iigs_assets.py` produces the checked-in scene/gem data and
`build_iigs_sounds.py` builds the DOC sound files in merlin32/build/.
Keeping both behind one command makes the generated inputs reproducible for
local builds and CI.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "iigs" / "merlin32" / "build"


def main() -> int:
    BUILD.mkdir(parents=True, exist_ok=True)
    for script, args in (
        ("iigs/tools/build_iigs_assets.py", []),
        ("iigs/tools/build_iigs_sounds.py", [str(BUILD)]),
    ):
        print(f"==> {script}")
        result = subprocess.run([sys.executable, str(ROOT / script), *args], cwd=ROOT)
        if result.returncode:
            return result.returncode
    print("IIgs assets regenerated in iigs/merlin32/generated/ and iigs/merlin32/build/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
