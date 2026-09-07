#!/usr/bin/env python3
"""Build and scan the server image; missing evidence and scanner errors fail closed."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TRIVY_VERSION = "0.70.0"
TRIVY_IMAGE = (
    "aquasec/trivy:0.70.0@sha256:"
    "85e87be1a96459c38a4eea47dc64eb2d342bb14cd4b4cef96adcf6ff03378b7c"
)
COSIGN_IMAGE = (
    "ghcr.io/sigstore/cosign/cosign:v3.1.3@sha256:"
    "9e5c2f2edc34351160407ca3416c61855bdf9403c3c5936e0f0be7fc261611b8"
)
BLOCKING_SEVERITIES = {"HIGH", "CRITICAL"}


def validate_database(metadata: dict, now: datetime) -> None:
    if metadata.get("Version") != 2:
        raise ValueError("Vulnerability database metadata is missing or unsupported")
    updated = datetime.fromisoformat(metadata["UpdatedAt"].replace("Z", "+00:00"))
    if updated.tzinfo is None or not -timedelta(minutes=5) <= now - updated <= timedelta(hours=48):
        raise ValueError("Vulnerability database must be at most 48 hours old and not future-dated")


def validate_report(report: dict, image_id: str, scan_exit_code: int) -> list[dict]:
    if report.get("SchemaVersion") != 2 or report.get("ArtifactType") != "container_image":
        raise ValueError("Scanner did not produce a supported container report")
    if report.get("Trivy", {}).get("Version") != TRIVY_VERSION:
        raise ValueError("Report does not identify the pinned scanner version")
    metadata = report.get("Metadata", {})
    if metadata.get("ImageID") != image_id:
        raise ValueError("Report image ID does not match the built image")
    operating_system = metadata.get("OS", {})
    if not operating_system.get("Family") or not operating_system.get("Name"):
        raise ValueError("Container operating system was not identified")
    if operating_system.get("EOSL"):
        raise ValueError("Container operating system is end-of-life")
    results = report.get("Results")
    if not isinstance(results, list) or not any(
        result.get("Class") == "os-pkgs" and result.get("Packages")
        for result in results
    ):
        raise ValueError("No operating-system package inventory was scanned")
    findings = []
    for result in results:
        for vulnerability in result.get("Vulnerabilities", []):
            if vulnerability.get("Severity") in BLOCKING_SEVERITIES:
                findings.append({
                    "target": result.get("Target"),
                    "id": vulnerability.get("VulnerabilityID"),
                    "package": vulnerability.get("PkgName"),
                    "installed": vulnerability.get("InstalledVersion"),
                    "fixed": vulnerability.get("FixedVersion"),
                    "severity": vulnerability["Severity"],
                    "status": vulnerability.get("Status"),
                })
    if scan_exit_code != 0 and not findings:
        raise ValueError(f"Scanner failed with exit code {scan_exit_code}")
    return findings


def container_command(name: str, mounts: list[tuple[Path, str, bool]]) -> list[str]:
    command = [
        "docker", "run", "--rm", "--name", name, "--read-only",
        "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
        "--tmpfs", "/tmp:rw,nosuid,nodev,size=1g",
    ]
    if os.name == "posix":
        command += ["--user", f"{os.getuid()}:{os.getgid()}"]
    for source, destination, read_only in mounts:
        command += [
            "--mount",
            f"type=bind,src={source},dst={destination}" + (",readonly" if read_only else ""),
        ]
    return command


def scan_command(name: str, image: Path, output: Path, cache: Path) -> list[str]:
    return container_command(name, [
        (image, "/input", True), (output, "/output", False), (cache, "/cache", False),
    ]) + [
        TRIVY_IMAGE, "image", "--input", "/input/image.tar",
        "--format", "json", "--output", "/output/trivy.json",
        "--cache-dir", "/cache", "--timeout", "10m", "--disable-telemetry",
        "--exit-code", "1", "--exit-on-eol", "1",
        "--scanners", "vuln", "--pkg-types", "os,library",
        "--severity", "HIGH,CRITICAL", "--list-all-pkgs",
        "--ignorefile", "/dev/null", "--config", "/dev/null",
    ]


def runtime_base_image() -> str:
    dockerfile = (ROOT / "services/server/Dockerfile").read_text(encoding="utf-8")
    matches = re.findall(r"^FROM (gcr\.io/distroless/cc-debian13:nonroot@sha256:[0-9a-f]{64})$",
                         dockerfile, re.MULTILINE)
    if len(matches) != 1:
        raise ValueError("Expected one digest-pinned, supported Distroless runtime base")
    return matches[0]


def verification_command(name: str, base: str) -> list[str]:
    return container_command(name, []) + [
        "--env", "HOME=/tmp", "--env", "XDG_CACHE_HOME=/tmp/cache",
        COSIGN_IMAGE, "verify", "--certificate-oidc-issuer", "https://accounts.google.com",
        "--certificate-identity", "keyless@distroless.iam.gserviceaccount.com", base,
    ]


def run(command: list[str], log: Path, timeout: int = 900) -> int:
    print(f"Running: {' '.join(command)}", flush=True)
    with log.open("a", encoding="utf-8") as stream:
        return subprocess.run(
            command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
            timeout=timeout, check=False,
        ).returncode


def require_success(command: list[str], log: Path, timeout: int = 900) -> None:
    status = run(command, log, timeout)
    if status != 0:
        raise RuntimeError(f"{command[0]} {command[1]} failed with exit code {status}; see {log.name}")


def remove_container(name: str, log: Path) -> None:
    if run(["docker", "rm", "--force", name], log, 60) == 0:
        return
    # --rm can remove it first; distinguish that race from a failed cleanup.
    result = subprocess.run(
        ["docker", "container", "ls", "--all", "--filter", f"name=^/{name}$",
         "--format", "{{.Names}}"],
        cwd=ROOT, capture_output=True, text=True, timeout=60, check=False,
    )
    with log.open("a", encoding="utf-8") as stream:
        stream.write(result.stdout + result.stderr)
    if result.returncode != 0 or result.stdout.strip():
        raise RuntimeError(f"Could not confirm removal of fixture container {name}")


def scan(evidence: Path) -> int:
    # A fresh directory/cache prevents old reports or an old local DB from passing this run.
    evidence = evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    result = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": os.environ.get("GITHUB_SHA"),
        "source_scope": "CI checkout" if os.environ.get("GITHUB_SHA") else "local working tree",
        "scanner": TRIVY_IMAGE,
        "policy": "HIGH/CRITICAL including unfixed; end-of-life OS and scanner errors fail",
        "result": "failed",
    }
    active_container = None
    try:
        result["runtime_base"] = runtime_base_image()
        result["signature_verifier"] = COSIGN_IMAGE
        active_container = f"aethertune-verify-{uuid.uuid4().hex}"
        try:
            require_success(verification_command(active_container, result["runtime_base"]),
                            evidence / "base-signature.log", 180)
            result["runtime_base_signature"] = "verified"
        finally:
            remove_container(active_container, evidence / "cleanup.log")
            active_container = None
        with tempfile.TemporaryDirectory(prefix=".container-scan-", dir=evidence.parent) as temporary:
            scratch = Path(temporary)
            image = scratch / "image"
            cache = scratch / "cache"
            image.mkdir()
            cache.mkdir()
            iid = scratch / "image-id.txt"
            require_success([
                "docker", "build", "--pull", "--iidfile", str(iid),
                str(ROOT / "services" / "server"),
            ], evidence / "build.log")
            image_id = iid.read_text(encoding="utf-8").strip()
            if not re.fullmatch(r"sha256:[0-9a-f]{64}", image_id):
                raise ValueError("Docker build did not produce an immutable image ID")
            result["image_id"] = image_id
            require_success([
                sys.executable, str(ROOT / "scripts/ci/server_container_runtime.py"),
                "--image", image_id, "--evidence", str(evidence / "runtime"),
            ], evidence / "runtime.log", 300)
            result["runtime_result"] = "passed"
            require_success([
                "docker", "image", "save", "--output", str(image / "image.tar"), image_id,
            ], evidence / "build.log")
            active_container = f"aethertune-scan-{uuid.uuid4().hex}"
            try:
                scan_status = run(scan_command(active_container, image, evidence, cache),
                                  evidence / "scanner.log")
                result["scanner_exit_code"] = scan_status
            finally:
                remove_container(active_container, evidence / "cleanup.log")
                active_container = None
            database = json.loads((cache / "db" / "metadata.json").read_text(encoding="utf-8"))
            result["database"] = database
            validate_database(database, datetime.now(timezone.utc))
            report = json.loads((evidence / "trivy.json").read_text(encoding="utf-8"))
            findings = validate_report(report, image_id, scan_status)
            result["findings"] = findings
            result["blocking_findings"] = len(findings)
            active_container = f"aethertune-scan-{uuid.uuid4().hex}"
            try:
                require_success(container_command(active_container, [(evidence, "/output", False)]) + [
                    "--network", "none", TRIVY_IMAGE, "convert",
                    "--format", "sarif", "--output", "/output/trivy.sarif", "/output/trivy.json",
                ], evidence / "scanner.log")
            finally:
                remove_container(active_container, evidence / "cleanup.log")
                active_container = None
            sarif = json.loads((evidence / "trivy.sarif").read_text(encoding="utf-8"))
            if sarif.get("version") != "2.1.0" or not sarif.get("runs"):
                raise ValueError("SARIF evidence is missing or invalid")
            if findings:
                raise ValueError(f"{len(findings)} HIGH/CRITICAL package vulnerabilities found")
            result["result"] = "passed"
    except (OSError, ValueError, KeyError, TypeError, AttributeError, RuntimeError, subprocess.SubprocessError) as error:
        result["error"] = str(error)
    finally:
        if active_container:
            try:
                remove_container(active_container, evidence / "cleanup.log")
            except (OSError, RuntimeError, subprocess.SubprocessError):
                result["cleanup_error"] = active_container
                result["result"] = "failed"
        (evidence / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in result.items() if key != "findings"}, indent=2), flush=True)
    return 0 if result["result"] == "passed" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True, help="New evidence directory")
    raise SystemExit(scan(parser.parse_args().evidence))
