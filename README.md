# RK3326 tablet — reproducible Debian BSP

This project builds a bootable Debian 13 arm64 image for the investigated
RK3326/PX30 tablet. Hardware knowledge is kept in source form: DTS files,
kernel configuration, rootfs recipe, boot-chain manifests and image-layout
scripts. The running tablet is a diagnostic target, not the place where
permanent fixes are made.

Version `0.4.0-rc5` has proven boot from microSD into Debian with UART2,
fixed-frequency LPDDR3, the 1024x600 DSI console, GSL3673 touch input,
physical keys, RK817 battery gauge, RTL8723CS Wi-Fi and Panfrost acceleration.
It also adds an isolated OEM charger-test profile; see `HARDWARE-NOTES.md`.

## Safety model

- The builder creates an ordinary image file and never writes `/dev/sdX`.
- Original tablet IDB, U-Boot, trust and security blobs are required.
- Every private blob is checked by size and SHA-256 before use.
- eMMC and NAND remain disabled in the DTS.
- The kernel source commit is pinned.
- The out-of-tree RTL8723CS driver commit is pinned.
- The working OEM touchscreen header is checked by SHA-256 before use.
- The known-booting full kernel configuration is the baseline.
- Root selection uses a fixed GPT `PARTUUID`, not a filesystem label.
- Charging remains disabled in normal UART and display DTBs.
- The two-wire battery has no temperature sensor; no software value is
  presented as battery temperature.

## Project layout

```text
blobs/       private boot-chain manifest and preparation instructions
configs/     pinned kernel state and deterministic image layout
dts/         UART, display and isolated charger-test device trees
extlinux/    boot profiles rendered by the image builder
kernel-overrides/ verified tablet-specific kernel data
rootfs/      Debian package list, fstab template and filesystem overlay
scripts/     kernel, rootfs, image and validation commands
hwtest/      automatic inventory and interactive tty1 hardware dashboard
.github/     public CI and guarded private-image workflows
```

`blobs/private/`, `third_party/`, build outputs and generated images are
intentionally ignored. They must not be added to a source archive.

## Host dependencies

On Debian or Ubuntu:

```sh
sudo apt update
sudo apt install \
  bc binfmt-support bison build-essential device-tree-compiler dosfstools \
  debian-archive-keyring e2fsprogs flex gcc-aarch64-linux-gnu gdisk git \
  libelf-dev libssl-dev mmdebstrap openssl python3 qemu-user-static \
  shellcheck xz-utils zip
```

Building Debian 13 requires `debian-archive-keyring` version `2025.1` or
newer. Ubuntu releases may provide an older package; update it from the
official Debian archive before running `build-rootfs.sh`.

Validate the source kit:

```sh
./scripts/validate-source.sh
```

## 1. Check out the exact sources

```sh
./scripts/fetch-kernel.sh "$HOME/rk3326-linux-6.1"
./scripts/fetch-rtw88.sh
```

Both fetchers verify their pinned commit. The RTW88 checkout is kept under
the ignored `third_party/` directory.

## 2. Prepare the private boot chain

Use the verified extraction already produced from this tablet:

```sh
./scripts/prepare-blobs.sh \
  "$HOME/rk3326-mainline/kit/ums-autoboot-source"
```

All seven checks must report `OK`.

## 3. Build the kernel

```sh
./scripts/build-kernel.sh \
  "$HOME/rk3326-linux-6.1" \
  "$HOME/rk3326-linux-6.1-out"
```

This installs the custom DTS files, begins from
`configs/kernel-working.config`, merges the reviewable project fragment and
builds `Image`, modules and all three DTBs. It also verifies and selects the OEM
GSL3673 firmware/configuration, then builds the five out-of-tree RTW88
modules required by RTL8723CS.

## 4. Build Debian

Create a password hash without storing the password in this project:

```sh
ROOT_PASSWORD_HASH="$(openssl passwd -6)"

sudo --preserve-env=ROOT_PASSWORD_HASH \
  env ROOT_PASSWORD_HASH="$ROOT_PASSWORD_HASH" \
  ./scripts/build-rootfs.sh \
  "$HOME/debian-rk3326-rootfs.tar.xz"

unset ROOT_PASSWORD_HASH
```

If `ROOT_PASSWORD_HASH` is omitted, the build succeeds with the root account
locked. GitHub-hosted CI deliberately uses this locked form.

The recipe includes hardware diagnostics, NetworkManager, OpenSSH,
regulatory data and the RTL8703B firmware used by this RTL8723CS module.

## Automatic hardware test

The bring-up rootfs enables two services:

- `rk3326-hwprobe.service` records a non-destructive inventory under
  `/var/lib/rk3326-hwtest/runs/`;
- `rk3326-hwtest.service` owns tty1 and displays the current PASS, FAIL and
  BLOCKED state, live input events and touchscreen coverage.

UART2 remains the administrative console. Add `rk3326.hwtest=0` to the
kernel command line to suppress the tty1 dashboard for a diagnostic boot.

The rootfs also installs `rk3326-charge-watch`. It deliberately prints
`bat_C=N/A`: the two-wire battery exposes no thermistor and the constant
`188` reported by the RK817 driver is a virtual fallback.

Once `wlan0` appears, configure the first connection from UART or tty1:

```sh
nmcli radio wifi on
nmcli device wifi list
nmcli --ask device wifi connect "YOUR_SSID"
ip -br address
```

NetworkManager persists the connection. OpenSSH is enabled by the rootfs
recipe; use a non-root account or an SSH key before exposing the tablet to
an untrusted network.

## 5. Build the image

UART is the default and known-good first-boot profile:

```sh
sudo env BOOT_PROFILE=uart IMAGE_SIZE_MIB=4096 \
  ./scripts/build-image.sh \
  "$HOME/rk3326-linux-6.1" \
  "$HOME/rk3326-linux-6.1-out" \
  "$HOME/debian-rk3326-rootfs.tar.xz" \
  "$HOME/rk3326-tablet-debian-uart.img"
```

To produce a display-test image from the same inputs:

```sh
sudo env BOOT_PROFILE=display IMAGE_SIZE_MIB=4096 \
  ./scripts/build-image.sh \
  "$HOME/rk3326-linux-6.1" \
  "$HOME/rk3326-linux-6.1-out" \
  "$HOME/debian-rk3326-rootfs.tar.xz" \
  "$HOME/rk3326-tablet-debian-display.img"
```

The display profile is the normal hardware-test choice. The UART profile
keeps the DSI pipeline disabled and remains the recovery profile.

For an attended charger validation, build the isolated profile:

```sh
sudo env BOOT_PROFILE=charge-test IMAGE_SIZE_MIB=4096 \
  ./scripts/build-image.sh \
  "$HOME/rk3326-linux-6.1" \
  "$HOME/rk3326-linux-6.1-out" \
  "$HOME/debian-rk3326-rootfs.tar.xz" \
  "$HOME/rk3326-tablet-debian-charge-test.img"
```

This profile restores the exact Android DTB policy: 4.40 V maximum charge
voltage, 2.00 A charge current, 1.50 A input limit and 120 mA termination.
Because the pack has no temperature signal, the first complete cycle requires
an external cell thermometer and continuous supervision:

```sh
rk3326-charge-watch
```

## 6. Validate before flashing

```sh
sudo ./scripts/validate-image.sh \
  "$HOME/rk3326-tablet-debian-uart.img"
```

Validation checks GPT offsets, every raw boot-chain region, both filesystems,
the active root `PARTUUID`, the five RTL8723CS modules, Wi-Fi firmware,
touch/battery/GPU DT properties and the DMC/DFI safety override in all DTBs.
It also confirms that only `charge-test` enables charging and that its limits
match the recovered Android values.

Only after validation should the image be written to a card. Resolve the
target again with `lsblk`; do not reuse an old `/dev/sdX` assumption.

## First-boot discipline

Do not fix the running rootfs manually. Capture evidence with:

```sh
sudo ./scripts/collect-first-boot.sh
```

Translate each accepted fix into one of:

- a DTS change;
- `configs/tablet-console.config`;
- `rootfs/packages.list`;
- `rootfs/overlay/`;
- an image-build or validation rule.

Then rebuild the image from clean inputs and repeat the cold-boot test.

## GitHub Actions

`validate.yml` runs source, Python and shell validation on every push and
pull request. `build.yml` builds and packages the kernel, all three DTBs,
in-tree modules, the pinned RTL8723CS modules, a locked Debian rootfs and a
clean source archive. It runs for pull requests, pushes to `main`, manual
dispatches and as the reusable build behind a release.

`release.yml` is tag-driven. A tag must be exactly `v` followed by the value
in `VERSION`, and the same version must have a section in `CHANGELOG.md`.
After all public builds succeed, the workflow creates a GitHub Release,
marks versions containing a hyphen as prereleases, uploads the three archives
and publishes a combined `SHA256SUMS`. A failed run can be re-run safely: an
existing release has its generated assets replaced instead of duplicated.

To publish the current version:

```sh
version=$(tr -d '\n' < VERSION)
git tag -a "v$version" -m "RK3326 tablet Debian BSP $version"
git push origin main "v$version"
```

The complete bootable image requires the exact IDB, security, U-Boot and
trust regions from this tablet. `build-private-image.yml` therefore runs
only by manual dispatch on a self-hosted runner labelled
`rk3326-builder`. The runner must expose the verified inputs at:

```text
/opt/rk3326-private/ums-autoboot-source
```

Private images are not uploaded unless the workflow operator explicitly
selects `upload_image`. Review `LICENSES.md` and the touchscreen provenance
before publishing a release.

The automatic public release deliberately does not contain a bootable disk
image: assembling one requires the tablet-specific private boot-chain blobs.
Use the guarded self-hosted workflow when a complete image is needed.

Create a clean source-only archive with:

```sh
./scripts/package-github.sh \
  "$HOME/rk3326-tablet-debian-bsp.zip"

./scripts/package-source.sh \
  "$HOME/rk3326-tablet-bsp6.1-source.tar.xz"
```

Both packaging scripts exclude private boot-chain blobs, fetched third-party
trees and all generated rootfs/image outputs.
