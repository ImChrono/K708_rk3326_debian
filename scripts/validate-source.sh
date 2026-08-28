#!/bin/sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")

required_files="
VERSION
README.md
HARDWARE-NOTES.md
LICENSES.md
.github/dependabot.yml
.github/workflows/build.yml
.github/workflows/build-private-image.yml
.github/workflows/release.yml
.github/workflows/validate.yml
configs/image-layout.conf
configs/kernel-source.commit
configs/kernel-source.url
configs/kernel-working.config
configs/rtw88-oot.commit
configs/tablet-console.config
dts/rk3326-863-tablet-common.dtsi
dts/rk3326-863-tablet-uart.dts
dts/rk3326-863-tablet-display.dts
dts/rk3326-863-tablet-charge-test.dts
extlinux/extlinux-uart.conf
extlinux/extlinux-display.conf
extlinux/extlinux-charge-test.conf
hwtest/expected-hardware.json
hwtest/rk3326-hwprobe.py
hwtest/rk3326-hwtest.py
hwtest/rk3326-charge-watch.py
tests/test_charge_watch.py
tests/test_install_kernel_overrides.py
kernel-overrides/README.md
kernel-overrides/gsl3673_800x1280_oem.h
rootfs/fstab.in
rootfs/packages.list
rootfs/overlay/etc/systemd/system/rk3326-hwprobe.service
rootfs/overlay/etc/systemd/system/rk3326-hwtest.service
"

for path in $required_files; do
	test -f "$kit_dir/$path" || {
		echo "error: missing $path" >&2
		exit 1
	}
done

for script in "$kit_dir"/scripts/*.sh; do
	sh -n "$script"
	test -x "$script" || {
		echo "error: script is not executable: $script" >&2
		exit 1
	}
done

grep -Eq '^[0-9a-f]{40}$' "$kit_dir/configs/kernel-source.commit"
grep -Eq '^[0-9a-f]{40}$' "$kit_dir/configs/rtw88-oot.commit"
printf '%s  %s\n' \
	63d9fd1141d4072201943283e30c01e39763d33b77e8152b339b80ed2036dcf8 \
	"$kit_dir/kernel-overrides/gsl3673_800x1280_oem.h" |
	sha256sum -c -
grep -q 'root=PARTUUID=@ROOT_PARTUUID@' \
	"$kit_dir/extlinux/extlinux-uart.conf"
grep -q 'root=PARTUUID=@ROOT_PARTUUID@' \
	"$kit_dir/extlinux/extlinux-display.conf"
grep -q 'root=PARTUUID=@ROOT_PARTUUID@' \
	"$kit_dir/extlinux/extlinux-charge-test.conf"
grep -q '^CONFIG_LOCALVERSION="-rk3326-tablet"$' \
	"$kit_dir/configs/tablet-console.config"
grep -q '^CONFIG_AUTOFS_FS=m$' \
	"$kit_dir/configs/tablet-console.config"
grep -q '^CONFIG_TOUCHSCREEN_GSL3673=y$' \
	"$kit_dir/configs/tablet-console.config"
grep -q '^CONFIG_TOUCHSCREEN_GSL3673_800X1280=y$' \
	"$kit_dir/configs/tablet-console.config"
grep -q '^CONFIG_BATTERY_RK817=y$' \
	"$kit_dir/configs/tablet-console.config"
grep -q '^CONFIG_CHARGER_RK817=y$' \
	"$kit_dir/configs/tablet-console.config"
grep -Eq 'irq_gpio_number[[:space:]]*=[[:space:]]*<&gpio0[[:space:]]+RK_PC1[[:space:]]+IRQ_TYPE_LEVEL_LOW>;' \
	"$kit_dir/dts/rk3326-863-tablet-common.dtsi"
grep -Eq 'rst_gpio_number[[:space:]]*=[[:space:]]*<&gpio0[[:space:]]+RK_PB4[[:space:]]+GPIO_ACTIVE_HIGH>;' \
	"$kit_dir/dts/rk3326-863-tablet-common.dtsi"
grep -Eq 'interrupt-names[[:space:]]*=[[:space:]]*"gpu",[[:space:]]*"mmu",[[:space:]]*"job";' \
	"$kit_dir/dts/rk3326-863-tablet-common.dtsi"
grep -q 'wifi_chip_type = "rtl8723cs";' \
	"$kit_dir/dts/rk3326-863-tablet-common.dtsi"
grep -q 'design_capacity = <2543>;' \
	"$kit_dir/dts/rk3326-863-tablet-common.dtsi"
grep -q 'max_chrg_voltage = <4400>;' \
	"$kit_dir/dts/rk3326-863-tablet-charge-test.dts"
grep -q 'max_chrg_current = <2000>;' \
	"$kit_dir/dts/rk3326-863-tablet-charge-test.dts"
grep -q 'max_input_current = <1500>;' \
	"$kit_dir/dts/rk3326-863-tablet-charge-test.dts"
grep -q 'chrg_finish_cur = <120>;' \
	"$kit_dir/dts/rk3326-863-tablet-charge-test.dts"
grep -A8 'charger {' "$kit_dir/dts/rk3326-863-tablet-common.dtsi" |
	grep -q 'status = "disabled";'
grep -q 'VIRTUAL_TEMPERATURE = 188' \
	"$kit_dir/hwtest/rk3326-charge-watch.py"
grep -q './scripts/fetch-rtw88.sh' \
	"$kit_dir/.github/workflows/build.yml"
grep -q './scripts/fetch-rtw88.sh' \
	"$kit_dir/.github/workflows/build-private-image.yml"
grep -q '^  workflow_call:$' \
	"$kit_dir/.github/workflows/build.yml"
grep -q 'uses: actions/upload-artifact@v7' \
	"$kit_dir/.github/workflows/build.yml"
grep -q 'package-ecosystem: github-actions' \
	"$kit_dir/.github/dependabot.yml"
grep -q 'tags:' \
	"$kit_dir/.github/workflows/release.yml"
grep -q 'gh release create' \
	"$kit_dir/.github/workflows/release.yml"
grep -q 'sha256sum -c SHA256SUMS' \
	"$kit_dir/.github/workflows/release.yml"

python3 -m json.tool \
	"$kit_dir/hwtest/expected-hardware.json" >/dev/null
python3 - \
	"$kit_dir/hwtest/rk3326-hwprobe.py" \
	"$kit_dir/hwtest/rk3326-hwtest.py" \
	"$kit_dir/hwtest/rk3326-charge-watch.py" \
	"$kit_dir/scripts/install-kernel-overrides.py" <<'PY'
import pathlib
import sys

for name in sys.argv[1:]:
	path = pathlib.Path(name)
	compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

python3 -m unittest discover \
	-s "$kit_dir/tests" \
	-p 'test_*.py'

echo "Source validation passed."
