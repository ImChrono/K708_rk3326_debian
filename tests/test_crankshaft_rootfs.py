import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
spec = importlib.util.spec_from_file_location("profile", SCRIPTS / "validate-crankshaft-rootfs.py")
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class RootfsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("usr/bin/crankshaft-core", "usr/bin/crankshaft-ui-slim",
                     "usr/share/rk3326-android-auto/SHA256SUMS",
                     "usr/share/rk3326-android-auto/source-reference.json",
                     "etc/systemd/system/crankshaft-ui-slim.service.d/k708.conf",
                     "var/lib/systemd/linger/crankshaft"):
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        self.units = self.root / "etc/systemd/system"
        for target, unit in (("multi-user.target", "crankshaft-core.service"),
                             ("graphical.target", "crankshaft-ui-slim.service")):
            folder = self.units / f"{target}.wants"
            folder.mkdir()
            (folder / unit).symlink_to(f"/usr/lib/systemd/system/{unit}")
        (self.units / "default.target").symlink_to("/usr/lib/systemd/system/graphical.target")
        (self.units / "getty@tty1.service").symlink_to("/dev/null")
        self.config = self.root / "etc/crankshaft/crankshaft.json"
        self.config.parent.mkdir()
        self.config.write_text(json.dumps({"core": {"android_auto": {"channels": {}},
                                                   "untouched": "value"}}))
        subprocess.run([sys.executable, str(SCRIPTS / "configure-crankshaft.py"),
                        str(self.root)], check=True)

    def test_valid_profile_and_preserved_settings(self):
        profile.validate(self.root)
        self.assertEqual(json.loads(self.config.read_text())["core"]["untouched"], "value")

    def test_competing_dashboard(self):
        (self.units / "multi-user.target.wants/rk3326-hwtest.service").symlink_to("../rk3326-hwtest.service")
        with self.assertRaisesRegex(ValueError, "compete"):
            profile.validate(self.root)

    def test_unvalidated_audio(self):
        data = json.loads(self.config.read_text())
        data["core"]["android_auto"]["channels"]["media_audio_enabled"] = True
        self.config.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "unvalidated"):
            profile.validate(self.root)

    def test_missing_binary(self):
        (self.root / "usr/bin/crankshaft-core").unlink()
        with self.assertRaisesRegex(ValueError, "missing"):
            profile.validate(self.root)
