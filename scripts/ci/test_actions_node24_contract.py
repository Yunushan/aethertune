#!/usr/bin/env python3
"""Prevent workflow regressions to GitHub Actions' deprecated Node 20 majors."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = (
    ROOT / ".github" / "workflows" / "aethertune-ci.yml",
    ROOT / ".github" / "workflows" / "aethertune-release.yml",
)


class ActionsNode24ContractTest(unittest.TestCase):
    def test_uses_node24_era_action_pins(self) -> None:
        workflows = "\n".join(
            workflow.read_text(encoding="utf-8") for workflow in WORKFLOWS
        )

        self.assertIn("actions/checkout@v7", workflows)
        self.assertIn("actions/upload-artifact@v7", workflows)
        self.assertIn("actions/download-artifact@v8", workflows)
        self.assertIn("dart-lang/setup-dart@v1.7.2", workflows)
        self.assertNotIn("actions/checkout@v4", workflows)
        self.assertNotIn("actions/upload-artifact@v4", workflows)
        self.assertNotIn("actions/download-artifact@v4", workflows)


if __name__ == "__main__":
    unittest.main()
