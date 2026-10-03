#!/usr/bin/env python3
"""Policy/orchestration fixtures; these do not prove Apple profile authorization."""
from __future__ import annotations

import copy
import hashlib
import json
import plistlib
import subprocess
import struct
import stat
import sys
import tempfile
import unittest
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

import macos_signing_contract as contract

TEAM = "ABCDEFGHIJ"
BUNDLE = "dev.aethertune.aethertune"
CERTIFICATE = b"fixture-public-certificate-not-an-Apple-identity"
FINGERPRINT = hashlib.sha1(CERTIFICATE).hexdigest()
PROFILE = b"fixture-CMS-bytes-not-an-Apple-profile"
MAGIC = bytes.fromhex("cffaedfe")
APPLEDOUBLE = (struct.pack(">II16sH", 0x00051607, 0x00020000, b"\0" * 16, 1)
               + struct.pack(">III", 9, 38, 4) + b"data")


def profile() -> dict:
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    return {
        "ExpirationDate": now + timedelta(days=30), "CreationDate": now - timedelta(days=1),
        "TeamIdentifier": [TEAM], "ApplicationIdentifierPrefix": [TEAM],
        "ProvisionsAllDevices": True, "Platform": ["OSX"],
        "DeveloperCertificates": [CERTIFICATE],
        "Entitlements": {contract.TEAM_ID: TEAM, contract.APP_ID: f"{TEAM}.{BUNDLE}",
                         contract.GROUPS: [f"{TEAM}.*"]},
    }


def policy() -> dict:
    return {**contract.CAPABILITIES, contract.GROUPS: []}


def slice_receipt(entitlements: dict) -> dict:
    return {"entitlements": entitlements, "team_id": TEAM, "certificate_sha1": FINGERPRINT,
            "certificate_sha256": contract.digest(CERTIFICATE)}


def signing_receipt(main: bytes, library: bytes) -> dict:
    decoded = plistlib.dumps(profile()).decode()
    expected = contract.validate_profile(plistlib.loads(decoded.encode()), TEAM, BUNDLE, FINGERPRINT, policy())
    return {
        "schema_version": 1, "team_id": TEAM, "bundle_id": BUNDLE, "certificate_sha1": FINGERPRINT,
        "profile": {"decoded_plist": decoded, "sha256": contract.digest(PROFILE),
                    "reviewed_sha256": contract.digest(PROFILE), "metadata_is_supplementary": True},
        "main_executable": "Contents/MacOS/aethertune", "main_sha256": contract.digest(main),
        "main_slices": {arch: slice_receipt(expected) for arch in contract.ARCHES},
        "libraries": {"Contents/Frameworks/App.framework/Versions/A/App": {
            "sha256": contract.digest(library),
            "slices": {arch: slice_receipt({}) for arch in contract.ARCHES}}},
        "release_policy": policy(), "native_code_requirement_verified": True,
    }


def write_archive(path: Path, *, main: bytes = MAGIC + b"main", library: bytes = MAGIC + b"library",
                  embedded: bytes | None = PROFILE) -> dict:
    signing = signing_receipt(main, library)
    with zipfile.ZipFile(path, "w") as archive:
        root = "aethertune.app/"
        archive.writestr(root + "Contents/Info.plist", plistlib.dumps({
            "CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "aethertune"}))
        archive.writestr(root + "Contents/_CodeSignature/CodeResources", b"fixture signature")
        archive.writestr(root + signing["main_executable"], main)
        archive.writestr(root + "Contents/Frameworks/App.framework/Versions/A/App", library)
        if embedded is not None:
            archive.writestr(root + "Contents/embedded.provisionprofile", embedded)
        archive.writestr("__MACOSX/._aethertune.app", APPLEDOUBLE)
    return signing


class ProfilePolicyTest(unittest.TestCase):
    def test_matching_profile_retains_sandbox_network_files_and_data_protection_keychain(self):
        actual = contract.validate_profile(profile(), TEAM, BUNDLE, FINGERPRINT, policy())
        self.assertEqual(actual, {**contract.CAPABILITIES, contract.APP_ID: f"{TEAM}.{BUNDLE}",
                                  contract.TEAM_ID: TEAM, contract.GROUPS: [f"{TEAM}.{BUNDLE}"]})

    def test_missing_expired_foreign_and_debug_profiles_are_rejected(self):
        variants = [({}, "expiration"), ({"ExpirationDate": datetime(2000, 1, 1)}, "expired"),
                    ({"TeamIdentifier": ["OTHERTEAM0"]}, "different team"),
                    ({"DeveloperCertificates": [b"wrong cert"]}, "not authorized"),
                    ({"ProvisionsAllDevices": False}, "Developer ID"),
                    ({"Platform": ["iOS"]}, "not macOS")]
        for changes, message in variants:
            candidate = profile() if changes else {}
            candidate.update(changes)
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, message):
                contract.validate_profile(candidate, TEAM, BUNDLE, FINGERPRINT, policy())
        for field, value in ((contract.APP_ID, "ABCDEFGHIJ.other.app"),
                             (contract.GROUPS, []), ("get-task-allow", True),
                             ("com.apple.security.get-task-allow", True)):
            candidate = profile()
            candidate["Entitlements"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                contract.validate_profile(candidate, TEAM, BUNDLE, FINGERPRINT, policy())

    def test_unexpected_debug_and_omitted_release_capabilities_are_rejected(self):
        for key in policy():
            candidate = policy()
            del candidate[key]
            with self.subTest(omitted=key), self.assertRaisesRegex(ValueError, "omitted"):
                contract.validate_profile(profile(), TEAM, BUNDLE, FINGERPRINT, candidate)
        candidate = policy()
        candidate["com.apple.security.get-task-allow"] = False
        with self.assertRaisesRegex(ValueError, "unexpected/debug"):
            contract.validate_profile(profile(), TEAM, BUNDLE, FINGERPRINT, candidate)

    def test_reviewed_input_hash_rejects_missing_malformed_or_changed_bytes(self):
        contract.validate_profile_input(PROFILE, contract.digest(PROFILE))
        for fingerprint in ("", "g" * 64, "0" * 64):
            with self.subTest(fingerprint=fingerprint), self.assertRaises(ValueError):
                contract.validate_profile_input(PROFILE, fingerprint)


class ArchiveBindingTest(unittest.TestCase):
    def test_matching_fixture_is_internally_consistent(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            signing = write_archive(path)
            contract.validate_archive(path, signing)

    def test_foreign_or_invalid_appledouble_metadata_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            for name, data in (("__MACOSX/._other.app", APPLEDOUBLE),
                               ("__MACOSX/aethertune.app/Contents/._Info.plist", b"bad magic"),
                               ("__MACOSX/aethertune.app/Contents/payload", b"arbitrary"),
                               ("__MACOSX/aethertune.app/Contents/._Info.plist", bytes.fromhex("00051607")),
                               ("__MACOSX/aethertune.app/Contents/._Info.plist", APPLEDOUBLE[:30]),
                               ("__MACOSX/aethertune.app/Contents/._Info.plist", APPLEDOUBLE[:30] + b"\xff" * 8)):
                signing = write_archive(path)
                with zipfile.ZipFile(path, "a") as archive:
                    archive.writestr(name, data)
                with self.subTest(name=name), self.assertRaises(ValueError):
                    contract.validate_archive(path, signing)

    def test_dot_and_repeated_separator_aliases_cannot_replace_recorded_executable(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            for name in ("aethertune.app/Contents/./MacOS/aethertune",
                         "aethertune.app/Contents//MacOS/aethertune"):
                signing = write_archive(path)
                with zipfile.ZipFile(path, "a") as archive:
                    archive.writestr(name, b"replacement non-Mach-O bytes")
                with self.subTest(name=name), self.assertRaisesRegex(ValueError, "noncanonical"):
                    contract.validate_archive(path, signing)

    def test_case_and_unicode_aliases_cannot_shadow_app_paths_on_macos_filesystems(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            signing = write_archive(path)
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr("aethertune.app/Contents/MacOS/AETHERTUNE", b"replacement")
            with self.assertRaisesRegex(ValueError, "alias collision"):
                contract.validate_archive(path, signing)
            signing = write_archive(path)
            with zipfile.ZipFile(path, "a") as archive:
                archive.writestr("aethertune.app/Contents/Resources/caf\u00e9.txt", b"first")
                archive.writestr("aethertune.app/Contents/Resources/cafe\u0301.txt", b"replacement")
            with self.assertRaisesRegex(ValueError, "alias collision"):
                contract.validate_archive(path, signing)

    def test_escaping_or_parent_symlinks_rejected_and_framework_alias_supported(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            for name, target in (("aethertune.app/Contents/MacOS", "../../../../outside-bundle"),
                                 ("aethertune.app/Contents/MacOS", "Frameworks"),
                                 ("aethertune.app/Contents/alias", "/outside-bundle")):
                signing = write_archive(path)
                with zipfile.ZipFile(path, "a") as archive:
                    entry = zipfile.ZipInfo(name); entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, target.encode())
                with self.subTest(name=name, target=target), self.assertRaisesRegex(ValueError, "symlink"):
                    contract.validate_archive(path, signing)
            signing = write_archive(path)
            with zipfile.ZipFile(path, "a") as archive:
                entry = zipfile.ZipInfo("aethertune.app/Contents/Frameworks/App.framework/Versions/Current")
                entry.create_system = 3; entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, b"A")
            contract.validate_archive(path, signing)

    def test_indirect_parent_traversal_symlink_escape_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            signing = write_archive(path)
            with zipfile.ZipFile(path, "a") as archive:
                for name, target in (("aethertune.app/Contents/A", ".."),
                                     ("aethertune.app/Contents/B", "A/../../outside-bundle")):
                    entry = zipfile.ZipInfo(name); entry.create_system = 3
                    entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                    archive.writestr(entry, target.encode())
            with self.assertRaisesRegex(ValueError, "parent traversal"):
                contract.validate_archive(path, signing)

    def test_embedded_profile_required_and_bound(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            for embedded in (None, b"substituted profile"):
                signing = write_archive(path, embedded=embedded)
                with self.subTest(embedded=embedded), self.assertRaisesRegex(ValueError, "profile"):
                    contract.validate_archive(path, signing)

    def test_main_library_slice_entitlement_certificate_team_tampering_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            original = write_archive(path)
            variants = []
            changed = copy.deepcopy(original); changed["main_sha256"] = "0" * 64; variants.append(changed)
            changed = copy.deepcopy(original); changed["libraries"] = {}; variants.append(changed)
            changed = copy.deepcopy(original); del changed["main_slices"]["arm64"]; variants.append(changed)
            for key, value in (("entitlements", {}), ("certificate_sha256", "0" * 64),
                               ("team_id", "OTHERTEAM0")):
                changed = copy.deepcopy(original)
                changed["main_slices"]["arm64"][key] = value
                variants.append(changed)
            changed = copy.deepcopy(original)
            next(iter(changed["libraries"].values()))["slices"]["arm64"]["entitlements"] = policy()
            variants.append(changed)
            for changed in variants:
                with self.subTest(receipt=changed), self.assertRaises(ValueError):
                    contract.validate_archive(path, changed)


class SigningOrderTest(unittest.TestCase):
    def make_app(self, root: Path) -> tuple[Path, Path, Path]:
        app = root / "aethertune.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/MacOS/aethertune").write_bytes(MAGIC + b"main")
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "aethertune"}))
        framework = app / "Contents/Frameworks/App.framework"
        framework.mkdir(parents=True)
        (framework / "App").write_bytes(MAGIC + b"library")
        (framework / "nested.dylib").write_bytes(MAGIC + b"nested")
        input_profile = root / "input.provisionprofile"; input_profile.write_bytes(PROFILE)
        release = root / "release.entitlements"; release.write_bytes(plistlib.dumps(policy()))
        return app, input_profile, release

    def test_rejections_happen_before_any_codesign_mutation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, input_profile, release = self.make_app(root)
            for input_hash, decoded in (("0" * 64, profile()), (contract.digest(PROFILE), {})):
                calls = []
                def fake(args, **kwargs):
                    calls.append(args)
                    if args[:2] == ["/usr/bin/security", "find-identity"]:
                        return f'1) {FINGERPRINT} "Developer ID Application: Fixture ({TEAM})"'.encode()
                    if args[:3] == ["/usr/bin/security", "cms", "-D"]:
                        return plistlib.dumps(decoded)
                    raise AssertionError(f"unexpected command {args}")
                with patch.object(contract.sys, "platform", "darwin"), patch.object(contract, "command", fake):
                    with self.assertRaises(ValueError):
                        contract.sign(app, f"Developer ID Application: Fixture ({TEAM})", input_profile,
                                      release, TEAM, BUNDLE, input_hash, "fixture-keychain", root / "receipt.json")
                self.assertFalse(any(args[0] == "/usr/bin/codesign" for args in calls))
                self.assertFalse((app / "Contents/embedded.provisionprofile").exists())

    def test_nested_code_signed_inside_out_without_entitlements_and_main_explicitly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app, input_profile, release = self.make_app(root)
            calls = []
            expected = contract.validate_profile(profile(), TEAM, BUNDLE, FINGERPRINT, policy())
            def fake(args, **kwargs):
                calls.append(args)
                if args[:2] == ["/usr/bin/security", "find-identity"]:
                    return f'1) {FINGERPRINT} "Developer ID Application: Fixture ({TEAM})"'.encode()
                if args[:3] == ["/usr/bin/security", "cms", "-D"]:
                    return plistlib.dumps(profile())
                if args[0] == "/usr/bin/file":
                    return b"Mach-O universal dynamically linked shared library"
                if args[0] == "/usr/bin/lipo":
                    return b"x86_64 arm64"
                extraction = next((arg for arg in args if arg.startswith("--extract-certificates=")), None)
                if extraction:
                    prefix = extraction.split("=", 1)[1]
                    Path(prefix + "0").write_bytes(CERTIFICATE)
                if "--display" in args and "--entitlements" in args:
                    return plistlib.dumps(expected if Path(args[-1]).resolve() == app.resolve() else {})
                if "--display" in args and "--verbose=4" in args:
                    return f"TeamIdentifier={TEAM}\n".encode()
                return b""
            with patch.object(contract.sys, "platform", "darwin"), patch.object(contract, "command", fake):
                contract.sign(app, f"Developer ID Application: Fixture ({TEAM})", input_profile, release,
                              TEAM, BUNDLE, contract.digest(PROFILE), "fixture-keychain", root / "receipt.json")
            mutations = [args for args in calls if "--sign" in args]
            self.assertEqual([Path(args[-1]).name for args in mutations],
                             ["nested.dylib", "App.framework", "aethertune.app"])
            self.assertTrue(all("--entitlements" not in args and "--deep" not in args for args in mutations[:-1]))
            self.assertIn("--entitlements", mutations[-1])
            self.assertIn("runtime", mutations[-1])
            receipt = json.loads((root / "receipt.json").read_text())
            self.assertEqual(receipt["profile"]["sha256"], contract.digest(PROFILE))
            self.assertEqual(set(receipt["main_slices"]), contract.ARCHES)

    @unittest.skipUnless(sys.platform == "darwin", "requires native macOS security tool")
    def test_native_decoder_rejects_non_cms_input(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "malformed.provisionprofile"
            path.write_bytes(PROFILE)
            with self.assertRaises(subprocess.CalledProcessError):
                contract.command(["/usr/bin/security", "cms", "-D", "-i", str(path)])


class NotarizationTest(unittest.TestCase):
    def test_notary_acceptance_is_bound_to_unchanged_submitted_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root / "fixture.dmg"; artifact.write_bytes(b"signed fixture")
            response = {"status": "Accepted", "id": "12345678-1234-1234-1234-123456789abc"}
            log = {"status": "Accepted", "jobId": response["id"], "archiveFilename": "Contained.app",
                   "sha256": contract.digest(b"signed fixture")}
            with patch.object(contract.sys, "platform", "darwin"), patch.object(
                    contract, "command", side_effect=[json.dumps(response).encode(), json.dumps(log).encode()]) as command:
                contract.notarize(artifact, root / "unused.p8", "KEYID", "ISSUER", root / "receipt.json")
            receipt = json.loads((root / "receipt.json").read_text())
            self.assertEqual(receipt["input_sha256"], contract.digest(b"signed fixture"))
            self.assertEqual(receipt["submission_id"], response["id"])
            self.assertEqual(receipt["log"]["archive_filename"], "Contained.app")
            self.assertEqual(receipt["log"]["sha256"], contract.digest(b"signed fixture"))
            self.assertEqual(receipt["log"]["job_id"], response["id"])
            self.assertIn("--wait", command.call_args_list[0].args[0])
            self.assertIn("--output-format", command.call_args_list[0].args[0])
            self.assertEqual(command.call_args_list[0].kwargs["timeout"], 1300)
            self.assertEqual(command.call_args_list[1].args[0][1:3], ["notarytool", "log"])

    def test_rejected_invalid_or_changed_submissions_never_write_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root / "fixture.dmg"
            for status, submission, mutate in (("Invalid", "12345678-1234-1234-1234-123456789abc", False),
                                               ("Accepted", "not-an-id", False),
                                               ("Accepted", "12345678-1234-1234-1234-123456789abc", True)):
                artifact.write_bytes(b"signed fixture")
                def fake(args, **kwargs):
                    if mutate:
                        artifact.write_bytes(b"substituted fixture")
                    return json.dumps({"status": status, "id": submission}).encode()
                with patch.object(contract.sys, "platform", "darwin"), patch.object(contract, "command", fake):
                    with self.subTest(status=status, mutate=mutate), self.assertRaises(ValueError):
                        contract.notarize(artifact, root / "unused.p8", "KEYID", "ISSUER", root / "receipt.json")
                self.assertFalse((root / "receipt.json").exists())

    def test_server_notary_log_job_status_or_hash_mismatch_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            artifact = root / "fixture.dmg"; artifact.write_bytes(b"signed fixture")
            response = {"status": "Accepted", "id": "12345678-1234-1234-1234-123456789abc"}
            original = {"status": "Accepted", "jobId": response["id"], "archiveFilename": artifact.name,
                        "sha256": contract.digest(b"signed fixture")}
            for key, value in (("status", "Invalid"), ("jobId", "87654321-1234-1234-1234-123456789abc"),
                               ("sha256", "0" * 64), ("sha256", None)):
                log = {**original, key: value}
                with patch.object(contract.sys, "platform", "darwin"), patch.object(
                        contract, "command", side_effect=[json.dumps(response).encode(), json.dumps(log).encode()]):
                    with self.subTest(key=key), self.assertRaisesRegex(ValueError, "log"):
                        contract.notarize(artifact, root / "unused.p8", "KEYID", "ISSUER", root / "receipt.json")
                self.assertFalse((root / "receipt.json").exists())

    def test_dmg_signer_has_timestamp_identifier_no_entitlements_and_verifies_same_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            image = root / "fixture.dmg"; image.write_bytes(b"fixture")
            calls = []
            def fake(args, **kwargs):
                calls.append(args)
                if args[:2] == ["/usr/bin/security", "find-identity"]:
                    return f'1) {FINGERPRINT} "Developer ID Application: Fixture ({TEAM})"'.encode()
                extraction = next((arg for arg in args if arg.startswith("--extract-certificates=")), None)
                if extraction:
                    Path(extraction.split("=", 1)[1] + "0").write_bytes(CERTIFICATE)
                if "--verbose=4" in args:
                    return f"TeamIdentifier={TEAM}\nIdentifier={BUNDLE}.disk-image\n".encode()
                return b""
            with patch.object(contract.sys, "platform", "darwin"), patch.object(contract, "command", fake):
                contract.sign_disk_image(image, f"Developer ID Application: Fixture ({TEAM})", TEAM, BUNDLE,
                                         "fixture-keychain", root / "receipt.json")
            mutation = next(args for args in calls if "--sign" in args)
            self.assertIn("--timestamp", mutation)
            self.assertIn("--identifier", mutation)
            self.assertNotIn("--entitlements", mutation)
            self.assertTrue(any("--verify" in args and "-R" in args for args in calls))


if __name__ == "__main__":
    unittest.main()
