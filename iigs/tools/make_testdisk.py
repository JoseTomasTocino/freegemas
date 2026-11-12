#!/usr/bin/env python3
"""Package a test build of FREEGEM into its own bootable .2mg.

Run from iigs/merlin32:
    python ../tools/make_testdisk.py FREEGEM_MTEST.S16 build/mtest.2mg

Same disk recipe as `make disk` (GS/OS template + the four 32 KB scene files +
System:SetStart.data), but it lets a variant S16 (key or mouse harness) be the
startup application without disturbing build/freegemas.2mg.  The scene files are
reused from build/ when present, otherwise copied from generated/.

Packing uses the repo's Cadius (../tools/cadius.exe) instead of cp2/CiderPress:
Cadius takes each file's ProDOS type/aux from a '#TTAAAA' suffix on the host
file name, so the files are staged under suffixed names in a temp directory.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

CADIUS = "../tools/cadius.exe"
TEMPLATE = pathlib.Path("../build/gsos-template.2mg")
VOLUME = "FREEGEMAS"
SCENES = {
    "SCENE4.RAW": "generated/scene_tt.bin",
    "SCENE4E.RAW": "generated/scene_end.bin",
    "TITLE.RAW": "generated/title_scene.bin",
    "HOWTO.RAW": "generated/howto_scene.bin",
}


def cadius(*args: str) -> None:
    proc = subprocess.run([CADIUS, *args], capture_output=True, text=True)
    out = (proc.stdout or "") + (proc.stderr or "")
    if "Error" in out or proc.returncode not in (0, 1):
        print(out.rstrip())
        raise SystemExit("cadius failed: %s" % " ".join(args))


def prodos_name(base: str) -> str:
    """ProDOS allows 15 chars of A-Z, 0-9 and '.' only (no underscore).

    Harness builds are named FREEGEM_MTEST.S16; the default guest name becomes
    MTEST.S16 so the SetStart path stays short and legal.
    """
    name = base.upper().replace("_", ".")
    if len(name) > 15 and name.startswith("FREEGEM."):
        name = name[len("FREEGEM."):]
    if len(name) > 15:
        stem, _, ext = name.rpartition(".")
        keep = 15 - len(ext) - 1
        name = (stem[:keep].rstrip(".") + "." + ext) if keep > 0 else name[:15]
    return name


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: make_testdisk.py APP.S16 [DISK.2mg] [NAME.S16]")
    app = sys.argv[1]
    disk = sys.argv[2] if len(sys.argv) > 2 else "build/mtest.2mg"
    # ProDOS keeps 15 characters and rejects underscores, so a harness build
    # (FREEGEM_MTEST.S16) is staged under a short name the SetStart path can use.
    name = sys.argv[3] if len(sys.argv) > 3 else prodos_name(pathlib.Path(app).name)
    build = pathlib.Path("build")
    if not (build / app).exists():
        raise SystemExit("missing %s (assemble it first)" % (build / app))
    if not TEMPLATE.exists():
        raise SystemExit("missing %s" % TEMPLATE)

    shutil.copyfile(TEMPLATE, disk)
    cadius("RENAMEVOLUME", disk, VOLUME)

    stage = pathlib.Path(tempfile.mkdtemp(prefix="fgdsk-"))
    try:
        staged = stage / (name + "#B3DB03")
        shutil.copyfile(build / app, staged)
        cadius("ADDFILE", disk, "/" + VOLUME, str(staged))

        for scene, src in SCENES.items():
            if not (build / scene).exists():
                shutil.copyfile(src, build / scene)
            staged = stage / (scene + "#060000")
            shutil.copyfile(build / scene, staged)
            cadius("ADDFILE", disk, "/" + VOLUME, str(staged))

        subprocess.run(
            [sys.executable, "../tools/make_startup.py", VOLUME, name, "build/SYSTEM/SetStart.data"],
            check=True,
        )
        staged = stage / "SetStart.data#5A0004"
        shutil.copyfile(build / "SYSTEM" / "SetStart.data", staged)
        cadius("REPLACEFILE", disk, "/" + VOLUME + "/SYSTEM", str(staged))
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    print("wrote", disk, "with", name)


if __name__ == "__main__":
    main()
