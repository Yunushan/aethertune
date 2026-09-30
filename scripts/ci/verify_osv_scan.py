#!/usr/bin/env python3
"""Reject unusable OSV scan evidence before the policy reporter consumes it."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _object(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def _list(value: object, label: str) -> list:
    if not isinstance(value, list):
        raise ValueError(f"{label} must be an array")
    return value


def _strings(value: object, label: str) -> list[str]:
    values = _list(value, label)
    if any(not isinstance(item, str) for item in values):
        raise ValueError(f"{label} must contain strings")
    return values


def _typed_fields(value: dict, fields: tuple[str, ...], kind: type, label: str) -> None:
    for field in fields:
        if field in value and not isinstance(value[field], kind):
            raise ValueError(f"{label}.{field} must be {kind.__name__}")


def _unique_object(pairs: list[tuple[str, object]]) -> dict:
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON field: {key}")
        value[key] = item
    return value


def _reject_constant(value: str) -> None:
    raise ValueError(f"invalid JSON constant: {value}")


def verify_osv_scan(path: Path, exit_code: int) -> None:
    if type(exit_code) is not int or exit_code not in {0, 1}:
        raise ValueError(f"scanner failed with exit code {exit_code}; only 0 and 1 are scan results")
    try:
        data = json.loads(
            path.read_text(encoding="utf-8"),
            object_pairs_hook=_unique_object,
            parse_constant=_reject_constant,
        )
    except (OSError, UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise ValueError(f"cannot read scanner results: {error}") from error
    data = _object(data, "scan")
    results = _list(data.get("results"), "scan.results")
    findings = False
    for result in results:
        result = _object(result, "result")
        source = _object(result.get("source"), "result.source")
        for field in ("path", "type"):
            if not isinstance(source.get(field), str):
                raise ValueError(f"result.source.{field} must be a string")
        for package in _list(result.get("packages"), "result.packages"):
            package = _object(package, "package")
            identity = _object(package.get("package"), "package.package")
            for field in ("name", "version", "ecosystem"):
                if not isinstance(identity.get(field), str):
                    raise ValueError(f"package.package.{field} must be a string")
            _typed_fields(identity, ("commit", "os_package_name"), str, "package.package")
            _typed_fields(identity, ("deprecated",), bool, "package.package")
            findings |= identity.get("deprecated", False)
            for field in ("licenses", "license_violations", "dependency_groups"):
                values = _strings(package.get(field, []), f"package.{field}")
                if field == "license_violations":
                    findings |= bool(values)
            group_ids = set()
            for group in _list(package.get("groups", []), "package.groups"):
                group = _object(group, "group")
                group_ids.update(_strings(group.get("ids"), "group.ids"))
                _strings(group.get("aliases", []), "group.aliases")
                _typed_fields(group, ("max_severity",), str, "group")
                for analysis in _object(
                    group.get("experimental_analysis", {}), "group.experimental_analysis"
                ).values():
                    analysis = _object(analysis, "analysis")
                    _typed_fields(analysis, ("called", "unimportant"), bool, "analysis")
            vulnerabilities = _list(
                package.get("vulnerabilities", []), "package.vulnerabilities"
            )
            for vulnerability in vulnerabilities:
                vulnerability = _object(vulnerability, "vulnerability")
                identifier = vulnerability.get("id")
                if not isinstance(identifier, str) or not identifier:
                    raise ValueError("vulnerability.id must be a nonempty string")
                if identifier not in group_ids:
                    raise ValueError(f"vulnerability {identifier} has no reporter group")
                _typed_fields(
                    vulnerability,
                    ("schema_version", "modified", "published", "withdrawn", "summary", "details"),
                    str,
                    "vulnerability",
                )
                for field in ("aliases", "related", "upstream"):
                    _strings(vulnerability.get(field, []), f"vulnerability.{field}")
                for field in ("affected", "references", "severity", "credits"):
                    for entry in _list(vulnerability.get(field, []), f"vulnerability.{field}"):
                        _object(entry, f"vulnerability.{field} entry")
            findings |= bool(vulnerabilities)
    # A nonzero exit with valid findings is expected. The reporter retains the
    # authority to apply fail-on-vuln, license and call-analysis policy.
    if exit_code == 1 and not findings:
        raise ValueError("scanner failed without producing reportable findings")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    parser.add_argument("--exit-code", type=int, required=True)
    args = parser.parse_args()
    try:
        verify_osv_scan(args.results, args.exit_code)
    except ValueError as error:
        print(f"::error::Unusable OSV scan evidence: {error}", file=sys.stderr)
        return 1
    print("OSV scan evidence is usable; the reporter will enforce finding policy.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
