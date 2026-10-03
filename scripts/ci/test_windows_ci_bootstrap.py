"""Exercise Windows setup failures and log capture without downloading an SDK.

Fixtures are retained under build for inspection; no recursive cleanup runs.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[2]
SETUP = ROOT / "scripts/ci/setup_flutter.ps1"
BUILD = ROOT / "scripts/ci/build_windows_with_log.ps1"
PIN = "ee80f08bbf97172ec030b8751ceab557177a34a6"
PWSH = shutil.which("pwsh")
FIXTURE_WORKSPACE = Path(os.environ.get("AETHERTUNE_WINDOWS_CI_FIXTURE_WORKSPACE", ROOT)).resolve()
FIXTURES = FIXTURE_WORKSPACE / "build" / f"windows-ci-bootstrap-{uuid.uuid4().hex}"

SETUP_DRIVER = r'''
param([string] $SetupScript, [string] $Fixture, [string] $Failure, [int] $FailureCode)
$ErrorActionPreference = 'Stop'
$env:RUNNER_TEMP = Join-Path $Fixture 'runner temp [literal]'
New-Item -ItemType Directory -Path $env:RUNNER_TEMP -Force | Out-Null
$env:GITHUB_ENV = Join-Path $Fixture 'github-env.txt'
$env:GITHUB_PATH = Join-Path $Fixture 'github-path.txt'
$global:BootstrapMockCalls = [Collections.Generic.List[object]]::new()
$global:BootstrapMockPin = 'ee80f08bbf97172ec030b8751ceab557177a34a6'
$global:BootstrapMockFailureName = $Failure
$global:BootstrapMockFailureNumber = $FailureCode
$sdk = Join-Path $env:RUNNER_TEMP "aethertune-flutter-$global:BootstrapMockPin"
$global:BootstrapMockSdk = $sdk
if ($Failure -eq 'non-git-root') {
    New-Item -ItemType Directory -Path $sdk | Out-Null
    [IO.File]::WriteAllText((Join-Path $sdk 'keep-me.txt'), 'preserve existing SDK root')
}
if ($Failure -eq 'relative-temp') { $env:RUNNER_TEMP = 'relative-runner-temp' }
function git {
    $items = @($args)
    $operation = @('init', 'remote', 'fetch', 'checkout', 'rev-parse') |
        Where-Object { $items -contains $_ } | Select-Object -First 1
    $global:BootstrapMockCalls.Add([ordered]@{ operation = $operation; arguments = $items })
    $global:LASTEXITCODE = if ($operation -eq $global:BootstrapMockFailureName) { $global:BootstrapMockFailureNumber } else { 0 }
    if ($operation -eq 'checkout' -and $global:LASTEXITCODE -eq 0) {
        New-Item -ItemType Directory -Path (Join-Path $global:BootstrapMockSdk 'bin') -Force | Out-Null
        $versionExit = if ($global:BootstrapMockFailureName -eq 'version') { $global:BootstrapMockFailureNumber } else { 0 }
        [IO.File]::WriteAllText((Join-Path $global:BootstrapMockSdk 'bin/flutter.bat'), "@echo off`r`necho synthetic version stub`r`nexit /b $versionExit`r`n")
    }
    if ($operation -eq 'rev-parse') {
        if ($global:BootstrapMockFailureName -eq 'wrong-pin') { '0000000000000000000000000000000000000000' }
        else { $global:BootstrapMockPin }
    }
}
$caught = $null
try { & $SetupScript } catch { $caught = $_.Exception.Message }
$result = [ordered]@{ error = $caught; calls = @($global:BootstrapMockCalls.ToArray());
    githubEnvExists = Test-Path -LiteralPath $env:GITHUB_ENV;
    githubPathExists = Test-Path -LiteralPath $env:GITHUB_PATH;
    sentinelExists = Test-Path -LiteralPath (Join-Path $sdk 'keep-me.txt') }
[IO.File]::WriteAllText((Join-Path $Fixture 'result.json'), ($result | ConvertTo-Json -Depth 8))
'''


@unittest.skipUnless(os.name == "nt" and PWSH, "Windows PowerShell execution")
class WindowsBootstrapTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        assert FIXTURES.resolve().is_relative_to((FIXTURE_WORKSPACE / "build").resolve())
        FIXTURES.mkdir(parents=True, exist_ok=False)
        cls.driver = FIXTURES / "setup-driver.ps1"
        cls.driver.write_text(SETUP_DRIVER, encoding="utf-8")

    def run_setup(self, failure: str, code: int = 73) -> dict:
        fixture = FIXTURES / failure
        fixture.mkdir(exist_ok=False)
        process = subprocess.run(
            [PWSH, "-NoLogo", "-NoProfile", "-File", str(self.driver),
             "-SetupScript", str(SETUP), "-Fixture", str(fixture),
             "-Failure", failure, "-FailureCode", str(code)],
            capture_output=True, text=True, timeout=30,
        )
        (fixture / "driver.stdout").write_text(process.stdout, encoding="utf-8")
        (fixture / "driver.stderr").write_text(process.stderr, encoding="utf-8")
        self.assertEqual(process.returncode, 0, process.stderr)
        return json.loads((fixture / "result.json").read_text(encoding="utf-8"))

    def test_each_git_failure_stops_before_later_commands_or_env_publication(self) -> None:
        operations = ["init", "remote", "fetch", "checkout", "rev-parse"]
        for offset, failure in enumerate(operations):
            with self.subTest(operation=failure):
                code = 71 + offset
                result = self.run_setup(failure, code)
                self.assertIn(f"failed with exit code {code}", result["error"])
                self.assertEqual([x["operation"] for x in result["calls"]], operations[:offset + 1])
                self.assertFalse(result["githubEnvExists"])
                self.assertFalse(result["githubPathExists"])

    def test_version_failure_is_not_published_as_a_valid_sdk(self) -> None:
        result = self.run_setup("version", 79)
        self.assertIn("version check failed with exit code 79", result["error"])
        self.assertFalse(result["githubEnvExists"])
        self.assertFalse(result["githubPathExists"])

    def test_wrong_pin_is_rejected_before_version_bootstrap(self) -> None:
        result = self.run_setup("wrong-pin")
        self.assertIn("Flutter SDK commit mismatch", result["error"])
        self.assertFalse(result["githubEnvExists"])
        self.assertFalse(result["githubPathExists"])

    def test_existing_non_git_root_is_preserved(self) -> None:
        result = self.run_setup("non-git-root")
        self.assertIn("preserving it", result["error"])
        self.assertEqual(result["calls"], [])
        self.assertTrue(result["sentinelExists"])
        sentinel = next((FIXTURES / "non-git-root").rglob("keep-me.txt"))
        self.assertEqual(sentinel.read_text(), "preserve existing SDK root")

    def test_relative_runner_temp_is_rejected_before_writes(self) -> None:
        result = self.run_setup("relative-temp")
        self.assertIn("must be absolute", result["error"])
        self.assertEqual(result["calls"], [])

    def test_success_keeps_pin_and_uses_only_command_scoped_longpaths(self) -> None:
        result = self.run_setup("success")
        self.assertIsNone(result["error"])
        self.assertTrue(result["githubEnvExists"])
        self.assertTrue(result["githubPathExists"])
        checkout = next(x for x in result["calls"] if x["operation"] == "checkout")
        self.assertEqual(checkout["arguments"][:2], ["-c", "core.longpaths=true"])
        self.assertFalse(any("config" in x["arguments"] for x in result["calls"]))

    def test_windows_log_retains_stdout_stderr_and_exact_exit(self) -> None:
        for exit_code in (0, 73):
            with self.subTest(exit_code=exit_code):
                workspace = FIXTURES / f"build-log-{exit_code}"
                (workspace / "scripts/ci").mkdir(parents=True)
                (workspace / "apps/mobile").mkdir(parents=True)
                fake_bin = workspace / "fake-bin"
                fake_bin.mkdir()
                shim = fake_bin / "flutter.cmd"
                shim.write_text(f"@echo off\necho stdout:%*\necho stderr-marker 1>&2\nexit /b {exit_code}\n", encoding="utf-8")
                staged_build = workspace / "scripts/ci/build_windows_with_log.ps1"
                shutil.copyfile(BUILD, staged_build)
                self.assertEqual(hashlib.sha256(BUILD.read_bytes()).digest(), hashlib.sha256(staged_build.read_bytes()).digest())
                environment = {**os.environ, "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"]}
                process = subprocess.run([PWSH, "-NoLogo", "-NoProfile", "-File", str(staged_build)],
                                         env=environment, capture_output=True, text=True, timeout=30)
                self.assertEqual(process.returncode, exit_code, process.stdout + process.stderr)
                log = (workspace / "build/windows-native-build/windows-build.log").read_text(encoding="utf-8-sig")
                self.assertIn("stdout:build windows --debug --verbose", log)
                self.assertIn("stderr-marker", log)

    def test_owned_git_long_path_checkout_with_command_override(self) -> None:
        git_exe = shutil.which("git")
        if not git_exe:
            self.skipTest("Git for Windows is unavailable")
        repository = FIXTURES / "owned-git-longpath"
        repository.mkdir(exist_ok=False)
        relative = "/".join(["fixture-segment-with-long-name"] * 8 + ["fixture.txt"])
        target = repository / relative
        self.assertGreater(len(str(target)), 300)
        content = b"owned long-path checkout fixture"

        def git(*arguments: str, stdin: bytes | None = None) -> subprocess.CompletedProcess:
            result = subprocess.run([git_exe, "-C", str(repository), *arguments], input=stdin,
                                    capture_output=True, timeout=30)
            return result

        self.assertEqual(git("init", "--quiet").returncode, 0)
        before = git("config", "--local", "--get", "core.longpaths")
        self.assertEqual(before.returncode, 1)
        blob = git("hash-object", "-w", "--stdin", stdin=content)
        self.assertEqual(blob.returncode, 0, blob.stderr)
        self.assertEqual(git("update-index", "--add", "--cacheinfo", "100644",
                             blob.stdout.decode().strip(), relative).returncode, 0)
        disabled = git("-c", "core.longpaths=false", "checkout-index", "--all")
        self.assertNotEqual(disabled.returncode, 0)
        self.assertIn(b"Filename too long", disabled.stderr)
        enabled = git("-c", "core.longpaths=true", "checkout-index", "--all")
        self.assertEqual(enabled.returncode, 0, enabled.stderr)
        self.assertEqual(Path("\\\\?\\" + str(target)).read_bytes(), content)
        after = git("config", "--local", "--get", "core.longpaths")
        self.assertEqual(after.returncode, 1)
        observation = {
            "absolutePathLength": len(str(target)), "relativePath": relative,
            "disabledExitCode": disabled.returncode, "disabledStderr": disabled.stderr.decode(),
            "enabledExitCode": enabled.returncode, "enabledStderr": enabled.stderr.decode(),
            "contentSha256": hashlib.sha256(content).hexdigest(),
            "localLongpathsConfigAbsentBeforeAndAfter": True,
            "noUserOrGlobalGitSettingChanged": True, "fixtureRetained": True,
        }
        (repository / "fixture-observation.json").write_text(json.dumps(observation, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    print(f"Retained owned fixtures: {FIXTURES}", flush=True)
    unittest.main(verbosity=2)
