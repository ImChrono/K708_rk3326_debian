#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
	echo "usage: $0 KERNEL_SRC KERNEL_OUT RTW88_SOURCE" >&2
	exit 2
fi

kernel_src=$(CDPATH='' cd -- "$1" && pwd)
kernel_out=$(CDPATH='' cd -- "$2" && pwd)
rtw88_src=$(CDPATH='' cd -- "$3" && pwd)
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
expected_commit=$(sed -n '1p' "$kit_dir/configs/rtw88-oot.commit")
actual_commit=$(git -C "$rtw88_src" rev-parse HEAD)

if [ "$actual_commit" != "$expected_commit" ]; then
	echo "error: RTW88 source revision mismatch" >&2
	echo "expected: $expected_commit" >&2
	echo "actual:   $actual_commit" >&2
	exit 1
fi

test -f "$rtw88_src/rtw8723cs.c"
test -f "$kernel_out/include/generated/autoconf.h"

jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
cross_compile=${CROSS_COMPILE:-aarch64-linux-gnu-}
kernel_release=$(
	make -s -C "$kernel_src" \
		O="$kernel_out" \
		ARCH=arm64 \
		CROSS_COMPILE="$cross_compile" \
		kernelrelease
)

make -C "$rtw88_src" \
	KSRC="$kernel_out" \
	KVER="$kernel_release" \
	ARCH=arm64 \
	CROSS_COMPILE="$cross_compile" \
	JOBS="$jobs"

for module in \
	rtw_core rtw_sdio rtw_8723x rtw_8703b rtw_8723cs
do
	test -f "$rtw88_src/$module.ko"
done

echo "RTW88 RTL8723CS modules built for $kernel_release."
