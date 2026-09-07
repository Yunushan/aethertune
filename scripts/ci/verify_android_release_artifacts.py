#!/usr/bin/env python3
"""Validate the essential contents of Android release APK and AAB files."""

from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path


REQUIRED_APK_ENTRIES = frozenset(
    {
        "AndroidManifest.xml",
        "assets/flutter_assets/AssetManifest.bin",
        "classes.dex",
    },
)
REQUIRED_AAB_ENTRIES = frozenset(
    {
        "base/assets/flutter_assets/AssetManifest.bin",
        "base/dex/classes.dex",
        "base/manifest/AndroidManifest.xml",
    },
)

ANDROID_ELF_ABIS = {'armeabi-v7a': (1, 40), 'arm64-v8a': (2, 183), 'x86_64': (2, 62)}


def verify_native_libraries(archive: zipfile.ZipFile, entries: set[str], label: str) -> None:
    prefix = 'base/lib/' if label == 'AAB' else 'lib/'
    engines = sorted(entry for entry in entries
                     if entry.startswith(prefix) and entry.endswith('/libflutter.so'))
    if not engines:
        raise ValueError(f'{label} has no native Flutter engine (libflutter.so)')
    for engine in engines:
        abi = engine[len(prefix):].split('/')[0]
        if abi not in ANDROID_ELF_ABIS or engine != f'{prefix}{abi}/libflutter.so':
            raise ValueError(f'{label} has an unsupported Flutter ABI: {engine}')
        elf_class, machine = ANDROID_ELF_ABIS[abi]
        for name in ('libflutter.so', 'librhttp.so'):
            entry = f'{prefix}{abi}/{name}'
            if entry not in entries:
                raise ValueError(f'{label} is missing required native library: {entry}')
            # Bounded header inspection detects empty, truncated and wrong-ABI
            # payloads; it does not replace native loading or signature checks.
            with archive.open(entry) as stream:
                header = stream.read(64)
            if (len(header) < (52 if elf_class == 1 else 64)
                    or header[:7] != b'\x7fELF' + bytes([elf_class, 1, 1])
                    or struct.unpack_from('<HH', header, 16) != (3, machine)):
                raise ValueError(f'{label} has an invalid {abi} ELF library: {entry}')


def verify_archive(
    path: Path,
    required_entries: frozenset[str],
    label: str,
    *,
    require_signing: bool = False,
) -> None:
    if not path.is_file():
        raise ValueError(f"{label} does not exist: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            entries = set(names)
            if len(entries) != len(names):
                raise ValueError(f'{label} contains duplicate archive entries')
            missing = sorted(required_entries - entries)
            if missing:
                raise ValueError(f"{label} is missing required entries: {', '.join(missing)}")
            if require_signing:
                signature_entries = {
                    entry
                    for entry in entries
                    if entry.startswith("META-INF/")
                    and entry.rsplit(".", 1)[-1].upper() in {"RSA", "DSA", "EC"}
                }
                if not signature_entries:
                    raise ValueError(f"{label} does not contain a signing signature")
            verify_native_libraries(archive, entries, label)
    except zipfile.BadZipFile as error:
        raise ValueError(f"{label} is not a valid ZIP archive: {path}") from error


def verify_android_release_artifacts(
    apk: Path,
    aab: Path | None = None,
    *,
    require_signing: bool = False,
) -> None:
    verify_archive(
        apk,
        REQUIRED_APK_ENTRIES,
        "APK",
        require_signing=require_signing,
    )
    if aab is not None:
        verify_archive(
            aab,
            REQUIRED_AAB_ENTRIES,
            "AAB",
            require_signing=require_signing,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--aab", type=Path, help="also verify a release app bundle")
    parser.add_argument(
        "--require-signing",
        action="store_true",
        help="require APK/AAB signing signature entries",
    )
    arguments = parser.parse_args()
    try:
        verify_android_release_artifacts(
            arguments.apk,
            arguments.aab,
            require_signing=arguments.require_signing,
        )
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
