#!/usr/bin/env python3
"""Regression tests for macOS signing and notarization evidence."""

from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_macos_release_artifacts import verify_macos_release_artifacts


class VerifyMacosReleaseArtifactsTest(unittest.TestCase):
    def test_accepts_signed_archive_and_stapled_attestation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            with zipfile.ZipFile(release_dir / "aethertune-macos.zip", "w") as archive:
                archive.writestr(
                    "aethertune.app/Contents/_CodeSignature/CodeResources",
                    b"signature",
                )
            (release_dir / "aethertune-macos.dmg").write_bytes(b"dmg")
            (release_dir / "aethertune-macos-notarization.json").write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "app_archive": "aethertune-macos.zip",
                        "disk_image": "aethertune-macos.dmg",
                        "notarized": True,
                        "stapled": True,
                    }
                ),
                encoding="utf-8",
            )

            verify_macos_release_artifacts(release_dir)

    def test_rejects_unsigned_archive_or_missing_attestation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            with zipfile.ZipFile(release_dir / "aethertune-macos.zip", "w") as archive:
                archive.writestr("aethertune.app/Contents/Info.plist", b"fixture")
            (release_dir / "aethertune-macos.dmg").write_bytes(b"dmg")

            with self.assertRaisesRegex(ValueError, "code signature"):
                verify_macos_release_artifacts(release_dir)


if __name__ == "__main__":
    unittest.main()
