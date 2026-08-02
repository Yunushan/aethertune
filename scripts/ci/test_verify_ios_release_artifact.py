#!/usr/bin/env python3
"""Regression tests for signed iOS IPA verification."""

from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_ios_release_artifact import verify_ios_release_artifact


class VerifyIosReleaseArtifactTest(unittest.TestCase):
    def test_accepts_a_signed_flutter_ipa(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            ipa = Path(temporary_directory) / "aethertune.ipa"
            entries = {
                "Payload/Runner.app/Info.plist",
                "Payload/Runner.app/embedded.mobileprovision",
                "Payload/Runner.app/_CodeSignature/CodeResources",
                "Payload/Runner.app/Frameworks/App.framework/flutter_assets/AssetManifest.bin",
            }
            with zipfile.ZipFile(ipa, "w") as archive:
                for entry in entries:
                    archive.writestr(entry, b"fixture")

            verify_ios_release_artifact(ipa)

    def test_rejects_an_unsigned_or_incomplete_ipa(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            ipa = Path(temporary_directory) / "aethertune.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/Runner.app/Info.plist", b"fixture")

            with self.assertRaisesRegex(ValueError, "required signed entries"):
                verify_ios_release_artifact(ipa)


if __name__ == "__main__":
    unittest.main()
