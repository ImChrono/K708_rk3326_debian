#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
destination=${1:-"$kit_dir/third_party/rtw88"}
expected_commit=$(sed -n '1p' "$kit_dir/configs/rtw88-oot.commit")
repository=https://github.com/lwfinger/rtw88.git

if [ -d "$destination/.git" ]; then
	actual_commit=$(git -C "$destination" rev-parse HEAD)
	if [ "$actual_commit" = "$expected_commit" ]; then
		echo "Pinned RTW88 source already present."
		exit 0
	fi

	echo "error: existing RTW88 checkout has the wrong revision" >&2
	echo "expected: $expected_commit" >&2
	echo "actual:   $actual_commit" >&2
	exit 1
fi

if [ -e "$destination" ]; then
	echo "error: destination exists but is not a Git checkout" >&2
	echo "$destination" >&2
	exit 1
fi

mkdir -p "$(dirname "$destination")"
git init "$destination"
git -C "$destination" remote add origin "$repository"
git -C "$destination" fetch --depth 1 origin "$expected_commit"
git -C "$destination" checkout --detach FETCH_HEAD

actual_commit=$(git -C "$destination" rev-parse HEAD)
test "$actual_commit" = "$expected_commit"
test -f "$destination/rtw8723cs.c"

echo "Fetched pinned RTW88 source: $actual_commit"
