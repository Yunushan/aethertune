#!/usr/bin/env python3
"""Verify fixed original release inputs for a separate, nonpublishing Linux test.

This receipt verifies inputs only. Runtime acceptance belongs to the coordinator.
The product is never rebuilt, patched, or certified as the executor's source.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import tarfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
REPOSITORY = "Yunushan/aethertune"
SOURCE = "4b9a309856ab028efc45d8a434ccaabda014e9c0"
SOURCE_REF = "refs/heads/codex/readiness-linux-behavior"
RUN_ID, RUN_ATTEMPT, ARTIFACT_ID = 37130672909, 1, 11277216890
REPOSITORY_ID = 1290323211
OUTER_SHA256 = "45556692c3d64e4f7890b7f9a3f4587e126d74cc54dfcd4188fb62ad5a491262"
ARCHIVE_BYTES = 432725553
MANIFEST_SHA256 = "8815e607e53d9b51cd4a54ab302958418ccd6a523105c090cd33aa5353ef7186"
DEB_SHA256 = "89e536125f1436d809c332e54ab9a85328d3308eec985223875aae63cd9ce3ef"
TARBALL_SHA256 = "d41c76c2a93ea5b0efdf466b081f30ead45d7dbf75f875b468b8e7f20345934f"
EXECUTABLE_SHA256 = "3d8ff13301a5c212be9e020a8d7a20899945d8d5e40401c84136a103357061fc"
WORKFLOW = ".github/workflows/aethertune-release.yml"
CERT_IDENTITY = f"https://github.com/{REPOSITORY}/{WORKFLOW}@{SOURCE_REF}"
INVOCATION = f"https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}/attempts/{RUN_ATTEMPT}"
MAX_ZIP_BYTES, MAX_TAR_BYTES = 768 * 1024 * 1024, 128 * 1024 * 1024
SOURCE_FILES = (
    "scripts/ci/generate_release_manifest.py",
    "scripts/ci/verify_release_manifest.py",
    "scripts/ci/verify_release_metadata.py",
    "scripts/ci/generate_dart_sbom.py",
    "scripts/ci/generate_native_transport_sbom.py",
    "scripts/ci/linux_packaged_release_acceptance.py",
    "apps/mobile/pubspec.yaml", "apps/mobile/pubspec.lock",
    "services/server/pubspec.lock",
    "apps/mobile/packages/rhttp/rust/Cargo.lock",
    "CHANGELOG.md", "docs/FEATURE_MATRIX.md", "LICENSE", "NOTICE",
)
DRIVER_FILES = (
    ".github/workflows/linux-release-behavior.yml",
    "scripts/ci/prepare_linux_release_behavior.py",
    "scripts/ci/linux_packaged_release_acceptance.py",
    "scripts/ci/linux_release_ui_acceptance.py",
)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha256(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def gh_environment():
    env = os.environ.copy()
    env.pop("GH_DEBUG", None)
    env["GH_HOST"] = "github.com"
    env["GH_PROMPT_DISABLED"] = "1"
    return env


def command(args, proof, label, *, env=None):
    try:
        result = subprocess.run(args, capture_output=True, timeout=180, env=env)
    except subprocess.TimeoutExpired as error:
        (proof / f"{label}.stdout").write_bytes(error.stdout or b"")
        (proof / f"{label}.stderr").write_bytes(error.stderr or b"")
        raise ValueError(f"{label} timed out; see retained partial proof") from error
    (proof / f"{label}.stdout").write_bytes(result.stdout)
    (proof / f"{label}.stderr").write_bytes(result.stderr)
    require(result.returncode == 0, f"{label} failed (exit {result.returncode}); see retained proof")
    return result.stdout


def verify_metadata(artifact, run):
    require(run.get("id") == RUN_ID and run.get("run_attempt") == RUN_ATTEMPT,
            "Original workflow run/attempt mismatch")
    require(run.get("head_sha") == SOURCE and run.get("head_branch") == SOURCE_REF.removeprefix("refs/heads/"),
            "Original workflow source mismatch")
    require(run.get("event") == "workflow_dispatch" and run.get("path") == WORKFLOW
            and run.get("status") == "completed" and run.get("conclusion") == "success",
            "Original candidate is not the completed successful nonpublishing workflow")
    for field in ("repository", "head_repository"):
        require(run.get(field, {}).get("id") == REPOSITORY_ID
                and run[field].get("full_name") == REPOSITORY, "Original run repository mismatch")
    require(artifact.get("id") == ARTIFACT_ID and artifact.get("name") == "aethertune-release-bundle",
            "Original artifact identity mismatch")
    require(artifact.get("expired") is False and artifact.get("digest") == "sha256:" + OUTER_SHA256
            and artifact.get("size_in_bytes") == ARCHIVE_BYTES, "Original artifact digest/size/expiry mismatch")
    origin = artifact.get("workflow_run", {})
    require(origin.get("id") == RUN_ID and origin.get("head_sha") == SOURCE
            and origin.get("head_branch") == SOURCE_REF.removeprefix("refs/heads/")
            and origin.get("repository_id") == REPOSITORY_ID
            and origin.get("head_repository_id") == REPOSITORY_ID, "Original artifact source mismatch")
    require(artifact.get("archive_download_url") ==
            f"https://api.github.com/repos/{REPOSITORY}/actions/artifacts/{ARTIFACT_ID}/zip",
            "Original artifact download endpoint mismatch")


def download_archive(path, proof):
    # gh follows the official artifact API redirect; no signed URL or token is recorded.
    with path.open("xb") as output, (proof / "artifact-download.stderr").open("xb") as errors:
        process = subprocess.Popen(
            ["gh", "api", f"repos/{REPOSITORY}/actions/artifacts/{ARTIFACT_ID}/zip"],
            stdout=output, stderr=errors, env=gh_environment())
        deadline = time.monotonic() + 180
        try:
            while process.poll() is None:
                require(time.monotonic() < deadline, "Original artifact download timed out")
                require(path.stat().st_size <= ARCHIVE_BYTES, "Original artifact download exceeded pinned size")
                time.sleep(0.2)
            require(process.returncode == 0, "Original artifact download failed; see retained proof")
        finally:
            if process.poll() is None:
                process.kill()
            process.wait(timeout=10)
    require(path.stat().st_size == ARCHIVE_BYTES and sha256(path) == OUTER_SHA256,
            "Actual official outer artifact digest/size mismatch")


def extract_zip(path, target):
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        require(len(entries) == 19, "Original artifact must contain exactly 19 root files")
        names = [item.filename for item in entries]
        require(len(set(names)) == len(names), "Duplicate outer artifact paths")
        require(sum(item.file_size for item in entries) <= MAX_ZIP_BYTES, "Oversized outer artifact payload")
        for item in entries:
            mode = item.external_attr >> 16
            require(not item.is_dir() and not stat.S_ISLNK(mode)
                    and (stat.S_IFMT(mode) in (0, stat.S_IFREG))
                    and re.fullmatch(r"[A-Za-z0-9._-]+", item.filename)
                    and item.filename not in (".", "..") and not item.flag_bits & 1,
                    "Unsafe outer artifact entry")
            require(0 <= item.file_size <= MAX_ZIP_BYTES, "Oversized outer artifact file")
        target.mkdir()
        for item in entries:
            # No extractall: every target is a fresh exclusive regular root file.
            count = 0
            with archive.open(item) as source, (target / item.filename).open("xb") as output:
                while chunk := source.read(1024 * 1024):
                    count += len(chunk)
                    require(count <= item.file_size, "ZIP entry exceeds declared size")
                    output.write(chunk)
            require(count == item.file_size, "Truncated ZIP entry")


def verify_checksums(release):
    files = {path.name for path in release.iterdir()}
    require(len(files) == 19 and all(path.is_file() and not path.is_symlink()
                                   for path in release.iterdir()), "Unexpected release inventory")
    sums = {}
    for line in (release / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(r"([0-9a-f]{64}) [ *]([A-Za-z0-9._-]+)", line)
        require(match is not None, "Malformed release checksum")
        value, name = match.groups()
        require(name not in sums and name not in (".", ".."), "Duplicate/unsafe release checksum")
        sums[name] = value
    require(set(sums) == files - {"SHA256SUMS.txt"}, "Incomplete release checksum coverage")
    for name, value in sums.items():
        require(sha256(release / name) == value, f"Release checksum mismatch: {name}")
    require(sums.get("RELEASE_MANIFEST.json") == MANIFEST_SHA256
            and sums.get("aethertune-linux-x64.deb") == DEB_SHA256
            and sums.get("aethertune-linux-x64.tar.gz") == TARBALL_SHA256, "Pinned Linux subjects changed")
    return sums


def verify_source(source):
    require(subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip() == SOURCE,
            "Original verifier checkout is not exact product source")
    records = {}
    for name in SOURCE_FILES:
        path = source / name
        require(path.is_file() and not path.is_symlink(), f"Missing original source: {name}")
        committed = subprocess.check_output(["git", "-C", str(source), "show", f"{SOURCE}:{name}"])
        require(path.read_bytes() == committed, f"Original verifier source changed: {name}")
        records[name] = sha256(path)
    return records


def verify_graph_lock(graph, locktext):
    blocks = re.findall(r"^  ([a-z0-9_]+):\n(.*?)(?=^  [a-z0-9_]+:|^sdks:|\Z)",
                        locktext, re.M | re.S)
    require(bool(blocks), "Original Dart lockfile has no packages")
    versions = {}
    for name, block in blocks:
        match = re.search(r'^    version: "?([^"\n]+)"?$', block, re.M)
        require(match is not None and name not in versions, "Malformed original Dart lockfile")
        versions[name] = match.group(1)
    packages = {}
    for package in graph["packages"]:
        if package["name"] == graph["root"]:
            continue
        require(package["name"] not in packages, "Duplicate Dart graph package")
        packages[package["name"]] = package["version"]
    require(packages == versions, "Attested dependency graph differs from original committed lock")
    return len(packages)


def verify_bundle_source(source, release, proof):
    env = os.environ.copy()
    for key in ("GH_TOKEN", "GITHUB_TOKEN", "GH_DEBUG"):
        env.pop(key, None)
    def verifier(label, filename, *args):
        command([sys.executable, "-B", str(source / "scripts/ci" / filename), *map(str, args)],
                proof, label, env=env)
    verifier("manifest", "verify_release_manifest.py", "--release-dir", release,
             "--manifest", release / "RELEASE_MANIFEST.json")
    verifier("repository-metadata", "verify_release_metadata.py")
    graph_counts = {}
    for component, lock in (("mobile", "apps/mobile/pubspec.lock"), ("server", "services/server/pubspec.lock")):
        verifier(component + "-sbom", "generate_dart_sbom.py", "--deps-json",
                 release / f"aethertune-{component}-dependencies.json", "--component-name",
                 "aethertune-" + component, "--output", release / f"aethertune-{component}.cdx.json", "--check")
        graph = json.loads((release / f"aethertune-{component}-dependencies.json").read_text(encoding="utf-8"))
        graph_counts[component] = verify_graph_lock(graph, (source / lock).read_text(encoding="utf-8"))
    verifier("native-sbom", "generate_native_transport_sbom.py", "--output",
             release / "aethertune-native-transport.cdx.json", "--check")
    require(re.search(r"^version: 0\.1\.0\+1$", (source / "apps/mobile/pubspec.yaml").read_text(encoding="utf-8"), re.M),
            "Original product version changed")
    return graph_counts


def verify_attestation(results, subjects):
    require(isinstance(results, list) and bool(results), "No cryptographically verified attestation")
    expected_cert = {
        "subjectAlternativeName": CERT_IDENTITY, "buildSignerURI": CERT_IDENTITY,
        "issuer": "https://token.actions.githubusercontent.com", "buildSignerDigest": SOURCE,
        "sourceRepositoryDigest": SOURCE, "sourceRepositoryRef": SOURCE_REF,
        "sourceRepositoryURI": f"https://github.com/{REPOSITORY}",
        "sourceRepositoryIdentifier": str(REPOSITORY_ID),
        "sourceRepositoryOwnerIdentifier": "24549832", "runnerEnvironment": "github-hosted",
        "runInvocationURI": INVOCATION, "githubWorkflowTrigger": "workflow_dispatch",
    }
    accepted = []
    for result in results:
        verified = result["verificationResult"]
        cert = verified["signature"]["certificate"]
        require(all(cert.get(key) == value for key, value in expected_cert.items()),
                "Verified certificate is not the exact original hosted candidate")
        statement = verified["statement"]
        require(statement.get("_type") == "https://in-toto.io/Statement/v1"
                and statement.get("predicateType") == "https://slsa.dev/provenance/v1", "Unexpected attestation type")
        signed_subjects = {}
        for subject in statement["subject"]:
            name = subject["name"]
            require(name not in signed_subjects, "Duplicate attestation subject")
            signed_subjects[name] = subject["digest"].get("sha256")
        require(signed_subjects == subjects, "Attestation subject inventory/digests differ from all release checksums")
        predicate = statement["predicate"]
        definition = predicate["buildDefinition"]
        require(definition["externalParameters"]["workflow"] == {
            "path": WORKFLOW, "ref": SOURCE_REF, "repository": f"https://github.com/{REPOSITORY}"
        }, "Attestation original workflow mismatch")
        require(definition["resolvedDependencies"] == [{
            "digest": {"gitCommit": SOURCE},
            "uri": f"git+https://github.com/{REPOSITORY}@{SOURCE_REF}",
        }], "Attestation original source dependency mismatch")
        require(predicate["runDetails"]["metadata"]["invocationId"] == INVOCATION
                and predicate["runDetails"]["builder"]["id"] == CERT_IDENTITY, "Attestation run/builder mismatch")
        require(bool(verified.get("verifiedTimestamps")), "Verified attestation lacks a trusted timestamp")
        accepted.append({key: cert[key] for key in expected_cert})
    return accepted


def extract_tar(path, target):
    # This fixed original bundle has only directories and regular files.
    # Reject all links/special files rather than broaden that known format.
    with tarfile.open(path, "r:gz") as archive:
        entries, total_bytes = [], 0
        for item in archive:
            entries.append(item)
            total_bytes += item.size
            require(len(entries) <= 256 and 0 <= item.size <= MAX_TAR_BYTES
                    and total_bytes <= MAX_TAR_BYTES, "Oversized Linux bundle archive")
        require(bool(entries), "Empty Linux bundle archive")
        names = {}
        for item in entries:
            pure = PurePosixPath(item.name)
            require(not pure.is_absolute() and ".." not in pure.parts
                    and "\\" not in item.name and "\x00" not in item.name, "Unsafe Linux bundle path")
            name = str(pure)
            require(name not in names and (item.isdir() or item.isfile())
                    and item.mode & ~0o777 == 0 and item.size >= 0, "Duplicate/link/special Linux bundle entry")
            require(name != "." or item.isdir(), "Linux bundle root is not a directory")
            names[name] = item
        for name in names:
            for parent in PurePosixPath(name).parents:
                if str(parent) in names:
                    require(names[str(parent)].isdir(), "Linux bundle path traverses a regular file")
        target.mkdir()
        for name, item in sorted(names.items(), key=lambda pair: len(PurePosixPath(pair[0]).parts)):
            if name == ".":
                continue
            output = target / name
            if item.isdir():
                output.mkdir(parents=True, exist_ok=False)
            else:
                require(output.parent.is_dir(), "Linux bundle archive omits parent directory")
                count = 0
                with archive.extractfile(item) as stream, output.open("xb") as destination:
                    while chunk := stream.read(1024 * 1024):
                        count += len(chunk)
                        require(count <= item.size, "Linux tar entry exceeds declared size")
                        destination.write(chunk)
                require(count == item.size, "Truncated Linux tar entry")
                output.chmod(item.mode)
        for name, item in sorted(names.items(), key=lambda pair: -len(PurePosixPath(pair[0]).parts)):
            if item.isdir():
                (target / name).chmod(item.mode)


def executor_identity():
    head = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip()
    expected = os.environ.get("EXECUTOR_SOURCE_COMMIT", "")
    require(re.fullmatch(r"[0-9a-f]{40}", expected) and head == expected, "Executor checkout differs from requested run source")
    require(os.environ.get("GITHUB_REPOSITORY") == REPOSITORY, "Unexpected executor repository")
    hashes = {}
    for name in DRIVER_FILES:
        path = ROOT / name
        require(path.is_file() and not path.is_symlink(), f"Executor driver missing: {name}")
        committed = subprocess.check_output(["git", "-C", str(ROOT), "show", f"{head}:{name}"])
        require(path.read_bytes() == committed, f"Executor driver has uncommitted changes: {name}")
        hashes[name] = sha256(path)
    for key in ("GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT"):
        require(re.fullmatch(r"[1-9][0-9]*", os.environ.get(key, "")), f"Missing executor {key}")
    return {
        "repository": REPOSITORY, "sourceCommit": head, "triggerSha": os.environ["GITHUB_SHA"],
        "ref": os.environ["GITHUB_REF"], "event": os.environ["GITHUB_EVENT_NAME"],
        "runId": int(os.environ["GITHUB_RUN_ID"]), "runAttempt": int(os.environ["GITHUB_RUN_ATTEMPT"]),
        "driverHashes": hashes,
    }


def prepare(source, output):
    require(not output.exists(), "Refusing to replace retained Linux input evidence")
    output.mkdir(parents=True)
    proof = output / "proof"
    proof.mkdir()
    result = {"schemaVersion": 1, "status": "failed", "observedAt": datetime.now(timezone.utc).isoformat(),
              "scope": "fixed original Linux product input verification"}
    try:
        executor = executor_identity()
        result["executor"] = executor
        source_hashes = verify_source(source)
        artifact = json.loads(command(["gh", "api", f"repos/{REPOSITORY}/actions/artifacts/{ARTIFACT_ID}"],
                                      proof, "artifact-metadata", env=gh_environment()))
        run = json.loads(command(["gh", "api", f"repos/{REPOSITORY}/actions/runs/{RUN_ID}/attempts/{RUN_ATTEMPT}"],
                                 proof, "original-run-metadata", env=gh_environment()))
        verify_metadata(artifact, run)
        archive, release, bundle = output / "original-artifact.zip", output / "release", output / "bundle"
        download_archive(archive, proof)
        extract_zip(archive, release)
        subjects = verify_checksums(release)
        graph_counts = verify_bundle_source(source, release, proof)
        attestation = json.loads(command([
            "gh", "attestation", "verify", str(release / "RELEASE_MANIFEST.json"),
            "--repo", REPOSITORY, "--signer-digest", SOURCE, "--source-digest", SOURCE,
            "--source-ref", SOURCE_REF, "--cert-identity", CERT_IDENTITY,
            "--deny-self-hosted-runners", "--format", "json",
        ], proof, "original-manifest-attestation", env=gh_environment()))
        certificates = verify_attestation(attestation, subjects)
        extract_tar(release / "aethertune-linux-x64.tar.gz", bundle)
        require(sha256(bundle / "aethertune") == EXECUTABLE_SHA256, "Reconstructed original executable changed")
        spec = importlib.util.spec_from_file_location("original_linux_gate", source / "scripts/ci/linux_packaged_release_acceptance.py")
        original_gate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(original_gate)
        tree = original_gate.tree_manifest(bundle)
        require(len(tree) == 43, "Reconstructed Linux bundle inventory changed")
        original_gate.verify_archives(tree, release / "aethertune-linux-x64.deb",
                                      release / "aethertune-linux-x64.tar.gz", "0.1.0")
        write_json(proof / "reconstructed-bundle-manifest.json", tree)
        receipt = {
            "schemaVersion": 1, "status": "verified-input", "observedAt": datetime.now(timezone.utc).isoformat(),
            "product": {
                "repository": REPOSITORY, "sourceCommit": SOURCE, "sourceRef": SOURCE_REF,
                "runId": RUN_ID, "runAttempt": RUN_ATTEMPT, "version": "0.1.0",
                "artifact": {"id": ARTIFACT_ID, "name": artifact["name"], "outerSha256": OUTER_SHA256,
                             "archiveBytes": ARCHIVE_BYTES},
                "subjects": subjects, "certificate": certificates[0], "sourceVerifierHashes": source_hashes,
                "linux": {"debSha256": DEB_SHA256, "tarballSha256": TARBALL_SHA256,
                          "executableSha256": EXECUTABLE_SHA256, "bundleEntries": len(tree)},
            },
            "executor": executor,
            "paths": {"releaseDir": str(release), "bundle": str(bundle),
                      "deb": str(release / "aethertune-linux-x64.deb"),
                      "tarball": str(release / "aethertune-linux-x64.tar.gz")},
            "checks": {"checksumSubjects": len(subjects), "graphLockPackageCounts": graph_counts,
                       "verifiedAttestations": len(certificates), "originalArchivePayloadEquality": True},
            "limits": ["Input verification is not runtime acceptance.",
                       "Original product attestation does not certify the new executor or final main.",
                       "Unsigned candidate; no production signing or deployed acceptance claim."],
        }
        write_json(output / "product-provenance.json", receipt)
        result["status"] = "verified-input"
        print(json.dumps({"status": "verified-input", "receipt": str(output / "product-provenance.json")}))
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        write_json(proof / "input-preparation-result.json", result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product-source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    prepare(args.product_source.resolve(), args.output.resolve())


if __name__ == "__main__":
    main()

