#!/usr/bin/env python3
"""Regression checks for desktop packaging proof steps in CI."""

from __future__ import annotations

import unittest
from pathlib import Path


WORKFLOW = (
    Path(__file__).resolve().parents[2]
    / ".github"
    / "workflows"
    / "aethertune-ci.yml"
)


class DesktopPackagingWorkflowTest(unittest.TestCase):
    def test_windows_ci_keeps_the_msix_package_and_install_proofs(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("scripts/ci/test_package_windows_zip.ps1", workflow)
        self.assertIn("scripts/ci/test_package_windows_msix.ps1", workflow)
        self.assertIn("scripts/ci/test_install_windows_msix.ps1", workflow)


if __name__ == "__main__":
    unittest.main()
