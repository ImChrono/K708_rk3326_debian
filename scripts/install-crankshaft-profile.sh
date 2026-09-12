#!/bin/sh
# Internal helper for a newly created, disposable rootfs only.
set -eu
[ "$#" -eq 2 ] || exit 2
root_dir=$1
bundle=$2
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
kit_dir=$(dirname "$script_dir")
[ "$root_dir" != / ] && [ -f "$root_dir/etc/debian_version" ] || exit 1
python3 "$script_dir/check-crankshaft-packages.py" "$bundle"
[ ! -e "$root_dir/usr/sbin/policy-rc.d" ] || { echo "error: existing policy-rc.d" >&2; exit 1; }
mkdir -p "$root_dir/tmp/crankshaft-debs"
cp "$bundle"/*.deb "$root_dir/tmp/crankshaft-debs/"
printf '#!/bin/sh\nexit 101\n' > "$root_dir/usr/sbin/policy-rc.d"
chmod 0755 "$root_dir/usr/sbin/policy-rc.d"
chroot "$root_dir" /bin/sh -ec 'apt-get update; DEBIAN_FRONTEND=noninteractive apt-get install -y /tmp/crankshaft-debs/*.deb'
rm "$root_dir/usr/sbin/policy-rc.d"
rm -rf "$root_dir/tmp/crankshaft-debs"
# Upstream postinst ignores failed group additions: make hardware access explicit.
for group in video render input audio plugdev aasdk; do
 chroot "$root_dir" getent group "$group" >/dev/null ||
  chroot "$root_dir" groupadd --system "$group"
done
chroot "$root_dir" usermod -a -G video,render,input,audio,plugdev,aasdk crankshaft
cp -a "$kit_dir/rootfs/profiles/android-auto/overlay/." "$root_dir/"
python3 "$script_dir/configure-crankshaft.py" "$root_dir"
systemctl --root="$root_dir" disable rk3326-hwtest.service
systemctl --root="$root_dir" mask getty@tty1.service
systemctl --root="$root_dir" enable crankshaft-core.service crankshaft-ui-slim-display-setup.service crankshaft-ui-slim.service
systemctl --root="$root_dir" set-default graphical.target
# Core expects PipeWire at /run/user/<uid>.
mkdir -p "$root_dir/var/lib/systemd/linger"
touch "$root_dir/var/lib/systemd/linger/crankshaft"
install -D -m 0644 "$bundle/SHA256SUMS" "$root_dir/usr/share/rk3326-android-auto/SHA256SUMS"
install -D -m 0644 "$kit_dir/configs/crankshaft-sources.json" "$root_dir/usr/share/rk3326-android-auto/source-reference.json"

python3 "$script_dir/validate-crankshaft-rootfs.py" "$root_dir"
