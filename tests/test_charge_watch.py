#!/usr/bin/python3
"""Regression tests for rk3326-charge-watch."""

from __future__ import annotations

import importlib.util
import pathlib
import tempfile
import unittest


PROJECT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = PROJECT / "hwtest" / "rk3326-charge-watch.py"
SPEC = importlib.util.spec_from_file_location("rk3326_charge_watch", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
charge_watch = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(charge_watch)


class ChargeWatchTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.temporary.name)
        self.power = root / "power_supply"
        self.thermal = root / "thermal"
        self.dt_battery = root / "device-tree" / "battery"
        self.power.mkdir()
        self.thermal.mkdir()
        self.dt_battery.mkdir(parents=True)

        battery = self.power / "battery"
        battery.mkdir()
        self.write(battery / "type", "Battery\n")
        self.write(battery / "capacity", "48\n")
        self.write(battery / "voltage_now", "3903000\n")
        self.write(battery / "current_now", "520000\n")
        self.write(battery / "temp", "188\n")

        mains = self.power / "ac"
        mains.mkdir()
        self.write(mains / "type", "Mains\n")
        self.write(mains / "online", "1\n")

        usb = self.power / "usb"
        usb.mkdir()
        self.write(usb / "type", "USB\n")
        self.write(usb / "online", "0\n")

        zone = self.thermal / "thermal_zone0"
        zone.mkdir()
        self.write(zone / "temp", "55000\n")

        charge_watch.POWER_SUPPLY = self.power
        charge_watch.THERMAL = self.thermal
        charge_watch.DT_BATTERY = self.dt_battery

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @staticmethod
    def write(path: pathlib.Path, value: str) -> None:
        path.write_text(value, encoding="utf-8")

    def test_virtual_188_is_not_reported_as_temperature(self) -> None:
        battery = charge_watch.battery()
        self.assertIsNotNone(battery)
        assert battery is not None
        self.assertEqual(
            charge_watch.battery_temperature(battery),
            ("N/A", False),
        )
        row = charge_watch.sample(battery)
        self.assertIn("N/A", row)
        self.assertIn("3903", row)
        self.assertIn("520", row)
        self.assertIn("55.0", row)

    def test_real_ntc_value_is_reported_when_table_exists(self) -> None:
        battery = charge_watch.battery()
        self.assertIsNotNone(battery)
        assert battery is not None
        self.write(self.dt_battery / "ntc_table", "configured")
        self.write(battery / "temp", "250\n")
        self.assertEqual(
            charge_watch.battery_temperature(battery),
            ("25.0", True),
        )


if __name__ == "__main__":
    unittest.main()
