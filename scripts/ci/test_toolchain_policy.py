#!/usr/bin/env python3
"""Keep CI and release workflows on the versions used by the lockfiles."""

from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FLUTTER_SETUP_SCRIPT = ROOT / "scripts" / "ci" / "setup_flutter.sh"
FLUTTER_SETUP_SCRIPT_WINDOWS = ROOT / "scripts" / "ci" / "setup_flutter.ps1"
WORKFLOWS = (
    ROOT / ".github" / "workflows" / "aethertune-ci.yml",
    ROOT / ".github" / "workflows" / "aethertune-release.yml",
)
ALL_WORKFLOWS = (
    *WORKFLOWS,
    ROOT / ".github" / "workflows" / "dependency-review.yml",
    ROOT / ".github" / "workflows" / "osv-scanner-pr.yml",
    ROOT / ".github" / "workflows" / "osv-scanner.yml",
    ROOT / ".github" / "workflows" / "governance-audit.yml",
)


def script_reference_exists(path: Path) -> bool:
    if path.suffix:
        return path.is_file()
    return path.is_file() or path.is_dir()


class ToolchainPolicyTest(unittest.TestCase):
    def test_directory_references_do_not_weaken_executable_file_checks(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'probe').mkdir()
            (root / 'not_a_script.py').mkdir()
            (root / 'actual.py').write_text('pass\n')
            self.assertTrue(script_reference_exists(root / 'probe'))
            self.assertTrue(script_reference_exists(root / 'actual.py'))
            self.assertFalse(script_reference_exists(root / 'not_a_script.py'))
            self.assertFalse(script_reference_exists(root / 'missing.py'))
            self.assertFalse(script_reference_exists(root / 'missing'))

    def test_workflow_script_references_exist(self) -> None:
        script_reference = re.compile(
            r"(?<![\w/])(?:\./)?scripts/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*"
        )
        for workflow_path in ALL_WORKFLOWS:
            workflow = workflow_path.read_text(encoding="utf-8")
            for reference in sorted(set(script_reference.findall(workflow))):
                relative_path = reference.removeprefix("./")
                self.assertTrue(
                    script_reference_exists(ROOT / relative_path),
                    f"{workflow_path} references missing script or directory {reference}",
                )

    def test_workflows_pin_flutter_and_dart_versions(self) -> None:
        for workflow_path in WORKFLOWS:
            workflow = workflow_path.read_text(encoding="utf-8")
            self.assertNotIn("channel: stable", workflow, workflow_path)
            self.assertNotIn("sdk: stable", workflow, workflow_path)
            self.assertIn("scripts/ci/setup_flutter.sh", workflow, workflow_path)
            self.assertTrue(
                "scripts/ci/setup_flutter.ps1" in workflow
                or "scripts\\ci\\setup_flutter.ps1" in workflow,
                workflow_path,
            )
            self.assertEqual(1, workflow.count("sdk: '3.12.2'"), workflow_path)
        for setup_script in (
            FLUTTER_SETUP_SCRIPT.read_text(encoding="utf-8"),
            FLUTTER_SETUP_SCRIPT_WINDOWS.read_text(encoding="utf-8"),
        ):
            self.assertIn("3.44.6", setup_script)
            self.assertIn("ee80f08bbf97172ec030b8751ceab557177a34a6", setup_script)

    def test_ci_and_release_verify_dart_formatting(self) -> None:
        command = "dart format --output=none --set-exit-if-changed"
        for workflow_path in WORKFLOWS:
            workflow = workflow_path.read_text(encoding="utf-8")
            self.assertIn(command, workflow, workflow_path)
            for line in workflow.splitlines():
                if "dart format " in line:
                    self.assertIn("apps/mobile/integration_test", line, workflow_path)
            self.assertIn("bash scripts/ci/test_shell_syntax.sh", workflow)
        check_script = (ROOT / "scripts" / "check.sh").read_text(encoding="utf-8")
        self.assertIn(command, check_script)
        self.assertIn(f"{command} lib test integration_test", check_script)
        makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
        self.assertIn("format-check:", makefile)
        self.assertIn(command, makefile)
        for line in makefile.splitlines():
            if "dart format " in line:
                self.assertIn("apps/mobile/integration_test", line)

    def test_flutter_analysis_does_not_fail_on_informational_lints(self) -> None:
        script = (
            ROOT / "scripts" / "ci" / "flutter_analyze_with_annotations.sh"
        ).read_text(encoding="utf-8")
        self.assertIn("flutter analyze --no-fatal-infos", script)
        self.assertIn('command = level == "info" ? "notice" : level', script)
        self.assertIn("awk -F ' • '", script)
        self.assertNotIn("if [[ ${status} -ne 0 ]]", script)

    def test_android_contract_and_wrapper_order_are_explicit(self) -> None:
        workflow = (ROOT / ".github" / "workflows" / "aethertune-ci.yml").read_text(
            encoding="utf-8"
        )
        provenance_job = workflow.split("\n  flutter:", 1)[0]
        flutter_job = workflow.split("\n  flutter:", 1)[1].split(
            "\n  desktop:", 1
        )[0]
        self.assertIn("test_android_signing_contract.py", provenance_job)
        self.assertLess(
            flutter_job.index("run: bash ./scripts/bootstrap_client.sh"),
            flutter_job.index("run: cd apps/mobile && flutter build apk --debug"),
        )
        bootstrap = (ROOT / "scripts" / "bootstrap_client.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("flutter create", bootstrap)
        self.assertIn("--no-pub", bootstrap)
        self.assertIn("restore_manifests()", bootstrap)
        self.assertIn('cp "$APP_DIR/pubspec.lock" "$PRESERVE_DIR/pubspec.lock"', bootstrap)

    def test_governance_audit_is_scheduled_and_fail_closed(self) -> None:
        workflow = (
            ROOT / ".github" / "workflows" / "governance-audit.yml"
        ).read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("cron: '17 4 * * 1'", workflow)
        self.assertIn(
            "if: github.ref == format('refs/heads/{0}', github.event.repository.default_branch)",
            workflow,
        )
        self.assertIn("ref: ${{ github.event.repository.default_branch }}", workflow)
        self.assertIn("AETHERTUNE_GOVERNANCE_TOKEN", workflow)
        self.assertIn("verify_github_governance.py", workflow)

    def test_quick_start_uses_the_canonical_repository(self) -> None:
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("git clone https://github.com/Yunushan/aethertune.git", readme)
        self.assertNotIn("YOUR_NAME/aethertune", readme)

    def test_linux_native_acceptance_is_a_ci_and_release_gate(self) -> None:
        for workflow_path in WORKFLOWS:
            workflow = workflow_path.read_text(encoding="utf-8")
            self.assertIn("run_linux_native_acceptance.sh --evidence build/linux-native-acceptance", workflow)
            self.assertIn("build/linux-native-acceptance/*.json", workflow)
            self.assertIn("build/linux-native-acceptance/*.png", workflow)
            self.assertIn("build-essential", workflow)
            self.assertIn("gnome-keyring", workflow)
            self.assertIn("pulseaudio-utils", workflow)
            step = workflow.split("- name: Verify Linux native startup storage and playback", 1)[1].split("- name:", 1)[0]
            self.assertIn("if: matrix.target == 'linux'", step)
            self.assertNotIn("continue-on-error", step)
        fixture = (ROOT / 'apps/mobile/integration_test/linux_native_acceptance_test.dart').read_text(encoding='utf-8')
        self.assertIn('await app.main()', fixture)
        self.assertIn('isA<FileLibraryStorage>()', fixture)
        self.assertNotIn('setMockInitialValues', fixture)
        self.assertNotIn('libraryStorageFactory =', fixture)
        runner = (ROOT / 'scripts/ci/run_linux_native_acceptance.sh').read_text(encoding='utf-8')
        self.assertIn('for phase in seed migrate reopen', runner)
        self.assertIn('dbus-run-session', runner)
        self.assertIn('module-null-sink', runner)
        self.assertIn('verify_native_audio.py', runner)
        self.assertIn('Evidence destination already exists', runner)


if __name__ == "__main__":
    unittest.main()
