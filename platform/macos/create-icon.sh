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

iconutil -c icns "$iconset_dir" -o "$output_icns"