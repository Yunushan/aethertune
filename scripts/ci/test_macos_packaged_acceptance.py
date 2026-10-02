#!/usr/bin/env python3
"""Regression tests for read-only candidate and owned-state boundaries."""
from __future__ import annotations

import copy
import hashlib
import os
from pathlib import Path
import stat
import tempfile
import time
import unittest
import warnings
import zipfile

import run_macos_packaged_acceptance as harness


class AcceptanceGuardsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.addCleanup(self.temp.cleanup)

    def archive(self, entries: list[tuple[str, bytes, int]]) -> Path:
        target = self.root / "fixture.zip"
        with zipfile.ZipFile(target, "w") as archive:
            for name, data, mode in entries:
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = mode << 16
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr(entry, data)
        return target

    def candidate(self) -> dict:
        return {"id": int(harness.DEFAULT_RUN), "head_sha": harness.DEFAULT_SOURCE,
                "head_branch": "main", "path": harness.WORKFLOW,
                "event": "workflow_dispatch", "status": "completed",
                "conclusion": "success", "run_attempt": 2,
                "repository": {"full_name": harness.REPO}}

    def certificate(self, ref: str = "refs/heads/main") -> tuple[list, dict]:
        checksums = {f"file{i}.zip": hashlib.sha256(str(i).encode()).hexdigest() for i in range(18)}
        certificate = {
            "subjectAlternativeName": f"https://github.com/{harness.REPO}/{harness.WORKFLOW}@{ref}",
            "buildSignerURI": f"https://github.com/{harness.REPO}/{harness.WORKFLOW}@{ref}",
            "buildSignerDigest": harness.DEFAULT_SOURCE,
            "sourceRepositoryDigest": harness.DEFAULT_SOURCE,
            "sourceRepositoryRef": ref,
            "sourceRepositoryURI": f"https://github.com/{harness.REPO}",
            "issuer": "https://token.actions.githubusercontent.com",
            "runnerEnvironment": "github-hosted",
            "runInvocationURI": f"https://github.com/{harness.REPO}/actions/runs/{harness.DEFAULT_RUN}/attempts/2",
        }
        return [{"verificationResult": {"signature": {"certificate": certificate},
                 "statement": {"subject": [{"name": name, "digest": {"sha256": value}}
                                             for name, value in checksums.items()]}}}], checksums

    def test_host_guard_rejects_personal_self_hosted_and_unscoped_event(self) -> None:
        env = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted",
               "RUNNER_OS": "macOS", "GITHUB_REPOSITORY": harness.REPO,
               "GITHUB_EVENT_NAME": "workflow_dispatch"}
        harness.require_host("darwin", env)
        harness.require_host("darwin", {**env, "GITHUB_EVENT_NAME": "pull_request"})
        for key, value in [("GITHUB_ACTIONS", "false"), ("RUNNER_ENVIRONMENT", "self-hosted"),
                           ("GITHUB_EVENT_NAME", "push"), ("GITHUB_REPOSITORY", "other/repo")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                harness.require_host("darwin", {**env, key: value})
        with self.assertRaises(ValueError):
            harness.require_host("win32", env)

    def test_exact_candidate_attempt_ref_and_source_are_required(self) -> None:
        harness.verify_run(self.candidate(), harness.DEFAULT_RUN, harness.DEFAULT_SOURCE, "refs/heads/main", 2)
        for key, value in [("run_attempt", 1), ("head_sha", "a" * 40), ("head_branch", "other"),
                           ("path", ".github/workflows/other.yml"), ("conclusion", "failure")]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                harness.verify_run({**self.candidate(), key: value}, harness.DEFAULT_RUN,
                                   harness.DEFAULT_SOURCE, "refs/heads/main", 2)

    def test_only_precise_main_or_codex_branch_inputs_are_accepted(self) -> None:
        harness.verify_inputs(harness.DEFAULT_RUN, harness.DEFAULT_SOURCE, "refs/heads/codex/readiness-linux-release", 2)
        for ref in ["main", "refs/tags/v1", "refs/heads/unreviewed", "refs/heads/codex/../main", "refs/heads/codex/a\n"]:
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                harness.verify_inputs(harness.DEFAULT_RUN, harness.DEFAULT_SOURCE, ref, 2)
        with self.assertRaises(ValueError):
            harness.verify_inputs("1;echo unsafe", harness.DEFAULT_SOURCE, "refs/heads/main", 2)

    def test_verified_certificate_must_bind_ref_source_attempt_and_host(self) -> None:
        verified, checksums = self.certificate()
        harness.verify_attestation(verified, harness.DEFAULT_SOURCE, "refs/heads/main", harness.DEFAULT_RUN, 2, checksums)
        for key, value in [("sourceRepositoryRef", "refs/heads/codex/other"), ("buildSignerDigest", "a" * 40),
                           ("sourceRepositoryDigest", "a" * 40), ("runnerEnvironment", "self-hosted"),
                           ("runInvocationURI", f"https://github.com/{harness.REPO}/actions/runs/{harness.DEFAULT_RUN}/attempts/1")]:
            altered = copy.deepcopy(verified)
            altered[0]["verificationResult"]["signature"]["certificate"][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                harness.verify_attestation(altered, harness.DEFAULT_SOURCE, "refs/heads/main", harness.DEFAULT_RUN, 2, checksums)
        branch, checksums = self.certificate("refs/heads/codex/readiness-linux-release")
        harness.verify_attestation(branch, harness.DEFAULT_SOURCE, "refs/heads/codex/readiness-linux-release", harness.DEFAULT_RUN, 2, checksums)

    def test_all_subjects_must_equal_local_bytes_without_duplicates(self) -> None:
        for alteration in ["duplicate", "digest", "missing"]:
            verified, checksums = self.certificate()
            rows = verified[0]["verificationResult"]["statement"]["subject"]
            if alteration == "duplicate":
                rows[-1] = rows[0]
            elif alteration == "digest":
                rows[0]["digest"]["sha256"] = "a" * 64
            else:
                rows.pop()
            with self.subTest(alteration=alteration), self.assertRaises(ValueError):
                harness.verify_attestation(verified, harness.DEFAULT_SOURCE, "refs/heads/main", harness.DEFAULT_RUN, 2, checksums)

    def test_archive_rejects_escape_case_alias_and_duplicate_directories(self) -> None:
        for entries in [
            [("../escaped", b"x", stat.S_IFREG | 0o644)],
            [("aethertune.app/A", b"x", stat.S_IFREG | 0o644), ("aethertune.app/a", b"x", stat.S_IFREG | 0o644)],
            [("aethertune.app/Contents/A", b"x", stat.S_IFREG | 0o644), ("aethertune.app/contents/B", b"x", stat.S_IFREG | 0o644)],
            [("aethertune.app/", b"", stat.S_IFDIR | 0o755), ("aethertune.app/", b"", stat.S_IFDIR | 0o755)],
            [("other.app/file", b"x", stat.S_IFREG | 0o644)],
        ]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                harness.archive_inventory(self.archive(entries), app=True)

    def test_archive_rejects_escaping_links_and_link_descendants(self) -> None:
        for entries in [
            [("aethertune.app/link", b"../../outside", stat.S_IFLNK | 0o777)],
            [("aethertune.app/link", b"/outside", stat.S_IFLNK | 0o777)],
            [("aethertune.app/link", b"target", stat.S_IFLNK | 0o777), ("aethertune.app/link/file", b"x", stat.S_IFREG | 0o644)],
        ]:
            with self.subTest(entries=entries), self.assertRaises(ValueError):
                harness.archive_inventory(self.archive(entries), app=True)

    def test_framework_links_are_preserved_and_payload_tamper_is_rejected(self) -> None:
        records = harness.archive_inventory(self.archive([
            ("aethertune.app/Contents/Frameworks/F.framework/Versions/A/F", b"original", stat.S_IFREG | 0o755),
            ("aethertune.app/Contents/Frameworks/F.framework/Versions/Current", b"A", stat.S_IFLNK | 0o777),
            ("aethertune.app/Contents/Frameworks/F.framework/F", b"Versions/Current/F", stat.S_IFLNK | 0o777),
        ]), app=True)
        extracted = self.root / "extracted"
        for name, record in records.items():
            path = extracted / name
            path.parent.mkdir(parents=True, exist_ok=True)
            if "target" in record:
                try:
                    path.symlink_to(record["target"])
                except OSError as error:
                    if os.name == "nt" and getattr(error, "winerror", None) == 1314:
                        self.skipTest("Windows account cannot create native symlinks; Ubuntu/macOS must execute.")
                    raise
            else:
                path.write_bytes(b"original")
                path.chmod(0o755)
                record["mode"] = path.stat().st_mode
        harness.compare_extracted(extracted, records)
        executable = next(name for name, row in records.items() if "target" not in row)
        (extracted / executable).write_bytes(b"changed")
        with self.assertRaises(ValueError):
            harness.compare_extracted(extracted, records)

    def test_owned_state_cleanup_preserves_preexisting_or_replaced_roots(self) -> None:
        path = self.root / "app-state"
        before = harness.snapshot_paths([path])
        path.mkdir()
        (path / "preferences").write_text("fixture", encoding="utf-8")
        owned = harness.snapshot_paths([path])
        uid = path.stat().st_uid
        with self.assertRaises(ValueError):
            harness.cleanup_paths(owned, owned, uid)
        altered = copy.deepcopy(owned)
        altered[0]["inode"] += 1
        with self.assertRaises(ValueError):
            harness.cleanup_paths(before, altered, uid)
        self.assertTrue((path / "preferences").exists())
        self.assertEqual(harness.cleanup_paths(before, owned, uid), before)

    def test_symlink_state_root_is_never_owned_or_removed(self) -> None:
        target = self.root / "unrelated"
        target.mkdir()
        path = self.root / "app-state"
        try:
            path.symlink_to(target, target_is_directory=True)
        except OSError as error:
            if os.name == "nt" and getattr(error, "winerror", None) == 1314:
                self.skipTest("Windows account cannot create native symlinks; Ubuntu/macOS must execute.")
            raise
        with self.assertRaises(ValueError):
            harness.snapshot_paths([path])
        self.assertTrue(target.exists())

    def test_launch_logs_are_time_bounded_and_match_only_exact_app_or_bundle(self) -> None:
        app = self.root / 'owned "quoted"' / "aethertune.app"
        command = harness.launch_log_arguments(app, 1_700_000_000.1, 1_700_000_045.9)
        self.assertEqual(command[:4], ["/usr/bin/log", "show", "--style", "json"])
        self.assertIn("--start", command)
        self.assertIn("--end", command)
        predicate = command[-1]
        self.assertIn(harness.BUNDLE_ID, predicate)
        self.assertIn('\\"quoted\\"', predicate)
        self.assertNotIn("process ==", predicate)
        self.assertEqual(predicate.count("eventMessage CONTAINS"), 3)
        for started, ended in [(100.0, 99.0), (100.0, 401.0), (0.0, 1.0)]:
            with self.subTest(started=started, ended=ended), self.assertRaises(ValueError):
                harness.launch_log_arguments(app, started, ended)
        with self.assertRaises(ValueError):
            harness.launch_log_arguments(self.root / "newline\n" / "aethertune.app", 100, 101)

    def test_only_new_bounded_app_identified_crash_reports_are_retained(self) -> None:
        reports = self.root / "reports"
        reports.mkdir()
        old = reports / "aethertune-old.ips"
        old.write_text(harness.BUNDLE_ID, encoding="utf-8")
        before = harness.crash_snapshot([reports])
        started = time.time() - 1
        old.write_text(harness.BUNDLE_ID + " changed", encoding="utf-8")
        expected = reports / "aethertune-new.ips"
        expected.write_text(harness.BUNDLE_ID, encoding="utf-8")
        (reports / "other-app.ips").write_text(harness.BUNDLE_ID, encoding="utf-8")
        (reports / "aethertune-unrelated.ips").write_text("unrelated process", encoding="utf-8")
        (reports / "aethertune-oversize.ips").write_bytes(b"x" * (2 * 1024 * 1024 + 1))
        stale = reports / "aethertune-stale.crash"
        stale.write_text(harness.BUNDLE_ID, encoding="utf-8")
        os.utime(stale, (started - 5, started - 5))
        rows = harness.retain_fresh_crashes([reports], before, self.root / "aethertune.app",
                                            started, time.time() + 1, self.root / "retained")
        retained = [row for row in rows if row["retained"]]
        self.assertEqual([row["source"] for row in retained], [str(expected)])
        self.assertEqual(Path(retained[0]["evidence"]).read_bytes(), expected.read_bytes())
        self.assertEqual(retained[0]["sha256"], harness.digest(expected))
        self.assertNotIn(str(old), [row["source"] for row in rows])
        self.assertEqual(len(list((self.root / "retained").iterdir())), 1)

    def test_diagnostic_command_failure_is_retained_without_hiding_crash_evidence(self) -> None:
        evidence = self.root / "evidence"
        evidence.mkdir()
        reports = self.root / "reports"
        reports.mkdir()
        (reports / "aethertune-new.ips").write_text(harness.BUNDLE_ID, encoding="utf-8")
        def denied(_arguments, **_options):
            raise ValueError("read-only log permission denied")
        result = harness.launch_diagnostics(denied, evidence, self.root / "aethertune.app", [reports], {},
                                           time.time() - 1, time.time())
        self.assertIn("permission denied", result["errors"][0])
        self.assertEqual(len([row for row in result["crashReports"] if row["retained"]]), 1)
        self.assertTrue((evidence / "launch-diagnostics.json").is_file())
        self.assertNotIn("status", result)

    def test_scoped_workflow_permissions_fixed_pr_target_and_input_transport(self) -> None:
        workflow = (harness.ROOT / ".github/workflows/macos-packaged-acceptance.yml").read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("pull_request:", workflow)
        self.assertIn("branches: [main]", workflow)
        for trigger in ["push:", "schedule:", "pull_request_target:"]:
            self.assertNotIn(trigger, workflow)
        for permission in ["actions: read", "contents: read", "attestations: read"]:
            self.assertIn(permission, workflow)
        self.assertNotIn(": write", workflow)
        self.assertNotIn("secrets.", workflow)
        self.assertIn(' --source-ref "$CANDIDATE_REF" --candidate-attempt "$CANDIDATE_ATTEMPT"', workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("runs-on: macos-26", workflow)
        self.assertIn("if: ${{ always() }}", workflow)
        paths = workflow.split("    paths:\n", 1)[1].split("  workflow_dispatch:", 1)[0]
        self.assertEqual({line.strip().removeprefix("- '").removesuffix("'") for line in paths.splitlines()}, {
            ".github/workflows/macos-packaged-acceptance.yml", ".github/workflows/aethertune-ci.yml",
            "scripts/ci/run_macos_packaged_acceptance.py", "scripts/ci/macos_packaged_observer.swift",
            "scripts/ci/test_macos_packaged_acceptance.py",
        })
        self.assertIn("github.event.pull_request.head.repo.full_name == github.repository", workflow)
        for key, value in [("candidate_run", harness.DEFAULT_RUN), ("candidate_source", harness.DEFAULT_SOURCE),
                           ("candidate_ref", harness.DEFAULT_REF), ("candidate_attempt", str(harness.DEFAULT_ATTEMPT))]:
            self.assertIn(f"github.event_name == 'workflow_dispatch' && inputs.{key} || '{value}'", workflow)


if __name__ == "__main__":
    unittest.main()
