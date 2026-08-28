#!/bin/sh
set -eu

usage()
{
	echo "usage: sudo -E $0 KERNEL_SRC KERNEL_OUT ROOTFS.tar.xz OUTPUT.img" >&2
	exit 2
}

[ "$#" -eq 4 ] || usage

if [ "$(id -u)" -ne 0 ]; then
	echo "error: build-image.sh must run as root" >&2
	exit 1
fi

kernel_src=$(CDPATH='' cd -- "$1" && pwd)
kernel_out=$(CDPATH='' cd -- "$2" && pwd)
rootfs_tar=$3
output=$4

test -f "$rootfs_tar"
rootfs_tar=$(CDPATH='' cd -- "$(dirname -- "$rootfs_tar")" && pwd)/$(basename "$rootfs_tar")

if [ -e "$output" ]; then
	echo "error: output already exists: $output" >&2
	exit 1
fi

output_dir=$(CDPATH='' cd -- "$(dirname -- "$output")" && pwd)
output="$output_dir/$(basename "$output")"

for command in \
	dd depmod fdtget losetup mkfs.ext4 mkfs.vfat mount mountpoint \
	partprobe sgdisk sha256sum tar udevadm umount
do
	command -v "$command" >/dev/null 2>&1 || {
		echo "error: missing command: $command" >&2
		exit 1
	}
done

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")

# shellcheck disable=SC1091
. "$kit_dir/configs/image-layout.conf"

"$kit_dir/scripts/verify-blobs.sh"

image_size_mib=${IMAGE_SIZE_MIB:-4096}
case "$image_size_mib" in
	*[!0-9]*|'')
		echo "error: IMAGE_SIZE_MIB must be an integer" >&2
		exit 1
		;;
esac

if [ "$image_size_mib" -lt 1024 ]; then
	echo "error: IMAGE_SIZE_MIB must be at least 1024" >&2
	exit 1
fi

boot_profile=${BOOT_PROFILE:-uart}
case "$boot_profile" in
	uart|display|charge-test) ;;
	*)
		echo "error: BOOT_PROFILE must be uart, display or charge-test" >&2
		exit 1
		;;
esac

image_tmp=$(mktemp "$output_dir/.rk3326-image.XXXXXX")
mount_tmp=$(mktemp -d /tmp/rk3326-image-mount.XXXXXX)
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
		/tmp/rk3326-image-mount.*) rm -rf -- "$mount_tmp" ;;
	esac
	case "$image_tmp" in
		"$output_dir"/.rk3326-image.*) rm -f -- "$image_tmp" ;;
	esac
}
trap cleanup EXIT INT TERM HUP

truncate -s "${image_size_mib}M" "$image_tmp"

sgdisk --zap-all "$image_tmp"
sgdisk \
	--disk-guid="$DISK_GUID" \
	--new=1:8192:16383 --typecode=1:FFFF --change-name=1:security \
	--new=2:16384:24575 --typecode=2:FFFF --change-name=2:uboot_a \
	--new=3:24576:32767 --typecode=3:FFFF --change-name=3:uboot_b \
	--new=4:32768:40959 --typecode=4:FFFF --change-name=4:trust_a \
	--new=5:40960:49151 --typecode=5:FFFF --change-name=5:trust_b \
	--new=6:49152:57343 --typecode=6:FFFF --change-name=6:misc \
	--new=7:"$BOOT_START":"$BOOT_END" --typecode=7:EF00 --change-name=7:BOOT \
	--new=8:"$ROOT_START":0 --typecode=8:8300 --change-name=8:ROOTFS \
	--partition-guid=1:"$SECURITY_PARTUUID" \
	--partition-guid=2:"$UBOOT_A_PARTUUID" \
	--partition-guid=3:"$UBOOT_B_PARTUUID" \
	--partition-guid=4:"$TRUST_A_PARTUUID" \
	--partition-guid=5:"$TRUST_B_PARTUUID" \
	--partition-guid=6:"$MISC_PARTUUID" \
	--partition-guid=7:"$BOOT_PARTUUID" \
	--partition-guid=8:"$ROOT_PARTUUID" \
	"$image_tmp"

# Rockchip's distro-boot scan uses the legacy-BIOS bootable GPT attribute.
sgdisk --attributes=7:set:2 "$image_tmp"

write_blob()
{
	name=$1
	start=$2
	dd \
		if="$kit_dir/blobs/private/$name" \
		of="$image_tmp" \
		bs=512 \
		seek="$start" \
		conv=notrunc,fsync \
		status=none
}

write_blob idb-area-lba64-8191.img "$IDB_START"
write_blob security.img "$SECURITY_START"
write_blob uboot_a.img "$UBOOT_A_START"
write_blob uboot_b.img "$UBOOT_B_START"
write_blob trust_a.img "$TRUST_A_START"
write_blob trust_b.img "$TRUST_B_START"
write_blob misc.img "$MISC_START"

loop_dev=$(losetup --find --show --partscan "$image_tmp")
partprobe "$loop_dev"
udevadm settle

boot_part="${loop_dev}p7"
root_part="${loop_dev}p8"
test -b "$boot_part"
test -b "$root_part"

mkfs.vfat -F 32 -n BOOT -i "$BOOT_FAT_ID" "$boot_part"
mkfs.ext4 -F -L ROOTFS -U "$ROOT_FS_UUID" "$root_part"

mount "$root_part" "$root_mnt"
mount "$boot_part" "$boot_mnt"

tar --numeric-owner --acls --xattrs -xpf "$rootfs_tar" -C "$root_mnt"

make -C "$kernel_src" \
	O="$kernel_out" \
	ARCH=arm64 \
	CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}" \
	INSTALL_MOD_PATH="$root_mnt" \
	INSTALL_MOD_STRIP=1 \
	modules_install

kernel_release=$(
	make -s -C "$kernel_src" \
		O="$kernel_out" \
		ARCH=arm64 \
		CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}" \
		kernelrelease
)
rtw88_src="$kit_dir/third_party/rtw88"
rtw88_dest="$root_mnt/lib/modules/$kernel_release/extra/rtw88"

mkdir -p "$rtw88_dest"
for module in \
	rtw_core rtw_sdio rtw_8723x rtw_8703b rtw_8723cs
do
	test -f "$rtw88_src/$module.ko"
	install -m 0644 "$rtw88_src/$module.ko" "$rtw88_dest/"
done
depmod -b "$root_mnt" "$kernel_release"

install -m 0644 \
	"$kernel_out/arch/arm64/boot/Image" \
	"$boot_mnt/Image-6.1-rockchip"

for profile in uart display charge-test; do
	install -m 0644 \
		"$kernel_out/arch/arm64/boot/dts/rockchip/rk3326-863-tablet-$profile.dtb" \
		"$boot_mnt/rk3326-863-tablet-$profile.dtb"

	sed "s/@ROOT_PARTUUID@/$ROOT_PARTUUID/g" \
		"$kit_dir/extlinux/extlinux-$profile.conf" \
		> "$boot_mnt/extlinux-$profile.conf"
done

mkdir -p "$boot_mnt/extlinux"
install -m 0644 \
	"$boot_mnt/extlinux-$boot_profile.conf" \
	"$boot_mnt/extlinux/extlinux.conf"

mkdir -p "$root_mnt/boot"
sed \
	-e "s/@ROOT_PARTUUID@/$ROOT_PARTUUID/g" \
	-e "s/@BOOT_PARTUUID@/$BOOT_PARTUUID/g" \
	"$kit_dir/rootfs/fstab.in" \
	> "$root_mnt/etc/fstab"

mkdir -p "$root_mnt/usr/share/rk3326-tablet-bsp"
install -m 0644 "$kit_dir/VERSION" \
	"$root_mnt/usr/share/rk3326-tablet-bsp/VERSION"
install -m 0644 "$kit_dir/HARDWARE-NOTES.md" \
	"$root_mnt/usr/share/rk3326-tablet-bsp/HARDWARE-NOTES.md"
printf '%s\n' "$boot_profile" \
	> "$root_mnt/usr/share/rk3326-tablet-bsp/boot-profile"

sync
umount "$boot_mnt"
umount "$root_mnt"
losetup -d "$loop_dev"
loop_dev=

mv "$image_tmp" "$output"
image_tmp=

# mktemp creates the image as root with mode 0600. When the builder was
# invoked through sudo, hand the finished artifact back to the caller while
# retaining private permissions: it embeds this tablet's boot-chain blobs.
if [ -n "${SUDO_UID:-}" ] && [ -n "${SUDO_GID:-}" ]; then
	chown "$SUDO_UID:$SUDO_GID" "$output"
fi
chmod 0600 "$output"

sha256sum "$output"
echo "Image created: $output"
echo "Default boot profile: $boot_profile"
