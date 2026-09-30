#!/usr/bin/env python3
"""Negative regressions for the release OSV evidence and policy boundary."""

from __future__ import annotations

import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

from verify_osv_scan import verify_osv_scan
from run_osv_scan import OSV_SCANNER_IMAGE, run_osv_scan


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/osv-scan-reusable.yml"
HELPER = ROOT / "scripts/ci/verify_osv_scan.py"
PACKAGE = {"package": {"name": "example", "version": "1.0.0", "ecosystem": "Pub"}}


def result(package: dict) -> dict:
    return {
        "results": [{"source": {"path": "pubspec.lock", "type": "lockfile"}, "packages": [package]}],
        "experimental_config": {"licenses": {"summary": False, "allowlist": ["MIT"]}},
    }


def vulnerable_package() -> dict:
    package = copy.deepcopy(PACKAGE)
    package["vulnerabilities"] = [{"id": "OSV-TEST-1", "modified": "2026-09-30T00:00:00Z"}]
    package["groups"] = [{"ids": ["OSV-TEST-1"], "aliases": ["OSV-TEST-1"], "max_severity": ""}]
    return package


class VerifyOsvScanTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "results.json"

    def write(self, data: object) -> None:
        self.path.write_text(json.dumps(data), encoding="utf-8")

    def test_success_with_no_findings_is_usable(self) -> None:
        # The scanner builds a non-nil empty results array when no findings exist.
        self.write({"results": []})
        verify_osv_scan(self.path, 0)
        self.write(result(copy.deepcopy(PACKAGE)))
        verify_osv_scan(self.path, 0)

    def test_failure_with_vulnerabilities_reaches_reporter_without_mutation(self) -> None:
        self.write(result(vulnerable_package()))
        before = self.path.read_bytes()
        verify_osv_scan(self.path, 1)
        self.assertEqual(self.path.read_bytes(), before)

    def test_failure_with_license_violations_reaches_reporter(self) -> None:
        package = copy.deepcopy(PACKAGE)
        package.update(licenses=["GPL-3.0"], license_violations=["GPL-3.0"])
        self.write(result(package))
        verify_osv_scan(self.path, 1)

    def test_failed_clean_scan_is_rejected_even_with_parseable_results(self) -> None:
        for data in ({"results": []}, result(copy.deepcopy(PACKAGE))):
            with self.subTest(data=data):
                self.write(data)
                with self.assertRaisesRegex(ValueError, "failed without producing"):
                    verify_osv_scan(self.path, 1)

    def test_runtime_codes_cannot_pass_with_valid_findings(self) -> None:
        self.write(result(vulnerable_package()))
        for exit_code in (2, 125, 127, 128, 129, 130, 137, -9, None, "1"):
            with self.subTest(exit_code=exit_code):
                with self.assertRaisesRegex(ValueError, "scanner failed with exit code"):
                    verify_osv_scan(self.path, exit_code)

    def test_missing_evidence_is_rejected_for_success_and_failure(self) -> None:
        for exit_code in (0, 1):
            with self.subTest(exit_code=exit_code):
                with self.assertRaisesRegex(ValueError, "cannot read scanner results"):
                    verify_osv_scan(self.path, exit_code)

    def test_empty_truncated_and_ambiguous_json_are_rejected(self) -> None:
        for text in ("", '{"results": [', '{"results": []} trailing',
                     '{"results": [], "results": []}', '{"results": [], "unknown": NaN}'):
            with self.subTest(text=text):
                self.path.write_text(text, encoding="utf-8")
                for exit_code in (0, 1):
                    with self.assertRaises(ValueError):
                        verify_osv_scan(self.path, exit_code)

    def test_missing_or_malformed_results_structure_is_rejected(self) -> None:
        for data in ([], {}, {"results": None}, {"results": {}}, {"results": [1]},
                     {"results": [{"source": {}, "packages": []}]},
                     {"results": [{"source": {"path": "x", "type": "lockfile"}, "packages": {}}]}):
            with self.subTest(data=data):
                self.write(data)
                with self.assertRaises(ValueError):
                    verify_osv_scan(self.path, 0)

    def test_malformed_package_and_finding_fields_are_rejected(self) -> None:
        packages = [None, {}, {"package": {"name": 1, "version": "1", "ecosystem": "Pub"}}]
        for field, malformed in (("vulnerabilities", {}), ("vulnerabilities", [None]),
                                 ("vulnerabilities", [{"id": 1}]), ("license_violations", "MIT"),
                                 ("license_violations", [1]), ("groups", [None])):
            package = vulnerable_package()
            package[field] = malformed
            packages.append(package)
        for package in packages:
            with self.subTest(package=package):
                self.write(result(package))
                with self.assertRaises(ValueError):
                    verify_osv_scan(self.path, 1)

    def test_vulnerability_without_reporter_group_is_rejected(self) -> None:
        package = vulnerable_package()
        package["groups"][0]["ids"] = ["different-id"]
        self.write(result(package))
        with self.assertRaisesRegex(ValueError, "has no reporter group"):
            verify_osv_scan(self.path, 1)

    def test_cli_fails_closed_with_an_annotation(self) -> None:
        self.write({"results": []})
        completed = subprocess.run(
            [sys.executable, "-B", str(HELPER), str(self.path), "--exit-code", "1"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(completed.returncode, 1)
        self.assertIn("::error::Unusable OSV scan evidence", completed.stderr)
        self.assertNotIn("evidence is usable", completed.stdout)


class OsvScannerProcessTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="OSV fixture ")
        self.addCleanup(self.temporary.cleanup)
        self.workspace = Path(self.temporary.name)
        self.fake_docker = self.workspace / "fake_docker.py"
        self.fake_docker.write_text(
            "import json, sys\n"
            "from pathlib import Path\n"
            "workspace = Path(sys.argv[1])\n"
            "status, payload = int(sys.argv[2]), sys.argv[3]\n"
            "output = [arg.split('=', 1)[1] for arg in sys.argv[4:] if arg.startswith('--output=')][-1]\n"
            "if (workspace / output).exists() or (workspace / 'results.sarif').exists():\n"
            "    raise SystemExit(254)\n"
            "(workspace / 'invocation.json').write_text(json.dumps(sys.argv[4:]), encoding='utf-8')\n"
            "if payload != 'MISSING':\n"
            "    (workspace / output).write_text(payload, encoding='utf-8')\n"
            "raise SystemExit(status)\n",
            encoding="utf-8",
        )

    def run_scanner(
        self, exit_code: int, payload: str, args: str = "--lockfile=pubspec.lock",
        *, output_name: str = "results.json",
    ) -> None:
        run_osv_scan(
            self.workspace, args, output_name=output_name,
            docker_command=(sys.executable, "-B", str(self.fake_docker),
                            str(self.workspace), str(exit_code), payload),
        )

    def test_actual_subprocess_status_distinguishes_findings_from_partial_crashes(self) -> None:
        payload = json.dumps(result(vulnerable_package()))
        self.run_scanner(1, payload)
        for exit_code in (2, 125, 127, 128, 129, 130, 137):
            with self.subTest(exit_code=exit_code):
                with self.assertRaisesRegex(ValueError, f"exit code {exit_code}"):
                    self.run_scanner(exit_code, payload)

    def test_old_results_are_removed_before_the_scanner_process(self) -> None:
        (self.workspace / "results.json").write_text(json.dumps(result(vulnerable_package())), encoding="utf-8")
        (self.workspace / "results.sarif").write_text("old SARIF", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "cannot read scanner results"):
            self.run_scanner(0, "MISSING")
        self.assertFalse((self.workspace / "results.json").exists())
        self.assertFalse((self.workspace / "results.sarif").exists())

    def test_successful_process_without_valid_evidence_is_rejected(self) -> None:
        for payload in ("MISSING", "", '{"results": ['):
            with self.subTest(payload=payload):
                with self.assertRaises(ValueError):
                    self.run_scanner(0, payload)

    def test_base_and_head_scans_require_their_own_fresh_output(self) -> None:
        payload = json.dumps(result(vulnerable_package()))
        for output in ("old-results.json", "new-results.json"):
            with self.subTest(output=output):
                other = "new-results.json" if output == "old-results.json" else "old-results.json"
                (self.workspace / other).write_text("previous completed scan", encoding="utf-8")
                (self.workspace / output).write_text("checkout-seeded scan", encoding="utf-8")
                self.run_scanner(1, payload, output_name=output)
                self.assertEqual(json.loads((self.workspace / output).read_text()), json.loads(payload))
                self.assertEqual((self.workspace / other).read_text(), "previous completed scan")
                with self.assertRaisesRegex(ValueError, "cannot read scanner results"):
                    self.run_scanner(0, "MISSING", output_name=output)
                self.assertFalse((self.workspace / output).exists())
                self.assertEqual((self.workspace / other).read_text(), "previous completed scan")

    def test_output_name_cannot_escape_or_replace_another_workspace_file(self) -> None:
        results = self.workspace / "results.json"
        results.write_text("existing evidence", encoding="utf-8")
        for output in ("../results.json", "/tmp/results.json", "pubspec.lock", "other.json"):
            with self.subTest(output=output):
                with self.assertRaisesRegex(ValueError, "fixed evidence filenames"):
                    self.run_scanner(0, '{"results": []}', output_name=output)
                self.assertEqual(results.read_text(), "existing evidence")
                self.assertFalse((self.workspace / "invocation.json").exists())

    def test_empty_or_unclosed_arguments_do_not_start_a_process(self) -> None:
        for arguments in ("", '"unclosed'):
            with self.subTest(arguments=arguments):
                with self.assertRaises(ValueError):
                    self.run_scanner(0, '{"results": []}', arguments)
                self.assertFalse((self.workspace / "invocation.json").exists())

    def test_arguments_are_literal_and_binary_entrypoint_and_image_are_fixed(self) -> None:
        self.run_scanner(
            0, '{"results": []}',
            '--lockfile="path with spaces/pubspec.lock"\n--config="$(should-not-run)"\n--output=other.json',
        )
        invocation = json.loads((self.workspace / "invocation.json").read_text(encoding="utf-8"))
        self.assertEqual(invocation[0:4], ["run", "--rm", "--platform", "linux/amd64"])
        image = invocation.index(OSV_SCANNER_IMAGE)
        self.assertEqual(invocation[image - 2:image], ["--entrypoint", "/root/osv-scanner"])
        self.assertIn(f"{self.workspace.resolve()}:/github/workspace", invocation)
        self.assertEqual(invocation[image + 1:], [
            "--lockfile=path with spaces/pubspec.lock", "--config=$(should-not-run)",
            "--output=other.json", "--output=results.json", "--format=json",
        ])
        self.assertNotIn("exit_code_redirect.sh", " ".join(invocation))


class OsvWorkflowContractTest(unittest.TestCase):
    def test_raw_scanner_gate_precedes_reporter_and_is_not_tolerated(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        scan = workflow.index("- name: Run scanner and verify evidence")
        report = workflow.index("- name: Run osv-scanner-reporter")
        self.assertLess(scan, report)
        scanner = workflow[scan:report]
        self.assertIn("OSV_SCAN_ARGS: ${{ inputs.scan-args }}", scanner)
        self.assertIn("python3 scripts/ci/run_osv_scan.py", scanner)
        self.assertNotIn("continue-on-error:", scanner)
        reporter = workflow[report:workflow.index("- name: Upload artifact")]
        self.assertNotIn("continue-on-error:", reporter)
        self.assertNotIn("if:", reporter)
        self.assertIn("--new=results.json", reporter)
        self.assertIn("--fail-on-vuln=${{ inputs.fail-on-vuln }}", reporter)

    def test_all_scanner_routes_use_the_raw_status_and_fresh_evidence_gate(self) -> None:
        workflows = ("osv-scanner.yml", "osv-required-context.yml", "osv-scan-pr-reusable.yml")
        for name in workflows:
            with self.subTest(workflow=name):
                workflow = (ROOT / ".github/workflows" / name).read_text(encoding="utf-8")
                self.assertIn("run_osv_scan.py", workflow)
                self.assertNotIn("continue-on-error:", workflow)
                self.assertNotIn("osv-scanner-action/osv-scanner-action@", workflow)
                self.assertIn("osv-scanner-action/osv-reporter-action@", workflow)
                self.assertIn("--fail-on-vuln=", workflow)
        comparison = (ROOT / ".github/workflows/osv-scan-pr-reusable.yml").read_text(encoding="utf-8")
        self.assertIn("OSV_SCAN_OUTPUT: old-results.json", comparison)
        self.assertIn("OSV_SCAN_OUTPUT: new-results.json", comparison)
        self.assertIn("--old=old-results.json", comparison)
        self.assertIn("--new=new-results.json", comparison)
        self.assertLess(comparison.index("Preserve scanner policy across checkouts"),
                        comparison.index("Checkout target branch"))

    def test_checkout_cannot_replace_scanner_policy_or_completed_base_evidence(self) -> None:
        workflow = (ROOT / ".github/workflows/osv-scan-pr-reusable.yml").read_text(encoding="utf-8")

        def commands(name):
            step = workflow.split("      - name: " + name + "\n", 1)[1].split("      - name:", 1)[0]
            return textwrap.dedent(step.split("        run: |\n", 1)[1]).strip()

        bash = shutil.which("bash")
        git_bash = Path(r"C:\Program Files\Git\bin\bash.exe")
        if os.name == "nt" and git_bash.is_file():
            bash = str(git_bash)
        if not bash:
            self.fail("bash is required for workflow policy retention")
        with tempfile.TemporaryDirectory(prefix="OSV checkout fixture ") as directory:
            fixture = Path(directory)
            workspace = fixture / "checkout"
            policy_source = workspace / "scripts/ci"
            policy_source.mkdir(parents=True)
            expected = {}
            for name in ("run_osv_scan.py", "verify_osv_scan.py"):
                expected[name] = (ROOT / "scripts/ci" / name).read_bytes()
                (policy_source / name).write_bytes(expected[name])
            environment_file = fixture / "environment"
            environment = {**os.environ, "RUNNER_TEMP": fixture.as_posix(),
                           "GITHUB_ENV": environment_file.as_posix()}

            def execute(script):
                subprocess.run([bash, "--noprofile", "--norc", "-c", script],
                               cwd=workspace, env=environment, check=True, capture_output=True, text=True)

            execute(commands("Preserve scanner policy across checkouts"))
            key, value = environment_file.read_text().strip().split("=", 1)
            self.assertEqual(key, "AETHERTUNE_OSV_POLICY_DIR")
            environment[key] = value
            policy = Path(value)
            base_evidence = b"actual completed base scan"
            (workspace / "old-results.json").write_bytes(base_evidence)
            old_commands = commands("Run scanner on existing code and verify evidence")
            execute(next(line for line in old_commands.splitlines() if line.startswith("mv ")))
            # Model a checkout whose source removes the helper and seeds fake scan JSON.
            shutil.rmtree(policy_source)
            (workspace / "old-results.json").write_text("checkout-seeded fake scan", encoding="utf-8")
            new_commands = commands("Run scanner on new code and verify evidence")
            execute(new_commands.split("python3", 1)[0])
            self.assertEqual((workspace / "old-results.json").read_bytes(), base_evidence)
            for name, content in expected.items():
                self.assertEqual((policy / name).read_bytes(), content)
            self.assertIn('python3 "$AETHERTUNE_OSV_POLICY_DIR/run_osv_scan.py"', old_commands)
            self.assertIn('python3 "$AETHERTUNE_OSV_POLICY_DIR/run_osv_scan.py"', new_commands)

            with self.subTest(checkout_seed="old evidence symlink to new evidence"):
                old_results = workspace / "old-results.json"
                new_results = workspace / "new-results.json"
                old_results.unlink()
                seeded_head = b"checkout-seeded current scan"
                new_results.write_bytes(seeded_head)
                try:
                    old_results.symlink_to(new_results.name)
                except OSError as error:
                    if os.name == "nt" and getattr(error, "winerror", None) in {1, 50, 1314}:
                        self.skipTest(f"Windows cannot create a native fixture symlink: {error}")
                    raise
                execute(new_commands.split("python3", 1)[0])
                self.assertFalse(old_results.is_symlink())
                self.assertEqual(old_results.read_bytes(), base_evidence)
                self.assertEqual(new_results.read_bytes(), seeded_head)
                # Model the runner removing its own seeded output and writing
                # a fresh head scan. The old reporter input must stay distinct.
                new_results.unlink()
                completed_head = b"actual completed current scan with new findings"
                new_results.write_bytes(completed_head)
                self.assertEqual(old_results.read_bytes(), base_evidence)
                self.assertEqual(new_results.read_bytes(), completed_head)
                self.assertEqual((policy / "old-results.json").read_bytes(), base_evidence)

    def test_release_requires_the_guarded_workflow_and_failing_policy(self) -> None:
        workflow = (ROOT / ".github/workflows/aethertune-release.yml").read_text(encoding="utf-8")
        osv = re.split(r"(?m)^  [a-z][a-z-]*:$", workflow.split("  osv-scan:\n", 1)[1], maxsplit=1)[0]
        self.assertIn("uses: ./.github/workflows/osv-scan-reusable.yml", osv)
        self.assertIn("fail-on-vuln: true", osv)

    def test_ci_runs_the_negative_evidence_regressions(self) -> None:
        workflow = (ROOT / ".github/workflows/aethertune-ci.yml").read_text(encoding="utf-8")
        provenance = workflow.split("  provenance:\n", 1)[1].split("  flutter:\n", 1)[0]
        self.assertIn("run: python3 scripts/ci/test_verify_osv_scan.py", provenance)


if __name__ == "__main__":
    unittest.main()
