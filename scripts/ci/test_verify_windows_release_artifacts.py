#!/usr/bin/env python3
"""Regression checks for Windows production artifact verification."""

from __future__ import annotations

import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from verify_windows_release_artifacts import verify_windows_release_artifacts


def signed_pe_fixture() -> bytes:
    payload = bytearray(0x208)
    payload[:2] = b"MZ"
    struct.pack_into("<I", payload, 0x3C, 0x80)
    payload[0x80:0x84] = b"PE\0\0"
    struct.pack_into("<H", payload, 0x80 + 20, 0xF0)
    optional_start = 0x80 + 24
    struct.pack_into("<H", payload, optional_start, 0x20B)
    struct.pack_into("<II", payload, optional_start + 112 + 32, 0x200, 8)
    payload[0x200:] = b"CERT\0\0\0\0"
    return bytes(payload)


class VerifyWindowsReleaseArtifactsTest(unittest.TestCase):
    def test_accepts_signed_portable_executable_and_msix(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            zip_path = directory / "aethertune-windows-x64.zip"
            msix_path = directory / "aethertune-windows-x64.msix"
            with zipfile.ZipFile(zip_path, "w") as archive:
                archive.writestr("aethertune.exe", signed_pe_fixture())
            with zipfile.ZipFile(msix_path, "w") as archive:
                archive.writestr("AppxSignature.p7x", b"signature")

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


if __name__ == "__main__":
    unittest.main()
