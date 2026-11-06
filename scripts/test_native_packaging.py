#!/usr/bin/env python3
"""Packaging failure boundaries; no real builds, disks or existing apps touched."""
import os
from pathlib import Path
import plistlib
import subprocess
import shutil
import time
import tempfile
import unittest
from unittest.mock import patch

from verify_native_binary import verify

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/package_dmg.sh"
with (ROOT / "Packaging/Info.plist").open("rb") as file:
    VERSION = plistlib.load(file)["CFBundleShortVersionString"]


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.fixture = tempfile.TemporaryDirectory(prefix="ShotMap packaging fixture ")
        self.addCleanup(self.fixture.cleanup)
        self.project = Path(self.fixture.name)
        (self.project / "scripts").mkdir()
        (self.project / "Packaging").mkdir()
        self.script = self.project / "scripts/package_dmg.sh"
        shutil.copyfile(SCRIPT, self.script)
        shutil.copyfile(ROOT / "Packaging/Info.plist", self.project / "Packaging/Info.plist")

    def run_packager(self, directory, *args, env=None):
        return subprocess.run(["/bin/bash", str(self.script), "--output-dir", str(directory), *args],
                              capture_output=True, text=True, env=env, timeout=15)

    def test_invalid_architecture_fails_before_creating_artifacts(self):
        with tempfile.TemporaryDirectory() as root:
            destination = Path(root) / "output"
            result = self.run_packager(destination, "--arch", "amd64")
            self.assertEqual(result.returncode, 2)
            self.assertFalse(destination.exists())

    def test_all_preflight_rejects_existing_intel_before_building_arm(self):
        with tempfile.TemporaryDirectory(prefix="ShotMap packaging test ") as root:
            existing = Path(root) / f"ShotMap-{VERSION}-x86_64"
            existing.mkdir()
            sentinel = existing / "keep.txt"
            sentinel.write_text("keep")
            result = self.run_packager(root, "--preflight-only")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(sentinel.read_text(), "keep")
            self.assertEqual(list(Path(root).iterdir()), [existing])

    def test_dangling_destination_and_output_symlinks_are_not_followed(self):
        with tempfile.TemporaryDirectory() as root:
            existing = Path(root) / f"ShotMap-{VERSION}-arm64"
            existing.symlink_to(Path(root) / "missing")
            self.assertNotEqual(self.run_packager(root, "--arch", "arm64", "--preflight-only").returncode, 0)
            self.assertTrue(existing.is_symlink())
            link = Path(root) / "output-link"
            link.symlink_to(Path(root) / "missing-output")
            self.assertNotEqual(self.run_packager(link, "--preflight-only").returncode, 0)
            self.assertFalse((Path(root) / "missing-output").exists())

    def test_failed_stage_creation_never_starts_a_build(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            tools = root / "tools"
            tools.mkdir()
            for name, body in {
                "mktemp": "exit 73\n",
                "swift": 'printf continued > "$QA_CONTINUED"\nexit 74\n',
            }.items():
                command = tools / name
                command.write_text("#!/bin/sh\n" + body)
                command.chmod(0o755)
            marker = root / "continued"
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", QA_CONTINUED=str(marker))
            result = self.run_packager(root / "output", "--arch", "arm64", env=env)
            self.assertEqual(result.returncode, 73, result.stderr)
            self.assertFalse(marker.exists(), "No path derived from an empty stage may be used")

    def test_failed_binary_location_does_not_copy_from_a_root_path(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            tools = root / "tools"
            tools.mkdir()
            for name, body in {
                "swift": 'case "$*" in *--show-bin-path*) exit 74 ;; *) exit 0 ;; esac\n',
                "ditto": 'printf copied > "$QA_CONTINUED"\nexit 76\n',
            }.items():
                command = tools / name
                command.write_text("#!/bin/sh\n" + body)
                command.chmod(0o755)
            marker = root / "continued"
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}", QA_CONTINUED=str(marker))
            result = self.run_packager(root / "output", "--arch", "arm64", env=env)
            self.assertEqual(result.returncode, 74, result.stderr)
            self.assertFalse(marker.exists(), "A failed bin-path lookup must not attempt /ShotMap")
            self.assertEqual(list((root / "output").iterdir()), [])

    def test_concurrent_architectures_do_not_share_a_mutating_tool_environment(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            tools = root / "tools"
            tools.mkdir()
            swift = tools / "swift"
            swift.write_text('''#!/bin/sh
printf '%s\n' "$$" >> "$QA_STARTED"
while [ ! -e "$QA_RELEASE" ]; do /bin/sleep 0.01; done
exit 73
''')
            swift.chmod(0o755)
            marker, release = root / "started", root / "release"
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       QA_STARTED=str(marker), QA_RELEASE=str(release))
            first = subprocess.Popen(["/bin/bash", str(self.script), "--output-dir", str(root / "output"),
                                      "--arch", "arm64"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, env=env)
            try:
                deadline = time.monotonic() + 5
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(marker.exists(), "First build must hold the packaging lock")
                second = self.run_packager(root / "output", "--arch", "x86_64", env=env)
                self.assertEqual(second.returncode, 75, second.stderr)
                self.assertEqual(len(marker.read_text().splitlines()), 1)
            finally:
                release.touch()
                _, errors = first.communicate(timeout=10)
            self.assertEqual(first.returncode, 73, errors)
            self.assertFalse((self.project / ".build/package-dmg.lock").exists())
            self.assertEqual(list((root / "output").iterdir()), [])

    def test_termination_releases_only_the_owned_lock_and_stage(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            tools = root / "tools"
            tools.mkdir()
            swift = tools / "swift"
            swift.write_text('''#!/bin/sh
printf ready > "$QA_STARTED"
while [ ! -e "$QA_RELEASE" ]; do /bin/sleep 0.01; done
exit 0
''')
            swift.chmod(0o755)
            marker, release = root / "started", root / "release"
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       QA_STARTED=str(marker), QA_RELEASE=str(release))
            process = subprocess.Popen(["/bin/bash", str(self.script), "--output-dir", str(root / "output"),
                                        "--arch", "arm64"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       text=True, env=env)
            try:
                deadline = time.monotonic() + 5
                while not marker.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(marker.exists())
                process.terminate()
            finally:
                release.touch()
                _, errors = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 143, errors)
            self.assertFalse((self.project / ".build/package-dmg.lock").exists())
            self.assertEqual(list((root / "output").iterdir()), [])

    def test_missing_version_fails_before_output_or_lock_creation(self):
        info = self.project / "Packaging/Info.plist"
        metadata = plistlib.loads(info.read_bytes())
        del metadata["CFBundleShortVersionString"]
        info.write_bytes(plistlib.dumps(metadata))
        with tempfile.TemporaryDirectory() as root:
            destination = Path(root) / "output"
            result = self.run_packager(destination, "--preflight-only")
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(destination.exists())
            self.assertFalse((self.project / ".build").exists())

    def test_raised_launchservices_target_is_rejected_before_build(self):
        info = self.project / "Packaging/Info.plist"
        metadata = plistlib.loads(info.read_bytes())
        metadata["LSMinimumSystemVersion"] = "27.0"
        info.write_bytes(plistlib.dumps(metadata))
        with tempfile.TemporaryDirectory() as root:
            destination = Path(root) / "output"
            result = self.run_packager(destination, "--preflight-only")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Packaging/Info.plist", result.stderr)
            self.assertFalse(destination.exists())
            self.assertFalse((self.project / ".build").exists())

    def test_existing_lock_is_not_removed_by_another_invocation(self):
        lock = self.project / ".build/package-dmg.lock"
        lock.mkdir(parents=True)
        (lock / "pid").write_text("12345\n")
        with tempfile.TemporaryDirectory() as root:
            result = self.run_packager(root, "--arch", "arm64")
            self.assertEqual(result.returncode, 75)
            self.assertEqual((lock / "pid").read_text(), "12345\n")

    def test_failed_build_cleans_only_its_owned_stage(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            tools = root / "tools"
            tools.mkdir()
            swift = tools / "swift"
            swift.write_text("#!/bin/sh\nexit 73\n")
            swift.chmod(0o755)
            destination = root / "output"
            destination.mkdir()
            sentinel = destination / "existing-old.dmg"
            sentinel.write_text("keep")
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}")
            result = self.run_packager(destination, "--arch", "arm64", env=env)
            self.assertEqual(result.returncode, 73, result.stderr)
            self.assertEqual(list(destination.iterdir()), [sentinel])
            self.assertEqual(sentinel.read_text(), "keep")


class BinaryVerificationTests(unittest.TestCase):
    def tool_output(self, *command):
        if "lipo" in command:
            return "arm64"
        if "otool" in command:
            return "cmd LC_BUILD_VERSION\nminos 13.0\nsdk 27.1"
        return "UUID: 1234-ABCD (arm64) artifact"

    def test_correct_native_binary_and_symbols(self):
        with patch("verify_native_binary.output", side_effect=self.tool_output):
            verify("binary", "arm64", "symbols")

    def test_universal_binary_cannot_be_mislabeled_native(self):
        with patch("verify_native_binary.output", return_value="arm64 x86_64"):
            with self.assertRaisesRegex(ValueError, "Expected"):
                verify("binary", "arm64")

    def test_unintentionally_raised_deployment_target_is_rejected(self):
        def output(*command):
            return "arm64" if "lipo" in command else "cmd LC_BUILD_VERSION\nminos 27.0"
        with patch("verify_native_binary.output", side_effect=output):
            with self.assertRaisesRegex(ValueError, "macOS 13.0"):
                verify("binary", "arm64")

    def test_mismatched_symbols_are_rejected(self):
        def output(*command):
            if command[-1] == "symbols":
                return "UUID: 5678-ABCD (arm64) symbols"
            return self.tool_output(*command)
        with patch("verify_native_binary.output", side_effect=output):
            with self.assertRaisesRegex(ValueError, "dSYM"):
                verify("binary", "arm64", "symbols")


if __name__ == "__main__":
    unittest.main()
