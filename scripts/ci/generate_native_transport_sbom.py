#!/usr/bin/env python3
"""Create a deterministic all-target transport lock inventory, not a whole-app SBOM."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import tomllib
from pathlib import Path
from urllib.parse import quote
from uuid import NAMESPACE_URL, uuid5


ROOT = Path(__file__).resolve().parents[2]
LOCK = ROOT / "apps/mobile/packages/rhttp/rust/Cargo.lock"
REGISTRY = "registry+https://github.com/rust-lang/crates.io-index"


def generate_bom(lock_bytes: bytes) -> dict:
    lock = tomllib.loads(lock_bytes.decode("utf-8"))
    components = []
    root = None
    seen = set()
    for package in lock["package"]:
        name, version = package["name"], package["version"]
        if not isinstance(name, str) or not name or not isinstance(version, str) or not version:
            raise ValueError("Native dependency name and version must be nonempty strings")
        if package.get("source") is None:
            if name != "rhttp" or root is not None:
                raise ValueError("Unexpected local native package")
            root = {"type": "library", "name": "aethertune-native-transport", "version": version}
            continue
        if package["source"] != REGISTRY:
            raise ValueError("Native dependency requires a reviewed registry source")
        checksum = package.get("checksum", "")
        if not isinstance(checksum, str) or not re.fullmatch(r"[a-f0-9]{64}", checksum):
            raise ValueError("Native registry dependency requires a SHA-256 checksum")
        purl = f"pkg:cargo/{quote(name, safe='.-_~')}@{quote(version, safe='.-_~')}"
        if purl in seen:
            raise ValueError("Duplicate native dependency")
        seen.add(purl)
        components.append({
            "type": "library", "name": name, "version": version,
            "bom-ref": purl, "purl": purl,
            "hashes": [{"alg": "SHA-256", "content": checksum}],
        })
    if root is None or not components:
        raise ValueError("Native inventory requires the transport root and dependencies")
    digest = hashlib.sha256(lock_bytes).hexdigest()
    return {
        "$schema": "https://cyclonedx.org/schema/bom-1.5.schema.json",
        "bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1,
        "serialNumber": f"urn:uuid:{uuid5(NAMESPACE_URL, 'aethertune-native:' + digest)}",
        "metadata": {
            "component": root,
            "properties": [
                {"name": "aethertune:cargo-lock-sha256", "value": digest},
                {"name": "aethertune:scope", "value": "All-target locked transport dependencies; not the complete application or a platform-specific linked-binary inventory"},
            ],
        },
        "components": sorted(components, key=lambda component: component["purl"]),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    rendered = json.dumps(generate_bom(LOCK.read_bytes()), indent=2, sort_keys=True) + "\n"
    if args.check:
        if args.output.read_text(encoding="utf-8") != rendered:
            raise ValueError("Native transport SBOM does not match the lockfile")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
