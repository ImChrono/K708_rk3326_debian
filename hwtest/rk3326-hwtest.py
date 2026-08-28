#!/usr/bin/python3
"""Full-screen RK3326 bring-up dashboard for tty1."""

from __future__ import annotations

import curses
import json
import pathlib
import select
import time
from collections import deque
from typing import Any

try:
    from evdev import InputDevice, ecodes, list_devices
except ImportError:
    InputDevice = None  # type: ignore[assignment]
    ecodes = None  # type: ignore[assignment]
    list_devices = None  # type: ignore[assignment]


SUMMARY = pathlib.Path("/var/lib/rk3326-hwtest/runs/latest/summary.json")
GRID_COLS = 8
GRID_ROWS = 4


def load_summary() -> dict[str, Any]:
    try:
        return json.loads(SUMMARY.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {"checks": [], "counts": {}}


def open_inputs() -> list[Any]:
    if InputDevice is None or list_devices is None:
        return []
    devices = []
    for path in list_devices():
        try:
            device = InputDevice(path)
            device.grab_context
            devices.append(device)
        except OSError:
            continue
    return devices


def abs_range(device: Any, code: int) -> tuple[int, int] | None:
    try:
        info = device.absinfo(code)
    except (KeyError, OSError):
        return None
    return info.min, info.max


def find_touchscreen(devices: list[Any]) -> tuple[Any, int, int] | None:
    if ecodes is None:
        return None
    for device in devices:
        capabilities = device.capabilities()
        abs_codes = {item[0] if isinstance(item, tuple) else item for item in capabilities.get(ecodes.EV_ABS, [])}
        if ecodes.ABS_MT_POSITION_X in abs_codes and ecodes.ABS_MT_POSITION_Y in abs_codes:
            return device, ecodes.ABS_MT_POSITION_X, ecodes.ABS_MT_POSITION_Y
        if ecodes.ABS_X in abs_codes and ecodes.ABS_Y in abs_codes:
            return device, ecodes.ABS_X, ecodes.ABS_Y
    return None


def safe_addstr(window: Any, row: int, col: int, text: str, attr: int = 0) -> None:
    height, width = window.getmaxyx()
    if row < 0 or row >= height or col >= width:
        return
    try:
        window.addnstr(row, col, text, max(0, width - col - 1), attr)
    except curses.error:
        pass


def draw(
    screen: Any,
    summary: dict[str, Any],
    devices: list[Any],
    touchscreen: tuple[Any, int, int] | None,
    covered: set[tuple[int, int]],
    last_touch: tuple[int, int] | None,
    events: deque[str],
) -> None:
    screen.erase()
    height, width = screen.getmaxyx()
    safe_addstr(
        screen,
        0,
        0,
        "RK3326 HARDWARE TEST  [q quit] [r reset grid] [l reload report]",
        curses.A_BOLD,
    )
    counts = summary.get("counts", {})
    safe_addstr(
        screen,
        1,
        0,
        f'PASS {counts.get("PASS", 0)}  FAIL {counts.get("FAIL", 0)}  '
        f'BLOCKED {counts.get("BLOCKED", 0)}',
    )

    row = 3
    for check in summary.get("checks", []):
        status = check.get("status", "?")
        attr = curses.A_BOLD if status == "FAIL" else 0
        safe_addstr(
            screen,
            row,
            0,
            f'{status:<8} {check.get("id", "?"):<14} {check.get("description", "")}',
            attr,
        )
        row += 1
        if row >= min(height - 10, 14):
            break

    row = max(row + 1, 14)
    safe_addstr(screen, row, 0, "INPUT DEVICES", curses.A_BOLD)
    row += 1
    if not devices:
        safe_addstr(screen, row, 0, "No evdev devices available (python3-evdev missing or no permissions)")
        row += 1
    else:
        names = ", ".join(device.name or device.path for device in devices)
        safe_addstr(screen, row, 0, names)
        row += 1

    safe_addstr(screen, row, 0, "TOUCH COVERAGE", curses.A_BOLD)
    row += 1
    if touchscreen is None:
        safe_addstr(screen, row, 0, "Touchscreen not detected")
        row += 1
    else:
        touch_name = touchscreen[0].name or touchscreen[0].path
        safe_addstr(
            screen,
            row,
            0,
            f"{touch_name}; touch every cell "
            f"({len(covered)}/{GRID_COLS * GRID_ROWS}) raw={last_touch}",
        )
        row += 1
        cell_width = max(3, min(8, (width - 2) // GRID_COLS))
        for grid_row in range(GRID_ROWS):
            line = ""
            for grid_col in range(GRID_COLS):
                mark = "XX" if (grid_col, grid_row) in covered else ".."
                line += mark.center(cell_width)
            safe_addstr(screen, row + grid_row, 0, line)
        row += GRID_ROWS

    safe_addstr(screen, row, 0, "RECENT INPUT EVENTS", curses.A_BOLD)
    row += 1
    for item in list(events)[-max(1, height - row - 1) :]:
        safe_addstr(screen, row, 0, item)
        row += 1
    screen.refresh()


def dashboard(screen: Any) -> None:
    curses.curs_set(0)
    screen.nodelay(True)
    screen.timeout(100)
    summary = load_summary()
    devices = open_inputs()
    touchscreen = find_touchscreen(devices)
    covered: set[tuple[int, int]] = set()
    events: deque[str] = deque(maxlen=12)
    last_touch: tuple[int, int] | None = None
    current_x: int | None = None
    current_y: int | None = None

    touch_ranges = None
    if touchscreen is not None:
        device, x_code, y_code = touchscreen
        x_range = abs_range(device, x_code)
        y_range = abs_range(device, y_code)
        if x_range and y_range:
            touch_ranges = x_range, y_range

    while True:
        draw(screen, summary, devices, touchscreen, covered, last_touch, events)
        key = screen.getch()
        if key in (ord("q"), ord("Q")):
            return
        if key in (ord("r"), ord("R")):
            covered.clear()
        if key in (ord("l"), ord("L")):
            summary = load_summary()

        if not devices:
            time.sleep(0.1)
            continue
        readable, _, _ = select.select(devices, [], [], 0.05)
        for device in readable:
            try:
                device_events = device.read()
            except OSError:
                continue
            for event in device_events:
                if ecodes is None:
                    continue
                if event.type == ecodes.EV_KEY:
                    key_name = ecodes.KEY.get(event.code, str(event.code))
                    events.appendleft(f"{device.name}: {key_name} value={event.value}")
                if touchscreen is None or device.path != touchscreen[0].path:
                    continue
                if event.type == ecodes.EV_ABS:
                    if event.code == touchscreen[1]:
                        current_x = event.value
                    elif event.code == touchscreen[2]:
                        current_y = event.value
                if event.type == ecodes.EV_SYN and event.code == ecodes.SYN_REPORT:
                    if current_x is None or current_y is None or touch_ranges is None:
                        continue
                    last_touch = current_x, current_y
                    (xmin, xmax), (ymin, ymax) = touch_ranges
                    xspan = max(1, xmax - xmin + 1)
                    yspan = max(1, ymax - ymin + 1)
                    grid_x = min(GRID_COLS - 1, max(0, (current_x - xmin) * GRID_COLS // xspan))
                    grid_y = min(GRID_ROWS - 1, max(0, (current_y - ymin) * GRID_ROWS // yspan))
                    covered.add((grid_x, grid_y))


def main() -> int:
    curses.wrapper(dashboard)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
