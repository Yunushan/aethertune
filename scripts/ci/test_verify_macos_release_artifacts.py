#!/usr/bin/env python3
"""Production receipt consistency tests with synthetic, non-Apple fixtures."""
from __future__ import annotations

import copy
import json
import tempfile
import unittest
import zipfile
import shutil
from pathlib import Path

from macos_signing_contract import bind_app_notarization_input, digest, file_digest, finalize, write_json
from test_macos_signing_contract import BUNDLE, CERTIFICATE, FINGERPRINT, TEAM, write_archive
from verify_macos_release_artifacts import verify_macos_release_artifacts


def write_package_fixture(release_dir: Path) -> dict:
    app = release_dir / "aethertune-macos.zip"
    dmg = release_dir / "aethertune-macos.dmg"
    with tempfile.TemporaryDirectory(dir=release_dir) as temporary:
        submission = Path(temporary) / "aethertune-macos-notarization.zip"
        signing = write_archive(submission)
        signing_path = Path(temporary) / "signing.json"; write_json(signing_path, signing)
        bind_app_notarization_input(submission, signing_path)
        signing = json.loads(signing_path.read_text())
        shutil.copyfile(submission, app)
    # Stapling changes the final packages; their hashes must stay separate from submitted bytes.
    with zipfile.ZipFile(app, "a") as archive:
        archive.writestr("aethertune.app/Contents/stapled-ticket", b"synthetic ticket")
    signed_image = b"synthetic signed DMG fixture"
    dmg.write_bytes(signed_image + b"synthetic stapled ticket")
    app_input = signing["notarization_input_sha256"]
    dmg_input = digest(signed_image)
    return {"schema_version": 2, "app_archive": app.name, "disk_image": dmg.name,
            "app_archive_sha256": file_digest(app), "disk_image_sha256": file_digest(dmg),
            "notarized": True, "stapled": True, "signing": signing,
            "disk_image_signing": {"team_id": TEAM, "identifier": BUNDLE + ".disk-image",
                                   "certificate_sha1": FINGERPRINT, "certificate_sha256": digest(CERTIFICATE),
                                   "signature_verified": True, "notarization_input_sha256": dmg_input},
            "app_notarization": {"artifact": "aethertune-macos-notarization.zip", "input_sha256": app_input,
                                 "submission_id": "12345678-1234-1234-1234-123456789abc", "status": "Accepted",
                                 "log": {"job_id": "12345678-1234-1234-1234-123456789abc", "sha256": app_input,
                                         "status": "Accepted", "archive_filename": "aethertune.app"}},
            "disk_image_notarization": {"artifact": dmg.name, "input_sha256": dmg_input,
                                        "submission_id": "87654321-1234-1234-1234-123456789abc", "status": "Accepted",
                                        "log": {"job_id": "87654321-1234-1234-1234-123456789abc", "sha256": dmg_input,
                                                "status": "Accepted", "archive_filename": dmg.name}}}


def write_receipt(release_dir: Path, evidence: dict) -> None:
    (release_dir / "aethertune-macos-notarization.json").write_text(json.dumps(evidence), encoding="utf-8")


def finalize_fixture(release_dir: Path, evidence: dict) -> None:
    with tempfile.TemporaryDirectory(dir=release_dir) as temporary:
        root = Path(temporary)
        paths = [root / name for name in ("signing.json", "image-signing.json", "app-notary.json", "image-notary.json")]
        for path, field in zip(paths, ("signing", "disk_image_signing", "app_notarization", "disk_image_notarization")):
            write_json(path, evidence[field])
        finalize(release_dir, *paths)


class VerifyMacosReleaseArtifactsTest(unittest.TestCase):
    def test_matching_fixture_is_internally_consistent(self):
        with tempfile.TemporaryDirectory() as temporary:
            release_dir = Path(temporary)
            evidence = write_package_fixture(release_dir)
            self.assertNotEqual(evidence["app_archive_sha256"], evidence["signing"]["notarization_input_sha256"])
            self.assertNotEqual(evidence["disk_image_sha256"], evidence["disk_image_signing"]["notarization_input_sha256"])
            write_receipt(release_dir, evidence)
            verify_macos_release_artifacts(release_dir)
            finalize_fixture(release_dir, evidence)

    def assert_both_gates_reject(self, release_dir: Path, evidence: dict) -> None:
        write_receipt(release_dir, evidence)
        with self.assertRaises(ValueError):
            verify_macos_release_artifacts(release_dir)
        with self.assertRaises(ValueError):
            finalize_fixture(release_dir, evidence)

    def test_paired_notary_input_and_log_hash_mutation_cannot_bypass_independent_signing_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            release_dir = Path(temporary)
            original = write_package_fixture(release_dir)
            before = [file_digest(release_dir / name) for name in ("aethertune-macos.zip", "aethertune-macos.dmg")]
            for fields in (("app_notarization",), ("disk_image_notarization",),
                           ("app_notarization", "disk_image_notarization")):
                candidate = copy.deepcopy(original)
                for field in fields:
                    candidate[field]["input_sha256"] = "a" * 64
                    candidate[field]["log"]["sha256"] = "a" * 64
                with self.subTest(fields=fields):
                    self.assert_both_gates_reject(release_dir, candidate)
            self.assertEqual(before, [file_digest(release_dir / name) for name in ("aethertune-macos.zip", "aethertune-macos.dmg")])

    def test_whole_stale_accepted_receipt_and_missing_or_invalid_independent_binding_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            release_dir = Path(temporary)
            original = write_package_fixture(release_dir)
            for field in ("app_notarization", "disk_image_notarization"):
                candidate = copy.deepcopy(original)
                stale = candidate[field]
                stale["submission_id"] = stale["log"]["job_id"] = "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
                stale["input_sha256"] = stale["log"]["sha256"] = digest(b"different earlier release")
                with self.subTest(stale=field):
                    self.assert_both_gates_reject(release_dir, candidate)
            for field in ("signing", "disk_image_signing"):
                for value in (None, "not-a-digest", 42):
                    candidate = copy.deepcopy(original)
                    if value is None:
                        del candidate[field]["notarization_input_sha256"]
                    else:
                        candidate[field]["notarization_input_sha256"] = value
                    with self.subTest(field=field, value=value):
                        self.assert_both_gates_reject(release_dir, candidate)

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
