#!/usr/bin/env python3
"""Verify Windows production archive signatures and required package payloads."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import struct
import sys
import zipfile
from pathlib import Path


REQUIRED_RUNTIME_FILES = {"msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"}
NATIVE_POLICY = json.loads(Path(__file__).with_name("windows_native_policy.json").read_text())
DEBUG_RUNTIME = re.compile(NATIVE_POLICY["debugRuntimePattern"], re.IGNORECASE)
NATIVE_SUFFIXES = {".exe", ".dll", ".so"}
REQUIRED_NATIVE_FILES = {"aethertune.exe", "flutter_windows.dll", "rhttp.dll", "data/app.so"}


def _safe_package_path(name: str) -> bool:
    if not isinstance(name, str) or not name or re.search(r'[\\:\x00-\x1f<>"|?*]', name):
        return False
    parts = name.split("/")
    return all(part not in ("", ".", "..") and not part.endswith((" ", ".")) for part in parts)


def _native_records(value: object, *, modules: bool) -> dict[str, dict]:
    if not isinstance(value, list) or (modules and not value):
        raise ValueError("Invalid native manifest file list")
    records = {}
    for entry in value:
        if not isinstance(entry, dict):
            raise ValueError("Invalid native manifest entry")
        name = entry.get("file")
        digest = entry.get("sha256")
        if (
            not _safe_package_path(name)
            or name.lower() in records
            or not isinstance(digest, str)
            or re.fullmatch(r"[0-9a-f]{64}", digest) is None
            or Path(name).suffix.lower() not in ({".exe", ".dll"} if modules else {".so"})
        ):
            raise ValueError("Invalid or duplicate native manifest file")
        if modules:
            imports = entry.get("imports")
            if not isinstance(imports, list) or any(
                not isinstance(item, str)
                or re.fullmatch(r"[a-z0-9_.-]+\.dll", item) is None
                for item in imports
            ):
                raise ValueError("Invalid native manifest import list")
            if len(set(imports)) != len(imports):
                raise ValueError("Duplicate native manifest import")
            if DEBUG_RUNTIME.fullmatch(Path(name).name) or any(DEBUG_RUNTIME.fullmatch(item) for item in imports):
                raise ValueError(f"Debug C++ runtime dependency in native manifest: {name}")
        records[name.lower()] = entry
    return records


def _verify_native_payload(archive: zipfile.ZipFile, prefix: str = "") -> dict:
    try:
        info = archive.getinfo(prefix + "aethertune-windows-native.json")
        if info.file_size > 2 * 1024 * 1024:
            raise ValueError("Native manifest exceeds the size limit")
        manifest = json.loads(archive.read(info))
    except (KeyError, ValueError, UnicodeError) as error:
        raise ValueError("Windows package is missing a valid native manifest") from error
    if (
        not isinstance(manifest, dict)
        or type(manifest.get("schemaVersion")) is not int
        or manifest["schemaVersion"] != 1
        or type(manifest.get("policyVersion")) is not int
        or manifest["policyVersion"] != NATIVE_POLICY["version"]
    ):
        raise ValueError("Unsupported native manifest schema or policy")
    modules = _native_records(manifest.get("modules"), modules=True)
    assets = _native_records(manifest.get("referenceScannedAssets"), modules=False)
    omitted = manifest.get("omitted")
    if not isinstance(omitted, list) or len(omitted) > 1:
        raise ValueError("Invalid native manifest omission list")
    if omitted:
        entry = omitted[0]
        if (
            not isinstance(entry, dict)
            or entry.get("file") != "zlib.dll"
            or entry.get("sha256") != NATIVE_POLICY["unusedAngleZlibSha256"]
            or not isinstance(entry.get("reason"), str)
            or not entry["reason"].strip()
        ):
            raise ValueError("Unapproved native manifest omission")

    records = modules | assets
    packaged = {}
    for info in archive.infolist():
        if info.is_dir() or Path(info.filename).suffix.lower() not in NATIVE_SUFFIXES:
            continue
        if not info.filename.startswith(prefix):
            raise ValueError(f"Native file is outside the application payload: {info.filename}")
        relative = info.filename[len(prefix):]
        packaged[relative.lower()] = info
    if set(records) != set(packaged) or not REQUIRED_NATIVE_FILES <= set(records):
        raise ValueError("Native manifest does not cover the complete packaged payload")

    for name, entry in records.items():
        info = packaged[name]
        if info.filename != prefix + entry["file"]:
            raise ValueError("Native manifest path does not match package casing")
        if info.file_size > 256 * 1024 * 1024:
            raise ValueError(f"Native module exceeds the inspection size limit: {name}")
        payload = archive.read(info)
        if hashlib.sha256(payload).hexdigest() != entry["sha256"]:
            raise ValueError(f"Native payload hash mismatch: {name}")
        if name in modules and not _is_x64_image(payload):
            raise ValueError(f"Native module is not an x64 PE image: {name}")
        if omitted:
            if Path(name).name == "zlib.dll" or "zlib.dll" in entry.get("imports", []):
                raise ValueError(f"Omitted zlib dependency remains in the native payload: {name}")
            lower_payload = payload.lower()
            for token in ("zlib.dll", "Cr_z_"):
                if any(token.lower().encode(encoding) in lower_payload for encoding in ("ascii", "utf-16-le")):
                    raise ValueError(f"Omitted zlib reference remains in the native payload: {name}")

    # Import classification comes from DUMPBIN at packaging time. Bind those
    # records to every final native file, not only the executable and CRT files.
    return {"modules": modules, "assets": assets, "omitted": omitted}


def _is_x64_image(payload: bytes) -> bool:
    if len(payload) < 64 or payload[:2] != b"MZ":
        return False
    offset = struct.unpack_from("<I", payload, 0x3C)[0]
    return (
        offset + 6 <= len(payload)
        and payload[offset:offset + 4] == b"PE\0\0"
        and struct.unpack_from("<H", payload, offset + 4)[0] == 0x8664
    )


def _verify_runtime_payload(archive: zipfile.ZipFile, prefix: str = "") -> None:
    manifest_path = prefix + "aethertune-windows-runtime.json"
    try:
        manifest = json.loads(archive.read(manifest_path))
    except (KeyError, ValueError, UnicodeError) as error:
        raise ValueError("Windows package is missing a valid runtime manifest") from error
    if not isinstance(manifest, list) or not manifest:
        raise ValueError("Windows runtime manifest must list the bundled runtime files")
    names = set()
    for entry in manifest:
        if not isinstance(entry, dict):
            raise ValueError("Invalid Windows runtime manifest entry")
        name = entry.get("file")
        if (
            not isinstance(name, str)
            or not name.endswith(".dll")
            or "/" in name
            or "\\" in name
            or name.lower() in names
            or not isinstance(entry.get("version"), str)
            or not entry["version"]
        ):
            raise ValueError("Invalid or duplicate Windows runtime manifest file")
        names.add(name.lower())
        try:
            payload = archive.read(prefix + name)
        except KeyError as error:
            raise ValueError(f"Windows package is missing runtime {name}") from error
        if hashlib.sha256(payload).hexdigest() != entry.get("sha256"):
            raise ValueError(f"Windows runtime hash mismatch: {name}")
        if not _has_authenticode_table(payload):
            raise ValueError(f"Windows runtime has no Authenticode table: {name}")
    if not REQUIRED_RUNTIME_FILES <= names:
        raise ValueError("Windows runtime manifest omits required C++ runtime files")


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
    except zipfile.BadZipFile as error:
        raise ValueError(f"{label} is not a valid ZIP archive: {path}") from error
    try:
        names = set()
        for entry in archive.infolist():
            name = entry.orig_filename.rstrip("/") if entry.is_dir() else entry.orig_filename
            if not _safe_package_path(name) or name.lower() in names or entry.orig_filename != entry.filename:
                raise ValueError(f"{label} contains an unsafe or duplicate path: {name}")
            if stat.S_ISLNK(entry.external_attr >> 16) or entry.flag_bits & 1:
                raise ValueError(f"{label} contains a link or encrypted payload: {name}")
            names.add(name.lower())
        return archive, set(archive.namelist())
    except BaseException:
        archive.close()
        raise


def verify_windows_release_artifacts(zip_path: Path, msix_path: Path) -> None:
    """Require a signed portable executable and a signed MSIX package."""
    portable, portable_entries = _read_zip(zip_path, "Windows portable archive")
    try:
        executable_entries = [entry for entry in portable_entries if entry == "aethertune.exe"]
        if len(executable_entries) != 1:
            raise ValueError("Windows portable archive must contain aethertune.exe at its root")
        if not _has_authenticode_table(portable.read(executable_entries[0])):
            raise ValueError("Windows portable executable does not contain an Authenticode signature")
        _verify_runtime_payload(portable)
        portable_native = _verify_native_payload(portable)
    finally:
        portable.close()

    msix, msix_entries = _read_zip(msix_path, "Windows MSIX")
    try:
        if "AppxSignature.p7x" not in msix_entries:
            raise ValueError("Windows MSIX is missing AppxSignature.p7x")
        _verify_runtime_payload(msix, "VFS/ProgramFilesX64/AetherTune/")
        msix_native = _verify_native_payload(msix, "VFS/ProgramFilesX64/AetherTune/")
        if portable_native != msix_native:
            raise ValueError("Windows ZIP and MSIX native payloads do not match")
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
