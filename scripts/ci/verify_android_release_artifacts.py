#!/usr/bin/env python3
"""Validate the essential contents of Android release APK and AAB files."""

from __future__ import annotations

import argparse
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


def verify_archive(path: Path, required_entries: frozenset[str], label: str) -> None:
    if not path.is_file():
        raise ValueError(f"{label} does not exist: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            entries = set(archive.namelist())
            missing = sorted(required_entries - entries)
    except zipfile.BadZipFile as error:
        raise ValueError(f"{label} is not a valid ZIP archive: {path}") from error
    if missing:
        raise ValueError(f"{label} is missing required entries: {', '.join(missing)}")


def verify_android_release_artifacts(apk: Path, aab: Path) -> None:
    verify_archive(apk, REQUIRED_APK_ENTRIES, "APK")
    verify_archive(aab, REQUIRED_AAB_ENTRIES, "AAB")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--aab", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        verify_android_release_artifacts(arguments.apk, arguments.aab)
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
