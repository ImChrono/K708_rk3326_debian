#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: $0 /path/to/rk3326-tablet-debian-bsp.zip" >&2
	exit 2
fi

command -v zip >/dev/null 2>&1 || {
	echo "error: missing command: zip" >&2
	exit 1
}

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

(
	cd "$kit_parent"
	zip -q -r "$output" "$kit_name" \
		-x "$kit_name/.git/*" \
		-x "$kit_name/blobs/private/*" \
		-x "$kit_name/build/*" \
		-x "$kit_name/dist/*" \
		-x "$kit_name/reports/*" \
		-x "$kit_name/third_party/*" \
		-x '*/__pycache__/*' \
		-x '*.pyc' \
		-x '*.img' \
		-x '*.img.xz' \
		-x '*.tar' \
		-x '*.tar.xz' \
		-x '*.zip'
)

sha256sum "$output"
