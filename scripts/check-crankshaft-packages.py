#!/usr/bin/env python3
"""Validate a supplied local package bundle before creating a rootfs."""
import hashlib
from pathlib import Path
import re
import subprocess
import sys


def validate(directory):
    directory = Path(directory)
    entries = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9][A-Za-z0-9_.+~-]*\.deb)", line)
        if not match or match[2] in entries:
            raise ValueError("invalid or duplicate SHA256SUMS entry")
        entries[match[2]] = match[1]
    files = {p.name for p in directory.glob("*.deb")}
    if not files or files != set(entries):
        raise ValueError("SHA256SUMS must cover exactly all .deb files")
    packages = set()
    for name, digest in entries.items():
        path = directory / name
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"checksum mismatch or symlink: {name}")
        def field(key):
            return subprocess.check_output(["dpkg-deb", "-f", str(path), key], text=True).strip()
        package, architecture = field("Package"), field("Architecture")
        if architecture not in ("arm64", "all"):
            raise ValueError(f"wrong architecture: {name}: {architecture}")
        if package in packages:
            raise ValueError(f"duplicate package: {package}")
        packages.add(package)
    missing = {"libaasdk", "crankshaft-core", "crankshaft-ui-slim"} - packages
    if missing:
        raise ValueError(f"missing required packages: {sorted(missing)}")


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("usage: check-crankshaft-packages.py DEB_DIRECTORY")
        validate(sys.argv[1])
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(f"error: {error}")
    print("Crankshaft package checks passed.")
