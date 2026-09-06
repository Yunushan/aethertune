#!/usr/bin/env python3
"""Verify that production dependency resolution is reproducible."""

from __future__ import annotations

import re
import tomllib
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
    def test_osv_license_policy_is_consistent_and_does_not_allow_nonstandard_licenses(self) -> None:
        policies = []
        for workflow in (OSV_WORKFLOW, OSV_PR_WORKFLOW, OSV_REQUIRED_CONTEXT_WORKFLOW,
                         ROOT / '.github/workflows/aethertune-release.yml'):
            with self.subTest(workflow=workflow):
                matches = re.findall(r'--licenses=([^\s]+)', workflow.read_text(encoding='utf-8'))
                self.assertEqual(len(matches), 1)
                policy = set(matches[0].split(','))
                self.assertTrue({'Apache-2.0', 'Unicode-3.0', 'CDLA-Permissive-2.0'} <= policy)
                self.assertNotIn('non-standard', policy)
                policies.append(policy)
        self.assertTrue(all(policy == policies[0] for policy in policies))

    def test_native_license_metadata_override_is_exact_and_keeps_vulnerability_scanning(self) -> None:
        native = ROOT / 'apps/mobile/packages/rhttp/rust'
        config = tomllib.loads((native / 'osv-scanner.toml').read_text(encoding='utf-8'))
        self.assertEqual(set(config), {'PackageOverrides'})
        self.assertEqual(len(config['PackageOverrides']), 1)
        override = config['PackageOverrides'][0]
        self.assertEqual(set(override), {'name', 'version', 'ecosystem', 'license', 'reason'})
        self.assertEqual(override['name'], 'allo-isolate')
        self.assertEqual(override['version'], '0.1.27')
        self.assertEqual(override['ecosystem'], 'crates.io')
        self.assertEqual(override['license'], {'override': ['Apache-2.0']})
        self.assertTrue(override['reason'])
        lock = tomllib.loads((native / 'Cargo.lock').read_text(encoding='utf-8'))
        versions = [package['version'] for package in lock['package'] if package['name'] == override['name']]
        self.assertEqual(versions, [override['version']], 'Re-review stale license metadata on crate updates')

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
            r"FROM dart:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64} AS build",
        )
        self.assertRegex(
            dockerfile,
            r"FROM gcr.io/distroless/cc-debian13:nonroot@sha256:[0-9a-f]{64}",
        )
        self.assertNotRegex(dockerfile, r"FROM dart:[^@\s]+ AS build")
        self.assertNotRegex(dockerfile, r"FROM gcr.io/distroless/[^@\s]+\n")

    def test_osv_scan_covers_locked_pub_graphs_and_license_policy(self) -> None:
        workflow = OSV_WORKFLOW.read_text(encoding="utf-8")
        reusable_workflow = OSV_REUSABLE_WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn("tags:", workflow)
        self.assertIn("- 'v*'", workflow)
        self.assertIn("pull_request:", workflow)
        self.assertIn("merge_group:", workflow)
        self.assertIn("schedule:", workflow)
        self.assertIn("actions: read", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("security-events: write", workflow)
        self.assertIn(
            "google/osv-scanner-action/osv-scanner-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            workflow,
        )
        self.assertIn(
            "google/osv-scanner-action/osv-reporter-action@8dc09193bb540e09b23da07ad7e30bd33bf87018",
            workflow,
        )
        self.assertIn("runs-on: ubuntu-latest", workflow)
        self.assertIn("Upload to code-scanning", workflow)
        self.assertIn("github/codeql-action/upload-sarif@", workflow)
        self.assertIn("google/osv-scanner-action/osv-scanner-action@", reusable_workflow)
        self.assertIn("--fail-on-vuln=true", workflow)
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
        self.assertNotIn("Upload to code-scanning", reusable_workflow)
        self.assertNotIn("github/codeql-action/upload-sarif@", reusable_workflow)
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
