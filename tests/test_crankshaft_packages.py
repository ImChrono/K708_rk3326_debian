import hashlib
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-crankshaft-packages.py"
spec = importlib.util.spec_from_file_location("bundle", SCRIPT)
bundle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bundle)


@unittest.skipUnless(shutil.which("dpkg-deb"), "dpkg-deb required")
class BundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "bundle"
        self.bundle.mkdir()
        for name in ("libaasdk", "crankshaft-core", "crankshaft-ui-slim"):
            self.package(name)
        self.checksums()

    def package(self, name, arch="arm64"):
        control = self.root / name / "DEBIAN"
        control.mkdir(parents=True, exist_ok=True)
        (control / "control").write_text(
            f"Package: {name}\nVersion: 1.0\nArchitecture: {arch}\n"
            "Maintainer: Test <test@example.com>\nDescription: fixture\n")
        subprocess.run(["dpkg-deb", "--build", str(control.parent),
                        str(self.bundle / f"{name}.deb")], check=True,
                       stdout=subprocess.DEVNULL)

    def checksums(self):
        (self.bundle / "SHA256SUMS").write_text("".join(
            f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n"
            for p in sorted(self.bundle.glob("*.deb"))))

    def test_valid_arm64_bundle(self):
        bundle.validate(self.bundle)

    def test_wrong_architecture(self):
        self.package("crankshaft-core", "amd64")
        self.checksums()
        with self.assertRaisesRegex(ValueError, "wrong architecture"):
            bundle.validate(self.bundle)

    def test_modified_package(self):
        with (self.bundle / "libaasdk.deb").open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaisesRegex(ValueError, "checksum mismatch"):
            bundle.validate(self.bundle)

    def test_missing_required_package(self):
        (self.bundle / "libaasdk.deb").unlink()
        self.checksums()
        with self.assertRaisesRegex(ValueError, "missing required"):
            bundle.validate(self.bundle)

    def test_unlisted_package(self):
        self.package("extra")
        with self.assertRaisesRegex(ValueError, "cover exactly"):
            bundle.validate(self.bundle)

    def test_path_traversal(self):
        (self.bundle / "SHA256SUMS").write_text("0" * 64 + "  ../escape.deb\n")
        with self.assertRaisesRegex(ValueError, "invalid"):
            bundle.validate(self.bundle)
