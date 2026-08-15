#!/usr/bin/env python3
"""Regression checks for production release metadata validation."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from verify_release_metadata import verify_release_metadata


def write_fixture(root: Path, *, version: str = "0.1.0") -> dict[str, Path]:
    paths = {
        "pubspec": root / "pubspec.yaml",
        "changelog": root / "CHANGELOG.md",
        "feature_matrix": root / "FEATURE_MATRIX.md",
        "license": root / "LICENSE",
        "notice": root / "NOTICE",
    }
    paths["pubspec"].write_text(
        f"name: fixture\nversion: {version}+1\n", encoding="utf-8"
    )
    paths["changelog"].write_text(
        f"# Changelog\n\n## Unreleased\n\n- pending\n\n## {version}\n\n- shipped\n",
        encoding="utf-8",
    )
    paths["feature_matrix"].write_text(
        "| Feature | Status |\n| --- | --- |\n", encoding="utf-8"
    )
    paths["license"].write_text("BSD Zero Clause License\n", encoding="utf-8")
    paths["notice"].write_text("AetherTune\n", encoding="utf-8")
    return paths


def verify_fixture(paths: dict[str, Path], tag: str | None) -> None:
    verify_release_metadata(
        tag=tag,
        **{f"{key}_path": value for key, value in paths.items()},
    )


class VerifyReleaseMetadataTest(unittest.TestCase):
    def test_accepts_matching_tag_and_required_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            paths = write_fixture(Path(temporary_directory))
            verify_fixture(paths, "v0.1.0")

    def test_accepts_manual_production_metadata_with_unreleased_notes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            paths = write_fixture(Path(temporary_directory))
            verify_fixture(paths, None)

    def test_rejects_tag_without_matching_changelog_section(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            paths = write_fixture(Path(temporary_directory))
            paths["changelog"].write_text(
                "# Changelog\n\n## Unreleased\n\n- pending\n", encoding="utf-8"
            )
            with self.assertRaisesRegex(ValueError, "no non-empty 0.1.0 section"):
                verify_fixture(paths, "v0.1.0")

    def test_rejects_missing_legal_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            paths = write_fixture(Path(temporary_directory))
            paths["license"].write_text("MIT\n", encoding="utf-8")
            paths["notice"].write_text("Third party\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "BSD Zero Clause.*NOTICE"):
                verify_fixture(paths, "v0.1.0")


if __name__ == "__main__":
    unittest.main()
