#!/usr/bin/python3
"""Monitor RK817 charging without misreporting its virtual temperature."""

from __future__ import annotations

import argparse
import datetime as dt
import os
import pathlib
import signal
import sys
import time
from typing import Iterator


POWER_SUPPLY = pathlib.Path(
    os.environ.get("RK3326_POWER_SUPPLY_PATH", "/sys/class/power_supply")
)
THERMAL = pathlib.Path(
    os.environ.get("RK3326_THERMAL_PATH", "/sys/class/thermal")
)
DT_BATTERY = pathlib.Path(
    os.environ.get(
        "RK3326_DT_BATTERY_PATH",
        "/proc/device-tree/i2c@ff180000/pmic@20/battery",
    )
)
VIRTUAL_TEMPERATURE = 188


def read_text(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8").strip()
    except (FileNotFoundError, IsADirectoryError, PermissionError, OSError):
        return ""


def read_int(path: pathlib.Path) -> int | None:
    value = read_text(path)
    try:
        return int(value)
    except ValueError:
        return None


def supplies_of_type(expected: str) -> Iterator[pathlib.Path]:
    try:
        supplies = sorted(POWER_SUPPLY.iterdir())
    except (FileNotFoundError, PermissionError, OSError):
        return
    for supply in supplies:
        if read_text(supply / "type").lower() == expected.lower():
            yield supply


def online(expected: str) -> int:
    values = [read_int(supply / "online") for supply in supplies_of_type(expected)]
    return int(any(value == 1 for value in values))


def battery() -> pathlib.Path | None:
    for supply in supplies_of_type("Battery"):
        return supply
    return None


def celsius_from_millidegrees(value: int | None) -> str:
    if value is None:
        return "N/A"
    return f"{value / 1000:.1f}"


def hottest_system_temperature() -> str:
    values: list[int] = []
    try:
        zones = sorted(THERMAL.glob("thermal_zone*"))
    except (PermissionError, OSError):
        zones = []
    for zone in zones:
        value = read_int(zone / "temp")
        if value is not None:
            values.append(value)
    return celsius_from_millidegrees(max(values) if values else None)


def battery_temperature(bat: pathlib.Path) -> tuple[str, bool]:
    raw = read_int(bat / "temp")
    ntc_configured = (DT_BATTERY / "ntc_table").exists()
    if not ntc_configured:
        return "N/A", False
    if raw is None:
        return "N/A", True
    return f"{raw / 10:.1f}", True


def format_scaled(value: int | None, divisor: int) -> str:
    if value is None:
        return "N/A"
    return str(value // divisor)


def sample(bat: pathlib.Path) -> str:
    capacity = read_text(bat / "capacity") or "N/A"
    voltage_mv = format_scaled(read_int(bat / "voltage_now"), 1000)
    current_ma = format_scaled(read_int(bat / "current_now"), 1000)
    temp_c, _ = battery_temperature(bat)
    timestamp = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    return (
        f"{timestamp:<25} {capacity:>8} {voltage_mv:>10} "
        f"{current_ma:>10} {temp_c:>10} "
        f"{hottest_system_temperature():>12} "
        f"{online('Mains'):>4} {online('USB'):>4}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Watch RK817 battery and charger telemetry"
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=5.0,
        help="seconds between samples (default: 5)",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="print one sample and exit",
    )
    args = parser.parse_args()
    if args.interval <= 0:
        parser.error("--interval must be greater than zero")

    bat = battery()
    if bat is None:
        print("error: no battery power-supply device found", file=sys.stderr)
        return 1

    _, ntc_configured = battery_temperature(bat)
    if not ntc_configured:
        raw = read_int(bat / "temp")
        detail = (
            f" (driver value {raw}, the RK817 virtual fallback)"
            if raw == VIRTUAL_TEMPERATURE
            else ""
        )
        print(
            "WARNING: battery temperature is unavailable: "
            "the two-wire pack exposes no NTC and the DT has no ntc_table"
            f"{detail}.",
            file=sys.stderr,
        )
        print(
            "Use an external cell thermometer during charger validation.",
            file=sys.stderr,
        )

    print(
        f"{'time':<25} {'capacity':>8} {'voltage_mV':>10} "
        f"{'current_mA':>10} {'bat_C':>10} {'system_max_C':>12} "
        f"{'AC':>4} {'USB':>4}"
    )

    stop = False

    def request_stop(_signum: int, _frame: object) -> None:
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    while not stop:
        print(sample(bat), flush=True)
        if args.once:
            break
        time.sleep(args.interval)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
