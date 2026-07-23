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
        self.assertIn("scripts/ci/generate_release_manifest.py", workflow)
        self.assertIn("RELEASE_MANIFEST.json", workflow)
        self.assertIn("sha256sum -- * > SHA256SUMS.txt", workflow)
        self.assertIn("sha256sum --check SHA256SUMS.txt", workflow)
        self.assertIn("scripts/ci/verify_release_manifest.py", workflow)
        self.assertIn("scripts/ci/verify_android_release_artifacts.py", workflow)
        self.assertIn("scripts/ci/package_linux_tarball.sh", workflow)
        self.assertIn("aethertune-linux-x64.tar.gz", workflow)
        self.assertIn("scripts/ci/package_linux_deb.sh", workflow)
        self.assertIn("aethertune-linux-x64.deb", workflow)
        self.assertIn("scripts/ci/package_windows_zip.ps1", workflow)
        self.assertIn("aethertune-windows-x64.zip", workflow)
        self.assertIn("scripts/ci/package_windows_msix.ps1", workflow)
        self.assertIn("aethertune-windows-x64.msix", workflow)
        self.assertIn("scripts/ci/package_macos_zip.sh", workflow)
        self.assertIn("aethertune-macos.zip", workflow)
        self.assertIn("scripts/ci/package_macos_dmg.sh", workflow)
        self.assertIn("aethertune-macos.dmg", workflow)
        self.assertIn("scripts/ci/package_ios_unsigned_zip.sh", workflow)
        self.assertIn("aethertune-ios-unsigned.zip", workflow)
        self.assertIn("scripts/ci/test_server_executable.dart", workflow)
        self.assertIn("name: aethertune-release-bundle", workflow)
        self.assertIn("startsWith(github.ref, 'refs/tags/v')", workflow)
        self.assertIn("contents: write", workflow)
        self.assertIn('gh release create "$RELEASE_TAG" release/*', workflow)
        self.assertIn('gh release upload "$RELEASE_TAG" release/* --clobber', workflow)


if __name__ == "__main__":
    unittest.main()
