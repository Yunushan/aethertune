#!/usr/bin/env python3
"""Verify Windows production archive signatures and required package payloads."""

from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path


def _has_authenticode_table(payload: bytes) -> bool:
    """Check that a PE image contains a non-empty Authenticode certificate table."""
    if len(payload) < 0x40 or payload[:2] != b"MZ":
        return False
    pe_offset = struct.unpack_from("<I", payload, 0x3C)[0]
    if pe_offset + 24 > len(payload) or payload[pe_offset : pe_offset + 4] != b"PE\0\0":
        return False
    optional_size = struct.unpack_from("<H", payload, pe_offset + 20)[0]
    optional_start = pe_offset + 24
    if optional_start + optional_size > len(payload) or optional_size < 112:
        return False
    magic = struct.unpack_from("<H", payload, optional_start)[0]
    directory_offset = 96 if magic == 0x10B else 112 if magic == 0x20B else None
    if directory_offset is None or directory_offset + 40 > optional_size:
        return False
    certificate_offset, certificate_size = struct.unpack_from(
        "<II", payload, optional_start + directory_offset + 32
    )
    return (
        certificate_offset > 0
        and certificate_size > 0
        and certificate_offset + certificate_size <= len(payload)
    )


def _read_zip(path: Path, label: str) -> tuple[zipfile.ZipFile, set[str]]:
    if not path.is_file():
        raise ValueError(f"{label} does not exist: {path}")
    try:
        archive = zipfile.ZipFile(path)
        return archive, set(archive.namelist())
    except zipfile.BadZipFile as error:
        raise ValueError(f"{label} is not a valid ZIP archive: {path}") from error


def verify_windows_release_artifacts(zip_path: Path, msix_path: Path) -> None:
    """Require a signed portable executable and a signed MSIX package."""
    portable, portable_entries = _read_zip(zip_path, "Windows portable archive")
    try:
        executable_entries = [entry for entry in portable_entries if entry == "aethertune.exe"]
        if len(executable_entries) != 1:
            raise ValueError("Windows portable archive must contain aethertune.exe at its root")
        if not _has_authenticode_table(portable.read(executable_entries[0])):
            raise ValueError("Windows portable executable does not contain an Authenticode signature")
    finally:
        portable.close()

    msix, msix_entries = _read_zip(msix_path, "Windows MSIX")
    try:
        if "AppxSignature.p7x" not in msix_entries:
            raise ValueError("Windows MSIX is missing AppxSignature.p7x")
    finally:
        msix.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zip", required=True, type=Path)
    parser.add_argument("--msix", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        verify_windows_release_artifacts(arguments.zip, arguments.msix)
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
