#!/usr/bin/env python3
"""Check the installed experimental profile without executing target binaries."""
import json
from pathlib import Path
import sys


def validate(root):
    root = Path(root)
    for name in (
        "usr/bin/crankshaft-core", "usr/bin/crankshaft-ui-slim",
        "usr/share/rk3326-android-auto/SHA256SUMS",
        "usr/share/rk3326-android-auto/source-reference.json",
        "etc/systemd/system/crankshaft-ui-slim.service.d/k708.conf",
        "var/lib/systemd/linger/crankshaft",
    ):
        if not (root / name).is_file():
            raise ValueError(f"missing profile file: {name}")
    units = root / "etc/systemd/system"
    for target, unit in (("multi-user.target", "crankshaft-core.service"),
                         ("graphical.target", "crankshaft-ui-slim.service")):
        link = units / f"{target}.wants" / unit
        if not link.is_symlink() or link.readlink().name != unit:
            raise ValueError(f"service not enabled: {unit}")
    if not (units / "default.target").is_symlink() or (units / "default.target").readlink().name != "graphical.target":
        raise ValueError("default target must be graphical")
    getty = units / "getty@tty1.service"
    if not getty.is_symlink() or str(getty.readlink()) != "/dev/null":
        raise ValueError("tty1 getty must be masked")
    dashboard = units / "multi-user.target.wants/rk3326-hwtest.service"
    if dashboard.exists() or dashboard.is_symlink():
        raise ValueError("hwtest must not compete for tty1")
    config = json.loads((root / "etc/crankshaft/crankshaft.json").read_text())
    channels = config["core"]["android_auto"]["channels"]
    for key in ("video_enabled", "input_enabled", "sensor_enabled"):
        if channels.get(key) is not True:
            raise ValueError(f"required channel disabled: {key}")
    for key in ("all_enabled", "bluetooth_enabled", "microphone_enabled",
                "telephony_audio_enabled", "media_audio_enabled",
                "system_audio_enabled", "speech_audio_enabled"):
        if channels.get(key) is not False:
            raise ValueError(f"unvalidated channel enabled: {key}")


if __name__ == "__main__":
    try:
        validate(sys.argv[1])
    except (OSError, ValueError, KeyError, IndexError) as error:
        sys.exit(f"error: {error}")
    print("Crankshaft rootfs structural checks passed (hardware untested).")
