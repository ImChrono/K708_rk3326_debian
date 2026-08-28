#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")

(
	cd "$kit_dir/blobs"
	sha256sum -c manifest.sha256
)

while read -r expected path; do
	actual=$(stat -c %s "$kit_dir/blobs/$path")
	if [ "$actual" -ne "$expected" ]; then
		echo "error: wrong size for blobs/$path" >&2
		echo "expected: $expected bytes" >&2
		echo "actual:   $actual bytes" >&2
		exit 1
	fi
done < "$kit_dir/blobs/manifest.sizes"

echo "Boot-chain blobs verified."
