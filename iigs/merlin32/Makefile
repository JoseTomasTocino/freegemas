# Freegemas Apple IIGS -- Merlin32 build.
#
# Run from this directory:
#   make          -- generate assets, assemble FREEGEM.S16
#   make disk     -- copy a GS/OS template, add FREEGEM.S16, select it as startup
#   make catalog  -- show the disk contents
#   make check    -- Cadius volume check
#   make clean    -- remove generated build products
#
# Override paths on the command line, e.g.
#   make MERLIN32=C:/tools/Merlin32.exe CADIUS=C:/tools/cadius.exe TEMPLATE=../build/gsos-template.2mg

MERLIN32 ?= Merlin32.exe
# Cadius does the whole pack (volume rename, file adds, per-file ProDOS type/aux).
# See tools/pack_cadius.py; no cp2/CiderPress needed.
CADIUS   ?= cadius.exe
TEMPLATE ?= ../build/gsos-template.2mg
DISK     ?= build/freegemas.2mg
S16      ?= build/FREEGEM.S16
VOLUME   ?= FREEGEMAS
# The GS/OS template ships as volume TIMEPILOT; the copy is renamed to $(VOLUME)
# right after it is made, so the image, its SetStart path and the Finder handoff
# in src/main.s (quitFinder) all agree.
# Startup app written into /SYSTEM/SetStart.data.
#   FREEGEM.S16 -> boot straight into the game.  Exit now hands the machine to
#                  the Finder through Quit's "next application" pointer (see
#                  quitFinder in src/main.s), so the GS/OS desktop appears.
#   SYSTEM:FINDER -> boot to the desktop instead; Freegemas is then started from
#                  its icon (needs a mouse double-click).
# Override on the command line: make disk APP=SYSTEM:FINDER
APP      ?= FREEGEM.S16

.PHONY: all assets disk catalog check clean

all: $(S16)

# A clean checkout has no build directory; Merlin32 and the packager write there.
build:
	python -c "from pathlib import Path; Path('build').mkdir(exist_ok=True)"

assets: generated/gem_data.s generated/gem_rasters.bin

generated/gem_data.s: ../tools/build_iigs_assets.py ../tools/shr_art.py ../tools/committed_art.py ../tools/hud_art.py ../../media/handCursor.png
	python ../tools/build_iigs_assets.py

generated/gem_rasters.bin generated/gem_fast0.bin generated/gem_fast1.bin generated/gem_fast2.bin: generated/gem_data.s
	python ../tools/build_iigs_assets.py

$(S16): src/main.s generated/gem_data.s | build
	$(MERLIN32) macros src/main.s

# Copy the template before adding so the template itself is never modified.
# The whole pack (template copy -> RENAMEVOLUME -> DATA resources + app/docs,
# saved Finder layout, and the custom Freegemas icon)
# lives in tools/pack_disk.py so it can be run without make; per-file type/aux
# comes from a '#TTAAAA' suffix on the staged host file name (Cadius strips it),
# because make cannot carry '#' inline (it starts a comment).
# SCENE4.RAW / SCENE4E.RAW are the full 32000-byte 4bpp screen images streamed
# into SHR RAM at boot (Time Trial / Endless); BIN files read via GS/OS Open+Read.
# SetStart.data is written before packing because pack_cadius.py replaces the
# stale copy the template ships in /SYSTEM (it points at :TIMEPILOT:TIME.PILOT
# and would fail the boot with $1002). Saved Finder.Data/Root preserve the
# icon arrangement from ../finder/.
disk: $(S16) build/GEMS.RAW build/GEMS0.RAW build/GEMS1.RAW build/GEMS2.RAW build/SCENE4.RAW build/SCENE4E.RAW build/TITLE.RAW build/HOWTO.RAW build/OPTIONS.RAW \
	build/SELECT.PCM build/FALL.PCM build/MATCH1.PCM build/MATCH2.PCM build/MATCH3.PCM \
	build/MUSIC.PCM build/HISCORE.DAT build/README.TXT build/Finder.Data build/Finder.Root \
	build/FREEGEMAS.ICONS
	python ../tools/pack_disk.py --template $(TEMPLATE) --image $(DISK) --volume $(VOLUME) --build build --app $(APP) --cadius $(CADIUS)

build/README.TXT: ../README.TXT
	python -c "from pathlib import Path; p=Path(r'../README.TXT').read_bytes(); p=p.replace(bytes([13,10]),bytes([10])); Path(r'build/README.TXT').write_bytes(p.replace(bytes([10]),bytes([13])))"

build/Finder.Data: ../finder/Finder.Data
	python -c "import shutil; shutil.copyfile(r'../finder/Finder.Data', r'build/Finder.Data')"

build/Finder.Root: ../finder/Finder.Root
	python -c "import shutil; shutil.copyfile(r'../finder/Finder.Root', r'build/Finder.Root')"

build/FREEGEMAS.ICONS: ../tools/build_app_icon.py
	python ../tools/build_app_icon.py build/FREEGEMAS.ICONS

build/GEMS.RAW: generated/gem_rasters.bin
	python -c "import shutil; shutil.copyfile(r'generated/gem_rasters.bin', r'build/GEMS.RAW')"

build/GEMS0.RAW: generated/gem_fast0.bin
	python -c "import shutil; shutil.copyfile(r'generated/gem_fast0.bin', r'build/GEMS0.RAW')"

build/GEMS1.RAW: generated/gem_fast1.bin
	python -c "import shutil; shutil.copyfile(r'generated/gem_fast1.bin', r'build/GEMS1.RAW')"

build/GEMS2.RAW: generated/gem_fast2.bin
	python -c "import shutil; shutil.copyfile(r'generated/gem_fast2.bin', r'build/GEMS2.RAW')"

build/SCENE4.RAW: generated/scene_tt.bin
	python -c "import shutil; shutil.copyfile(r'generated/scene_tt.bin', r'build/SCENE4.RAW')"

build/SCENE4E.RAW: generated/scene_end.bin
	python -c "import shutil; shutil.copyfile(r'generated/scene_end.bin', r'build/SCENE4E.RAW')"

build/TITLE.RAW: generated/title_scene.bin
	python -c "import shutil; shutil.copyfile(r'generated/title_scene.bin', r'build/TITLE.RAW')"

build/HOWTO.RAW: generated/howto_scene.bin
	python -c "import shutil; shutil.copyfile(r'generated/howto_scene.bin', r'build/HOWTO.RAW')"

build/OPTIONS.RAW: generated/options_scene.bin
	python -c "import shutil; shutil.copyfile(r'generated/options_scene.bin', r'build/OPTIONS.RAW')"

# Five DOC waves generated from media/*.ogg plus the streamed music track (see
# tools/build_iigs_sounds.py).  SELECT / FALL are 4 KB tables, MATCH1-3 16 KB,
# MUSIC.PCM is 126 s of PCM streamed into the two 4 KB music buffers.
build/SELECT.PCM build/FALL.PCM build/MATCH1.PCM build/MATCH2.PCM build/MATCH3.PCM build/MUSIC.PCM: ../tools/build_iigs_sounds.py
	python ../tools/build_iigs_sounds.py build

# 4-byte high score file (Time Trial, Endless), shipped zeroed so the game can
# reopen it with write access instead of having to Create it on the first run.
build/HISCORE.DAT:
	python -c "open(r'build/HISCORE.DAT','wb').write(bytes(4))"

catalog: disk
	$(CADIUS) CATALOG $(DISK)

check: disk
	$(CADIUS) CHECKVOLUME $(DISK)

clean:
	python -c "import shutil, os; [os.remove(p) for p in [r'build/FREEGEM.S16', r'build/FREEGEM.S16#B30000', r'build/freegemas.2mg', r'build/_FileInformation.txt', r'build/catalog.txt', r'build/GEMS.RAW', r'build/GEMS0.RAW', r'build/GEMS1.RAW', r'build/GEMS2.RAW', r'build/SCENE4.RAW', r'build/SCENE4E.RAW', r'build/TITLE.RAW', r'build/HOWTO.RAW', r'build/OPTIONS.RAW', r'build/HISCORE.DAT', r'build/README.TXT', r'build/Finder.Data', r'build/Finder.Root', r'build/FREEGEMAS.ICONS', r'build/SELECT.PCM', r'build/FALL.PCM', r'build/MATCH1.PCM', r'build/MATCH2.PCM', r'build/MATCH3.PCM', r'build/MUSIC.PCM'] if os.path.exists(p)]; shutil.rmtree(r'build/SYSTEM', ignore_errors=True)"
