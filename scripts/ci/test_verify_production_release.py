#!/usr/bin/env python3
"""Regression checks for the production release fail-closed policy."""

from __future__ import annotations

import json
import hashlib
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from generate_release_manifest import generate_manifest
from verify_production_release import (
    PRODUCTION_ARTIFACTS,
    verify_checksum_sidecar,
    verify_production_release,
)


def write_checksum_sidecar(release_dir: Path, names: set[str]) -> None:
    checksummed = set(names) | {"RELEASE_MANIFEST.json"}
    lines = []
    for name in sorted(checksummed):
        digest = hashlib.sha256((release_dir / name).read_bytes()).hexdigest()
        lines.append(f"{digest}  {name}")
    (release_dir / "SHA256SUMS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


class VerifyProductionReleaseTest(unittest.TestCase):
    def test_rejects_a_stale_checksum_sidecar(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            (release_dir / "fixture.bin").write_bytes(b"original")
            (release_dir / "RELEASE_MANIFEST.json").write_bytes(b"manifest")
            write_checksum_sidecar(release_dir, {"fixture.bin"})
            (release_dir / "fixture.bin").write_bytes(b"changed")

            with self.assertRaisesRegex(ValueError, "checksum does not match"):
                verify_checksum_sidecar(release_dir, {"fixture.bin"})

    def test_rejects_the_current_unsigned_release_bundle(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            for name in (
                "app-release.aab",
                "app-release.apk",
                "aethertune-ios-unsigned.zip",
                "aethertune-linux-x64.deb",
                "aethertune-linux-x64.tar.gz",
                "aethertune-macos.dmg",
                "aethertune-macos.zip",
                "aethertune-server-linux-x64",
                "aethertune-server-macos",
                "aethertune-server-windows-x64.exe",
                "aethertune-windows-x64.msix",
                "aethertune-windows-x64.zip",
            ):
                if name.endswith(".msix"):
                    with zipfile.ZipFile(release_dir / name, "w") as archive:
                        archive.writestr("AppxManifest.xml", b"fixture")
                else:
                    (release_dir / name).write_bytes(name.encode("utf-8"))
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            manifest_path.write_text(
                json.dumps(generate_manifest(release_dir, manifest_path)),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "unsigned or debug"):
                verify_production_release(release_dir, manifest_path)

    def test_accepts_a_manifest_without_nonproduction_markers(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            for name in PRODUCTION_ARTIFACTS:
                if name.endswith(".msix"):
                    with zipfile.ZipFile(release_dir / name, "w") as archive:
                        archive.writestr("AppxSignature.p7x", b"signature")
                else:
                    (release_dir / name).write_bytes(name.encode("utf-8"))
            manifest_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifacts": [{"file": name, "kind": "verified"} for name in PRODUCTION_ARTIFACTS],
                    }
                ),
                encoding="utf-8",
            )
            write_checksum_sidecar(release_dir, set(PRODUCTION_ARTIFACTS))

            with patch("verify_production_release.verify_release_manifest"), patch(
                "verify_production_release.verify_android_release_artifacts"
            ), patch("verify_production_release.verify_ios_release_artifact"), patch(
                "verify_production_release.verify_macos_release_artifacts"
            ), patch("verify_production_release.verify_windows_release_artifacts"):
                verify_production_release(release_dir, manifest_path)

    def test_rejects_an_unreviewed_extra_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            (release_dir / "unreviewed.bin").write_bytes(b"fixture")
            manifest_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifacts": [{"file": "unreviewed.bin", "kind": "supporting-file"}],
                    }
                ),
                encoding="utf-8",
            )

            with patch("verify_production_release.verify_release_manifest"):
                with self.assertRaisesRegex(ValueError, "artifact set is not exact"):
                    verify_production_release(release_dir, manifest_path)

    def test_rejects_an_unsigned_msix_even_without_a_filename_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            msix = release_dir / "aethertune-windows-x64.msix"
            with zipfile.ZipFile(msix, "w") as archive:
                archive.writestr("AppxManifest.xml", b"fixture")
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifacts": [
                            {"file": msix.name, "kind": "msix-installer"},
                        ],
                    }
                ),
                encoding="utf-8",
            )

            with patch("verify_production_release.verify_release_manifest"):
                with self.assertRaisesRegex(ValueError, "AppxSignature.p7x"):
                    verify_production_release(release_dir, manifest_path)

    def test_rechecks_the_windows_portable_signature(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            release_dir = Path(temporary_directory)
            portable = release_dir / "aethertune-windows-x64.zip"
            msix = release_dir / "aethertune-windows-x64.msix"
            with zipfile.ZipFile(portable, "w") as archive:
                archive.writestr("aethertune.exe", b"MZ")
            with zipfile.ZipFile(msix, "w") as archive:
                archive.writestr("AppxSignature.p7x", b"signature")
            manifest_path = release_dir / "RELEASE_MANIFEST.json"
            for name in PRODUCTION_ARTIFACTS - {portable.name, msix.name}:
                (release_dir / name).write_bytes(name.encode("utf-8"))
            manifest_path.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "artifacts": [
                            {"file": name, "kind": "verified"}
                            for name in PRODUCTION_ARTIFACTS
                        ],
                    }
                ),
                encoding="utf-8",
            )
            write_checksum_sidecar(release_dir, set(PRODUCTION_ARTIFACTS))

            with patch("verify_production_release.verify_release_manifest"), patch(
                "verify_production_release.verify_android_release_artifacts"
            ), patch("verify_production_release.verify_ios_release_artifact"), patch(
                "verify_production_release.verify_macos_release_artifacts"
            ):
                with self.assertRaisesRegex(ValueError, "Authenticode"):
                    verify_production_release(release_dir, manifest_path)


if __name__ == "__main__":
    unittest.main()
