#!/usr/bin/env python3
"""Verify that a release manifest exactly describes an assembled bundle."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path, PurePosixPath

from generate_release_manifest import sha256


METADATA_FILES = frozenset({"RELEASE_MANIFEST.json", "SHA256SUMS.txt"})


def bundle_files(release_dir: Path) -> set[str]:
    return {
        path.relative_to(release_dir).as_posix()
        for path in release_dir.rglob("*")
        if path.is_file() and path.relative_to(release_dir).as_posix() not in METADATA_FILES
    }


def verify_release_manifest(release_dir: Path, manifest_path: Path) -> None:
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read release manifest: {manifest_path}") from error

    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ValueError("release manifest must have schema_version 1")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, list):
        raise ValueError("release manifest must contain an artifacts list")

    entries: dict[str, dict[str, object]] = {}
    for artifact in artifacts:
        if not isinstance(artifact, dict):
            raise ValueError("release manifest artifacts must be objects")
        name = artifact.get("file")
        if not isinstance(name, str):
            raise ValueError("release manifest artifact file names must be strings")
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or name in METADATA_FILES:
            raise ValueError(f"release manifest has an unsafe artifact path: {name}")
        if name in entries:
            raise ValueError(f"release manifest has a duplicate artifact: {name}")
        entries[name] = artifact

    actual_files = bundle_files(release_dir)
    if set(entries) != actual_files:
        missing = sorted(actual_files - set(entries))
        unexpected = sorted(set(entries) - actual_files)
        raise ValueError(
            f"release manifest does not match bundle files; missing={missing}, unexpected={unexpected}"
        )

    for name, artifact in entries.items():
        path = release_dir.joinpath(*PurePosixPath(name).parts)
        expected_size = artifact.get("size_bytes")
        expected_digest = artifact.get("sha256")
        if not isinstance(expected_size, int) or expected_size < 0:
            raise ValueError(f"release manifest has an invalid size for {name}")
        if not isinstance(expected_digest, str):
            raise ValueError(f"release manifest has an invalid digest for {name}")
        if path.stat().st_size != expected_size:
            raise ValueError(f"release manifest size does not match {name}")
        if sha256(path) != expected_digest:
            raise ValueError(f"release manifest digest does not match {name}")


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
        verify_release_manifest(release_dir, manifest_path)
    except ValueError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
