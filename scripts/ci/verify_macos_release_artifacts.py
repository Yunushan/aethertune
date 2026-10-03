#!/usr/bin/env python3
"""Check archive bindings in the attested macOS production signing receipt.

Portable consistency checks do not replace native Apple authorization, signature
assessment, notarization or installed execution/Keychain continuity acceptance.
"""
from __future__ import annotations

import argparse
import json
import plistlib
import sys
import zipfile
from pathlib import Path

from macos_signing_contract import validate_package_receipt

ATTESTATION_NAME = "aethertune-macos-notarization.json"


def verify_macos_release_artifacts(release_dir: Path) -> None:
    if not (release_dir / "aethertune-macos.zip").is_file() or not (release_dir / "aethertune-macos.dmg").is_file():
        raise ValueError("production release is missing macOS ZIP or DMG")
    try:
        evidence = json.loads((release_dir / ATTESTATION_NAME).read_text(encoding="utf-8"))
        validate_package_receipt(release_dir, evidence)
    except (OSError, ValueError, TypeError, KeyError, AttributeError, zipfile.BadZipFile,
            plistlib.InvalidFileException) as error:
        raise ValueError(f"invalid macOS production receipt: {error}") from error


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
