#!/usr/bin/env python3
"""Resolve Debian package owners of ELF dependencies in the build container."""
from pathlib import Path
import re
import subprocess
import sys

packages = {"libqt5multimedia5-plugins", "gstreamer1.0-plugins-base",
            "gstreamer1.0-plugins-good", "gstreamer1.0-plugins-bad",
            "gstreamer1.0-libav", "libgl1-mesa-dri", "libegl1", "libinput10"}
for line in Path(sys.argv[1]).read_text().splitlines():
    match = re.search(r"=> (/[^ ]+)", line)
    if not match:
        continue
    path = Path(match[1])
    if path.name.startswith(("libaasdk.so", "libaap_protobuf.so")):
        continue
    result = subprocess.run(["dpkg-query", "-S", str(path)], text=True, capture_output=True)
    if result.returncode:
        result = subprocess.run(["dpkg-query", "-S", str(path.resolve())], text=True, capture_output=True)
    if result.returncode:
        sys.exit(f"Cannot resolve runtime package for {path}")
    packages.add(result.stdout.split(": ", 1)[0].removesuffix(":arm64"))
print("\n".join(sorted(packages)))
