"""Execute the native-build batch wrapper, including its failure paths."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / 'apps/mobile/packages/rhttp/cargokit/run_build_tool.cmd'
FLUTTER = Path(os.environ.get('FLUTTER_ROOT', Path.home() / 'flutter'))


@unittest.skipUnless(os.name == 'nt', 'Windows batch execution')
class WindowsRunnerTest(unittest.TestCase):
    def setUp(self) -> None:
        (ROOT / 'build').mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix='cargokit-runner-', dir=ROOT / 'build')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.assertTrue(self.root.is_relative_to((ROOT / 'build').resolve()))
        shutil.copyfile(RUNNER, self.root / RUNNER.name)
        package = self.root / 'build_tool'
        (package / 'lib').mkdir(parents=True)
        (package / 'pubspec.yaml').write_text(
            'name: build_tool\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n', encoding='utf-8')
        self.library = package / 'lib/build_tool.dart'
        self.env = {**os.environ, 'CARGOKIT_TOOL_TEMP_DIR': str(self.root / 'work'),
                    'FLUTTER_ROOT': str(FLUTTER)}

    def run_wrapper(self) -> subprocess.CompletedProcess:
        return subprocess.run(
            ['cmd.exe', '/d', '/c', str(self.root / RUNNER.name), 'fixture'],
            env=self.env, cwd=self.root, capture_output=True, text=True,
            errors='replace', timeout=120)

    def require_dart(self) -> None:
        if not (FLUTTER / 'bin/cache/dart-sdk/bin/dart.exe').is_file():
            self.skipTest('Set FLUTTER_ROOT to an installed Flutter SDK')

    def test_missing_flutter_fails_before_generating_any_files(self) -> None:
        self.env['FLUTTER_ROOT'] = str(self.root / 'missing-flutter')
        result = self.run_wrapper()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'work/pubspec.yaml').exists())

    def test_invalid_temp_directory_fails(self) -> None:
        self.require_dart()
        (self.root / 'not-a-directory').write_text('fixture', encoding='utf-8')
        self.env['CARGOKIT_TOOL_TEMP_DIR'] = str(self.root / 'not-a-directory')
        result = self.run_wrapper()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'pubspec.yaml').exists())

    def test_builder_failure_is_not_changed_to_success(self) -> None:
        self.require_dart()
        self.library.write_text(
            "import 'dart:io';\nvoid runMain(List<String> args) { exit(73); }\n", encoding='utf-8')
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 73, result.stdout + result.stderr)

    def test_kernel_compile_failure_is_propagated(self) -> None:
        self.require_dart()
        self.library.write_text('not valid Dart code', encoding='utf-8')
        result = self.run_wrapper()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'work/bin/build_tool_runner.dill').exists())

    def test_pub_failure_is_propagated_before_compiling(self) -> None:
        self.require_dart()
        (self.root / 'build_tool/pubspec.yaml').write_text(
            'name: build_tool\nenvironment:\n  sdk: ">=999.0.0 <1000.0.0"\n', encoding='utf-8')
        result = self.run_wrapper()
        direct = subprocess.run(
            [str(FLUTTER / 'bin/cache/dart-sdk/bin/dart.exe'), 'pub', 'get', '--no-precompile'],
            cwd=self.root / 'work', capture_output=True, text=True, errors='replace', timeout=30)
        self.assertNotEqual(direct.returncode, 0, f'Dart fixture did not fail: {direct.stdout} {direct.stderr}')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('Compiling bin/build_tool_runner.dart', result.stdout)

    def test_success_is_preserved(self) -> None:
        self.require_dart()
        self.library.write_text('void runMain(List<String> args) {}\n', encoding='utf-8')
        for _ in range(2):
            result = self.run_wrapper()
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_snapshot_retry_propagates_the_retried_failure(self) -> None:
        self.require_dart()
        self.library.write_text(
            "import 'dart:io';\nvoid runMain(List<String> args) {\n"
            " final mark = File('attempted');\n"
            " if (!mark.existsSync()) { mark.writeAsStringSync('1'); exit(253); }\n"
            " exit(74);\n}\n", encoding='utf-8')
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 74, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
