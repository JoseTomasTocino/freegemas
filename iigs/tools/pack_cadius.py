#!/usr/bin/env python3
"""Packs the Freegemas IIGS build products into a bootable GS/OS image with Cadius.

Replaces the cp2 (CiderPress II) steps the Makefile used to run.  Cadius 1.4.5
already ships with the repo and can set a ProDOS file type/aux type from a
'#TTAAAA' suffix on the *host* file name (T = type byte, AAAA = aux word), e.g.

    FREEGEM.S16#B3DB03   ->  type $B3 (S16), aux $DB03 (GS/OS launchable)
    SCENE4.RAW#060000    ->  type $06 (BIN), aux $0000 in /DATA
    HISCORE.DAT#200000   ->  type $20 (TXT), aux $0000
    SetStart.data#5A0004 ->  type $5A (CFG), aux $0004

Cadius strips the suffix from the ProDOS name, so the guest still sees
FREEGEM.S16 / SetStart.data.  The suffix cannot be written straight in the
Makefile because make treats '#' as the start of a comment, therefore this
script stages the files with suffixed names in a temporary directory and calls
Cadius from there.

Cadius reports failures on stdout ("Error : ...") while still exiting 0, so
every call's output is checked.

Usage: python pack_cadius.py --image build/freegemas.2mg --volume FREEGEMAS
                             [--cadius C:/dev/cadius.exe] [--build build]
"""
import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# ProDOS type numbers used by the image.
T_S16 = 0xB3
T_BIN = 0x06
T_TXT = 0x20
T_TEXT = 0x04  # GS/OS TXT document; recognized by Teach
T_FND = 0xC9   # Finder information files
T_ICN = 0xCA   # Finder icon file
T_CFG = 0x5A

# (source relative to --build, ProDOS folder, ProDOS name, type, aux)
DATA_FOLDER = "/{volume}/DATA"
FILES = [
    ("GEMS2.RAW", DATA_FOLDER, "GEMS2.RAW", T_BIN, 0x0000),
    ("GEMS0.RAW", DATA_FOLDER, "GEMS0.RAW", T_BIN, 0x0000),
    ("GEMS1.RAW", DATA_FOLDER, "GEMS1.RAW", T_BIN, 0x0000),
    ("GEMS.RAW", DATA_FOLDER, "GEMS.RAW", T_BIN, 0x0000),
    ("FREEGEM.S16", "/{volume}", "FREEGEM.S16", T_S16, 0xDB03),
    ("SCENE4.RAW", DATA_FOLDER, "SCENE4.RAW", T_BIN, 0x0000),
    ("SCENE4E.RAW", DATA_FOLDER, "SCENE4E.RAW", T_BIN, 0x0000),
    ("TITLE.RAW", DATA_FOLDER, "TITLE.RAW", T_BIN, 0x0000),
    ("HOWTO.RAW", DATA_FOLDER, "HOWTO.RAW", T_BIN, 0x0000),
    ("OPTIONS.RAW", DATA_FOLDER, "OPTIONS.RAW", T_BIN, 0x0000),
    ("SELECT.PCM", DATA_FOLDER, "SELECT.PCM", T_BIN, 0x0000),
    ("FALL.PCM", DATA_FOLDER, "FALL.PCM", T_BIN, 0x0000),
    ("MATCH1.PCM", DATA_FOLDER, "MATCH1.PCM", T_BIN, 0x0000),
    ("MATCH2.PCM", DATA_FOLDER, "MATCH2.PCM", T_BIN, 0x0000),
    ("MATCH3.PCM", DATA_FOLDER, "MATCH3.PCM", T_BIN, 0x0000),
    ("MUSIC.PCM", DATA_FOLDER, "MUSIC.PCM", T_BIN, 0x0000),
    ("HISCORE.DAT", DATA_FOLDER, "HISCORE.DAT", T_TXT, 0x0000),
    ("README.TXT", "/{volume}", "README.TXT", T_TEXT, 0x0000),
    ("Finder.Data", "/{volume}", "Finder.Data", T_FND, 0x0000),
    ("Finder.Root", "/{volume}", "Finder.Root", T_FND, 0x0000),
    ("FREEGEMAS.ICONS", "/{volume}/Icons", "FREEGEMAS.ICONS", T_ICN, 0x0000),
    # The template already has /SYSTEM/SetStart.data, so it is replaced rather
    # than added.  Its stale path points at :TIMEPILOT:TIME.PILOT and would fail
    # the boot with $1002.
    ("SYSTEM/SetStart.data", "/{volume}/SYSTEM", "SetStart.data", T_CFG, 0x0004),
]


def run(cadius: Path, args) -> None:
    cmd = [str(cadius), *args]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    # Cadius prints "  Error : <text>" and still exits 0 on failures.
    failed = re.search(r"^\s*Error\s*:", out, re.MULTILINE) is not None
    if failed or proc.returncode not in (0, 1):
        print(out.rstrip())
        raise SystemExit(f"cadius failed: {' '.join(args)}")
    for line in out.splitlines():
        if line.strip().startswith("- "):
            print(line.strip())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True, help="2mg image to write")
    parser.add_argument("--volume", required=True, help="ProDOS volume name")
    parser.add_argument("--build", default="build", help="directory with build products")
    parser.add_argument("--cadius", default="cadius.exe", help="cadius executable")
    args = parser.parse_args()

    image = Path(args.image)
    build = Path(args.build)
    cadius = Path(args.cadius)
    volume = args.volume
    if not image.exists():
        raise SystemExit(f"image not found: {image}")

    stage = Path(tempfile.mkdtemp(prefix="fgdsk-"))
    try:
        for rel, folder, name, ftype, aux in FILES:
            src = build / rel
            if not src.exists():
                raise SystemExit(f"missing build product: {src}")
            suffix = f"#{ftype:02X}{aux:04X}"
            # Keep the folder layout so SetStart.data can be staged separately.
            dest = stage / (name + suffix)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)
            prodos_folder = folder.format(volume=volume)
            if rel.startswith("SYSTEM/") or rel == "Finder.Data":
                run(cadius, ["REPLACEFILE", str(image), prodos_folder, str(dest)])
            else:
                run(cadius, ["ADDFILE", str(image), prodos_folder, str(dest)])
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    print(f"packed {len(FILES)} files into {image} (volume {volume})")


if __name__ == "__main__":
    main()
