#!/usr/bin/env python3
"""Validate signed and notarized macOS release evidence."""

from __future__ import annotations

import json
import argparse
import sys
import zipfile
from pathlib import Path


ATTESTATION_NAME = "aethertune-macos-notarization.json"


def verify_macos_release_artifacts(release_dir: Path) -> None:
    """Require a signed app archive and a stapled DMG attestation."""
    app_archive = release_dir / "aethertune-macos.zip"
    disk_image = release_dir / "aethertune-macos.dmg"
    attestation = release_dir / ATTESTATION_NAME
    if not app_archive.is_file() or not disk_image.is_file():
        raise ValueError("production release is missing macOS ZIP or DMG")
    try:
        with zipfile.ZipFile(app_archive) as archive:
            entries = set(archive.namelist())
    except zipfile.BadZipFile as error:
        raise ValueError("macOS app archive is not a valid ZIP") from error
    if not any(
        entry.endswith(".app/Contents/_CodeSignature/CodeResources")
        for entry in entries
    ):
        raise ValueError("macOS app archive does not contain a code signature")

    try:
        evidence = json.loads(attestation.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError("macOS notarization attestation is missing or invalid") from error
    expected = {
        "schema_version": 1,
        "app_archive": app_archive.name,
        "disk_image": disk_image.name,
        "notarized": True,
        "stapled": True,
    }
    if evidence != expected:
        raise ValueError("macOS notarization attestation does not prove a stapled release")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-dir", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        verify_macos_release_artifacts(arguments.release_dir.resolve())
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
