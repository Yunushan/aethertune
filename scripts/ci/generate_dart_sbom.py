#!/usr/bin/env python3
"""Generate a deterministic CycloneDX SBOM from `dart pub deps --json` output.

The Dart/Flutter package lockfiles are intentionally generated in CI rather than
checked into this multi-package repository. This tool records the exact resolved
graph used by a build without adding another network service or action.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any
from urllib.parse import quote
from uuid import NAMESPACE_URL, uuid5


_SCHEMA_URL = "https://cyclonedx.org/schema/bom-1.5.schema.json"
_GENERATOR = "aethertune/scripts/ci/generate_dart_sbom.py"


def _require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{field} must be a non-empty string")
    return value


def _component_purl(name: str, version: str, source: str) -> str:
    package_type = "pub" if source == "hosted" else "generic"
    encoded_name = quote(name, safe=".-_~")
    encoded_version = quote(version, safe=".-_~")
    return f"pkg:{package_type}/{encoded_name}@{encoded_version}"


def _dependency_components(graph: dict[str, Any]) -> list[dict[str, Any]]:
    packages = graph.get("packages")
    if not isinstance(packages, list):
        raise ValueError("dependency graph must contain a packages array")

    root = graph.get("root")
    root_name = root.get("name") if isinstance(root, dict) else None
    components: list[dict[str, Any]] = []
    names: set[str] = set()

    for package in packages:
        if not isinstance(package, dict):
            raise ValueError("each package must be an object")
        name = _require_string(package.get("name"), "package name")
        if name == root_name or package.get("kind") == "root":
            continue
        if name in names:
            raise ValueError(f"dependency graph contains duplicate package {name!r}")
        names.add(name)
        version = _require_string(package.get("version"), f"version for {name}")
        source = _require_string(package.get("source"), f"source for {name}")
        kind = _require_string(package.get("kind"), f"kind for {name}")
        purl = _component_purl(name, version, source)
        components.append(
            {
                "type": "library",
                "name": name,
                "version": version,
                "bom-ref": purl,
                "purl": purl,
                "properties": [
                    {"name": "aethertune:dart-kind", "value": kind},
                    {"name": "aethertune:dart-source", "value": source},
                ],
            }
        )

    if not components:
        raise ValueError("dependency graph contains no resolved dependencies")
    return sorted(components, key=lambda component: component["name"].lower())


def generate_bom(graph: dict[str, Any], component_name: str) -> dict[str, Any]:
    """Return a stable CycloneDX 1.5 document for one resolved Dart graph."""
    component_name = _require_string(component_name, "component name")
    root = graph.get("root")
    if not isinstance(root, dict):
        raise ValueError("dependency graph must contain a root object")
    root_version = _require_string(root.get("version"), "root version")
    components = _dependency_components(graph)
    graph_sha256 = hashlib.sha256(
        json.dumps(graph, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    root_purl = _component_purl(component_name, root_version, "root")

    return {
        "$schema": _SCHEMA_URL,
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": f"urn:uuid:{uuid5(NAMESPACE_URL, f'aethertune:{component_name}:{graph_sha256}')}",
        "version": 1,
        "metadata": {
            "component": {
                "type": "application",
                "name": component_name,
                "version": root_version,
                "bom-ref": root_purl,
                "purl": root_purl,
            },
            "tools": {
                "components": [
                    {
                        "type": "application",
                        "author": "AetherTune",
                        "name": _GENERATOR,
                    }
                ]
            },
            "properties": [
                {"name": "aethertune:dependency-graph-sha256", "value": graph_sha256},
                {"name": "aethertune:reproducible", "value": "true"},
            ],
        },
        "components": components,
    }


def _render_bom(graph: dict[str, Any], component_name: str) -> str:
    return json.dumps(generate_bom(graph, component_name), indent=2, sort_keys=True) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--deps-json", type=Path, required=True)
    parser.add_argument("--component-name", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail when an existing SBOM differs from deterministic output",
    )
    args = parser.parse_args()

    try:
        graph = json.loads(args.deps_json.read_text(encoding="utf-8"))
        if not isinstance(graph, dict):
            raise ValueError("dependency graph must be a JSON object")
        rendered = _render_bom(graph, args.component_name)
        if args.check:
            if not args.output.is_file():
                raise ValueError(f"SBOM does not exist: {args.output}")
            if args.output.read_text(encoding="utf-8") != rendered:
                raise ValueError(f"SBOM is not reproducible: {args.output}")
            print(f"Verified reproducible SBOM: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8")
            print(f"Wrote {args.output}")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        parser.error(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
