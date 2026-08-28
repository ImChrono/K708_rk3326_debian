# Private boot-chain blobs

The image builder needs the exact boot-chain sectors extracted from this
tablet. They are deliberately not distributed in this source archive.

Prepare `blobs/private/` from the previously verified
`ums-autoboot-source` directory:

```sh
./scripts/prepare-blobs.sh /path/to/ums-autoboot-source
```

The script copies only:

- `idb-area-lba64-8191.img`;
- `security.img`;
- `uboot_a.img` and `uboot_b.img`;
- `trust_a.img` and `trust_b.img`;
- `misc.img`.

Every file must match both `manifest.sha256` and `manifest.sizes`. The image
builder refuses to continue on any mismatch. Never substitute a loader or
trust image taken from another RK3326 board.
