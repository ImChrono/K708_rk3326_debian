#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: $0 /path/to/ums-autoboot-source" >&2
	exit 2
fi

source_dir=$(CDPATH='' cd -- "$1" && pwd)
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
private_dir="$kit_dir/blobs/private"

# Accept both the original flat extraction and the later archival layout
# where the verified files live below an explicit private/ directory.
if [ ! -f "$source_dir/idb-area-lba64-8191.img" ] &&
	[ -d "$source_dir/private" ]
then
	source_dir=$(CDPATH='' cd -- "$source_dir/private" && pwd)
fi

mkdir -p "$private_dir"

missing=0
for name in \
	idb-area-lba64-8191.img \
	security.img \
	uboot_a.img \
	uboot_b.img \
	trust_a.img \
	trust_b.img \
	misc.img
do
	if [ ! -f "$source_dir/$name" ]; then
		echo "error: missing source blob: $source_dir/$name" >&2
		missing=1
	fi
done

if [ "$missing" -ne 0 ]; then
	echo "error: source directory is incomplete: $source_dir" >&2
	exit 1
fi

for name in \
	idb-area-lba64-8191.img \
	security.img \
	uboot_a.img \
	uboot_b.img \
	trust_a.img \
	trust_b.img \
	misc.img
do
	install -m 0600 "$source_dir/$name" "$private_dir/$name"
done

"$kit_dir/scripts/verify-blobs.sh"
