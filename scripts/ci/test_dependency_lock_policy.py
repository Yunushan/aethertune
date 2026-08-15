#!/usr/bin/env python3
"""Verify that production dependency resolution is reproducible."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OSV_WORKFLOW = ROOT / ".github" / "workflows" / "osv-scanner.yml"
OSV_PR_WORKFLOW = ROOT / ".github" / "workflows" / "osv-scanner-pr.yml"
OSV_REUSABLE_WORKFLOW = ROOT / ".github" / "workflows" / "osv-scan-reusable.yml"
OSV_PR_REUSABLE_WORKFLOW = ROOT / ".github" / "workflows" / "osv-scan-pr-reusable.yml"
OSV_REQUIRED_CONTEXT_WORKFLOW = (
    ROOT / ".github" / "workflows" / "osv-required-context.yml"
)
LOCKFILES = (
    ROOT / "apps" / "mobile" / "pubspec.lock",
    ROOT / "services" / "server" / "pubspec.lock",
)
COMMAND_FILES = (
    ROOT / ".github" / "workflows" / "aethertune-ci.yml",
    ROOT / ".github" / "workflows" / "aethertune-release.yml",
    ROOT / "scripts" / "bootstrap_client.sh",
    ROOT / "scripts" / "check.sh",
    ROOT / "Makefile",
    ROOT / "services" / "server" / "Dockerfile",
)


class DependencyLockPolicyTest(unittest.TestCase):
    def test_application_lockfiles_are_present(self) -> None:
        for lockfile in LOCKFILES:
            with self.subTest(lockfile=lockfile):
                self.assertTrue(lockfile.is_file(), f"missing lockfile: {lockfile}")

    def test_lockfiles_are_not_ignored(self) -> None:
        gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertNotIn("/apps/mobile/pubspec.lock", gitignore)
        self.assertNotIn("/services/server/pubspec.lock", gitignore)

    def test_dependency_commands_enforce_lockfiles(self) -> None:
        for command_file in COMMAND_FILES:
            text = command_file.read_text(encoding="utf-8")
            with self.subTest(command_file=command_file):
                if "flutter pub get" in text:
                    self.assertIn("flutter pub get --enforce-lockfile", text)
                if "dart pub get" in text:
                    self.assertIn("dart pub get --enforce-lockfile", text)

    def test_docker_base_images_are_multiarch_digest_pinned(self) -> None:
        dockerfile = (ROOT / "services" / "server" / "Dockerfile").read_text(
            encoding="utf-8"
        )
        self.assertRegex(
            dockerfile,
            r"FROM dart:3\.12\.2@sha256:[0-9a-f]{64} AS build",
        )
        self.assertRegex(
            dockerfile,
            r"FROM debian:bookworm-slim@sha256:[0-9a-f]{64}",
        )
        self.assertNotIn("FROM dart:3.12.2 AS", dockerfile)
        self.assertNotIn("FROM debian:bookworm-slim\n", dockerfile)

    def test_osv_scan_covers_locked_pub_graphs_and_license_policy(self) -> None:
        workflow = OSV_WORKFLOW.read_text(encoding="utf-8")
        osv_job = workflow.split("  osv-scan:\n", 1)[1]
        self.assertTrue(
            any(
                line == "    uses: ./.github/workflows/osv-scan-reusable.yml"
                for line in osv_job.splitlines()
            )
        )
        reusable_workflow = OSV_REUSABLE_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn("tags:", workflow)
        self.assertIn("- 'v*'", workflow)
        self.assertIn("schedule:", workflow)
        self.assertIn("actions: read", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("security-events: write", workflow)
        self.assertIn(
            "google/osv-scanner-action/osv-scanner-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            reusable_workflow,
        )
        self.assertIn(
            "google/osv-scanner-action/osv-reporter-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            reusable_workflow,
        )
        self.assertIn("fail-on-vuln: true", workflow)
        self.assertIn("--lockfile=./apps/mobile/pubspec.lock", workflow)
        self.assertIn("--lockfile=./services/server/pubspec.lock", workflow)
        self.assertIn("--licenses=", workflow)
        self.assertIn(",UNKNOWN", workflow)

    def test_osv_pr_scan_covers_pull_requests_and_merge_queue(self) -> None:
        workflow = OSV_PR_WORKFLOW.read_text(encoding="utf-8")
        osv_job = workflow.split("  osv-scan:\n", 1)[1]
        self.assertTrue(
            any(
                line == "    uses: ./.github/workflows/osv-scan-pr-reusable.yml"
                for line in osv_job.splitlines()
            )
        )
        reusable_workflow = OSV_PR_REUSABLE_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("pull_request:", workflow)
        self.assertIn("merge_group:", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn(
            "google/osv-scanner-action/osv-scanner-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            reusable_workflow,
        )
        self.assertIn(
            "google/osv-scanner-action/osv-reporter-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            reusable_workflow,
        )
        self.assertIn("fail-on-vuln: true", workflow)
        self.assertIn("        -r\n        ./", workflow)
        self.assertIn("--allow-no-lockfiles", workflow)
        self.assertIn("--licenses=", workflow)
        self.assertIn(",UNKNOWN", workflow)

    def test_legacy_required_osv_context_remains_pinned_and_enforced(self) -> None:
        workflow = OSV_REQUIRED_CONTEXT_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("name: New OSV vulnerabilities and license violations", workflow)
        self.assertIn("pull_request:", workflow)
        self.assertIn("merge_group:", workflow)
        self.assertIn("  osv-scan:\n", workflow)
        self.assertIn(
            "name: New OSV vulnerabilities and license violations / osv-scan",
            workflow,
        )
        self.assertIn(
            "google/osv-scanner-action/osv-scanner-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            workflow,
        )
        self.assertIn(
            "google/osv-scanner-action/osv-reporter-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            workflow,
        )
        self.assertIn("--fail-on-vuln=true", workflow)
        self.assertIn("--licenses=", workflow)


if __name__ == "__main__":
    unittest.main()
