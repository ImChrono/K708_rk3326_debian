#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: $0 /path/to/rockchip-kernel"
	exit 2
fi

kernel_src=$1
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
dts_dir="$kernel_src/arch/arm64/boot/dts/rockchip"
makefile="$dts_dir/Makefile"

test -f "$dts_dir/rk3326-863-lp3-v10.dtsi"
test -f "$makefile"

install -m 0644 "$kit_dir/dts/rk3326-863-tablet-common.dtsi" "$dts_dir/"
install -m 0644 "$kit_dir/dts/rk3326-863-tablet-uart.dts" "$dts_dir/"
install -m 0644 "$kit_dir/dts/rk3326-863-tablet-display.dts" "$dts_dir/"
install -m 0644 "$kit_dir/dts/rk3326-863-tablet-charge-test.dts" "$dts_dir/"

for profile in uart display charge-test; do
	entry="dtb-\$(CONFIG_ARCH_ROCKCHIP) += rk3326-863-tablet-$profile.dtb"
	if ! grep -Fqx "$entry" "$makefile"; then
		printf '%s\n' "$entry" >> "$makefile"
	fi
done

echo "Installed custom RK3326 tablet DTS files in $dts_dir"
