#!/usr/bin/env python3
"""Prevent workflow regressions to mutable or deprecated GitHub Actions refs."""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CI_WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-ci.yml"
WORKFLOWS = (
    CI_WORKFLOW,
    ROOT / ".github" / "workflows" / "aethertune-release.yml",
    ROOT / ".github" / "workflows" / "dependency-review.yml",
)
ACTION_REFERENCE = re.compile(
    r"^\s*uses:\s+(?P<action>[^\s#]+)(?:\s+#.*)?$", re.MULTILINE
)
IMMUTABLE_REF = re.compile(r"@[0-9a-f]{40}$")


class ActionsNode24ContractTest(unittest.TestCase):
    def test_all_workflow_actions_are_versioned_or_sha_pinned(self) -> None:
        workflow_dir = ROOT / ".github" / "workflows"
        workflow_text = "\n".join(
            workflow.read_text(encoding="utf-8")
            for workflow in sorted(workflow_dir.glob("*.yml"))
        )

        references = [
            reference
            for reference in ACTION_REFERENCE.findall(workflow_text)
            if not reference.startswith("./")
        ]
        self.assertTrue(references)
        self.assertTrue(
            all(IMMUTABLE_REF.search(reference) for reference in references),
            references,
        )

    def test_uses_node24_era_action_commit_pins(self) -> None:
        workflows = "\n".join(
            workflow.read_text(encoding="utf-8") for workflow in WORKFLOWS
        )

        self.assertIn(
            "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
            workflows,
        )
        self.assertIn(
            "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
            workflows,
        )
        self.assertIn(
            "actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c",
            workflows,
        )
        self.assertIn(
            "actions/dependency-review-action@595b5aeba73380359d98a5e087f648dbb0edce1b",
            workflows,
        )
        self.assertIn(
            "actions/attest@1e69f48acb82d1966a394da916b4c1698aa569d6",
            workflows,
        )
        self.assertIn(
            "dart-lang/setup-dart@7654d458321ee25acccccfdb86cd48bd95768ff1",
            workflows,
        )
        self.assertNotIn("subosito/flutter-action@", workflows)
        self.assertNotIn("actions/checkout@v4", workflows)
        self.assertNotIn("actions/upload-artifact@v4", workflows)
        self.assertNotIn("actions/download-artifact@v4", workflows)

    def test_ci_workflow_has_least_privilege_and_bounded_jobs(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("permissions:\n  contents: read", workflow)
        self.assertIn("concurrency:", workflow)
        self.assertEqual(workflow.count("timeout-minutes:"), 4)
        self.assertEqual(workflow.count("persist-credentials: false"), 4)

    def test_dependency_review_is_pull_request_only_and_bounded(self) -> None:
        workflow = (
            ROOT / ".github" / "workflows" / "dependency-review.yml"
        ).read_text(encoding="utf-8")

        self.assertIn("pull_request:", workflow)
        self.assertIn("branches: [main]", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("timeout-minutes: 15", workflow)
        self.assertIn("fail-on-severity: moderate", workflow)

    def test_security_sensitive_paths_have_code_owner_review(self) -> None:
        codeowners = (ROOT / ".github" / "CODEOWNERS").read_text(encoding="utf-8")
        self.assertIn("* @Yunushan", codeowners)
        self.assertIn("/.github/workflows/ @Yunushan", codeowners)
        self.assertIn("/scripts/ci/ @Yunushan", codeowners)
        self.assertIn("/services/server/deploy/ @Yunushan", codeowners)


if __name__ == "__main__":
    unittest.main()
