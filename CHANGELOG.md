# Changelog

## 0.4.0-rc5

- Add tag-driven GitHub Releases with strict `VERSION`/tag/changelog matching,
  automatic public kernel, DTB, modules, rootfs and source packages, combined
  SHA-256 checksums and prerelease detection.
- Run the complete public build on pull requests and pushes to `main`, and make
  it reusable by the release workflow.
- Update the official checkout and artifact actions used by hosted CI while
  retaining the guarded self-hosted path for private bootable images.
- Build a dedicated Debian 13 archive keyring from the official signing keys,
  verifying all three fingerprints before the rootfs build starts.
- Make the touchscreen override reproduce the verified VDDIO mode by
  deterministically disabling the pinned Rockchip driver's active 1.8 V path.

## 0.4.0-rc4

- Add a deliberately separate `charge-test` DTB and extlinux profile which
  restores the exact charger policy recovered from this tablet's Android DTB:
  4.40 V charge voltage, 2.00 A charge current, 1.50 A input limit, 4.50 V
  minimum input and 120 mA termination current.
- Keep the charger disabled in the normal UART and display profiles until a
  complete externally monitored charge cycle has been accepted.
- Enable the RK817 charger driver in the pinned kernel configuration.
- Add `rk3326-charge-watch`, which reports battery voltage/current, supply
  state and the hottest system thermal zone while correctly showing battery
  temperature as unavailable.
- Document that the two-wire battery exposes no thermistor and that the
  RK817 driver's constant `188` is a virtual 18.8 C fallback, not a sensor.
- Validate all three DTBs and reject accidental charger enablement in the
  normal profiles, altered OEM limits or an unverified `ntc_table`.
- Accept both flat and `private/`-nested verified boot-blob source layouts.
- Record the completed RTL8723CS association test, working Panfrost/Mali-G31
  acceleration and successful conservative RK817 charge-current test.

## 0.4.0-rc1

- Include the verified OEM GSL3673 configuration and firmware header that
  made the touchscreen generate events; install it into the pinned kernel
  tree automatically and verify its SHA-256.
- Mark display, framebuffer, touchscreen, physical keys and RK817 battery
  gauge as proven on Debian 13 with the Rockchip 6.1 kernel.
- Enable Mali-G31 through Panfrost and correct the vendor DT interrupt names
  from uppercase to the lowercase names required by the upstream binding.
- Enable the tablet's SDIO host and recover the RTL8723CS power/wake wiring
  from the Android DTB.
- Pin the `lwfinger/rtw88` out-of-tree driver at commit
  `a56bcd26e770257612a0803249cbd4095fc6feca` for SDIO ID `024c:b703`.
- Build and install `rtw_core`, `rtw_sdio`, `rtw_8723x`, `rtw_8703b` and
  `rtw_8723cs` in both local images and public CI artifacts.
- Preserve charging, audio, Bluetooth, eMMC and camera support as explicit
  deferred work.

## 0.3.2-dev

- Override the generic 863 GSL3673 interrupt route with the tablet-specific
  GPIO0_C1 wiring recovered from its Android DTB.
- Validate the touchscreen IRQ and reset GPIO cells in every generated DTB.

## 0.3.1-dev

- Render GPT identifiers in lowercase so util-linux and systemd resolve the
  generated `/dev/disk/by-partuuid` links during root remount and `/boot`
  mounting.
- Validate enabled hardware-test units as symlinks inside an offline rootfs.
- Return generated images to the invoking sudo user with private permissions.
- Make missing private boot-chain inputs fail with explicit diagnostics.
- Require the Debian 13 archive keyring when building the rootfs.

## 0.3.0-dev

- Mark the 1024x600 DSI display, backlight and framebuffer as proven.
- Declare the panel as 8 bits per colour to match RGB888.
- Enable the Android-identified GSL3673 touchscreen on I2C1 address `0x40`.
- Add an automatic JSON hardware inventory and a tty1 input-test dashboard.
- Add Debian bring-up tools for evdev, DRM, Mesa, audio, video, networking
  and Bluetooth.
- Add compressed zram swap for the 2 GiB target.
- Add public GitHub Actions for source validation, kernel/DTB and locked
  Debian rootfs artifacts.
- Add a guarded self-hosted workflow for assembling the image with private
  tablet boot-chain blobs.

## 0.2.0

- Pin the exact Rockchip kernel commit and known-booting full configuration.
- Keep the reviewed kernel fragment for deliberate changes.
- Fix root selection by rendering a deterministic GPT PARTUUID.
- Keep LPDDR3 fixed at the firmware-trained 332/333 MHz.
- Add the USB2 PHY IRQs extracted from the tablet DTB.
- Remove zero-sized Android DRM-logo and vendor-storage reservations.
- Add deterministic GPT layout and private boot-chain manifests.
- Add Debian 13 rootfs, image and validation scripts.
- Include kernel modules, autofs, wireless regulatory data and RTL8723CS
  firmware in the generated rootfs.
- Make UART the conservative default while retaining a display-test profile.

## 0.1.0

- First Rockchip 6.1 kernel boot into Debian from microSD.
- UART2 M1 console at 1,500,000 baud.
- RK817 safe default pin state.
- Initial 1024x600 display DTB.
