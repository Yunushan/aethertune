#!/usr/bin/env python3
"""Guard native transport source builds and dependency scanning."""

from __future__ import annotations

import tempfile
import tomllib
import unittest
from pathlib import Path

from build_native_transport import APP, ROOT, build_commands


class NativeTransportPolicyTest(unittest.TestCase):
    def test_host_build_and_tests_are_version_and_lock_pinned(self) -> None:
        commands = build_commands(APP, install=True, test=True)
        self.assertEqual(commands[0][:4], ["rustup", "toolchain", "install", "1.95.0"])
        for command in commands[1:]:
            self.assertEqual(command[:4], ["rustup", "run", "1.95.0", "cargo"])
            self.assertIn("--locked", command)
            self.assertIn("--release", command)
            self.assertEqual(command[command.index("--target-dir") + 1], str(APP / "rust/target"))
        self.assertEqual(commands[-1][-1], "--lib")

    def test_floating_toolchain_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory)
            (app / "rust-toolchain.toml").write_text('[toolchain]\nchannel = "stable"\n')
            with self.assertRaises(ValueError):
                build_commands(app, install=False, test=False)

    def test_native_lock_has_the_audited_versions(self) -> None:
        lock = tomllib.loads((APP / "packages/rhttp/rust/Cargo.lock").read_text())
        versions = {(entry["name"], entry["version"]) for entry in lock["package"]}
        for entry in [("h2", "0.4.16"), ("quinn-proto", "0.11.15"), ("anyhow", "1.0.103")]:
            self.assertIn(entry, versions)

    def test_platform_builds_and_scanners_include_native_lock(self) -> None:
        config = (APP / "packages/rhttp/rust/cargokit.yaml").read_text()
        for mode in ("debug", "release"):
            self.assertIn(f'{mode}:\n    extra_flags: ["--locked"]', config)
        for workflow in ("osv-scanner.yml", "aethertune-release.yml"):
            text = (ROOT / ".github/workflows" / workflow).read_text()
            self.assertIn("--lockfile=./apps/mobile/packages/rhttp/rust/Cargo.lock", text)

    def test_test_entrypoints_build_the_host_library(self) -> None:
        for path in ("Makefile", "scripts/check.sh", ".github/workflows/aethertune-ci.yml"):
            self.assertIn("build_native_transport.py", (ROOT / path).read_text())

    def test_android_compile_sdk_uses_typed_api_not_display_string(self) -> None:
        plugin = (APP / 'packages/rhttp/cargokit/gradle/plugin.gradle').read_text()
        self.assertIn('compileSdkVersion = plugin.project.android.compileSdk\n', plugin)
        self.assertNotIn('compileSdkVersion.substring', plugin)

    def test_gradle_provides_the_configured_flutter_sdk_to_the_native_builder(self) -> None:
        plugin = (APP / 'packages/rhttp/cargokit/gradle/plugin.gradle').read_text()
        self.assertIn('flutterProperties.load(it)', plugin)
        self.assertIn('plugin.project.findProperty("flutter.sdk")', plugin)
        self.assertIn('flutterRoot = plugin.project.file(flutterSdk).absolutePath', plugin)
        self.assertIn('environment "FLUTTER_ROOT", flutterRoot', plugin)

    def test_ci_checks_android_payload_and_windows_native_failures(self) -> None:
        workflow = (ROOT / '.github/workflows/aethertune-ci.yml').read_text()
        self.assertIn('python scripts/ci/test_cargokit_windows_runner.py', workflow)
        self.assertIn('Verify Android native payload', workflow)
        self.assertIn('--apk apps/mobile/build/app/outputs/flutter-apk/app-debug.apk', workflow)

    def test_linux_acceptance_defines_a_real_unavailable_documents_fixture(self) -> None:
        launcher = (ROOT / 'scripts/ci/run_linux_native_acceptance.sh').read_text()
        self.assertIn('XDG_DOCUMENTS_DIR="$HOME/unavailable-documents"', launcher)
        self.assertIn('> "$fixture/config/user-dirs.dirs"', launcher)
        self.assertIn('> "$fixture/unavailable-documents"', launcher)
        test = (APP / 'integration_test/linux_native_acceptance_test.dart').read_text()
        self.assertIn("expect(documents.path, p.join(home, 'unavailable-documents'))", test)
        self.assertIn('FileSystemEntityType.file', test)
        self.assertIn("find.text('Could not read cache usage.')", test)


if __name__ == "__main__":
    unittest.main()
