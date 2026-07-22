#!/usr/bin/env python3
"""Regression checks for the release artifact manifest generator."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from generate_release_manifest import generate_manifest


class ReleaseManifestTest(unittest.TestCase):
    def test_records_known_artifacts_and_provenance_deterministically(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            apk = release_dir / "app-release.apk"
            apk.write_bytes(b"android release")
            ios_archive = release_dir / "aethertune-ios-unsigned.zip"
            ios_archive.write_bytes(b"ios unsigned archive")
            sbom = release_dir / "aethertune-server.cdx.json"
            sbom.write_text("{}", encoding="utf-8")
            output = release_dir / "RELEASE_MANIFEST.json"

            manifest = generate_manifest(release_dir, output)
            output.write_text(
                json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
            )

            self.assertEqual(1, manifest["schema_version"])
            self.assertEqual(
                [
                    {
                        "file": "aethertune-ios-unsigned.zip",
                        "kind": "unsigned-app-archive",
                        "platform": "ios",
                        "sha256": hashlib.sha256(b"ios unsigned archive").hexdigest(),
                        "size_bytes": len(b"ios unsigned archive"),
                    },
                    {
                        "file": "aethertune-server.cdx.json",
                        "kind": "cyclonedx-sbom",
                        "platform": "provenance",
                        "sha256": hashlib.sha256(b"{}").hexdigest(),
                        "size_bytes": 2,
                    },
                    {
                        "file": "app-release.apk",
                        "kind": "apk",
                        "platform": "android",
                        "sha256": hashlib.sha256(b"android release").hexdigest(),
                        "size_bytes": len(b"android release"),
                    },
                ],
                manifest["artifacts"],
            )
            self.assertNotIn("RELEASE_MANIFEST.json", output.read_text(encoding="utf-8"))
