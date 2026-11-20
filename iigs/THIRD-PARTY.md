# Third-party components

The Freegemas code and original media are distributed under the repository's
GPLv2 license.

## Build tools

- **Merlin32** assembles the 65816 source.
- **Cadius** creates and inspects the GS/OS 2MG image.
- **Python/Pillow** and **ffmpeg** convert the original media into SHR graphics
  and Ensoniq DOC PCM.

## GS/OS template

The bootable image is based on a GS/OS template disk. That template is not
included in this repository because it contains Apple system files; use a
copy you are licensed to use and pass it through `TEMPLATE`.

## Graphics and audio

`iigs/merlin32/generated/` contains build inputs derived from the original
Freegemas `media/` assets. `iigs/tools/build_iigs_assets.py` and
`build_iigs_sounds.py` regenerate them from those sources.
