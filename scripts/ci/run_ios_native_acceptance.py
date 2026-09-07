#!/usr/bin/env python3
"""Execute the real iOS app only in a newly owned, hosted-runner Simulator."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps/mobile"
BUNDLE = "dev.aethertune.aethertune"
PREFIX = "AetherTune_Acceptance_"
TARGET = "integration_test/ios_native_acceptance_test.dart"
MARKER = "aethertune-ios-native-acceptance-v1\n"
PHASES = ("seed", "reopen", "sync")
COMMON = {"production-app-startup"}
CHECKS = {
    "seed": COMMON | {
        "native-keychain-round-trip", "native-library-snapshot",
        "native-decode-progress-pause-seek-stop", "persistent-fixture-checkpoint",
    },
    "reopen": COMMON | {
        "keychain-survived-process-restart", "native-library-snapshot",
        "library-queue-settings-survived-process-restart", "native-keychain-deletion",
    },
    "sync": COMMON | {
        "platform-trusted-TLS-UTF8-upload-status-auth-redirect", "untrusted-root",
        "wrong-hostname", "rejected-TLS-sends-no-HTTP-credentials",
        "stalled-TLS-cleanup-0", "stalled-TLS-cleanup-1", "stalled-TLS-cleanup-2",
        "three-independent-isolate-roundtrips",
    },
}


def require_host(platform: str, env: dict[str, str]) -> None:
    if (platform != "darwin" or env.get("GITHUB_ACTIONS") != "true"
            or env.get("RUNNER_ENVIRONMENT") != "github-hosted"):
        raise ValueError("Acceptance requires a GitHub-hosted macOS runner, not a personal Mac.")


def version(value: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(\.\d+){0,2}", value):
        raise ValueError(f"Unexpected iOS runtime version: {value!r}")
    return tuple(int(part) for part in value.split("."))


def select_simulator(inventory: dict) -> tuple[dict, dict]:
    types = {item["identifier"]: item for item in inventory["devicetypes"]
             if item.get("productFamily") == "iPhone"}
    runtimes = sorted((item for item in inventory["runtimes"]
                       if item.get("isAvailable") is True
                       and item["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")),
                      key=lambda item: version(item["version"]), reverse=True)
    for runtime in runtimes:
        # Existing devices provide compatibility metadata only. Never boot or reuse one.
        compatible = {item.get("deviceTypeIdentifier")
                      for item in inventory["devices"].get(runtime["identifier"], [])
                      if item.get("isAvailable") is True}
        compatible.update(item["identifier"] for item in runtime.get("supportedDeviceTypes", []))
        candidates = sorted(identifier for identifier in compatible if identifier in types)
        if candidates:
            return runtime, types[candidates[-1]]
    raise ValueError("No available iOS runtime with a known compatible iPhone; inspect inventory.json.")


def require_uuid(value: str) -> str:
    parsed = str(uuid.UUID(value)).upper()
    if parsed != value.upper():
        raise ValueError("Simulator must be an exact UUID, never an alias.")
    return parsed


def owned_device(inventory: dict, device: str, name: str, *, absent_ok: bool = False) -> dict | None:
    require_uuid(device)
    if not name.startswith(PREFIX) or not re.fullmatch(r"[0-9a-f]{32}", name[len(PREFIX):]):
        raise ValueError("Invalid simulator ownership name.")
    matches = [item for devices in inventory["devices"].values() for item in devices
               if item["udid"].upper() == device.upper()]
    if absent_ok and not matches:
        return None
    if len(matches) != 1 or matches[0]["name"] != name:
        raise ValueError("Simulator ownership changed; refusing operation.")
    return matches[0]


def contained(path: Path, parent: Path) -> Path:
    resolved, root = path.resolve(), parent.resolve()
    if resolved == root or not resolved.is_relative_to(root):
        raise ValueError(f"Path escapes fixture boundary: {path}")
    return resolved


def support_directory(container: Path, guest: dict) -> Path:
    data = Path(guest["dataPath"]).resolve(strict=True)
    if data.name != "data" or data.parent.name.upper() != guest["udid"].upper():
        raise ValueError("Unexpected simulator dataPath.")
    base = data / "Containers/Data/Application"
    container = contained(container, base)
    if container.parent != base.resolve():
        raise ValueError("Expected the immediate application container.")
    require_uuid(container.name)
    return contained(container / "Library/Application Support", container)


def verify_report(report: dict, phase: str, device: str, source: str, previous_pids: set[int]) -> int:
    if (report.get("status") != "passed" or report.get("phase") != phase
            or report.get("device") != device or report.get("sourceCommit") != source):
        raise ValueError(f"Missing, failed or mismatched {phase} runtime report.")
    checks = report.get("checks", [])
    if (len(checks) != len(CHECKS[phase]) or any(item.get("passed") is not True for item in checks)
            or {item.get("name") for item in checks} != CHECKS[phase]):
        raise ValueError(f"Incomplete {phase} acceptance checks.")
    pid = report.get("pid")
    if type(pid) is not int or pid <= 0 or pid in previous_pids:
        raise ValueError("Each phase must execute in a distinct app process.")
    return pid


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


class Commands:
    def __init__(self, evidence: Path):
        self.evidence = evidence
        self.sequence = 0

    def __call__(self, args: list[str], *, cwd: Path = ROOT, timeout: int = 120,
                 env: dict[str, str] | None = None) -> str:
        self.sequence += 1
        stem = f"{self.sequence:03d}-{Path(args[0]).name}"
        stdout = self.evidence / f"{stem}.log"
        stderr = self.evidence / f"{stem}-stderr.log"
        print(f"Running {args!r}", flush=True)
        with stdout.open("wb") as out, stderr.open("wb") as err:
            child = subprocess.Popen(args, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                                     stdout=out, stderr=err, start_new_session=True)
            try:
                code = child.wait(timeout=timeout)
            except BaseException:
                # Stop this command's process group, including owned build/driver children.
                for sig in (signal.SIGTERM, signal.SIGKILL):
                    try:
                        os.killpg(child.pid, sig)
                    except ProcessLookupError:
                        pass
                    if sig == signal.SIGTERM:
                        time.sleep(1)
                child.wait(timeout=30)
                raise
        if code:
            raise RuntimeError(f"Command exited {code}; see {stdout.name} and {stderr.name}.")
        return stdout.read_text(encoding="utf-8", errors="replace").strip()


class Simulator:
    def __init__(self, run: Commands, name: str):
        self.run = run
        self.name = name
        self.device: str | None = None

    def inventory(self) -> dict:
        return json.loads(self.run(["xcrun", "simctl", "list", "--json"]))

    def current(self, *, absent_ok: bool = False) -> dict | None:
        if self.device is None:
            raise ValueError("No owned simulator.")
        return owned_device(self.inventory(), self.device, self.name, absent_ok=absent_ok)

    def command(self, verb: str, *args: str, timeout: int = 120) -> str:
        self.current()
        return self.run(["xcrun", "simctl", verb, self.device, *args], timeout=timeout)

    def create(self, runtime: dict, device_type: dict) -> None:
        try:
            result = self.run(["xcrun", "simctl", "create", self.name,
                               device_type["identifier"], runtime["identifier"]])
            self.device = require_uuid(result)
        except Exception:
            # A create timeout can still leave a guest. Recover only this random name.
            matches = [item for devices in self.inventory()["devices"].values()
                       for item in devices if item["name"] == self.name]
            if len(matches) == 1:
                self.device = require_uuid(matches[0]["udid"])
            raise
        self.current()

    def support(self) -> Path:
        container = self.command("get_app_container", BUNDLE, "data")
        return support_directory(Path(container), self.current())

    def cleanup(self) -> dict:
        if self.device is None:
            return {"status": "not-created"}
        guest = self.current(absent_ok=True)
        if guest is None:
            return {"status": "deleted", "device": self.device}
        if guest["state"] != "Shutdown":
            try:
                self.command("shutdown")
            except Exception:
                if self.current()["state"] != "Shutdown":
                    raise
        try:
            self.command("delete")
        except Exception:
            if self.current(absent_ok=True) is not None:
                raise
        if self.current(absent_ok=True) is not None:
            raise RuntimeError("Owned simulator still exists after deletion.")
        return {"status": "deleted", "device": self.device}


def certificates(run: Commands, directory: Path) -> None:
    directory.mkdir(mode=0o700)
    for name in ("trusted", "untrusted"):
        ca, leaf = directory / f"{name}-ca", directory / f"{name}-leaf"
        run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-keyout", f"{ca}.key", "-out", f"{ca}.pem", "-days", "2",
             "-subj", f"/CN=AetherTune Synthetic {name} CA",
             "-addext", "basicConstraints=critical,CA:TRUE",
             "-addext", "keyUsage=critical,keyCertSign,cRLSign"])
        run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes",
             "-keyout", f"{leaf}.key", "-out", f"{leaf}.csr", "-subj", "/CN=127.0.0.1"])
        run(["openssl", "x509", "-req", "-in", f"{leaf}.csr", "-CA", f"{ca}.pem",
             "-CAkey", f"{ca}.key", "-set_serial", "1", "-out", f"{leaf}.pem",
             "-days", "2", "-extfile", str(ROOT / "scripts/ci/testdata/sync_transport_leaf.ext")])


def collect(sim: Simulator, evidence: Path, phase: str) -> dict:
    support = sim.support()
    for extension in ("json", "png"):
        source = contained(support / f"ios-acceptance-{phase}.{extension}", support)
        shutil.copyfile(source, evidence / source.name)
    png = (evidence / f"ios-acceptance-{phase}.png").read_bytes()
    if not png.startswith(b"\x89PNG\r\n\x1a\n") or len(png) < 1024:
        raise ValueError("Missing or invalid runtime screenshot.")
    return json.loads((evidence / f"ios-acceptance-{phase}.json").read_text(encoding="utf-8"))


def execute(evidence: Path, run: Commands, source: str) -> dict:
    result = {"status": "failed", "sourceCommit": source, "phases": [], "errors": []}
    sim = Simulator(run, PREFIX + uuid.uuid4().hex)
    build_attempted = False
    try:
        inventory = sim.inventory()
        write_json(evidence / "inventory.json", inventory)
        runtime, device_type = select_simulator(inventory)
        result.update(runtime=runtime, deviceType=device_type)
        result["flutter"] = json.loads(run(["flutter", "--version", "--machine"]))
        result["xcode"] = run(["xcodebuild", "-version"])
        sim.create(runtime, device_type)
        result["device"] = sim.device
        write_json(evidence / "ownership.json", {"name": sim.name, "device": sim.device})
        sim.command("boot")
        sim.command("bootstatus", "-b", timeout=300)
        certs = evidence / "certificates"
        certificates(run, certs)
        sim.command("keychain", "add-root-cert", str(certs / "trusted-ca.pem"))
        build_attempted = True
        run(["flutter", "build", "ios", "--simulator", "--debug", "--no-pub",
             "--target", TARGET, f"--dart-define=AETHERTUNE_ACCEPTANCE_SHA={source}",
             f"--dart-define=AETHERTUNE_ACCEPTANCE_UDID={sim.device}",
             f"--dart-define=AETHERTUNE_ACCEPTANCE_NAME={sim.name}"],
            cwd=APP, timeout=1200)
        bundles = list((APP / "build/ios/iphonesimulator").glob("*.app"))
        if len(bundles) != 1:
            raise ValueError("Expected exactly one compiled Simulator app.")
        bundle = bundles[0]
        with (bundle / "Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if info.get("CFBundleIdentifier") != BUNDLE:
            raise ValueError("Unexpected compiled application bundle ID.")
        executable = contained(bundle / info["CFBundleExecutable"], bundle)
        result["executableSha256"] = hashlib.sha256(executable.read_bytes()).hexdigest()
        sim.command("install", str(bundle))
        fixture = contained(sim.support() / "aethertune-ios-fixture", sim.support())
        fixture.mkdir(parents=True, mode=0o700)
        (fixture / "marker").write_text(MARKER, encoding="utf-8")
        for name in ("trusted-ca.pem", "trusted-leaf.pem", "trusted-leaf.key",
                     "untrusted-leaf.pem", "untrusted-leaf.key"):
            shutil.copyfile(certs / name, fixture / name)
        pids: set[int] = set()
        for phase in PHASES:
            current_fixture = contained(sim.support() / "aethertune-ios-fixture", sim.support())
            write_json(current_fixture / "control.json", {
                "phase": phase, "device": sim.device, "fixtureName": sim.name,
                "sourceCommit": source,
            })
            try:
                run(["flutter", "drive", "--no-pub", "-d", sim.device,
                     "--target", TARGET, "--driver", "test_driver/native_acceptance_driver.dart",
                     "--use-application-binary", str(bundle), "--keep-app-running"],
                    cwd=APP, timeout=360)
            except Exception:
                try:
                    collect(sim, evidence, phase)
                except Exception as error:
                    result["errors"].append(f"Failed-phase evidence: {error}")
                raise
            report = collect(sim, evidence, phase)
            pids.add(verify_report(report, phase, sim.device, source, pids))
            result["phases"].append(phase)
            sim.command("terminate", BUNDLE)
    except (Exception, KeyboardInterrupt) as error:
        result["errors"].append(f"{type(error).__name__}: {error}")
    finally:
        if build_attempted:
            try:
                run(["flutter", "build", "ios", "--simulator", "--debug", "--no-pub",
                     "--target", "lib/main.dart"], cwd=APP, timeout=1200)
                result["ordinaryOutputRestored"] = True
            except (Exception, KeyboardInterrupt) as error:
                result["errors"].append(f"Ordinary build restoration: {error}")
        try:
            result["cleanup"] = sim.cleanup()
        except (Exception, KeyboardInterrupt) as error:
            result["cleanup"] = {"status": "failed", "device": sim.device}
            result["errors"].append(f"Simulator cleanup: {error}")
    if (not result["errors"] and result["phases"] == list(PHASES)
            and result.get("ordinaryOutputRestored") is True
            and result["cleanup"]["status"] == "deleted"):
        result["status"] = "passed"
    write_json(evidence / "result.json", result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    require_host(sys.platform, dict(os.environ))
    evidence = contained(args.evidence, ROOT / "build")
    evidence.mkdir(parents=True, exist_ok=False)
    run = Commands(evidence)
    source = run(["git", "rev-parse", "HEAD"])
    if not re.fullmatch(r"[0-9a-f]{40}", source) or source != os.environ.get("GITHUB_SHA"):
        raise ValueError("Checked out commit does not match the workflow commit.")

    def interrupted(signum, _frame):
        raise InterruptedError(f"Acceptance interrupted by signal {signum}.")

    signal.signal(signal.SIGTERM, interrupted)
    result = execute(evidence, run, source)
    print(json.dumps(result, indent=2))
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
