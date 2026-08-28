#!/usr/bin/python3
"""Collect a non-destructive RK3326 hardware inventory and test summary."""

from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import pathlib
import platform
import shutil
import subprocess
import sys
from typing import Any


DEFAULT_EXPECTED = pathlib.Path(
    "/usr/share/rk3326-hwtest/expected-hardware.json"
)
DEFAULT_RUNS = pathlib.Path("/var/lib/rk3326-hwtest/runs")


def read_text(path: os.PathLike[str] | str) -> str:
    try:
        data = pathlib.Path(path).read_bytes()
    except (FileNotFoundError, IsADirectoryError, PermissionError, OSError):
        return ""
    return data.replace(b"\0", b"\n").decode("utf-8", "replace").strip()


def run_command(argv: list[str], timeout: int = 20) -> dict[str, Any]:
    executable = shutil.which(argv[0])
    if executable is None:
        return {
            "argv": argv,
            "available": False,
            "returncode": None,
            "stdout": "",
            "stderr": "command not installed",
        }
    try:
        result = subprocess.run(
            [executable, *argv[1:]],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "argv": argv,
            "available": True,
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }
    except subprocess.TimeoutExpired as error:
        return {
            "argv": argv,
            "available": True,
            "returncode": None,
            "stdout": error.stdout or "",
            "stderr": f"timeout after {timeout} seconds",
        }


def collect_named_class(class_name: str, fields: list[str]) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for item in sorted(glob.glob(f"/sys/class/{class_name}/*")):
        path = pathlib.Path(item)
        record: dict[str, Any] = {"name": path.name}
        for field in fields:
            value = read_text(path / field)
            if value:
                record[field] = value
        records.append(record)
    return records


def evaluate_check(check: dict[str, Any]) -> dict[str, Any]:
    kind = check["kind"]
    path_pattern = check["path"]
    expected = str(check.get("value", ""))
    matched_paths = sorted(glob.glob(path_pattern))
    observed: list[str] = []
    passed = False

    if kind in {"file_equals", "file_contains"}:
        value = read_text(path_pattern)
        observed = [value] if value else []
        passed = value == expected if kind == "file_equals" else expected.lower() in value.lower()
    elif kind == "glob_exists":
        observed = matched_paths
        passed = bool(matched_paths)
    elif kind == "glob_contains":
        observed = [read_text(path) for path in matched_paths]
        passed = any(expected.lower() in value.lower() for value in observed)
    else:
        observed = [f"unsupported check kind: {kind}"]

    required = bool(check.get("required", False))
    status = "PASS" if passed else ("FAIL" if required else "BLOCKED")
    return {
        "id": check["id"],
        "description": check.get("description", check["id"]),
        "status": status,
        "required": required,
        "expected": expected,
        "observed": observed,
    }


def write_text(path: pathlib.Path, value: str) -> None:
    path.write_text(value, encoding="utf-8")


def update_latest(runs_dir: pathlib.Path, run_dir: pathlib.Path) -> None:
    latest = runs_dir / "latest"
    temporary = runs_dir / f".latest.{os.getpid()}.tmp"
    try:
        temporary.unlink()
    except FileNotFoundError:
        pass
    temporary.symlink_to(run_dir.name)
    os.replace(temporary, latest)


def create_run_dir(runs_dir: pathlib.Path) -> tuple[pathlib.Path, str]:
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    runs_dir.mkdir(parents=True, exist_ok=True)
    for collision in range(1000):
        suffix = "" if collision == 0 else f"-{collision:03d}"
        run_dir = runs_dir / f"{timestamp}{suffix}"
        try:
            run_dir.mkdir()
        except FileExistsError:
            continue
        return run_dir, timestamp
    raise RuntimeError("unable to allocate a unique hardware-report directory")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", type=pathlib.Path, default=DEFAULT_EXPECTED)
    parser.add_argument("--runs-dir", type=pathlib.Path, default=DEFAULT_RUNS)
    args = parser.parse_args()

    expected = json.loads(args.expected.read_text(encoding="utf-8"))
    run_dir, timestamp = create_run_dir(args.runs_dir)

    commands = {
        "dmesg": run_command(["dmesg"]),
        "lsmod": run_command(["lsmod"]),
        "ip-link": run_command(["ip", "-details", "link", "show"]),
        "iw-dev": run_command(["iw", "dev"]),
        "rfkill": run_command(["rfkill", "list"]),
        "lsusb": run_command(["lsusb"]),
        "lsusb-tree": run_command(["lsusb", "-t"]),
        "drm-info": run_command(["drm_info"]),
        "aplay": run_command(["aplay", "-l"]),
        "arecord": run_command(["arecord", "-l"]),
        "v4l2": run_command(["v4l2-ctl", "--list-devices"]),
        "bluetooth": run_command(["bluetoothctl", "show"]),
    }

    inventory = {
        "schema_version": 1,
        "timestamp_utc": timestamp,
        "board": expected.get("board"),
        "system": {
            "model": read_text("/proc/device-tree/model"),
            "compatible": read_text("/proc/device-tree/compatible").splitlines(),
            "kernel": platform.release(),
            "machine": platform.machine(),
            "cmdline": read_text("/proc/cmdline"),
        },
        "drm": collect_named_class(
            "drm", ["status", "enabled", "modes", "dpms", "uevent"]
        ),
        "framebuffers": collect_named_class(
            "graphics", ["name", "modes", "mode", "virtual_size", "bits_per_pixel"]
        ),
        "backlights": collect_named_class(
            "backlight",
            ["type", "max_brightness", "brightness", "actual_brightness", "bl_power"],
        ),
        "inputs": collect_named_class("input", ["device/name", "device/uevent"]),
        "network": collect_named_class(
            "net", ["address", "operstate", "carrier", "speed", "uevent"]
        ),
        "power_supply": collect_named_class(
            "power_supply",
            [
                "type",
                "status",
                "capacity",
                "voltage_now",
                "current_now",
                "temp",
                "online",
            ],
        ),
        "thermal": collect_named_class("thermal", ["type", "temp"]),
        "commands": commands,
    }

    summary = {
        "schema_version": 1,
        "timestamp_utc": timestamp,
        "board": expected.get("board"),
        "checks": [evaluate_check(check) for check in expected["checks"]],
    }
    counts = {"PASS": 0, "FAIL": 0, "BLOCKED": 0}
    for check in summary["checks"]:
        counts[check["status"]] += 1
    summary["counts"] = counts

    write_text(
        run_dir / "inventory.json",
        json.dumps(inventory, indent=2, sort_keys=True) + "\n",
    )
    write_text(
        run_dir / "summary.json",
        json.dumps(summary, indent=2, sort_keys=True) + "\n",
    )
    write_text(run_dir / "dmesg.txt", commands["dmesg"]["stdout"])
    write_text(run_dir / "interrupts.txt", read_text("/proc/interrupts") + "\n")
    write_text(run_dir / "input-devices.txt", read_text("/proc/bus/input/devices") + "\n")
    update_latest(args.runs_dir, run_dir)

    for check in summary["checks"]:
        print(f'{check["status"]:<8} {check["id"]}: {check["description"]}')
    print(
        "summary: "
        f'{counts["PASS"]} pass, {counts["FAIL"]} fail, '
        f'{counts["BLOCKED"]} blocked'
    )
    print(f"report: {run_dir}")
    return 1 if counts["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
