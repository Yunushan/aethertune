#!/usr/bin/env python3
"""Production receipt consistency tests with synthetic, non-Apple fixtures."""
from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from macos_signing_contract import digest, file_digest
from test_macos_signing_contract import BUNDLE, CERTIFICATE, FINGERPRINT, TEAM, write_archive
from verify_macos_release_artifacts import verify_macos_release_artifacts


def write_package_fixture(release_dir: Path) -> dict:
    app = release_dir / "aethertune-macos.zip"
    dmg = release_dir / "aethertune-macos.dmg"
    signing = write_archive(app)
    dmg.write_bytes(b"synthetic signed/stapled DMG fixture")
    return {"schema_version": 2, "app_archive": app.name, "disk_image": dmg.name,
            "app_archive_sha256": file_digest(app), "disk_image_sha256": file_digest(dmg),
            "notarized": True, "stapled": True, "signing": signing,
            "disk_image_signing": {"team_id": TEAM, "identifier": BUNDLE + ".disk-image",
                                   "certificate_sha1": FINGERPRINT, "certificate_sha256": digest(CERTIFICATE),
                                   "signature_verified": True},
            "app_notarization": {"artifact": "aethertune-macos-notarization.zip", "input_sha256": "1" * 64,
                                 "submission_id": "12345678-1234-1234-1234-123456789abc", "status": "Accepted",
                                 "log": {"job_id": "12345678-1234-1234-1234-123456789abc", "sha256": "1" * 64,
                                         "status": "Accepted", "archive_filename": "aethertune.app"}},
            "disk_image_notarization": {"artifact": dmg.name, "input_sha256": "2" * 64,
                                        "submission_id": "87654321-1234-1234-1234-123456789abc", "status": "Accepted",
                                        "log": {"job_id": "87654321-1234-1234-1234-123456789abc", "sha256": "2" * 64,
                                                "status": "Accepted", "archive_filename": dmg.name}}}


def write_receipt(release_dir: Path, evidence: dict) -> None:
    (release_dir / "aethertune-macos-notarization.json").write_text(json.dumps(evidence), encoding="utf-8")


class VerifyMacosReleaseArtifactsTest(unittest.TestCase):
    def test_matching_fixture_is_internally_consistent(self):
        with tempfile.TemporaryDirectory() as temporary:
            release_dir = Path(temporary)
            write_receipt(release_dir, write_package_fixture(release_dir))
            verify_macos_release_artifacts(release_dir)

    def test_legacy_boolean_only_attestation_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            release_dir = Path(temporary)
            write_package_fixture(release_dir)
            write_receipt(release_dir, {"schema_version": 1, "app_archive": "aethertune-macos.zip",
                                       "disk_image": "aethertune-macos.dmg", "notarized": True, "stapled": True})
            with self.assertRaisesRegex(ValueError, "schema v2"):
                verify_macos_release_artifacts(release_dir)

    def test_missing_receipt_and_changed_packages_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            release_dir = Path(temporary)
            evidence = write_package_fixture(release_dir)
            with self.assertRaisesRegex(ValueError, "receipt"):
                verify_macos_release_artifacts(release_dir)
            write_receipt(release_dir, evidence)
            (release_dir / "aethertune-macos.dmg").write_bytes(b"replacement")
            with self.assertRaisesRegex(ValueError, "package hash"):
                verify_macos_release_artifacts(release_dir)

    def test_receipt_identity_notary_and_capability_tampering_are_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            release_dir = Path(temporary)
            original = write_package_fixture(release_dir)
            changes = [(["disk_image_signing", "team_id"], "OTHERTEAM0"),
                       (["disk_image_signing", "certificate_sha256"], "0" * 64),
                       (["app_notarization", "status"], "Invalid"),
                       (["app_notarization", "submission_id"], "not-a-submission"),
                       (["app_notarization", "log", "sha256"], "0" * 64),
                       (["app_notarization", "log", "job_id"], "87654321-1234-1234-1234-123456789abc"),
                       (["disk_image_notarization", "artifact"], "other.dmg"),
                       (["signing", "native_code_requirement_verified"], False),
                       (["signing", "main_slices", "arm64", "entitlements"], {})]
            for keys, value in changes:
                candidate = copy.deepcopy(original)
                target = candidate
                for key in keys[:-1]:
                    target = target[key]
                target[keys[-1]] = value
                write_receipt(release_dir, candidate)
                with self.subTest(keys=keys), self.assertRaises(ValueError):
                    verify_macos_release_artifacts(release_dir)


if __name__ == "__main__":
    unittest.main()
