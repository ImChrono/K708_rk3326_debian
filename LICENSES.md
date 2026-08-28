# Licensing and redistribution notes

This repository combines material with different provenance:

- the custom DTS files carry their own
  `SPDX-License-Identifier: (GPL-2.0+ OR MIT)`;
- the OEM GSL3673 header carries `SPDX-License-Identifier: GPL-2.0` and was
  reconstructed from the tablet's original GPL-licensed Android kernel;
- the Rockchip kernel and `lwfinger/rtw88` trees retain their upstream
  licences and are fetched at pinned commits rather than vendored here;
- Debian packages and firmware retain their package licences;
- the tablet-specific IDB, security, U-Boot, trust and misc images are not
  redistributed by this repository.

Before publishing binary releases, verify that redistribution of every
included firmware component is acceptable for the intended distribution.
The generated bootable image contains private tablet boot-chain data and is
therefore produced only by the guarded self-hosted workflow.
