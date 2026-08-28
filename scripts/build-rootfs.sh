#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: sudo -E $0 /path/to/debian-rootfs.tar.xz" >&2
	exit 2
fi

if [ "$(id -u)" -ne 0 ]; then
	echo "error: build-rootfs.sh must run as root" >&2
	exit 1
fi

if [ -n "${ROOT_PASSWORD_HASH:-}" ]; then
	case "$ROOT_PASSWORD_HASH" in
		\$*) ;;
		*)
			echo "error: ROOT_PASSWORD_HASH does not look encrypted" >&2
			exit 1
			;;
	esac
fi

output=$1
if [ -e "$output" ]; then
	echo "error: output already exists: $output" >&2
	exit 1
fi

for command in mmdebstrap chroot dpkg dpkg-query systemctl tar xz; do
	command -v "$command" >/dev/null 2>&1 || {
		echo "error: missing command: $command" >&2
		exit 1
	}
done

keyring=${DEBIAN_ARCHIVE_KEYRING:-/usr/share/keyrings/debian-archive-keyring.gpg}
if [ ! -r "$keyring" ]; then
	echo "error: Debian archive keyring not found: $keyring" >&2
	echo "install debian-archive-keyring 2025.1 or newer" >&2
	exit 1
fi

if [ -z "${DEBIAN_ARCHIVE_KEYRING:-}" ]; then
	keyring_version=$(
		dpkg-query -W -f='${Version}' debian-archive-keyring 2>/dev/null ||
		true
	)
	if [ -z "$keyring_version" ] ||
		! dpkg --compare-versions "$keyring_version" ge 2025.1
	then
		echo "error: debian-archive-keyring 2025.1 or newer is required" >&2
		echo "installed version: ${keyring_version:-not installed}" >&2
		exit 1
	fi
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
work_dir=$(mktemp -d /tmp/rk3326-rootfs.XXXXXX)
root_dir="$work_dir/root"

cleanup()
{
	case "$work_dir" in
		/tmp/rk3326-rootfs.*) rm -rf -- "$work_dir" ;;
	esac
}
trap cleanup EXIT INT TERM HUP

packages=$(
	sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' \
		"$kit_dir/rootfs/packages.list" |
	paste -sd, -
)

suite=${DEBIAN_SUITE:-trixie}
mirror=${DEBIAN_MIRROR:-http://deb.debian.org/debian}

mmdebstrap \
	--mode=root \
	--architectures=arm64 \
	--variant=minbase \
	--keyring="$keyring" \
	--components=main,contrib,non-free-firmware \
	--include="$packages" \
	"$suite" \
	"$root_dir" \
	"$mirror"

cp -a "$kit_dir/rootfs/overlay/." "$root_dir/"

install -D -m 0755 \
	"$kit_dir/hwtest/rk3326-hwprobe.py" \
	"$root_dir/usr/local/sbin/rk3326-hwprobe"
install -D -m 0755 \
	"$kit_dir/hwtest/rk3326-hwtest.py" \
	"$root_dir/usr/local/sbin/rk3326-hwtest"
install -D -m 0755 \
	"$kit_dir/hwtest/rk3326-charge-watch.py" \
	"$root_dir/usr/local/sbin/rk3326-charge-watch"
install -D -m 0644 \
	"$kit_dir/hwtest/expected-hardware.json" \
	"$root_dir/usr/share/rk3326-hwtest/expected-hardware.json"

if [ -n "${ROOT_PASSWORD_HASH:-}" ]; then
	printf 'root:%s\n' "$ROOT_PASSWORD_HASH" |
		chroot "$root_dir" chpasswd -e
else
	chroot "$root_dir" passwd --lock root
	echo "warning: root account is locked in this rootfs" >&2
fi

systemctl --root="$root_dir" enable \
	serial-getty@ttyS2.service \
	ssh.service \
	NetworkManager.service \
	systemd-timesyncd.service \
	rk3326-hwprobe.service \
	rk3326-hwtest.service

chroot "$root_dir" apt-get clean
: > "$root_dir/etc/machine-id"

epoch=${SOURCE_DATE_EPOCH:-0}
tar \
	--sort=name \
	--mtime="@$epoch" \
	--clamp-mtime \
	--numeric-owner \
	--owner=0 \
	--group=0 \
	--acls \
	--xattrs \
	-cpf - \
	-C "$root_dir" . |
xz -T0 -6 > "$output"

sha256sum "$output"
