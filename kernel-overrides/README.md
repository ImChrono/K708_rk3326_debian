# Kernel source overrides

The pinned Rockchip 6.1 tree contains a GSL3673 driver, but its bundled
firmware/configuration is not the one used by this tablet. The resulting
input device registers successfully yet produces no touch events.

`gsl3673_800x1280_oem.h` was deterministically reconstructed from the
tablet's original GPL-licensed Android 4.19.193 kernel:

- configuration: 512 little-endian words, SHA-256
  `d563014999a7ad8d1aac58de9cad4105f0ead26438d3fd7f3926139f61052a72`;
- firmware: 5313 offset/value records, SHA-256
  `8f275a08760ca1c55a17766a9e8411575acefa8ec66635b27360da2a663b64b6`;
- generated header SHA-256
  `63d9fd1141d4072201943283e30c01e39763d33b77e8152b339b80ed2036dcf8`.

`scripts/install-kernel-overrides.py` verifies the generated header and
selects it in `gsl3673_800x1280.c`. `scripts/build-kernel.sh` invokes the
installer automatically. The firmware header remains separate from the
upstream kernel checkout so its provenance and review boundary are clear.
