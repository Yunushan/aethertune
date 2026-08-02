#!/usr/bin/env python3
"""Verify that production dependency resolution is reproducible."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OSV_WORKFLOW = ROOT / ".github" / "workflows" / "osv-scanner.yml"
OSV_PR_WORKFLOW = ROOT / ".github" / "workflows" / "osv-scanner-pr.yml"
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
                line.startswith("    uses: google/osv-scanner-action/")
                for line in osv_job.splitlines()
            )
        )
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn("tags:", workflow)
        self.assertIn("- 'v*'", workflow)
        self.assertIn("schedule:", workflow)
        self.assertIn("actions: read", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("security-events: write", workflow)
        self.assertIn(
            "google/osv-scanner-action/.github/workflows/osv-scanner-reusable.yml@9a498708959aeaef5ef730655706c5a1df1edbc2",
            workflow,
        )
        self.assertIn("fail-on-vuln: true", workflow)
        self.assertIn("--lockfile=./apps/mobile/pubspec.lock", workflow)
        self.assertIn("--lockfile=./services/server/pubspec.lock", workflow)
        self.assertIn("--licenses=", workflow)

    def test_osv_pr_scan_covers_pull_requests_and_merge_queue(self) -> None:
        workflow = OSV_PR_WORKFLOW.read_text(encoding="utf-8")
        osv_job = workflow.split("  osv-scan:\n", 1)[1]
        self.assertTrue(
            any(
                line.startswith("    uses: google/osv-scanner-action/")
                for line in osv_job.splitlines()
            )
        )
        self.assertIn("pull_request:", workflow)
        self.assertIn("merge_group:", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn(
            "google/osv-scanner-action/.github/workflows/osv-scanner-reusable-pr.yml@9a498708959aeaef5ef730655706c5a1df1edbc2",
            workflow,
        )
        self.assertIn("fail-on-vuln: true", workflow)
        self.assertIn("        -r\n        ./", workflow)
        self.assertIn("--allow-no-lockfiles", workflow)
        self.assertIn("--licenses=", workflow)


if __name__ == "__main__":
    unittest.main()
