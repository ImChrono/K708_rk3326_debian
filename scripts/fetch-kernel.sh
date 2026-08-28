#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: $0 /new/kernel/source/directory" >&2
	exit 2
fi

destination=$1
if [ -e "$destination" ]; then
	echo "error: destination already exists: $destination" >&2
	exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
repository=$(sed -n '1p' "$kit_dir/configs/kernel-source.url")
commit=$(sed -n '1p' "$kit_dir/configs/kernel-source.commit")

mkdir -p "$destination"
git -C "$destination" init
git -C "$destination" remote add origin "$repository"
git -C "$destination" fetch --depth=1 origin "$commit"
git -C "$destination" checkout --detach FETCH_HEAD

actual=$(git -C "$destination" rev-parse HEAD)
if [ "$actual" != "$commit" ]; then
	echo "error: fetched unexpected kernel commit: $actual" >&2
	exit 1
fi

echo "Kernel source ready: $destination"
echo "Commit: $actual"
