#!/usr/bin/env python3
"""Regression checks for Android release artifact verification."""

from __future__ import annotations

import tempfile
import struct
import unittest
import zipfile
from pathlib import Path

from verify_android_release_artifacts import (
    REQUIRED_AAB_ENTRIES,
    REQUIRED_APK_ENTRIES,
    verify_android_release_artifacts,
    verify_archive,
)


def native_entries(prefix: str, abi: str = 'arm64-v8a') -> frozenset[str]:
    return frozenset(f'{prefix}/{abi}/{name}' for name in ('libflutter.so', 'librhttp.so'))


def elf_header(abi: str) -> bytes:
    bits, machine = {'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183), 'x86_64': (2, 62)}[abi]
    header = bytearray(64)
    header[:7] = b'\x7fELF' + bytes([bits, 1, 1])
    struct.pack_into('<HH', header, 16, 3, machine)
    return bytes(header)


def write_archive(path: Path, entries: frozenset[str]) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        for entry in entries:
            data = elf_header(entry.split('/')[-2]) if entry.endswith('.so') else b'fixture'
            archive.writestr(entry, data)


APK_ENTRIES = REQUIRED_APK_ENTRIES | native_entries('lib')
AAB_ENTRIES = REQUIRED_AAB_ENTRIES | native_entries('base/lib')


class AndroidReleaseArtifactsTest(unittest.TestCase):
    def test_accepts_archives_with_required_entries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            apk = directory / "app-release.apk"
            aab = directory / "app-release.aab"
            write_archive(apk, APK_ENTRIES)
            write_archive(aab, AAB_ENTRIES)

            verify_android_release_artifacts(apk, aab)

    def test_rejects_an_archive_missing_flutter_assets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            apk = directory / "app-release.apk"
            aab = directory / "app-release.aab"
            write_archive(apk, APK_ENTRIES)
            write_archive(aab, AAB_ENTRIES - {"base/assets/flutter_assets/AssetManifest.bin"})

            with self.assertRaisesRegex(ValueError, "AssetManifest.bin"):
                verify_android_release_artifacts(apk, aab)

    def test_requires_signatures_for_production_verification(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            apk = directory / "app-release.apk"
            aab = directory / "app-release.aab"
            write_archive(apk, APK_ENTRIES)
            write_archive(aab, AAB_ENTRIES)

            with self.assertRaisesRegex(ValueError, "signing signature"):
                verify_android_release_artifacts(
                    apk,
                    aab,
                    require_signing=True,
                )

            signed_entries_apk = APK_ENTRIES | {"META-INF/CERT.RSA"}
            signed_entries_aab = AAB_ENTRIES | {"META-INF/CERT.RSA"}
            write_archive(apk, signed_entries_apk)
            write_archive(aab, signed_entries_aab)
            verify_android_release_artifacts(
                apk,
                aab,
                require_signing=True,
            )

    def test_rejects_missing_transport_for_each_flutter_abi(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            for label, required, prefix in [('APK', REQUIRED_APK_ENTRIES, 'lib'),
                                             ('AAB', REQUIRED_AAB_ENTRIES, 'base/lib')]:
                for abi in ('armeabi-v7a', 'arm64-v8a', 'x86_64'):
                    with self.subTest(label=label, abi=abi):
                        path = Path(temporary_directory) / ('app.' + label.lower())
                        entries = required | native_entries(prefix, abi)
                        write_archive(path, entries - {f'{prefix}/{abi}/librhttp.so'})
                        with self.assertRaisesRegex(ValueError, 'librhttp.so'):
                            verify_archive(path, required, label)
                        write_archive(path, entries)
                        verify_archive(path, required, label)

    def test_rejects_no_flutter_abi(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'app.apk'
            write_archive(path, REQUIRED_APK_ENTRIES)
            with self.assertRaisesRegex(ValueError, 'libflutter.so'):
                verify_archive(path, REQUIRED_APK_ENTRIES, 'APK')

    def test_rejects_empty_or_wrong_architecture_transport(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'app.apk'
            for payload in (b'', b'not an ELF', elf_header('x86_64')):
                with self.subTest(payload=payload):
                    write_archive(path, APK_ENTRIES - {'lib/arm64-v8a/librhttp.so'})
                    with zipfile.ZipFile(path, 'a') as archive:
                        archive.writestr('lib/arm64-v8a/librhttp.so', payload)
                    with self.assertRaisesRegex(ValueError, 'librhttp.so'):
                        verify_archive(path, REQUIRED_APK_ENTRIES, 'APK')

    def test_every_flutter_abi_requires_its_own_transport(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'app.apk'
            entries = APK_ENTRIES | native_entries('lib', 'x86_64')
            write_archive(path, entries - {'lib/x86_64/librhttp.so'})
            with self.assertRaisesRegex(ValueError, 'lib/x86_64/librhttp.so'):
                verify_archive(path, REQUIRED_APK_ENTRIES, 'APK')

    def test_rejects_duplicate_archive_names(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'app.apk'
            write_archive(path, APK_ENTRIES)
            with self.assertWarns(UserWarning), zipfile.ZipFile(path, 'a') as archive:
                archive.writestr('lib/arm64-v8a/librhttp.so', elf_header('arm64-v8a'))
            with self.assertRaisesRegex(ValueError, 'duplicate'):
                verify_archive(path, REQUIRED_APK_ENTRIES, 'APK')


if __name__ == "__main__":
    unittest.main()
