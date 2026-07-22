#!/usr/bin/env python3
"""Generate a deterministic inventory of files in an assembled release bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


ARTIFACT_DETAILS = {
    "app-release.aab": ("android", "app-bundle"),
    "app-release.apk": ("android", "apk"),
    "aethertune-linux-x64.deb": ("linux", "debian-package"),
    "aethertune-linux-x64.tar.gz": ("linux", "portable-archive"),
    "aethertune-macos.dmg": ("macos", "disk-image"),
    "aethertune-macos.zip": ("macos", "app-archive"),
    "aethertune-server-linux-x64": ("linux", "server-executable"),
    "aethertune-server-macos": ("macos", "server-executable"),
    "aethertune-server-windows-x64.exe": ("windows", "server-executable"),
    "aethertune-windows-x64.zip": ("windows", "portable-archive"),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def artifact_details(relative_path: Path) -> tuple[str, str]:
    known = ARTIFACT_DETAILS.get(relative_path.name)
    if known is not None:
        return known
    if relative_path.name.endswith(".cdx.json"):
        return "provenance", "cyclonedx-sbom"
    if relative_path.name.endswith("-dependencies.json"):
        return "provenance", "dependency-graph"
    return "other", "supporting-file"


def generate_manifest(release_dir: Path, output_path: Path) -> dict[str, object]:
    output_relative = output_path.relative_to(release_dir)
    artifacts = []
    for path in sorted(release_dir.rglob("*")):
        if not path.is_file() or path.relative_to(release_dir) == output_relative:
            continue
        relative_path = path.relative_to(release_dir)
        platform, kind = artifact_details(relative_path)
        artifacts.append(
            {
                "file": relative_path.as_posix(),
                "kind": kind,
                "platform": platform,
                "sha256": sha256(path),
                "size_bytes": path.stat().st_size,
            }
        )
    return {"artifacts": artifacts, "schema_version": 1}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release-dir", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    arguments = parser.parse_args()

    release_dir = arguments.release_dir.resolve()
    output_path = arguments.output.resolve()
    if not release_dir.is_dir():
        parser.error(f"release directory does not exist: {release_dir}")
    if release_dir not in output_path.parents:
        parser.error("output must be inside the release directory")

    manifest = generate_manifest(release_dir, output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
