#!/usr/bin/env python3
"""Builds the bootable GS/OS image in one shot (the `make disk` steps).

Steps, in order:

  1. copy the GS/OS template to --image (the template itself is never touched)
  2. cadius RENAMEVOLUME --image --volume
  3. make_startup.py -> <build>/SYSTEM/SetStart.data  (CFG $0004)
  4. create /DATA, add game resources there, and replace SetStart.data
  5. cadius CATALOG    -> assert FREEGEM.S16 is S16/$DB03 and SetStart.data is
                          CFG/$0004, so a silently wrong type cannot ship

Cadius 1.4.5 usage (verified with --help and on the images in this repo):

    cadius CATALOG      <image> [-V]
    cadius CHECKVOLUME  <image> [-V]
    cadius RENAMEVOLUME <image> <new_volume_name>
    cadius ADDFILE      <image> <prodos_folder_path> <host_file_path>
    cadius REPLACEFILE  <image> <prodos_folder_path> <host_file_path>

    A host file name of the form NAME#TTAAAA sets the ProDOS type ($TT) and aux
    type ($AAAA); Cadius strips the '#' part from the ProDOS name.  The name
    itself must be ProDOS-legal (letters/digits/'.'; no '_' or other symbols),
    and Cadius prints "Error : ..." but still exits 0, so its stdout must be
    checked instead of its exit code.

This script exists because `make` is not installed on every machine that has
Python -- running it directly reproduces `make disk` exactly.

Usage (from iigs/merlin32):
    python ../tools/pack_disk.py
    python ../tools/pack_disk.py --image C:/tmp/test.2mg --volume FREEGEMAS
"""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def run(cadius: Path, args, expect_ok_text: str | None = None) -> str:
    proc = subprocess.run([str(cadius), *args], capture_output=True, text=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    # Cadius prints "  Error : <text>" and still exits 0 on failures.  Match the
    # "Error :" form only: a CATALOG listing legitimately contains file names
    # such as /System/Error.Msg.
    failed = re.search(r"^\s*Error\s*:", out, re.MULTILINE) is not None
    if failed or proc.returncode != 0:
        print(out.rstrip())
        raise SystemExit(f"cadius failed: {' '.join(args)}")
    if expect_ok_text and expect_ok_text not in out:
        print(out.rstrip())
        raise SystemExit(f"cadius did not report '{expect_ok_text}' for {' '.join(args)}")
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", default="../build/gsos-template.2mg")
    parser.add_argument("--image", default="build/freegemas.2mg")
    parser.add_argument("--volume", default="FREEGEMAS")
    parser.add_argument("--build", default="build")
    parser.add_argument("--app", default="FREEGEM.S16")
    parser.add_argument("--cadius", default="../cadius.exe")
    args = parser.parse_args()

    template = Path(args.template)
    image = Path(args.image)
    build = Path(args.build)
    cadius = Path(args.cadius)
    if not template.exists():
        raise SystemExit(f"template not found: {template}")
    if not cadius.exists():
        raise SystemExit(f"cadius not found: {cadius}")

    image.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(template, image)
    print(f"copied {template} -> {image}")

    # Cadius prints "Rename volume 'TIMEPILOT' as 'FREEGEMAS' :".
    run(cadius, ["RENAMEVOLUME", str(image), args.volume],
        expect_ok_text=f"as '{args.volume}'")

    run(cadius, ["CREATEFOLDER", str(image), f"/{args.volume}/DATA"])

    startup = build / "SYSTEM" / "SetStart.data"
    subprocess.run([sys.executable, str(HERE / "make_startup.py"),
                    args.volume, args.app, str(startup)], check=True)

    subprocess.run([sys.executable, str(HERE / "pack_cadius.py"),
                    "--image", str(image), "--volume", args.volume,
                    "--build", str(build), "--cadius", str(cadius)], check=True)

    catalog = run(cadius, ["CATALOG", str(image)])
    # Catalog rows look like:
    #   FREEGEM.S16           S16   $DB03    32287 ...
    #   SetStart.data         CFG   $0004       24 ...
    wanted = {args.app: ("S16", "$DB03"), "SetStart.data": ("CFG", "$0004")}
    found = {}
    for line in catalog.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[0] in wanted:
            found[fields[0]] = (fields[1], fields[2])
    for name, (ftype, aux) in wanted.items():
        got = found.get(name)
        if got != (ftype, aux):
            raise SystemExit(f"catalog says {name} is {got}, expected {(ftype, aux)}")
        print(f"  verify: {name} {ftype} {aux} OK")
    print(f"image ready: {image} (volume {args.volume}, startup :{args.volume}:{args.app})")


if __name__ == "__main__":
    main()
