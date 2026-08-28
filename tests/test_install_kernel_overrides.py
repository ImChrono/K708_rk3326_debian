import importlib.util
import pathlib
import tempfile
import unittest


SCRIPT = pathlib.Path(__file__).parents[1] / "scripts" / "install-kernel-overrides.py"
SPEC = importlib.util.spec_from_file_location("install_kernel_overrides", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class InstallKernelOverridesTests(unittest.TestCase):
    def test_patch_driver_is_complete_and_idempotent(self):
        source = (
            "#define GSL9XX_VDDIO_1800\n"
            '#include "rochkchip_gslX680_8inch_800x1280_tg806_10.h"\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            driver = pathlib.Path(directory) / "driver.c"
            driver.write_text(source, encoding="utf-8")

            MODULE.patch_driver(driver)
            patched = driver.read_text(encoding="utf-8")

            self.assertIn(MODULE.VDDIO_DISABLED_MARKER, patched)
            self.assertNotIn(MODULE.VDDIO_DEFINE, patched)
            self.assertIn(f'#include "{MODULE.HEADER_NAME}"', patched)

            MODULE.patch_driver(driver)
            self.assertEqual(driver.read_text(encoding="utf-8"), patched)


if __name__ == "__main__":
    unittest.main()
