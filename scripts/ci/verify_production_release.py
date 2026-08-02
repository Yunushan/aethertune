#!/usr/bin/env python3
"""Reject release bundles that are explicitly marked as non-production."""

from __future__ import annotations

import argparse
import re
import json
import sys
import zipfile
from pathlib import Path, PurePosixPath

from generate_release_manifest import ARTIFACT_DETAILS, sha256
from verify_android_release_artifacts import verify_android_release_artifacts
from verify_ios_release_artifact import verify_ios_release_artifact
from verify_macos_release_artifacts import verify_macos_release_artifacts
from verify_release_manifest import verify_release_manifest
from verify_windows_release_artifacts import verify_windows_release_artifacts


PROVENANCE_ARTIFACTS = frozenset(
    {
        "aethertune-mobile-dependencies.json",
        "aethertune-mobile.cdx.json",
        "aethertune-server-dependencies.json",
        "aethertune-server.cdx.json",
    }
)
PRODUCTION_ARTIFACTS = frozenset(
    (set(ARTIFACT_DETAILS) - {"aethertune-ios-unsigned.zip"})
    | PROVENANCE_ARTIFACTS
)
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


def verify_checksum_sidecar(release_dir: Path, artifact_names: set[str]) -> None:
    checksum_path = release_dir / "SHA256SUMS.txt"
    if not checksum_path.is_file():
        raise ValueError("production release is missing SHA256SUMS.txt")

    entries: dict[str, str] = {}
    for line in checksum_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        digest, separator, name = line.partition("  ")
        path = PurePosixPath(name)
        if (
            not separator
            or not SHA256_PATTERN.fullmatch(digest)
            or path.is_absolute()
            or len(path.parts) != 1
            or ".." in path.parts
            or "\\" in name
            or name == "SHA256SUMS.txt"
            or name in entries
        ):
            raise ValueError(f"production release has an invalid checksum entry: {line}")
        entries[name] = digest

    expected_names = set(artifact_names) | {"RELEASE_MANIFEST.json"}
    if set(entries) != expected_names:
        raise ValueError(
            "production checksum sidecar does not match the artifact set; "
            f"missing={sorted(expected_names - set(entries))}, "
            f"unexpected={sorted(set(entries) - expected_names)}"
        )
    for name, expected_digest in entries.items():
        path = release_dir / name
        if not path.is_file() or sha256(path) != expected_digest:
            raise ValueError(f"production checksum does not match {name}")


def verify_production_release(release_dir: Path, manifest_path: Path) -> None:
    """Validate the bundle and fail closed on unsigned or debug artifacts."""
    verify_release_manifest(release_dir, manifest_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    rejected: list[str] = []
    artifact_names = {str(artifact["file"]) for artifact in manifest["artifacts"]}
    for artifact in manifest["artifacts"]:
        file_name = str(artifact["file"])
        kind = str(artifact.get("kind", ""))
        marker = f"{file_name} {kind}".lower()
        if "unsigned" in marker or "debug" in marker:
            rejected.append(file_name)
            continue
        if file_name.lower().endswith(".msix"):
            path = release_dir / file_name
            try:
                with zipfile.ZipFile(path) as archive:
                    signed = "AppxSignature.p7x" in archive.namelist()
            except zipfile.BadZipFile as error:
                raise ValueError(f"MSIX is not a valid package: {file_name}") from error
            if not signed:
                rejected.append(f"{file_name} (missing AppxSignature.p7x)")
    if rejected:
        raise ValueError(
            "production release contains unsigned or debug artifacts: "
            + ", ".join(sorted(rejected))
        )
    missing = sorted(PRODUCTION_ARTIFACTS - artifact_names)
    unexpected = sorted(artifact_names - PRODUCTION_ARTIFACTS)
    if missing or unexpected:
        raise ValueError(
            "production release artifact set is not exact; "
            f"missing={missing}, unexpected={unexpected}"
        )
    verify_checksum_sidecar(release_dir, artifact_names)
    if {"app-release.apk", "app-release.aab"}.issubset(artifact_names):
        verify_android_release_artifacts(
            release_dir / "app-release.apk",
            release_dir / "app-release.aab",
            require_signing=True,
        )
    if "aethertune-ios.ipa" in artifact_names:
        verify_ios_release_artifact(release_dir / "aethertune-ios.ipa")
    if {"aethertune-macos.zip", "aethertune-macos.dmg"}.issubset(artifact_names):
        verify_macos_release_artifacts(release_dir)
    if {"aethertune-windows-x64.zip", "aethertune-windows-x64.msix"}.issubset(
        artifact_names
    ):
        verify_windows_release_artifacts(
            release_dir / "aethertune-windows-x64.zip",
            release_dir / "aethertune-windows-x64.msix",
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-dir", required=True, type=Path)
    parser.add_argument("--manifest", required=True, type=Path)
    arguments = parser.parse_args()
    release_dir = arguments.release_dir.resolve()
    manifest_path = arguments.manifest.resolve()
    if not release_dir.is_dir():
        parser.error(f"release directory does not exist: {release_dir}")
    try:
        verify_production_release(release_dir, manifest_path)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
