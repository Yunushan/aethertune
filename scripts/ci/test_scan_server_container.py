#!/usr/bin/env python3
"""Regression checks for the container scan policy and required CI/release gates."""

import json
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import scan_server_container as scanner


IMAGE_ID = "sha256:" + "a" * 64


def clean_report():
    return {
        "SchemaVersion": 2,
        "Trivy": {"Version": scanner.TRIVY_VERSION},
        "ArtifactType": "container_image",
        "Metadata": {"ImageID": IMAGE_ID, "OS": {"Family": "debian", "Name": "12"}},
        "Results": [{"Class": "os-pkgs", "Packages": [{"Name": "libc6"}]}],
    }


class ContainerScanTest(unittest.TestCase):
    def test_base_signature_requires_pinned_verifier_and_exact_publisher(self):
        base = scanner.runtime_base_image()
        self.assertRegex(base, r"^gcr.io/distroless/cc-debian13:nonroot@sha256:[0-9a-f]{64}$")
        command = scanner.verification_command("unique", base)
        self.assertIn(scanner.COSIGN_IMAGE, command)
        self.assertEqual(command[command.index("--certificate-identity") + 1],
                         "keyless@distroless.iam.gserviceaccount.com")
        self.assertEqual(command[command.index("--certificate-oidc-issuer") + 1],
                         "https://accounts.google.com")
        for bypass in ("--insecure-ignore-tlog", "--insecure-ignore-sct", "--allow-insecure-registry",
                       "--certificate-identity-regexp", "--mount"):
            self.assertNotIn(bypass, command)

    def test_database_requires_recent_versioned_timestamp(self):
        now = datetime.now(timezone.utc)
        scanner.validate_database({"Version": 2, "UpdatedAt": now.isoformat()}, now)
        for delta in (timedelta(hours=-49), timedelta(minutes=6)):
            with self.subTest(delta=delta), self.assertRaises(ValueError):
                scanner.validate_database({"Version": 2, "UpdatedAt": (now + delta).isoformat()}, now)
        for metadata in ({}, {"Version": 2, "UpdatedAt": "invalid"},
                         {"Version": 2, "UpdatedAt": "2026-09-05T00:00:00"}):
            with self.subTest(metadata=metadata), self.assertRaises(ValueError):
                scanner.validate_database(metadata, now)

    def test_clean_matching_report_passes(self):
        self.assertEqual(scanner.validate_report(clean_report(), IMAGE_ID, 0), [])

    def test_report_must_identify_image_scanner_and_scanned_packages(self):
        changes = [
            ("SchemaVersion", 1), ("ArtifactType", "filesystem"),
            ("Trivy", {"Version": "other"}), ("Results", []),
            ("Results", [{"Class": "os-pkgs"}]),
            ("Metadata", {"ImageID": "sha256:wrong"}),
            ("Metadata", {"ImageID": IMAGE_ID}),
            ("Metadata", {"ImageID": IMAGE_ID, "OS": {"Family": "debian", "Name": "12", "EOSL": True}}),
        ]
        for key, value in changes:
            with self.subTest(key=key, value=value):
                report = clean_report()
                report[key] = value
                with self.assertRaises(ValueError):
                    scanner.validate_report(report, IMAGE_ID, 0)

    def test_scanner_error_cannot_pass_with_clean_report(self):
        for status in (1, 2, 125, -9):
            with self.subTest(status=status), self.assertRaises(ValueError):
                scanner.validate_report(clean_report(), IMAGE_ID, status)

    def test_fixed_and_unfixed_findings_block_even_if_scanner_returns_zero(self):
        for severity in ("HIGH", "CRITICAL"):
            for fixed in (None, "1.2.3"):
                with self.subTest(severity=severity, fixed=fixed):
                    report = clean_report()
                    vulnerability = {"VulnerabilityID": "CVE-test", "Severity": severity}
                    if fixed:
                        vulnerability["FixedVersion"] = fixed
                    report["Results"][0]["Vulnerabilities"] = [vulnerability]
                    for status in (0, 1):
                        findings = scanner.validate_report(report, IMAGE_ID, status)
                        self.assertEqual(len(findings), 1)
                        self.assertEqual(findings[0]["fixed"], fixed)

    def test_scanner_mounts_only_archive_output_and_fresh_cache(self):
        command = scanner.scan_command("unique", Path("image"), Path("output"), Path("cache"))
        self.assertIn("type=bind,src=image,dst=/input,readonly", command)
        self.assertNotIn("docker.sock", " ".join(command))
        self.assertIn("--read-only", command)
        self.assertIn("no-new-privileges=true", command)
        self.assertEqual(command[command.index("--exit-code") + 1], "1")
        self.assertEqual(command[command.index("--exit-on-eol") + 1], "1")
        self.assertEqual(command[command.index("--ignorefile") + 1], "/dev/null")
        self.assertIn(scanner.TRIVY_IMAGE, command)
        for bypass in ("--ignore-unfixed", "--skip-db-update", "--offline-scan", "--insecure"):
            self.assertNotIn(bypass, command)

    def run_fixture(self, root, *, vulnerability=False, scan_status=0, missing_report=False):
        commands = []
        evidence = root / "evidence"

        def fake_run(command, log, timeout=900):
            commands.append(command)
            if command[1] == "build":
                Path(command[command.index("--iidfile") + 1]).write_text(IMAGE_ID)
            if "--input" in command:
                cache = next(Path(value.split(",src=", 1)[1].split(",dst=", 1)[0])
                             for value in command if value.endswith(",dst=/cache"))
                (cache / "db").mkdir()
                (cache / "db/metadata.json").write_text(json.dumps({
                    "Version": 2, "UpdatedAt": datetime.now(timezone.utc).isoformat(),
                }))
                report = clean_report()
                if vulnerability:
                    report["Results"][0]["Vulnerabilities"] = [{"Severity": "CRITICAL"}]
                if not missing_report:
                    (evidence / "trivy.json").write_text(json.dumps(report))
                return scan_status
            if "convert" in command:
                (evidence / "trivy.sarif").write_text(json.dumps({"version": "2.1.0", "runs": [{}]}))
            return 0

        with patch.object(scanner, "run", side_effect=fake_run):
            status = scanner.scan(evidence)
        return status, json.loads((evidence / "summary.json").read_text()), commands

    def test_end_to_end_driver_retains_success_and_failure_evidence(self):
        for options, expected in (({}, 0), ({"vulnerability": True, "scan_status": 1}, 1),
                                  ({"scan_status": 125}, 1), ({"missing_report": True}, 1)):
            with self.subTest(options=options), tempfile.TemporaryDirectory() as directory:
                status, summary, commands = self.run_fixture(Path(directory), **options)
                self.assertEqual(status, expected)
                self.assertEqual(summary["result"], "passed" if expected == 0 else "failed")
                self.assertTrue(any(command[1:3] == ["rm", "--force"] for command in commands))
                self.assertEqual(list(Path(directory).glob(".container-scan-*")), [])

    def test_existing_evidence_is_not_reused(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(scanner, "run") as run:
            with self.assertRaises(FileExistsError):
                scanner.scan(Path(directory))
            run.assert_not_called()

    def test_build_failure_retains_failed_summary(self):
        def fake_run(command, log, timeout=900):
            return 1 if command[1] == "build" else 0

        with tempfile.TemporaryDirectory() as directory, patch.object(scanner, "run", side_effect=fake_run):
            evidence = Path(directory) / "evidence"
            self.assertEqual(scanner.scan(evidence), 1)
            summary = json.loads((evidence / "summary.json").read_text())
            self.assertEqual(summary["result"], "failed")
            self.assertIn("docker build failed", summary["error"])

    def test_invalid_publisher_signature_prevents_build(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"
            with patch.object(scanner, "run", side_effect=lambda command, *_: int("verify" in command)) as run:
                self.assertEqual(scanner.scan(evidence), 1)
            self.assertFalse(any(call.args[0][1] == "build" for call in run.call_args_list))

    def test_successful_cleanup_needs_no_daemon_probe(self):
        with patch.object(scanner, "run", return_value=0) as run, patch.object(scanner.subprocess, "run") as probe:
            scanner.remove_container("unique-fixture", Path("unused.log"))
        run.assert_called_once_with(["docker", "rm", "--force", "unique-fixture"], Path("unused.log"), 60)
        probe.assert_not_called()

    def test_cleanup_accepts_auto_removed_container_only_after_successful_exact_probe(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(scanner, "run", return_value=1):
            with patch.object(scanner.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "", "")) as probe:
                scanner.remove_container("unique-fixture", Path(directory) / "cleanup.log")
        self.assertEqual(probe.call_args.args[0], [
            "docker", "container", "ls", "--all", "--filter", "name=^/unique-fixture$", "--format", "{{.Names}}",
        ])

    def test_cleanup_rejects_running_container_and_unavailable_daemon(self):
        for code, output in ((0, "unique-fixture\n"), (125, "")):
            with self.subTest(code=code), tempfile.TemporaryDirectory() as directory:
                with patch.object(scanner, "run", return_value=1), patch.object(scanner.subprocess, "run",
                        return_value=subprocess.CompletedProcess([], code, output, "cleanup diagnostic")):
                    log = Path(directory) / "cleanup.log"
                    with self.assertRaisesRegex(RuntimeError, "Could not confirm removal"):
                        scanner.remove_container("unique-fixture", log)
                    self.assertIn("cleanup diagnostic", log.read_text())

    def test_cleanup_failure_retains_failed_summary_and_retries_only_owned_container(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(scanner, "run", return_value=0):
            with patch.object(scanner, "remove_container", side_effect=RuntimeError("cleanup failed")) as cleanup:
                evidence = Path(directory) / "evidence"
                self.assertEqual(scanner.scan(evidence), 1)
            summary = json.loads((evidence / "summary.json").read_text())
            self.assertEqual(summary["result"], "failed")
            self.assertIn("cleanup failed", summary["error"])
            self.assertEqual(cleanup.call_count, 2)
            self.assertEqual(cleanup.call_args_list[0].args[0], summary["cleanup_error"])
            self.assertEqual(cleanup.call_args_list[1].args[0], summary["cleanup_error"])

    def test_runtime_failure_cannot_pass_or_start_the_vulnerability_scan(self):
        commands = []

        def fake_run(command, log, timeout=900):
            commands.append(command)
            if command[1] == "build":
                Path(command[command.index("--iidfile") + 1]).write_text(IMAGE_ID)
            return 1 if command[1].endswith("server_container_runtime.py") else 0

        with tempfile.TemporaryDirectory() as directory, patch.object(scanner, "run", side_effect=fake_run):
            evidence = Path(directory) / "evidence"
            self.assertEqual(scanner.scan(evidence), 1)
            self.assertNotIn("runtime_result", json.loads((evidence / "summary.json").read_text()))
        self.assertFalse(any("--input" in command for command in commands))

    def test_timed_out_scanner_removes_only_its_named_container(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"
            commands = []

            def fake_run(command, log, timeout=900):
                commands.append(command)
                if command[1] == "build":
                    Path(command[command.index("--iidfile") + 1]).write_text(IMAGE_ID)
                if "--input" in command:
                    raise subprocess.TimeoutExpired(command, timeout)
                return 0

            with patch.object(scanner, "run", side_effect=fake_run):
                self.assertEqual(scanner.scan(evidence), 1)
            scan = next(command for command in commands if "--input" in command)
            name = scan[scan.index("--name") + 1]
            self.assertIn(["docker", "rm", "--force", name], commands)
            self.assertEqual(list(Path(directory).glob(".container-scan-*")), [])


class ContainerWorkflowTest(unittest.TestCase):
    def test_required_server_job_runs_scan_without_failure_bypass(self):
        workflow = (scanner.ROOT / ".github/workflows/aethertune-ci.yml").read_text()
        server = workflow.split("\n  server:\n", 1)[1]
        self.assertIn("name: Server analyze and test", server)
        step = server.split("      - name: Enforce container vulnerability policy\n", 1)[1].split("      - name:", 1)[0]
        self.assertIn("python3 scripts/ci/scan_server_container.py", step)
        self.assertNotIn("if:", step)
        self.assertNotIn("continue-on-error", server)
        self.assertIn("python3 scripts/ci/test_scan_server_container.py", workflow)

    def test_release_scan_blocks_existing_assembly_dependency(self):
        workflow = (scanner.ROOT / ".github/workflows/aethertune-release.yml").read_text()
        server, assembly = workflow.split("\n  server:\n", 1)[1].split("\n  assemble-release:\n", 1)
        step = server.split("      - name: Enforce container vulnerability policy\n", 1)[1].split("      - name:", 1)[0]
        self.assertIn("if: matrix.label == 'linux-x64'", step)
        self.assertIn("python3 scripts/ci/scan_server_container.py", step)
        self.assertNotIn("continue-on-error", server)
        self.assertIn("needs: [provenance, osv-scan, governance, android, desktop, server]", assembly)
        self.assertIn("always() && matrix.label == 'linux-x64'", server)

    def test_standalone_scan_is_not_report_only_or_event_restricted(self):
        workflow = (scanner.ROOT / ".github/workflows/container-scan.yml").read_text()
        self.assertIn("name: Trivy container scan (fail closed)", workflow)
        self.assertIn("python3 scripts/ci/scan_server_container.py", workflow)
        self.assertNotIn("--exit-code 0", workflow)
        self.assertNotIn("github.event_name ==", workflow)
        self.assertIn("always() && hashFiles(", workflow)


if __name__ == "__main__":
    unittest.main()
