#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: $0 /path/to/rockchip-kernel /path/to/output"
	exit 2
fi

kernel_src=$(CDPATH= cd -- "$1" && pwd)
mkdir -p "$2"
output_dir=$(CDPATH= cd -- "$2" && pwd)
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN)}
cross_compile=${CROSS_COMPILE:-aarch64-linux-gnu-}

test -x "$kernel_src/scripts/kconfig/merge_config.sh"
test -f "$kit_dir/configs/tablet-console.config"
test -f "$kit_dir/configs/kernel-working.config"
test -f "$kit_dir/configs/kernel-source.commit"
test -x "$kit_dir/scripts/install-kernel-overrides.py"
rtw88_src="$kit_dir/third_party/rtw88"

if [ ! -f "$rtw88_src/rtw8723cs.c" ]; then
	echo "error: the pinned out-of-tree RTW88 source is not present" >&2
	echo "run scripts/fetch-rtw88.sh first" >&2
	exit 1
fi

expected_commit=$(sed -n '1p' "$kit_dir/configs/kernel-source.commit")
actual_commit=$(git -C "$kernel_src" rev-parse HEAD)

if [ "$actual_commit" != "$expected_commit" ]; then
	echo "error: kernel commit mismatch" >&2
	echo "expected: $expected_commit" >&2
	echo "actual:   $actual_commit" >&2
	exit 1
fi

"$kit_dir/scripts/install-kernel-overrides.py" "$kernel_src"
"$kit_dir/scripts/install-dts.sh" "$kernel_src"

# Start from the exact configuration that produced the first successful
# Debian boot, then merge the small, reviewable project fragment.
install -m 0644 "$kit_dir/configs/kernel-working.config" \
	"$output_dir/.config"

(
	cd "$kernel_src"
	scripts/kconfig/merge_config.sh \
		-m \
		-O "$output_dir" \
		"$output_dir/.config" \
		"$kit_dir/configs/tablet-console.config"
)

make -C "$kernel_src" \
	O="$output_dir" \
	ARCH=arm64 \
	CROSS_COMPILE="$cross_compile" \
	olddefconfig

make -C "$kernel_src" \
	O="$output_dir" \
	ARCH=arm64 \
	CROSS_COMPILE="$cross_compile" \
	-j"$jobs" \
	Image modules dtbs

"$kit_dir/scripts/build-rtw88.sh" \
	"$kernel_src" \
	"$output_dir" \
	"$rtw88_src"

echo
echo "Kernel: $output_dir/arch/arm64/boot/Image"
echo "UART DTB: $output_dir/arch/arm64/boot/dts/rockchip/rk3326-863-tablet-uart.dtb"
echo "Display DTB: $output_dir/arch/arm64/boot/dts/rockchip/rk3326-863-tablet-display.dtb"
echo "OEM charge-test DTB: $output_dir/arch/arm64/boot/dts/rockchip/rk3326-863-tablet-charge-test.dtb"
