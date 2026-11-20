#!/usr/bin/env python3
"""Writes the GS/OS /SYSTEM/SetStart.data config that selects the startup app.

Layout taken byte-for-byte from the GS/OS 6.0.1 template's own file
(`TIMEPILOT`'s original entry was 23 bytes for ":TIMEPILOT:TIME.PILOT"):

  word 0   : length of the colon path in characters, NOT counting a NUL
  bytes 2..: ':VOLUME:APP' (no trailing NUL)

The earlier version wrote len+1 plus a trailing NUL (25 bytes). Start counts
the word as a character count, so the extra byte made the path one char too
long and the trailing NUL was copied into the name; the launch then failed
and Start fell back to the Finder.

Usage: python make_startup.py VOLUME APP OUTPUT
"""
import os
import struct
import sys

volume, app, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
path = f":{volume}:{app}".encode("ascii")
data = struct.pack("<H", len(path)) + path
os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
with open(out_path, "wb") as handle:
    handle.write(data)
print(f"wrote {out_path} ({len(data)} bytes, startup {path.decode()})")
