#!/usr/bin/env python3
"""Regression checks for Windows production artifact verification."""

from __future__ import annotations

import hashlib
import io
import json
import stat
import struct
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path

from verify_windows_release_artifacts import (
    DEBUG_RUNTIME,
    NATIVE_POLICY,
    REQUIRED_RUNTIME_FILES,
    _read_zip,
    _verify_native_payload,
    _verify_runtime_payload,
    verify_windows_release_artifacts,
)


def signed_pe_fixture() -> bytes:
    payload = bytearray(0x208)
    payload[:2] = b"MZ"
    struct.pack_into("<I", payload, 0x3C, 0x80)
    payload[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<H", payload, 0x84, 0x8664)
    struct.pack_into("<H", payload, 0x80 + 20, 0xF0)
    optional_start = 0x80 + 24
    struct.pack_into("<H", payload, optional_start, 0x20B)
    struct.pack_into("<II", payload, optional_start + 112 + 32, 0x200, 8)
    payload[0x200:] = b"CERT\0\0\0\0"
    return bytes(payload)


def add_runtime_fixture(archive: zipfile.ZipFile, prefix: str = "") -> None:
    payload = signed_pe_fixture()
    manifest = []
    for name in sorted(REQUIRED_RUNTIME_FILES):
        archive.writestr(prefix + name, payload)
        manifest.append({
            "file": name,
            "version": "14.50.0.0",
            "sha256": hashlib.sha256(payload).hexdigest(),
        })
    archive.writestr(prefix + "aethertune-windows-runtime.json", json.dumps(manifest))


def native_manifest(payloads: dict[str, bytes]) -> dict:
    modules = []
    assets = []
    for name, payload in sorted(payloads.items()):
        entry = {"file": name, "sha256": hashlib.sha256(payload).hexdigest()}
        if name.endswith((".exe", ".dll")):
            modules.append({**entry, "imports": ["kernel32.dll"]})
        elif name.endswith(".so"):
            assets.append(entry)
    return {
        "schemaVersion": 1,
        "policyVersion": NATIVE_POLICY["version"],
        "modules": modules,
        "omitted": [],
        "referenceScannedAssets": assets,
    }


def add_native_fixture(archive: zipfile.ZipFile, prefix: str = "", *, extra: bytes = b"") -> None:
    for name, payload in {
        "aethertune.exe": signed_pe_fixture(),
        "flutter_windows.dll": signed_pe_fixture() + extra,
        "rhttp.dll": signed_pe_fixture(),
        "data/app.so": b"Dart AOT fixture, not executable",
    }.items():
        if prefix + name not in archive.namelist():
            archive.writestr(prefix + name, payload)
    payloads = {
        name[len(prefix):]: archive.read(name)
        for name in archive.namelist()
        if name.startswith(prefix) and name.endswith((".exe", ".dll", ".so"))
    }
    archive.writestr(prefix + "aethertune-windows-native.json", json.dumps(native_manifest(payloads)))


def verify_native_fixture(payloads: dict[str, bytes], manifest: object, prefix: str) -> dict:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, payload in payloads.items():
            archive.writestr(prefix + name, payload)
        archive.writestr(prefix + "aethertune-windows-native.json", json.dumps(manifest))
    with zipfile.ZipFile(buffer) as archive:
        return _verify_native_payload(archive, prefix)


def native_payloads() -> dict[str, bytes]:
    return {
        "aethertune.exe": signed_pe_fixture(),
        "flutter_windows.dll": signed_pe_fixture(),
        "rhttp.dll": signed_pe_fixture(),
        "data/app.so": b"Dart AOT fixture, not executable",
    }


class VerifyWindowsReleaseArtifactsTest(unittest.TestCase):
    def test_rejects_missing_native_transport_even_with_a_matching_manifest(self) -> None:
        for prefix in ("", "VFS/ProgramFilesX64/AetherTune/"):
            payloads = native_payloads()
            del payloads["rhttp.dll"]
            with self.subTest(prefix=prefix), self.assertRaisesRegex(ValueError, "complete packaged payload"):
                verify_native_fixture(payloads, native_manifest(payloads), prefix)

    def test_requires_native_manifest(self) -> None:
        for missing in ("zip", "msix"):
            with self.subTest(missing=missing), tempfile.TemporaryDirectory() as temporary_directory:
                directory = Path(temporary_directory)
                zip_path = directory / "app.zip"
                msix_path = directory / "app.msix"
                with zipfile.ZipFile(zip_path, "w") as archive:
                    archive.writestr("aethertune.exe", signed_pe_fixture())
                    add_runtime_fixture(archive)
                    if missing != "zip":
                        add_native_fixture(archive)
                with zipfile.ZipFile(msix_path, "w") as archive:
                    archive.writestr("AppxSignature.p7x", b"signature")
                    add_runtime_fixture(archive, "VFS/ProgramFilesX64/AetherTune/")
                    if missing != "msix":
                        add_native_fixture(archive, "VFS/ProgramFilesX64/AetherTune/")
                with self.assertRaisesRegex(ValueError, "native manifest"):
                    verify_windows_release_artifacts(zip_path, msix_path)

    def test_accepts_signed_portable_executable_and_msix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            zip_path = directory / "aethertune-windows-x64.zip"
            msix_path = directory / "aethertune-windows-x64.msix"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("aethertune.exe", signed_pe_fixture())
                add_runtime_fixture(archive)
                add_native_fixture(archive)
            with zipfile.ZipFile(msix_path, "w") as archive:
                archive.writestr("AppxSignature.p7x", b"signature")
                add_runtime_fixture(archive, "VFS/ProgramFilesX64/AetherTune/")
                add_native_fixture(archive, "VFS/ProgramFilesX64/AetherTune/")

            verify_windows_release_artifacts(zip_path, msix_path)

    def test_rejects_unsigned_portable_executable(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            zip_path = directory / "aethertune-windows-x64.zip"
            msix_path = directory / "aethertune-windows-x64.msix"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("aethertune.exe", b"MZ")
            with zipfile.ZipFile(msix_path, "w") as archive:
                archive.writestr("AppxSignature.p7x", b"signature")

            with self.assertRaisesRegex(ValueError, "Authenticode"):
                verify_windows_release_artifacts(zip_path, msix_path)

    def test_requires_runtime_in_both_package_formats(self) -> None:
        for missing in ("zip", "msix"):
            with (
                self.subTest(missing=missing),
                tempfile.TemporaryDirectory() as temporary_directory,
            ):
                directory = Path(temporary_directory)
                zip_path = directory / "app.zip"
                msix_path = directory / "app.msix"
                with zipfile.ZipFile(zip_path, "w") as archive:
                    archive.writestr("aethertune.exe", signed_pe_fixture())
                    if missing != "zip":
                        add_runtime_fixture(archive)
                    add_native_fixture(archive)
                with zipfile.ZipFile(msix_path, "w") as archive:
                    archive.writestr("AppxSignature.p7x", b"signature")
                    if missing != "msix":
                        add_runtime_fixture(archive, "VFS/ProgramFilesX64/AetherTune/")
                    add_native_fixture(archive, "VFS/ProgramFilesX64/AetherTune/")
                with self.assertRaisesRegex(ValueError, "runtime manifest"):
                    verify_windows_release_artifacts(zip_path, msix_path)

    def test_native_manifest_rejects_invalid_records(self) -> None:
        payloads = native_payloads()
        good = native_manifest(payloads)
        entry = good["modules"][0]
        cases = [None, [], {}, {**good, "schemaVersion": True}, {**good, "policyVersion": 999}]
        for invalid in (
            None, [], [0], [entry, entry],
            [{**entry, "file": "../aethertune.exe"}],
            [{**entry, "file": "C:/aethertune.exe"}],
            [{**entry, "file": "app\\aethertune.exe"}],
            [{**entry, "sha256": "unknown"}],
            [{**entry, "imports": None}],
            [{**entry, "imports": [None]}],
            [{**entry, "imports": ["../kernel32.dll"]}],
            [{**entry, "imports": ["kernel32.dll", "kernel32.dll"]}],
        ):
            cases.append({**good, "modules": invalid})
        for invalid in (None, {}, [None], [{"file": "data/app.so", "sha256": "bad"}]):
            cases.append({**good, "referenceScannedAssets": invalid})
        for prefix in ("", "VFS/ProgramFilesX64/AetherTune/"):
            for index, manifest in enumerate(cases):
                with self.subTest(prefix=prefix, case=index), self.assertRaises(ValueError):
                    verify_native_fixture(payloads, manifest, prefix)

    def test_native_manifest_binds_complete_payload_and_architecture(self) -> None:
        good = native_payloads()
        manifest = native_manifest(good)
        wrong_arch = bytearray(good["aethertune.exe"])
        struct.pack_into("<H", wrong_arch, 0x84, 0xAA64)
        arm = {**good, "aethertune.exe": bytes(wrong_arch)}
        missing = {name: data for name, data in good.items() if name != "data/app.so"}
        cases = [
            ({**good, "extra.dll": signed_pe_fixture()}, manifest, "complete packaged"),
            (missing, manifest, "complete packaged"),
            (missing, native_manifest(missing), "complete packaged"),
            ({**good, "aethertune.exe": good["aethertune.exe"] + b"changed"}, manifest, "hash mismatch"),
            ({**good, "data/app.so": b"changed"}, manifest, "hash mismatch"),
            (arm, native_manifest(arm), "x64 PE"),
        ]
        for prefix in ("", "VFS/ProgramFilesX64/AetherTune/"):
            verify_native_fixture(good, manifest, prefix)
            for payloads, description, pattern in cases:
                with self.subTest(prefix=prefix, pattern=pattern), self.assertRaisesRegex(ValueError, pattern):
                    verify_native_fixture(payloads, description, prefix)

    def test_debug_policy_rejects_native_names_and_imports(self) -> None:
        debug_names = (
            "ucrtbased.dll", "msvcrtd.dll", "msvcr120d.dll", "concrt140d.dll",
            "vccorlib140d.dll", "msvcp140d.dll", "msvcp140_1d.dll", "msvcp140_2d.dll",
            "msvcp140d_atomic_wait.dll", "msvcp140d_codecvt_ids.dll",
            "vcruntime140d.dll", "VCRUNTIME140_1D.dll", "vcruntime140_threadsd.dll",
        )
        for name in debug_names:
            with self.subTest(name=name):
                self.assertIsNotNone(DEBUG_RUNTIME.fullmatch(name))
                payloads = native_payloads()
                manifest = native_manifest(payloads)
                manifest["modules"][0]["imports"] = [name.lower()]
                with self.assertRaisesRegex(ValueError, "Debug C\\+\\+ runtime"):
                    verify_native_fixture(payloads, manifest, "")
                payloads[name] = signed_pe_fixture()
                with self.assertRaisesRegex(ValueError, "Debug C\\+\\+ runtime"):
                    verify_native_fixture(payloads, native_manifest(payloads), "")
        for name in ("ucrtbase.dll", "msvcp140.dll", "msvcp140_1.dll", "vcruntime140_threads.dll", "media_kit.dll"):
            self.assertIsNone(DEBUG_RUNTIME.fullmatch(name))

    def test_omission_requires_exact_known_artifact(self) -> None:
        payloads = native_payloads()
        good = native_manifest(payloads)
        record = {"file": "zlib.dll", "sha256": NATIVE_POLICY["unusedAngleZlibSha256"], "reason": "Reviewed artifact"}
        good["omitted"] = [record]
        for prefix in ("", "VFS/ProgramFilesX64/AetherTune/"):
            verify_native_fixture(payloads, good, prefix)
            for omitted in (None, {}, [0], [record, record], [{**record, "file": "other.dll"}], [{**record, "sha256": "0" * 64}], [{**record, "reason": ""}]):
                with self.subTest(prefix=prefix, omitted=omitted), self.assertRaises(ValueError):
                    verify_native_fixture(payloads, {**good, "omitted": omitted}, prefix)

    def test_omitted_native_references_are_rejected_in_final_bytes(self) -> None:
        record = {"file": "zlib.dll", "sha256": NATIVE_POLICY["unusedAngleZlibSha256"], "reason": "Reviewed artifact"}
        for prefix in ("", "VFS/ProgramFilesX64/AetherTune/"):
            for file in ("aethertune.exe", "data/app.so"):
                for token in (b"ZLIB.DLL", "Cr_z_zlibVersion".encode("utf-16-le")):
                    payloads = native_payloads()
                    payloads[file] += token
                    manifest = native_manifest(payloads)
                    manifest["omitted"] = [record]
                    with self.subTest(prefix=prefix, file=file, token=token), self.assertRaisesRegex(ValueError, "zlib reference"):
                        verify_native_fixture(payloads, manifest, prefix)
            payloads = native_payloads()
            manifest = native_manifest(payloads)
            manifest["omitted"] = [record]
            manifest["modules"][0]["imports"] = ["zlib.dll"]
            with self.assertRaisesRegex(ValueError, "zlib dependency"):
                verify_native_fixture(payloads, manifest, prefix)
            payloads["zlib.dll"] = signed_pe_fixture()
            manifest = native_manifest(payloads)
            manifest["omitted"] = [record]
            with self.assertRaisesRegex(ValueError, "zlib dependency"):
                verify_native_fixture(payloads, manifest, prefix)

    def test_archives_reject_unsafe_paths_aliases_and_links(self) -> None:
        for name in ("aethertune.exe", "AetherTune.exe", "../extra.dll", "/extra.dll", "C:/extra.dll", "data\\extra.dll", "extra.dll."):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary) / "fixture.zip"
                with warnings.catch_warnings(), zipfile.ZipFile(path, "w") as archive:
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr("aethertune.exe", b"fixture")
                    entry = zipfile.ZipInfo()
                    entry.filename = name
                    archive.writestr(entry, b"fixture")
                with self.assertRaisesRegex(ValueError, "unsafe or duplicate"):
                    _read_zip(path, "fixture")
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "fixture.zip"
            with zipfile.ZipFile(path, "w") as archive:
                link = zipfile.ZipInfo("data/app.so")
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(link, b"outside")
            with self.assertRaisesRegex(ValueError, "link or encrypted"):
                _read_zip(path, "fixture")

    def test_zip_and_msix_must_describe_the_same_native_payload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            zip_path = directory / "app.zip"
            msix_path = directory / "app.msix"
            with zipfile.ZipFile(zip_path, "w") as archive:
                add_runtime_fixture(archive)
                add_native_fixture(archive)
            with zipfile.ZipFile(msix_path, "w") as archive:
                archive.writestr("AppxSignature.p7x", b"signature")
                prefix = "VFS/ProgramFilesX64/AetherTune/"
                add_runtime_fixture(archive, prefix)
                add_native_fixture(archive, prefix, extra=b"different build")
            with self.assertRaisesRegex(ValueError, "native payloads do not match"):
                verify_windows_release_artifacts(zip_path, msix_path)

    def test_runtime_manifest_rejects_bad_payloads(self) -> None:
        payload = signed_pe_fixture()
        good_entry = {
            "file": "msvcp140.dll",
            "version": "14.50.0.0",
            "sha256": hashlib.sha256(payload).hexdigest(),
        }
        cases = [
            ("{", payload, "valid runtime manifest"),
            ("{}", payload, "must list"),
            ("[]", payload, "must list"),
            ("[0]", payload, "Invalid Windows runtime"),
            (
                json.dumps([{**good_entry, "file": "../msvcp140.dll"}]),
                payload,
                "Invalid or duplicate",
            ),
            (json.dumps([good_entry, good_entry]), payload, "duplicate"),
            (json.dumps([good_entry]), None, "missing runtime"),
            (json.dumps([good_entry]), b"tampered", "hash mismatch"),
            (
                json.dumps([{**good_entry, "sha256": hashlib.sha256(b"MZ").hexdigest()}]),
                b"MZ",
                "Authenticode table",
            ),
            (json.dumps([good_entry]), payload, "omits required"),
        ]
        for manifest, runtime, pattern in cases:
            with (
                self.subTest(pattern=pattern),
                tempfile.TemporaryDirectory() as temporary_directory,
            ):
                path = Path(temporary_directory) / "app.zip"
                with zipfile.ZipFile(path, "w") as archive:
                    archive.writestr("aethertune-windows-runtime.json", manifest)
                    if runtime is not None:
                        archive.writestr("msvcp140.dll", runtime)
                with (
                    zipfile.ZipFile(path) as archive,
                    self.assertRaisesRegex(ValueError, pattern),
                ):
                    _verify_runtime_payload(archive)


if __name__ == "__main__":
    unittest.main()
