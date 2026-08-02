#!/usr/bin/env python3
"""Validate the signed structure of an iOS IPA release artifact."""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path


def verify_ios_release_artifact(path: Path) -> None:
    """Require one signed Flutter app with its provisioning profile."""
    if not path.is_file():
        raise ValueError(f"IPA does not exist: {path}")
    try:
        with zipfile.ZipFile(path) as archive:
            entries = set(archive.namelist())
    except zipfile.BadZipFile as error:
        raise ValueError(f"IPA is not a valid ZIP archive: {path}") from error

    app_roots = sorted(
        {
            f"Payload/{parts[1]}/"
            for entry in entries
            if len(parts := entry.split("/")) >= 3
            and parts[0] == "Payload"
            and parts[1].endswith(".app")
        }
    )
    if len(app_roots) != 1:
        raise ValueError("IPA must contain exactly one app bundle under Payload/")
    app_root = app_roots[0]
    required_entries = {
        f"{app_root}Info.plist",
        f"{app_root}embedded.mobileprovision",
        f"{app_root}_CodeSignature/CodeResources",
        f"{app_root}Frameworks/App.framework/flutter_assets/AssetManifest.bin",
    }
    missing = sorted(required_entries - entries)
    if missing:
        raise ValueError("IPA is missing required signed entries: " + ", ".join(missing))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True, type=Path)
    arguments = parser.parse_args()
    try:
        verify_ios_release_artifact(arguments.ipa)
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
