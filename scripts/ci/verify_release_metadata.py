#!/usr/bin/env python3
"""Fail closed when a production release is missing repository metadata."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TAG_PATTERN = re.compile(r"^v(?P<version>[0-9]+\.[0-9]+\.[0-9]+)$")
PUBSPEC_VERSION_PATTERN = re.compile(
    r"^version:\s*(?P<version>[0-9]+\.[0-9]+\.[0-9]+)(?:\+[0-9]+)?\s*$",
    re.MULTILINE,
)


def _read(path: Path, label: str) -> str:
    if not path.is_file():
        raise ValueError(f"{label} does not exist: {path}")
    return path.read_text(encoding="utf-8")


def _has_release_section(changelog: str, heading: str) -> bool:
    match = re.search(
        rf"^##\s+{re.escape(heading)}\s*$([\s\S]*?)(?=^##\s+|\Z)",
        changelog,
        re.MULTILINE,
    )
    return bool(match and re.search(r"^\s*-\s+\S", match.group(1), re.MULTILINE))


def verify_release_metadata(
    *,
    tag: str | None,
    pubspec_path: Path,
    changelog_path: Path,
    feature_matrix_path: Path,
    license_path: Path,
    notice_path: Path,
) -> None:
    failures: list[str] = []
    pubspec = _read(pubspec_path, "pubspec")
    changelog = _read(changelog_path, "changelog")
    feature_matrix = _read(feature_matrix_path, "feature matrix")
    license_text = _read(license_path, "license")
    notice = _read(notice_path, "NOTICE")

    if not feature_matrix.strip() or "|" not in feature_matrix:
        failures.append("feature matrix is missing or empty")
    if "BSD Zero Clause License" not in license_text:
        failures.append("root license is not the BSD Zero Clause License")
    if "AetherTune" not in notice:
        failures.append("NOTICE does not identify AetherTune")

    if tag is None:
        if not _has_release_section(changelog, "Unreleased"):
            failures.append("changelog is missing a non-empty Unreleased section")
    else:
        tag_match = TAG_PATTERN.fullmatch(tag)
        if tag_match is None:
            failures.append(f"release tag must use vMAJOR.MINOR.PATCH: {tag}")
        else:
            version = tag_match.group("version")
            pubspec_match = PUBSPEC_VERSION_PATTERN.search(pubspec)
            if pubspec_match is None:
                failures.append("pubspec has no semantic version field")
            elif pubspec_match.group("version") != version:
                failures.append(
                    f"release tag {tag} does not match pubspec version "
                    f"{pubspec_match.group('version')}"
                )
            if not _has_release_section(changelog, version):
                failures.append(f"changelog has no non-empty {version} section")

    if failures:
        raise ValueError("; ".join(failures))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag")
    parser.add_argument(
        "--pubspec",
        type=Path,
        default=ROOT / "apps" / "mobile" / "pubspec.yaml",
    )
    parser.add_argument(
        "--changelog", type=Path, default=ROOT / "CHANGELOG.md"
    )
    parser.add_argument(
        "--feature-matrix",
        type=Path,
        default=ROOT / "docs" / "FEATURE_MATRIX.md",
    )
    parser.add_argument("--license", type=Path, default=ROOT / "LICENSE")
    parser.add_argument("--notice", type=Path, default=ROOT / "NOTICE")
    arguments = parser.parse_args()
    try:
        verify_release_metadata(
            tag=arguments.tag,
            pubspec_path=arguments.pubspec.resolve(),
            changelog_path=arguments.changelog.resolve(),
            feature_matrix_path=arguments.feature_matrix.resolve(),
            license_path=arguments.license.resolve(),
            notice_path=arguments.notice.resolve(),
        )
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
    print("Production release metadata passed.")


if __name__ == "__main__":
    main()
