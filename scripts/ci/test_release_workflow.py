#!/usr/bin/env python3
"""Regression checks for the version-tag release publication contract."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-release.yml"


class ReleaseWorkflowTest(unittest.TestCase):
    def test_builds_a_verified_bundle_and_publishes_version_tags(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("uses: actions/download-artifact@v8", workflow)
        self.assertIn("merge-multiple: true", workflow)
        self.assertIn("sha256sum -- * > SHA256SUMS.txt", workflow)
        self.assertIn("scripts/ci/package_linux_deb.sh", workflow)
        self.assertIn("aethertune-linux-x64.deb", workflow)
        self.assertIn("name: aethertune-release-bundle", workflow)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn('gh release create "$RELEASE_TAG" release/*', workflow)
        self.assertIn('gh release upload "$RELEASE_TAG" release/* --clobber', workflow)


if __name__ == "__main__":
    unittest.main()
