#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: sudo $0 /path/to/rk3326-tablet.img" >&2
	exit 2
fi

if [ "$(id -u)" -ne 0 ]; then
	echo "error: validate-image.sh must run as root" >&2
	exit 1
fi

image=$1
test -f "$image"
image=$(CDPATH= cd -- "$(dirname -- "$image")" && pwd)/$(basename "$image")

for command in \
	dd e2fsck fdtget fsck.vfat losetup mount mountpoint \
	sgdisk sha256sum udevadm umount
do
	command -v "$command" >/dev/null 2>&1 || {
		echo "error: missing command: $command" >&2
		exit 1
	}
done

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")

# shellcheck disable=SC1091
. "$kit_dir/configs/image-layout.conf"

check_partition()
{
	number=$1
	expected_start=$2
	expected_name=$3
	info=$(sgdisk -i "$number" "$image")
	actual_start=$(printf '%s\n' "$info" | awk '/First sector:/ {print $3}')
	actual_name=$(
		printf '%s\n' "$info" |
		sed -n "s/^Partition name: '\\(.*\\)'$/\\1/p"
	)

	[ "$actual_start" = "$expected_start" ] || {
		echo "error: partition $number starts at $actual_start, expected $expected_start" >&2
		exit 1
	}
	[ "$actual_name" = "$expected_name" ] || {
		echo "error: partition $number is '$actual_name', expected '$expected_name'" >&2
		exit 1
	}
}

check_raw_hash()
{
	start=$1
	count=$2
	expected=$3
	name=$4
	actual=$(
		dd if="$image" bs=512 skip="$start" count="$count" status=none |
		sha256sum |
		awk '{print $1}'
	)
	[ "$actual" = "$expected" ] || {
		echo "error: raw hash mismatch for $name" >&2
		exit 1
	}
}

sgdisk -v "$image"
check_partition 1 "$SECURITY_START" security
check_partition 2 "$UBOOT_A_START" uboot_a
check_partition 3 "$UBOOT_B_START" uboot_b
check_partition 4 "$TRUST_A_START" trust_a
check_partition 5 "$TRUST_B_START" trust_b
check_partition 6 "$MISC_START" misc
check_partition 7 "$BOOT_START" BOOT
check_partition 8 "$ROOT_START" ROOTFS

boot_attributes=$(
	sgdisk -i 7 "$image" |
	awk '/Attribute flags:/ {print $3}'
)
[ "$boot_attributes" = 0000000000000004 ] || {
	echo "error: BOOT GPT attribute is $boot_attributes, expected 0000000000000004" >&2
	exit 1
}

check_raw_hash "$IDB_START" "$IDB_SECTORS" \
	2255239c737c9af3b821f6da519cc05b1c1404f489a760349e3e246889f73465 \
	idb-area
check_raw_hash "$SECURITY_START" 8192 \
	5659f7d7199bdd08348e1b48d24c892e21c8e0f563ae770657790a38094c772f \
	security
check_raw_hash "$UBOOT_A_START" 8192 \
	05187842f92f905da371f69724bade6dd0368f7769312d0307115fac472d8aa5 \
	uboot_a
check_raw_hash "$UBOOT_B_START" 8192 \
	05187842f92f905da371f69724bade6dd0368f7769312d0307115fac472d8aa5 \
	uboot_b
check_raw_hash "$TRUST_A_START" 8192 \
	cec60518762918ccc150f814cfa03256b6dadc436b70474102bddf17ff48b71b \
	trust_a
check_raw_hash "$TRUST_B_START" 8192 \
	cec60518762918ccc150f814cfa03256b6dadc436b70474102bddf17ff48b71b \
	trust_b
check_raw_hash "$MISC_START" 8192 \
	7b6176a7bddec59387258c58b7ea6ea216e7f17acd906bd4363b7a87f8b32889 \
	misc

mount_tmp=$(mktemp -d /tmp/rk3326-image-check.XXXXXX)
boot_mnt="$mount_tmp/boot"
root_mnt="$mount_tmp/root"
loop_dev=
mkdir -p "$boot_mnt" "$root_mnt"

cleanup()
{
	set +e
	mountpoint -q "$boot_mnt" && umount "$boot_mnt"
	mountpoint -q "$root_mnt" && umount "$root_mnt"
	[ -n "$loop_dev" ] && losetup -d "$loop_dev"
	case "$mount_tmp" in
		/tmp/rk3326-image-check.*) rm -rf -- "$mount_tmp" ;;
	esac
}
trap cleanup EXIT INT TERM HUP

loop_dev=$(losetup --find --show --partscan --read-only "$image")
udevadm settle
boot_part="${loop_dev}p7"
root_part="${loop_dev}p8"

fsck.vfat -n "$boot_part"
e2fsck -fn "$root_part"

mount -o ro "$boot_part" "$boot_mnt"
mount -o ro,noload "$root_part" "$root_mnt"

for path in \
	Image-6.1-rockchip \
	rk3326-863-tablet-uart.dtb \
	rk3326-863-tablet-display.dtb \
	rk3326-863-tablet-charge-test.dtb \
	extlinux/extlinux.conf
do
	test -f "$boot_mnt/$path"
done

if grep -q '@ROOT_PARTUUID@\\|root=LABEL=' \
	"$boot_mnt/extlinux/extlinux.conf"
then
	echo "error: unresolved or unsafe root selector in extlinux.conf" >&2
	exit 1
fi

grep -qi "root=PARTUUID=$ROOT_PARTUUID" \
	"$boot_mnt/extlinux/extlinux.conf"
grep -qi "PARTUUID=$ROOT_PARTUUID[[:space:]]*/" \
	"$root_mnt/etc/fstab"
grep -qi "PARTUUID=$BOOT_PARTUUID[[:space:]]*/boot" \
	"$root_mnt/etc/fstab"

for profile in uart display charge-test; do
	dtb="$boot_mnt/rk3326-863-tablet-$profile.dtb"
	[ "$(fdtget -t s "$dtb" /dmc status)" = disabled ]
	[ "$(fdtget -t s "$dtb" /dfi@ff610000 status)" = disabled ]
	[ "$(fdtget -t s "$dtb" /i2c@ff190000/ts@40 status)" = okay ]
	[ "$(fdtget -t s "$dtb" /wireless-wlan status)" = okay ]
	[ "$(fdtget -t s "$dtb" /gpu@ff400000 status)" = okay ]
	[ "$(
		fdtget -t s "$dtb" /gpu@ff400000 interrupt-names
	)" = "gpu mmu job" ]
	[ "$(
		fdtget -t s "$dtb" /i2c@ff180000/pmic@20/battery status
	)" = okay ]
	set -- $(
		fdtget -t u "$dtb" \
			/i2c@ff190000/ts@40 irq_gpio_number
	)
	[ "$2" = 17 ]
	[ "$3" = 8 ]
	set -- $(
		fdtget -t u "$dtb" \
			/i2c@ff190000/ts@40 rst_gpio_number
	)
	[ "$2" = 12 ]
	[ "$3" = 0 ]

	if fdtget -l "$dtb" /reserved-memory |
		grep -Eq '^drm-logo@|^vendor-storage-rm@'
	then
		echo "error: Android zero-sized reserved-memory node in $profile DTB" >&2
		exit 1
	fi
done

[ "$(
	fdtget -t u \
		"$boot_mnt/rk3326-863-tablet-display.dtb" \
		/dsi@ff450000/panel@0 bpc
)" = 8 ]

for profile in uart display; do
	dtb="$boot_mnt/rk3326-863-tablet-$profile.dtb"
	[ "$(
		fdtget -t s "$dtb" \
			/i2c@ff180000/pmic@20/charger status
	)" = disabled ]
done

charge_dtb="$boot_mnt/rk3326-863-tablet-charge-test.dtb"
charge_node=/i2c@ff180000/pmic@20/charger
[ "$(fdtget -t s "$charge_dtb" "$charge_node" status)" = okay ]
[ "$(fdtget -t u "$charge_dtb" "$charge_node" min_input_voltage)" = 4500 ]
[ "$(fdtget -t u "$charge_dtb" "$charge_node" max_input_current)" = 1500 ]
[ "$(fdtget -t u "$charge_dtb" "$charge_node" max_chrg_current)" = 2000 ]
[ "$(fdtget -t u "$charge_dtb" "$charge_node" max_chrg_voltage)" = 4400 ]
[ "$(fdtget -t u "$charge_dtb" "$charge_node" chrg_term_mode)" = 1 ]
[ "$(fdtget -t u "$charge_dtb" "$charge_node" chrg_finish_cur)" = 120 ]
if fdtget "$charge_dtb" \
	/i2c@ff180000/pmic@20/battery ntc_table >/dev/null 2>&1
then
	echo "error: charge-test DTB unexpectedly declares an unverified NTC table" >&2
	exit 1
fi

for firmware in \
	lib/firmware/rtw88/rtw8703b_fw.bin \
	lib/firmware/rtw88/rtw8703b_wow_fw.bin
do
	test -s "$root_mnt/$firmware"
done

for module in \
	rtw_core rtw_sdio rtw_8723x rtw_8703b rtw_8723cs
do
	find "$root_mnt/lib/modules" -type f -name "$module.ko" |
		grep -q .
done

for path in \
	usr/local/sbin/rk3326-hwprobe \
	usr/local/sbin/rk3326-hwtest \
	usr/local/sbin/rk3326-charge-watch \
	usr/share/rk3326-hwtest/expected-hardware.json \
	etc/systemd/system/rk3326-hwprobe.service \
	etc/systemd/system/rk3326-hwtest.service
do
	test -e "$root_mnt/$path"
done

for unit in rk3326-hwprobe.service rk3326-hwtest.service; do
	link="$root_mnt/etc/systemd/system/multi-user.target.wants/$unit"
	test -L "$link" || {
		echo "error: $unit is not enabled in the image" >&2
		exit 1
	}

	target=$(readlink "$link")
	case "$target" in
		"/etc/systemd/system/$unit"|"../$unit") ;;
		*)
			echo "error: unexpected enablement target for $unit: $target" >&2
			exit 1
			;;
	esac
done

find "$root_mnt/lib/modules" -mindepth 1 -maxdepth 1 -type d |
	grep -q .

echo "Image validation passed."
sha256sum "$image"
