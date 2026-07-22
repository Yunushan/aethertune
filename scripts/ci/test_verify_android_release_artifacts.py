#!/usr/bin/env python3
"""Regression checks for Android release artifact verification."""

from __future__ import annotations

import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_android_release_artifacts import (
    REQUIRED_AAB_ENTRIES,
    REQUIRED_APK_ENTRIES,
    verify_android_release_artifacts,
)


def write_archive(path: Path, entries: frozenset[str]) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        for entry in entries:
            archive.writestr(entry, b"fixture")


class AndroidReleaseArtifactsTest(unittest.TestCase):
    def test_accepts_archives_with_required_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            apk = directory / "app-release.apk"
            aab = directory / "app-release.aab"
            write_archive(apk, REQUIRED_APK_ENTRIES)
            write_archive(aab, REQUIRED_AAB_ENTRIES)

            verify_android_release_artifacts(apk, aab)

    def test_rejects_an_archive_missing_flutter_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            apk = directory / "app-release.apk"
            aab = directory / "app-release.aab"
            write_archive(apk, REQUIRED_APK_ENTRIES)
            write_archive(aab, REQUIRED_AAB_ENTRIES - {"base/assets/flutter_assets/AssetManifest.bin"})

            with self.assertRaisesRegex(ValueError, "AssetManifest.bin"):
                verify_android_release_artifacts(apk, aab)
