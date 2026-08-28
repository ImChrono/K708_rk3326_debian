#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: $0 /path/to/rk3326-tablet-bsp-source.tar.xz" >&2
	exit 2
fi

output=$1
if [ -e "$output" ]; then
	echo "error: output already exists: $output" >&2
	exit 1
fi

output_dir=$(CDPATH= cd -- "$(dirname -- "$output")" && pwd)
output="$output_dir/$(basename "$output")"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
kit_parent=$(dirname "$kit_dir")
kit_name=$(basename "$kit_dir")

"$kit_dir/scripts/validate-source.sh"

tar \
	--sort=name \
	--mtime="@${SOURCE_DATE_EPOCH:-0}" \
	--clamp-mtime \
	--numeric-owner \
	--owner=0 \
	--group=0 \
	--exclude="$kit_name/.git" \
	--exclude="$kit_name/blobs/private" \
	--exclude="$kit_name/build" \
	--exclude="$kit_name/dist" \
	--exclude="$kit_name/reports" \
	--exclude="$kit_name/third_party" \
	--exclude='__pycache__' \
	--exclude='*.pyc' \
	--exclude='*.img' \
	--exclude='*.img.xz' \
	--exclude='*.tar' \
	--exclude='*.tar.xz' \
	--exclude='*.zip' \
	-cJf "$output" \
	-C "$kit_parent" "$kit_name"

sha256sum "$output"
