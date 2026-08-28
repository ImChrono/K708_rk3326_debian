#!/usr/bin/env python3
"""Install the tablet-specific source overrides into the pinned kernel tree."""

from __future__ import annotations

import argparse
import hashlib
import pathlib
import shutil


DRIVER_RELATIVE_PATH = pathlib.Path(
    "drivers/input/touchscreen/gsl3673_800x1280.c"
)
HEADER_NAME = "gsl3673_800x1280_oem.h"
HEADER_SHA256 = (
    "63d9fd1141d4072201943283e30c01e39763d33b77e8152b339b80ed2036dcf8"
)
REPLACED_HEADERS = {
    "gsl3673_800x1280.h",
    "rochkchip_gslX680_8inch_800x1280_tg806_10.h",
}


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def patch_driver(driver_path: pathlib.Path) -> None:
    original = driver_path.read_text(encoding="utf-8")

    if any(
        line.lstrip().startswith("#define GSL9XX_VDDIO_1800")
        for line in original.splitlines()
    ):
        raise SystemExit(
            "error: GSL9XX_VDDIO_1800 is active in the touchscreen driver"
        )

    output: list[str] = []
    replacements = 0
    already_selected = False

    for line in original.splitlines(keepends=True):
        stripped = line.lstrip()
        if stripped.startswith('#include "') and f'"{HEADER_NAME}"' in stripped:
            already_selected = True
            output.append(line)
            continue

        if stripped.startswith('#include "') and any(
            f'"{name}"' in stripped for name in REPLACED_HEADERS
        ):
            indentation = line[: len(line) - len(stripped)]
            newline = "\n" if line.endswith("\n") else ""
            output.append(f'{indentation}#include "{HEADER_NAME}"{newline}')
            replacements += 1
            continue

        output.append(line)

    if not already_selected and replacements != 1:
        raise SystemExit(
            "error: expected exactly one active stock GSL3673 firmware include"
        )

    patched = "".join(output)
    if patched != original:
        driver_path.write_text(patched, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("kernel_tree", type=pathlib.Path)
    args = parser.parse_args()

    kernel_tree = args.kernel_tree.expanduser().resolve()
    kit_dir = pathlib.Path(__file__).resolve().parent.parent
    source_header = kit_dir / "kernel-overrides" / HEADER_NAME
    driver_path = kernel_tree / DRIVER_RELATIVE_PATH
    destination_header = driver_path.parent / HEADER_NAME

    if not driver_path.is_file():
        raise SystemExit(f"error: touchscreen driver not found: {driver_path}")
    if not source_header.is_file():
        raise SystemExit(f"error: OEM touchscreen header not found: {source_header}")

    actual_hash = file_sha256(source_header)
    if actual_hash != HEADER_SHA256:
        raise SystemExit(
            "error: OEM touchscreen header checksum mismatch\n"
            f"expected: {HEADER_SHA256}\n"
            f"actual:   {actual_hash}"
        )

    patch_driver(driver_path)
    shutil.copyfile(source_header, destination_header)

    if file_sha256(destination_header) != HEADER_SHA256:
        raise SystemExit("error: installed touchscreen header verification failed")

    print(f"Installed OEM touchscreen header: {destination_header}")
    print(f"Selected OEM touchscreen header in: {driver_path}")


if __name__ == "__main__":
    main()
