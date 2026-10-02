#!/usr/bin/env python3
"""Observe an unchanged attested macOS app only on a fresh hosted runner."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import re
import shutil
import signal
import stat
import subprocess
import sys
import time
import uuid
import zipfile

from verify_release_manifest import verify_release_manifest

ROOT = Path(__file__).resolve().parents[2]
REPO = "Yunushan/aethertune"
BUNDLE_ID = "dev.aethertune.aethertune"
WORKFLOW = ".github/workflows/aethertune-release.yml"
DEFAULT_RUN = "37041509348"
DEFAULT_SOURCE = "a1d75fbc37fd9951130194798811cfd913e34724"
DEFAULT_REF = "refs/heads/codex/readiness-linux-release"
DEFAULT_ATTEMPT = 1


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def require_host(platform: str, env: dict[str, str]) -> None:
    require(platform == "darwin" and env.get("GITHUB_ACTIONS") == "true"
            and env.get("RUNNER_ENVIRONMENT") == "github-hosted"
            and env.get("RUNNER_OS") == "macOS"
            and env.get("GITHUB_REPOSITORY") == REPO
            and env.get("GITHUB_EVENT_NAME") in ("workflow_dispatch", "pull_request"),
            "Acceptance requires the scoped workflow on a fresh GitHub-hosted Mac.")


def safe_name(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    require(name == path.as_posix() and not path.is_absolute() and ".." not in path.parts
            and "\\" not in name and "\x00" not in name, f"Unsafe ZIP entry: {name}")
    return path


def archive_inventory(path: Path, *, app: bool) -> dict[str, dict]:
    records: dict[str, dict] = {}
    seen: set[str] = set()
    kinds: dict[str, int] = {}
    spellings: dict[str, str] = {}
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "Archive CRC failure.")
        for entry in archive.infolist():
            name = entry.filename.rstrip("/") if entry.is_dir() else entry.filename
            parts = safe_name(name)
            require(bool(parts.parts), "Empty archive entry.")
            require(name.casefold() not in seen, "Duplicate/case-aliased ZIP entries.")
            seen.add(name.casefold())
            for component in [parts, *parts.parents]:
                lexical = str(component)
                require(spellings.get(lexical.casefold(), lexical) == lexical,
                        "Case-aliased archive ancestor.")
                spellings[lexical.casefold()] = lexical
            if app:
                require(parts.parts[0] == "aethertune.app", "Unexpected app archive root.")
            else:
                require(len(parts.parts) == 1 and not entry.is_dir(), "Bundle artifact must contain flat files only.")
            mode = entry.external_attr >> 16
            require(stat.S_IFMT(mode) in (0, stat.S_IFREG, stat.S_IFDIR, stat.S_IFLNK), "Unsupported archive entry type.")
            kinds[name] = stat.S_IFDIR if entry.is_dir() else stat.S_IFMT(mode)
            record = {"sha256": hashlib.sha256(archive.read(entry)).hexdigest(), "mode": mode}
            if stat.S_ISLNK(mode):
                require(app, "Unexpected release bundle symlink.")
                target = archive.read(entry).decode("utf-8")
                require(target and not target.startswith("/") and "\\" not in target and "\x00" not in target, "Unsafe app symlink.")
                resolved = posixpath.normpath(posixpath.join(str(parts.parent), target))
                require(resolved == "aethertune.app" or resolved.startswith("aethertune.app/"), "App symlink escapes bundle.")
                record["target"] = target
            if not entry.is_dir():
                records[name] = record
    for name in kinds:
        for parent in PurePosixPath(name).parents:
            require(str(parent) not in kinds or kinds[str(parent)] == stat.S_IFDIR,
                    "Archive entry descends through a file or symlink.")
    return records


def compare_extracted(root: Path, records: dict[str, dict]) -> None:
    actual = {path.relative_to(root).as_posix(): path for path in root.rglob("*")
              if path.is_file() or path.is_symlink()}
    require(set(actual) == set(records), "Extracted app inventory changed.")
    for name, record in records.items():
        path = actual[name]
        if "target" in record:
            require(path.is_symlink() and os.readlink(path) == record["target"], "Extracted symlink changed.")
            require(path.resolve().is_relative_to(root.resolve()), "Extracted symlink escapes owned root.")
        else:
            require(not path.is_symlink() and digest(path) == record["sha256"], "Extracted app file changed.")
            require(stat.S_IMODE(path.stat().st_mode) == stat.S_IMODE(record["mode"]), "Extracted app permissions changed.")


def verify_inputs(run_id: str, source: str, ref: str, attempt: int) -> None:
    require(re.fullmatch(r"[1-9][0-9]{0,15}", run_id) is not None
            and re.fullmatch(r"[0-9a-f]{40}", source) is not None
            and (ref == "refs/heads/main" or re.fullmatch(r"refs/heads/codex/[a-z0-9][a-z0-9-]{0,63}", ref) is not None)
            and type(attempt) is int and attempt > 0,
            "Expected exact source, positive run/attempt and main or reviewed codex branch.")


def verify_run(run: dict, run_id: str, source: str, ref: str, attempt: int) -> None:
    require(run.get("id") == int(run_id) and run.get("head_sha") == source
            and run.get("head_branch") == ref.removeprefix("refs/heads/") and run.get("path") == WORKFLOW
            and run.get("event") == "workflow_dispatch" and run.get("status") == "completed"
            and run.get("conclusion") == "success"
            and run.get("repository", {}).get("full_name") == REPO
            and run.get("run_attempt") == attempt,
            "Candidate run/source/ref/workflow/attempt is not the expected successful candidate.")


def verify_attestation(data: list, source: str, ref: str, run_id: str, attempt: int,
                       checksums: dict[str, str]) -> None:
    require(len(data) == 1, "Expected one verified manifest attestation.")
    result = data[0]["verificationResult"]
    certificate = result["signature"]["certificate"]
    for key, expected in {
        "subjectAlternativeName": f"https://github.com/{REPO}/{WORKFLOW}@{ref}",
        "buildSignerURI": f"https://github.com/{REPO}/{WORKFLOW}@{ref}",
        "buildSignerDigest": source, "sourceRepositoryDigest": source,
        "sourceRepositoryRef": ref, "sourceRepositoryURI": f"https://github.com/{REPO}",
        "issuer": "https://token.actions.githubusercontent.com", "runnerEnvironment": "github-hosted",
        "runInvocationURI": f"https://github.com/{REPO}/actions/runs/{run_id}/attempts/{attempt}",
    }.items():
        require(certificate.get(key) == expected, f"Verified certificate mismatch: {key}")
    subjects = result["statement"]["subject"]
    require(len(subjects) == len(checksums) == 18, "Complete 18 subject verification required.")
    require(len({row["name"] for row in subjects}) == len(subjects), "Duplicate attested subjects.")
    require({row["name"]: row["digest"]["sha256"] for row in subjects} == checksums,
            "Attested subjects do not exactly match checked local bytes.")


def state_paths(home: Path) -> list[Path]:
    require(home.is_absolute() and home.parent == Path("/Users"), "Unexpected actual Foundation home.")
    library = home / "Library"
    return [library / "Containers" / BUNDLE_ID,
            library / "Application Support" / BUNDLE_ID,
            library / "Caches" / BUNDLE_ID,
            library / "Preferences" / f"{BUNDLE_ID}.plist",
            library / "Saved Application State" / f"{BUNDLE_ID}.savedState"]


def snapshot_paths(paths: list[Path]) -> list[dict]:
    result = []
    for path in paths:
        # Inspect lexical app-owned paths without following a replaced root.
        require(path.parent.resolve() == path.parent, "App-state parent is a symlink; refusing ownership.")
        if not path.exists() and not path.is_symlink():
            result.append({"path": str(path), "present": False})
            continue
        value = path.lstat()
        require(not stat.S_ISLNK(value.st_mode), "App-state root is a symlink; refusing ownership.")
        result.append({"path": str(path), "present": True, "device": value.st_dev,
                       "inode": value.st_ino, "uid": value.st_uid, "mode": value.st_mode})
    return result


def cleanup_paths(before: list[dict], owned: list[dict], uid: int) -> list[dict]:
    require(all(row["present"] is False for row in before), "Preexisting app state cannot be removed.")
    require([row["path"] for row in before] == [row["path"] for row in owned], "App-state path set changed.")
    for record in owned:
        if not record["present"]:
            continue
        path = Path(record["path"])
        require(path.parent.resolve() == path.parent, "App-state parent changed; refusing cleanup.")
        value = path.lstat()
        require(not stat.S_ISLNK(value.st_mode) and value.st_uid == uid
                and value.st_ino == record["inode"] and value.st_dev == record["device"],
                "App-state identity changed; refusing cleanup.")
        if stat.S_ISDIR(value.st_mode):
            shutil.rmtree(path)
        else:
            path.unlink()
    return snapshot_paths([Path(row["path"]) for row in before])


def launch_log_arguments(app: Path, started: float, ended: float) -> list[str]:
    require(0 < started <= ended and ended - started <= 300, "Unbounded launch diagnostic interval.")
    path = str(app)
    require(app.name == "aethertune.app" and not any(char in path for char in "\r\n\x00"),
            "Unsafe launch diagnostic app path.")
    # log show uses the host's local time. Round only to its supported seconds,
    # retaining the actual interval separately in the diagnostic receipt.
    start = datetime.fromtimestamp(math.floor(started)).strftime("%Y-%m-%d %H:%M:%S")
    end = datetime.fromtimestamp(math.ceil(ended)).strftime("%Y-%m-%d %H:%M:%S")
    predicate = " OR ".join(f"eventMessage CONTAINS {json.dumps(value, ensure_ascii=False)}"
                            for value in [path, str(app / "Contents/MacOS/aethertune"), BUNDLE_ID])
    return ["/usr/bin/log", "show", "--style", "json", "--info", "--debug",
            "--start", start, "--end", end, "--predicate", f"({predicate})"]


def crash_snapshot(roots: list[Path]) -> dict[str, dict]:
    records: dict[str, dict] = {}
    for root in roots:
        if not root.exists():
            continue
        require(root.resolve() == root and root.is_dir(), "Unexpected crash-report directory identity.")
        for path in root.iterdir():
            if not re.fullmatch(r"aethertune[A-Za-z0-9_. -]*\.(ips|crash)", path.name, re.IGNORECASE):
                continue
            value = path.lstat()
            records[str(path)] = {"device": value.st_dev, "inode": value.st_ino,
                                  "mtimeNs": value.st_mtime_ns, "size": value.st_size,
                                  "mode": value.st_mode}
    return records


def retain_fresh_crashes(roots: list[Path], before: dict[str, dict], app: Path,
                        started: float, ended: float, destination: Path) -> list[dict]:
    records = []
    for name, metadata in crash_snapshot(roots).items():
        if name in before or not started <= metadata["mtimeNs"] / 1e9 <= ended:
            continue
        row = {"source": name, **metadata, "retained": False}
        records.append(row)
        if not stat.S_ISREG(metadata["mode"]) or metadata["size"] > 2 * 1024 * 1024 or len(records) > 8:
            row["reason"] = "Not a regular report, exceeds 2 MiB, or exceeds eight report limit."
            continue
        path = Path(name)
        with path.open("rb") as stream:
            value = os.fstat(stream.fileno())
            require((value.st_dev, value.st_ino, value.st_mtime_ns, value.st_size, value.st_mode)
                    == tuple(metadata[key] for key in ["device", "inode", "mtimeNs", "size", "mode"]),
                    "Crash-report identity changed before read.")
            data = stream.read(2 * 1024 * 1024 + 1)
            require(len(data) == metadata["size"] and len(data) <= 2 * 1024 * 1024,
                    "Crash-report size changed or exceeded limit.")
            after = os.fstat(stream.fileno())
            require((after.st_mtime_ns, after.st_size) == (value.st_mtime_ns, value.st_size),
                    "Crash-report changed during read.")
        after_path = path.lstat()
        require((after_path.st_dev, after_path.st_ino, after_path.st_mtime_ns, after_path.st_size, after_path.st_mode)
                == tuple(metadata[key] for key in ["device", "inode", "mtimeNs", "size", "mode"]),
                "Crash-report path identity changed during read.")
        if str(app).encode() not in data and BUNDLE_ID.encode() not in data:
            row["reason"] = "Report does not identify the exact app path or bundle ID."
            continue
        destination.mkdir(exist_ok=True)
        target = destination / f"{len(records):02d}-{path.name}"
        target.write_bytes(data)
        row.update(retained=True, evidence=str(target), sha256=hashlib.sha256(data).hexdigest())
    return records


def launch_diagnostics(run: Commands, evidence: Path, app: Path, roots: list[Path],
                       before: dict[str, dict], started: float, ended: float) -> dict:
    result = {"startedUnix": started, "endedUnix": ended, "errors": [], "crashReports": [],
              "scope": "Exact attempt interval and app path/bundle ID only; read-only diagnostics do not change failure status."}
    try:
        run(launch_log_arguments(app, started, ended), timeout=30,
            binary=evidence / "launch-system-log.json")
    except Exception as error:
        result["errors"].append(f"Unified log collection: {error}")
    try:
        result["crashCollectionEndedUnix"] = time.time()
        result["crashReports"] = retain_fresh_crashes(roots, before, app, started, result["crashCollectionEndedUnix"],
                                                     evidence / "crash-reports")
    except Exception as error:
        result["errors"].append(f"Fresh app crash-report collection: {error}")
    write(evidence / "launch-diagnostics.json", result)
    return result


class Commands:
    def __init__(self, evidence: Path):
        self.evidence, self.sequence = evidence, 0
        self.receipts: list[dict] = []

    def __call__(self, args: list[str], *, timeout: int = 60, binary: Path | None = None) -> str:
        self.sequence += 1
        stem = f"{self.sequence:03d}-{Path(args[0]).name}"
        stdout = binary or self.evidence / f"{stem}.log"
        stderr = self.evidence / f"{stem}-stderr.log"
        receipt = {"arguments": args, "startedUnix": time.time(),
                   "stdout": str(stdout), "stderr": str(stderr)}
        self.receipts.append(receipt)
        write(self.evidence / "commands.json", {"commands": self.receipts})
        with stdout.open("wb") as out, stderr.open("wb") as err:
            child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                     start_new_session=True)
            receipt["pid"] = child.pid
            write(self.evidence / "commands.json", {"commands": self.receipts})
            try:
                code = child.wait(timeout=timeout)
            except BaseException:
                for sig in (signal.SIGTERM, signal.SIGKILL):
                    try:
                        os.killpg(child.pid, sig)
                    except ProcessLookupError:
                        pass
                    if sig == signal.SIGTERM:
                        try:
                            child.wait(timeout=2)
                            break
                        except subprocess.TimeoutExpired:
                            pass
                child.wait(timeout=5)
                receipt.update(exitCode=child.returncode, timedOutOrInterrupted=True, endedUnix=time.time())
                write(self.evidence / "commands.json", {"commands": self.receipts})
                raise
        receipt.update(exitCode=code, endedUnix=time.time())
        write(self.evidence / "commands.json", {"commands": self.receipts})
        require(code == 0, f"Command failed ({code}); retain {stdout.name} and {stderr.name}.")
        return "" if binary else stdout.read_text(encoding="utf-8").strip()


def execute(args: argparse.Namespace) -> int:
    require_host(sys.platform, dict(os.environ))
    verify_inputs(args.candidate_run, args.source, args.source_ref, args.candidate_attempt)
    evidence = args.evidence.resolve()
    require(evidence.is_relative_to(ROOT / "build") and evidence != ROOT / "build"
            and not evidence.exists(), "Evidence requires a new directory inside build.")
    evidence.mkdir(parents=True)
    report = {"status": "starting", "candidateSource": args.source, "candidateRun": args.candidate_run,
              "candidateRef": args.source_ref, "candidateAttempt": args.candidate_attempt,
              "harnessSource": os.environ.get("GITHUB_SHA"), "errors": [], "checks": [],
              "productionSigningClaimed": False, "privacySettingsChanged": False,
              "limits": ["Ordinary packaged app smoke only; no production signer/Gatekeeper trust, physical audio, credentials or upgrade/rollback proof.",
                         "Only the actual host architecture is exercised; universal packaging does not prove both architectures ran.",
                         "Keychain query is metadata-only and observer-visible; it is not a credential roundtrip or global access-group inventory."]}
    write(evidence / "result.json", report)
    run = Commands(evidence)
    stage: Path | None = None
    observer: Path | None = None
    before: list[dict] | None = None
    paths: list[Path] = []
    try:
        metadata = json.loads(run(["gh", "api", f"repos/{REPO}/actions/runs/{args.candidate_run}"]))
        write(evidence / "candidate-run.json", metadata)
        verify_run(metadata, args.candidate_run, args.source, args.source_ref, args.candidate_attempt)
        artifacts = json.loads(run(["gh", "api", f"repos/{REPO}/actions/runs/{args.candidate_run}/artifacts?per_page=100"]))
        write(evidence / "candidate-artifacts.json", artifacts)
        candidates = [row for row in artifacts["artifacts"] if row["name"] == "aethertune-release-bundle" and not row["expired"]]
        require(len(candidates) == 1, "Exact assembled bundle artifact unavailable.")
        artifact = candidates[0]
        require(artifact.get("workflow_run", {}).get("head_sha") == args.source
                and re.fullmatch(r"sha256:[0-9a-f]{64}", artifact.get("digest", "")) is not None,
                "Artifact source/digest binding unavailable.")
        outer = evidence / "release-bundle-artifact.zip"
        run(["gh", "api", f"repos/{REPO}/actions/artifacts/{artifact['id']}/zip"], timeout=240, binary=outer)
        require(digest(outer) == artifact["digest"][7:], "Official artifact ZIP digest mismatch.")
        records = archive_inventory(outer, app=False)
        require(len(records) == 19, "Unexpected assembled candidate inventory.")
        bundle = evidence / "bundle"
        bundle.mkdir()
        with zipfile.ZipFile(outer) as archive:
            archive.extractall(bundle)
        checksums = {}
        for line in (bundle / "SHA256SUMS.txt").read_text(encoding="utf-8").splitlines():
            match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
            require(match is not None and match[2] not in checksums, "Unsafe/duplicate checksum entry.")
            checksums[match[2]] = match[1]
        require(set(checksums) == set(records) - {"SHA256SUMS.txt"} and len(checksums) == 18,
                "Checksum inventory differs from downloaded bundle.")
        require(all(digest(bundle / name) == value for name, value in checksums.items()), "Candidate byte checksum mismatch.")
        verify_release_manifest(bundle, bundle / "RELEASE_MANIFEST.json")
        verified = json.loads(run(["gh", "attestation", "verify", str(bundle / "RELEASE_MANIFEST.json"),
                                  "--repo", REPO, "--signer-digest", args.source, "--source-digest", args.source,
                                  "--source-ref", args.source_ref, "--cert-identity", f"https://github.com/{REPO}/{WORKFLOW}@{args.source_ref}",
                                  "--deny-self-hosted-runners", "--format", "json"]))
        write(evidence / "manifest-attestation.json", verified)
        verify_attestation(verified, args.source, args.source_ref, args.candidate_run, args.candidate_attempt, checksums)
        report.update(artifactId=artifact["id"], archiveSha256=checksums["aethertune-macos.zip"],
                      manifestSha256=checksums["RELEASE_MANIFEST.json"])
        report["checks"].append("exact-run-source-ref-workflow-attempt-certificate-and-18-subjects")
        archive = bundle / "aethertune-macos.zip"
        app_records = archive_inventory(archive, app=True)
        write(evidence / "app-archive-inventory.json", {"archiveSha256": digest(archive), "entries": app_records})
        stage = Path(os.environ["RUNNER_TEMP"]).resolve() / f"aethertune-macos-ordinary-{uuid.uuid4().hex}"
        stage.mkdir()
        (stage / ".owned").write_text("aethertune-macos-packaged-v1\n", encoding="utf-8")
        report["ownedStage"] = str(stage)
        run(["/usr/bin/ditto", "-x", "-k", str(archive), str(stage)])
        compare_extracted(stage, {**app_records, ".owned": {"sha256": digest(stage / ".owned"), "mode": (stage / ".owned").stat().st_mode}})
        write(evidence / "package-preservation.json", {"appEntries": len(app_records), "beforeLaunchEqual": True,
                                                       "afterQuitEqual": False})
        app = stage / "aethertune.app"
        plist = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        require(plist.get("CFBundleIdentifier") == BUNDLE_ID and plist.get("CFBundleExecutable") == "aethertune", "Unexpected app identity.")
        executable = app / "Contents/MacOS/aethertune"
        archs = run(["/usr/bin/lipo", "-archs", str(executable)]).split()
        require(set(archs) == {"arm64", "x86_64"}, "Candidate executable must remain universal.")
        run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
        run(["/usr/bin/codesign", "--display", "--verbose=4", str(app)])
        entitlements = {}
        for architecture in sorted(archs):
            target = evidence / f"codesign-entitlements-{architecture}.xml"
            run(["/usr/bin/codesign", "--display", "--arch", architecture,
                 "--entitlements", "-", "--xml", str(app)], binary=target)
            value = plistlib.loads(target.read_bytes())
            require(isinstance(value, dict), "Unexpected embedded entitlement dictionary.")
            entitlements[architecture] = value
        write(evidence / "codesign-entitlements.json", entitlements)
        xattrs = run(["/usr/bin/xattr", "-lr", str(app)])
        require("com.apple.quarantine" not in xattrs, "Quarantined package requires external trust review; it will not be stripped.")
        observer = stage / "observer"
        run(["xcrun", "swiftc", str(ROOT / "scripts/ci/macos_packaged_observer.swift"), "-o", str(observer)], timeout=120)
        snapshot = json.loads(run([str(observer), "snapshot"]))
        write(evidence / "native-preflight.json", snapshot)
        require(snapshot["screenCaptureAllowed"] is True and snapshot["foundationHome"] == snapshot["passwdHome"], "Existing capture permission/actual Foundation home unavailable.")
        require(snapshot["runningAppCount"] == 0 and snapshot["keychainAppItemCount"] == 0,
                "Existing app or visible app-prefixed keychain state prevents isolated launch.")
        paths = state_paths(Path(snapshot["foundationHome"]))
        before = snapshot_paths(paths)
        write(evidence / "state-before.json", {"paths": before})
        require(all(row["present"] is False for row in before), "Existing app-owned storage prevents isolated launch.")
        crash_roots = [Path(snapshot["foundationHome"]) / "Library/Logs/DiagnosticReports",
                       Path("/Library/Logs/DiagnosticReports")]
        crash_before = crash_snapshot(crash_roots)
        write(evidence / "crash-reports-before.json", crash_before)
        attempt_started = time.time()
        try:
            run([str(observer), "run", str(app), str(evidence), digest(executable)], timeout=180)
        except Exception:
            attempt_ended = time.time()
            try:
                launch_diagnostics(run, evidence, app, crash_roots, crash_before,
                                   attempt_started, attempt_ended)
            except Exception as error:
                report["diagnosticError"] = str(error)
            try:
                compare_extracted(stage, {**app_records,
                                          ".owned": {"sha256": digest(stage / ".owned"), "mode": (stage / ".owned").stat().st_mode},
                                          "observer": {"sha256": digest(observer), "mode": observer.stat().st_mode}})
                write(evidence / "package-preservation.json", {"appEntries": len(app_records), "beforeLaunchEqual": True,
                                                               "afterQuitEqual": False, "afterFailedAttemptEqual": True})
            except Exception as error:
                report["failedAttemptPackageComparisonError"] = str(error)
            raise
        native = json.loads((evidence / "native-result.json").read_text(encoding="utf-8"))
        require(native["status"] == "passed" and native["normalQuit"] is True
                and native["ownedProcessAbsent"] is True and native["exit"]["rawWaitStatus"] == 0,
                "Ordinary launch/window/normal quit with zero native exit status failed.")
        compare_extracted(stage, {**app_records, ".owned": {"sha256": digest(stage / ".owned"), "mode": (stage / ".owned").stat().st_mode},
                                  "observer": {"sha256": digest(observer), "mode": observer.stat().st_mode}})
        write(evidence / "package-preservation.json", {"appEntries": len(app_records), "beforeLaunchEqual": True,
                                                       "afterQuitEqual": True})
        report.update(executableSha256=digest(executable), universalArchitectures=archs,
                      executedArchitecture=native["executedArchitecture"], native=native,
                      screenshotSha256=digest(evidence / "ordinary-window.png"))
        report["checks"] += ["unchanged-ordinary-package", "exact-app-pid-path-launch-date", "owned-window-alive15seconds", "normal-quit-zero-native-exit"]
        report["status"] = "passed"
    except Exception as error:
        report["status"] = "failed"
        report["errors"].append(f"{type(error).__name__}: {error}")
    finally:
        if observer is not None and (evidence / "launch-identity.json").exists():
            try:
                run([str(observer), "cleanup", str(evidence / "launch-identity.json")], timeout=30)
            except Exception as error:
                report["errors"].append(f"Owned process cleanup: {error}")
                report["status"] = "failed"
        if before is not None:
            try:
                final = json.loads(run([str(observer), "snapshot"]))
                write(evidence / "native-after.json", final)
                require(final["runningAppCount"] == 0 and final["keychainAppItemCount"] == 0,
                        "App or unexpected keychain state remains; no unrelated keychain item is deleted.")
                owned = snapshot_paths(paths)
                write(evidence / "state-owned-before-cleanup.json", {"paths": owned})
                after = cleanup_paths(before, owned, os.getuid())
                time.sleep(1)
                require(all(row["present"] is False for row in snapshot_paths(paths)), "App-owned storage remains/reappeared.")
                write(evidence / "state-after-cleanup.json", {"paths": after})
                report["checks"].append("exact-new-app-storage-cleanup")
            except Exception as error:
                report["errors"].append(f"App state cleanup: {error}")
                report["status"] = "failed"
        if stage is not None:
            report["stageRetainedForEvidence"] = str(stage)
            # The staged unmodified app/helper is retained until the hosted VM
            # is decommissioned. Never recursively delete unrelated runner data.
        write(evidence / "result.json", report)
    print(json.dumps({"status": report["status"], "errors": report["errors"], "evidence": str(evidence)}, indent=2))
    return 0 if report["status"] == "passed" else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate-run", default=DEFAULT_RUN)
    parser.add_argument("--source", default=DEFAULT_SOURCE)
    parser.add_argument("--source-ref", default=DEFAULT_REF)
    parser.add_argument("--candidate-attempt", type=int, default=DEFAULT_ATTEMPT)
    parser.add_argument("--evidence", type=Path, default=ROOT / "build/macos-packaged-acceptance")
    return execute(parser.parse_args())


if __name__ == "__main__":
    sys.exit(main())
