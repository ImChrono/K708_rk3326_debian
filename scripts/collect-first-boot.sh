#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "usage: sudo $0 [output-directory]" >&2
	exit 1
fi

output_dir=${1:-"rk3326-first-boot-$(date -u +%Y%m%dT%H%M%SZ)"}

if [ -e "$output_dir" ]; then
	echo "error: output already exists: $output_dir" >&2
	exit 1
fi

mkdir -p "$output_dir"

uname -a > "$output_dir/uname.txt"
cat /proc/cmdline > "$output_dir/cmdline.txt"
cat /proc/meminfo > "$output_dir/meminfo.txt"
cat /proc/cpuinfo > "$output_dir/cpuinfo.txt"
cat /proc/partitions > "$output_dir/partitions.txt"
cat /proc/mounts > "$output_dir/mounts.txt"
dmesg > "$output_dir/dmesg.txt"
journalctl -b --no-pager > "$output_dir/journal.txt"
lsblk -O > "$output_dir/lsblk.txt"
blkid > "$output_dir/blkid.txt"
find /sys/class/devfreq -maxdepth 3 -type f -print \
	> "$output_dir/devfreq-files.txt"
find /sys/class/drm -maxdepth 3 -print \
	> "$output_dir/drm-tree.txt"
find /sys/class/input -maxdepth 3 -print \
	> "$output_dir/input-tree.txt"
find /sys/class/power_supply -maxdepth 3 -print \
	> "$output_dir/power-supply-tree.txt"
find /sys/class/rfkill -maxdepth 3 -print \
	> "$output_dir/rfkill-tree.txt"
if command -v rk3326-charge-watch >/dev/null 2>&1; then
	rk3326-charge-watch --once \
		> "$output_dir/charge-watch.txt" 2>&1 ||
	true
fi

tar -cJf "$output_dir.tar.xz" "$output_dir"
sha256sum "$output_dir.tar.xz"
