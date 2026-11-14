# Third-party components

## Audio assets

`assets/music.zcm` is derived from the original `media/music.ogg` soundtrack
that ships with Freegemas. It is converted locally by
`tools/build_music_zcm.py` (NumPy, `soundfile` and `soxr`) and is covered by
the project's own licensing. `hostfs/*.pcm` contains the five original sound
effects.

The X16 port does not embed a PSG/ZSM music engine or any ZSMKit binary.
