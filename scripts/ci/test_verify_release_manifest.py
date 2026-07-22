#!/usr/bin/env python3
"""Regression checks for release bundle manifest verification."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from generate_release_manifest import ARTIFACT_DETAILS, generate_manifest
from verify_release_manifest import verify_release_manifest


class VerifyReleaseManifestTest(unittest.TestCase):
    def test_accepts_the_exact_generated_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            for name in ARTIFACT_DETAILS:
                (release_dir / name).write_bytes(name.encode("utf-8"))
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            manifest_path.write_text(
                json.dumps(generate_manifest(release_dir, manifest_path)),
                encoding="utf-8",
            )
            (release_dir / "SHA256SUMS.txt").write_text("fixture\n", encoding="utf-8")

            verify_release_manifest(release_dir, manifest_path)

    def test_rejects_a_file_changed_after_manifest_generation(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            artifact = release_dir / "app-release.apk"
            for name in ARTIFACT_DETAILS:
                (release_dir / name).write_bytes(name.encode("utf-8"))
            artifact.write_bytes(b"original")
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            manifest_path.write_text(
                json.dumps(generate_manifest(release_dir, manifest_path)),
                encoding="utf-8",
            )
            artifact.write_bytes(b"changed")

            with self.assertRaisesRegex(ValueError, "digest"):
                verify_release_manifest(release_dir, manifest_path)

    def test_rejects_a_bundle_missing_a_required_release_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            (release_dir / "app-release.apk").write_bytes(b"apk")
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            manifest_path.write_text(
                json.dumps(generate_manifest(release_dir, manifest_path)),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ValueError, "missing required artifacts"):
                verify_release_manifest(release_dir, manifest_path)
