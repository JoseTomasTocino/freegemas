#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
	printf 'Usage: %s <source.png> <output.icns>\n' "$0" >&2
	exit 1
fi

source_image=$1
output_icns=$2
iconset_dir=${output_icns%.icns}.iconset

mkdir -p "$iconset_dir"

make_icon() {
	size=$1
	filename=$2
	sips -z "$size" "$size" "$source_image" --out "$iconset_dir/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
make_icon 1024 icon_512x512@2x.png

# iconutil refuses to build an iconset in some restricted environments. Fall
# back to packing the rendered PNGs into an ICNS container directly, so the app
# bundle still gets a usable icon instead of failing the whole build.
if ! iconutil -c icns "$iconset_dir" -o "$output_icns" 2>/dev/null; then
	printf 'iconutil failed; packing ICNS manually\n' >&2
	python3 - "$iconset_dir" "$output_icns" <<'PY'
import struct, sys

iconset_dir, output_icns = sys.argv[1], sys.argv[2]

# (ICNS type, file in the .iconset)
members = [
    (b'icp4', 'icon_16x16.png'),
    (b'icp5', 'icon_32x32.png'),
    (b'icp6', 'icon_32x32@2x.png'),
    (b'ic07', 'icon_128x128.png'),
    (b'ic08', 'icon_256x256.png'),
    (b'ic09', 'icon_512x512.png'),
    (b'ic10', 'icon_512x512@2x.png'),
]

chunks = []
for icns_type, name in members:
    with open('%s/%s' % (iconset_dir, name), 'rb') as handle:
        data = handle.read()
    chunks.append(icns_type + struct.pack('>I', len(data) + 8) + data)

body = b''.join(chunks)
with open(output_icns, 'wb') as handle:
    handle.write(b'icns' + struct.pack('>I', len(body) + 8) + body)
PY
fi