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
from urllib.parse import urlencode, urlsplit
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "apps/mobile"
BUNDLE = "dev.aethertune.aethertune"
PREFIX = "AetherTune_Acceptance_"
TARGET = "integration_test/ios_native_acceptance_test.dart"
IOS_ACCEPTANCE_BUILD_TIMEOUT_SECONDS = 1500
VM_SERVICE_DISCOVERY_TIMEOUT_SECONDS = 60
VM_SERVICE_LOG_MAX_BYTES = 1024 * 1024
MARKER = "aethertune-ios-native-acceptance-v1\n"
PHASES = ("seed", "reopen", "sync")
COMMON = {"production-app-startup", "native-background-cancellation"}
CHECKS = {
    "seed": COMMON | {
        "native-keychain-round-trip", "native-library-snapshot",
        "native-decode-progress-pause-seek-stop", "persistent-fixture-checkpoint",
    },
    "reopen": COMMON | {
        "keychain-survived-process-restart", "native-library-snapshot",
        "library-queue-settings-survived-process-restart", "native-keychain-deletion",
        "onboarding-offline-preferences-survived-process-restart",
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


def verify_report(report: dict, phase: str, device: str, source: str, previous_pids: set[int],
                  *, launch_pid: int) -> int:
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
    if pid != launch_pid:
        raise ValueError("Runtime report PID does not match the owned simulator launch.")
    return pid


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


class CommandTimedOut(TimeoutError):
    def __init__(self, command: list[str], timeout: int,
                 stdout_path: Path, stderr_path: Path,
                 cleanup_warnings: tuple[str, ...] = (), reaped: bool = True,
                 group_gone: bool = True):
        self.command = command
        self.timeout = timeout
        self.stdout_path = stdout_path
        self.stderr_path = stderr_path
        self.cleanup_warnings = cleanup_warnings
        self.reaped = reaped
        self.group_gone = group_gone
        super().__init__(f"Command {command!r} timed out after {timeout} seconds; "
                         f"see {stdout_path.name} and {stderr_path.name}.")


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
            except BaseException as error:
                # Stop this command's process group, including owned build/driver children.
                cleanup_warnings: list[str] = []
                for sig in (signal.SIGTERM, signal.SIGKILL):
                    try:
                        os.killpg(child.pid, sig)
                    except ProcessLookupError:
                        pass
                    except PermissionError as signal_error:
                        # CoreSimulator can attach a process the runner cannot
                        # signal to flutter's group. Still stop the owned leader
                        # and preserve the original timeout for diagnosis.
                        cleanup_warnings.append(
                            f"Process group signal {sig} denied: {signal_error}")
                        try:
                            child.send_signal(sig)
                        except ProcessLookupError:
                            pass
                        except PermissionError as leader_error:
                            cleanup_warnings.append(
                                f"Process leader signal {sig} denied: {leader_error}")
                    if sig == signal.SIGTERM:
                        time.sleep(1)
                reaped = True
                try:
                    child.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    try:
                        child.kill()
                    except ProcessLookupError:
                        pass
                    except PermissionError as kill_error:
                        cleanup_warnings.append(f"Process leader kill denied: {kill_error}")
                    try:
                        child.wait(timeout=30)
                    except subprocess.TimeoutExpired:
                        reaped = False
                        cleanup_warnings.append("Process leader was not reaped after 60 seconds")
                group_gone = False
                for attempt in range(5):
                    try:
                        os.killpg(child.pid, 0)
                    except ProcessLookupError:
                        group_gone = True
                        break
                    except PermissionError:
                        pass
                    if attempt < 4:
                        time.sleep(1)
                if not group_gone:
                    cleanup_warnings.append(
                        "Process group remains present or inaccessible after timeout cleanup")
                for warning in cleanup_warnings:
                    print(f"Timeout cleanup warning: {warning}", flush=True)
                if isinstance(error, subprocess.TimeoutExpired):
                    raise CommandTimedOut(args, timeout, stdout, stderr,
                                          tuple(cleanup_warnings), reaped, group_gone) from error
                raise
        if code:
            raise RuntimeError(f"Command exited {code}; see {stdout.name} and {stderr.name}.")
        return stdout.read_text(encoding="utf-8", errors="replace").strip()


class Simulator:
    def __init__(self, run: Commands, name: str):
        self.run = run
        self.name = name
        self.device: str | None = None
        self.expected_support: Path | None = None

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
        support = support_directory(Path(container), self.current())
        if self.expected_support is not None and support != self.expected_support:
            raise ValueError("Application Data container changed during process restart.")
        return support

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


def _drive_timeout_diagnostic(error: CommandTimedOut, phase: str, attempt: int) -> str:
    lines = [f"{phase} flutter drive attempt {attempt} timed out after "
             f"{error.timeout} seconds."]
    lines.extend(f"Timeout cleanup warning: {item}" for item in error.cleanup_warnings)
    for path in (error.stdout_path, error.stderr_path):
        try:
            size = path.stat().st_size
            if size == 0:
                lines.append(f"{path.name}: 0 bytes (no output)")
                continue
            with path.open("rb") as stream:
                stream.seek(max(0, size - 2048))
                tail = stream.read().decode("utf-8", errors="replace")
            lines.append(f"{path.name}: {size} bytes; last {min(size, 2048)} bytes:\n{tail}")
        except OSError as read_error:
            lines.append(f"{path.name}: cannot read log: {read_error}")
    return "\n".join(lines)


def _record_drive_timeout(error: CommandTimedOut, phase: str, attempt: int) -> None:
    diagnostic = _drive_timeout_diagnostic(error, phase, attempt)
    print(diagnostic, flush=True)
    (error.stdout_path.parent / f"{phase}-drive-timeout-attempt-{attempt}.log").write_text(
        diagnostic + "\n", encoding="utf-8")


def _silent_drive_timeout(error: CommandTimedOut) -> bool:
    try:
        return (error.stdout_path.is_file() and error.stderr_path.is_file()
                and error.stdout_path.stat().st_size == 0
                and error.stderr_path.stat().st_size == 0)
    except OSError:
        return False


def _sync_launch_recovery_reason(error: CommandTimedOut) -> str | None:
    if (not error.reaped or not error.group_gone
            or error.command[:2] != ["flutter", "drive"]):
        return None
    if _silent_drive_timeout(error):
        return "silent-flutter-drive-timeout"
    return None


class _NoVMRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, _request, _fp, _code, _msg, _headers, _newurl):
        return None


def vm_is_paused_at_start(uri: str, pid: int) -> bool:
    """Permit a silent attach retry only if this exact VM has not run its main isolate."""
    authenticated_vm_uri(uri)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoVMRedirect())

    def result(method: str, parameters: dict[str, str] | None = None) -> dict:
        suffix = method + ("?" + urlencode(parameters) if parameters else "")
        with opener.open(uri + suffix, timeout=5) as response:
            raw = response.read(65537)
        if len(raw) > 65536:
            raise ValueError("VM service readiness response exceeds its size bound.")
        value = json.loads(raw)
        if not isinstance(value, dict) or not isinstance(value.get("result"), dict):
            raise ValueError("Malformed VM service readiness response.")
        return value["result"]

    try:
        vm = result("getVM")
        if vm.get("type") != "VM" or type(vm.get("pid")) is not int or vm["pid"] != pid:
            return False
        isolates = vm.get("isolates")
        if not isinstance(isolates, list):
            return False
        main = [item for item in isolates if isinstance(item, dict)
                and item.get("isSystemIsolate") is False]
        if len(main) != 1 or not isinstance(main[0].get("id"), str):
            return False
        isolate = result("getIsolate", {"isolateId": main[0]["id"]})
        return (isolate.get("type") == "Isolate" and isolate.get("id") == main[0]["id"]
                and isinstance(isolate.get("pauseEvent"), dict)
                and isolate["pauseEvent"].get("kind") == "PauseStart")
    except (OSError, ValueError, urllib.error.URLError):
        return False


def launch_pid(output: str) -> int:
    match = re.fullmatch(re.escape(BUNDLE) + r": ([1-9][0-9]*)", output.strip())
    if match is None:
        raise ValueError("Missing or malformed owned app launch PID.")
    return int(match[1])


def authenticated_vm_uri(value: str) -> str:
    # Retain the engine's authentication token; never attach to a remote service
    # or an unauthenticated port, and never disable service authentication.
    uri = urlsplit(value)
    if (uri.scheme != "http" or uri.hostname != "127.0.0.1"
            or uri.username is not None or uri.password is not None
            or uri.query or uri.fragment or uri.port is None
            or not 1 <= uri.port <= 65535
            or re.fullmatch(r"/[A-Za-z0-9_-]{1,256}={0,2}/", uri.path) is None
            or value != f"http://127.0.0.1:{uri.port}{uri.path}"):
        raise ValueError("Expected an authenticated loopback Dart VM service URI.")
    return value


def vm_uri_from_log(contents: str, pid: int) -> str | None:
    # `log stream --style json` is an array of multiline records and can be
    # incomplete while the process writes. Decode complete records only. Ignore
    # other processes even when they print a service URI into the same log.
    decoder = json.JSONDecoder()
    position = 0
    uris: set[str] = set()
    while (position := contents.find("{", position)) != -1:
        try:
            record, length = decoder.raw_decode(contents[position:])
        except json.JSONDecodeError:
            break
        position += length
        if (not isinstance(record, dict) or type(record.get("processID")) is not int
                or record["processID"] != pid):
            continue
        message = record.get("eventMessage")
        if not isinstance(message, str):
            continue
        match = re.search(r"The Dart VM service is listening on (\S+)", message)
        if match is not None:
            uris.add(authenticated_vm_uri(match[1]))
    if len(uris) > 1:
        raise ValueError("Multiple VM service URIs for the owned launch PID.")
    return next(iter(uris), None)


class VMServiceLog:
    """Bounded, reaped log reader for this owned simulator and app executable."""

    def __init__(self, sim: Simulator, run: Commands, phase: str, attempt: int,
                 executable_name: str):
        if re.fullmatch(r"[A-Za-z0-9_.-]+", executable_name) is None:
            raise ValueError("Unexpected compiled executable name.")
        if phase not in PHASES or type(attempt) is not int or attempt not in (1, 2):
            raise ValueError("Unexpected VM service discovery phase or attempt.")
        self.sim = sim
        self.run = run
        self.stdout_path = run.evidence / f"{phase}-launch-{attempt}-vm-service.log"
        self.stderr_path = run.evidence / f"{phase}-launch-{attempt}-vm-service-stderr.log"
        self.command = ["xcrun", "simctl", "spawn", sim.device, "log", "stream",
                        "--style", "json", "--predicate",
                        f'eventType = logEvent AND processImagePath ENDSWITH "/{executable_name}"']

    def __enter__(self):
        self.sim.current()
        self.stdout = self.stdout_path.open("wb")
        try:
            self.stderr = self.stderr_path.open("wb")
        except BaseException:
            self.stdout.close()
            raise
        try:
            self.child = subprocess.Popen(self.command, cwd=APP, stdin=subprocess.DEVNULL,
                                          stdout=self.stdout, stderr=self.stderr,
                                          start_new_session=True)
        except BaseException:
            self.stdout.close()
            self.stderr.close()
            raise
        return self

    def uri(self, pid: int) -> str:
        deadline = time.monotonic() + VM_SERVICE_DISCOVERY_TIMEOUT_SECONDS
        last_fallback = float("-inf")
        while time.monotonic() < deadline:
            if self.child.poll() is not None:
                raise RuntimeError("Owned simulator VM service log reader exited early.")
            with self.stdout_path.open("rb") as stream:
                contents = stream.read(VM_SERVICE_LOG_MAX_BYTES + 1)
            if len(contents) > VM_SERVICE_LOG_MAX_BYTES:
                raise ValueError("Owned VM service discovery log exceeds its size bound.")
            uri = vm_uri_from_log(contents.decode("utf-8", errors="replace"), pid)
            if uri is not None:
                return uri
            # Popen is not proof that the stream subscription is active. Recover
            # an early announcement from this exact owned launch's retained log;
            # never guess a port or turn off its authentication token.
            if time.monotonic() - last_fallback >= 1:
                snapshot = self.sim.command(
                    "spawn", "log", "show", "--last", "1m", "--style", "json",
                    "--predicate", self.command[-1]
                    + ' AND eventMessage CONTAINS "The Dart VM service is listening on "',
                    timeout=10)
                if len(snapshot.encode("utf-8")) > VM_SERVICE_LOG_MAX_BYTES:
                    raise ValueError("Owned VM service snapshot exceeds its size bound.")
                uri = vm_uri_from_log(snapshot, pid)
                if uri is not None:
                    return uri
                last_fallback = time.monotonic()
            # Poll only service readiness, before any test assertion is resumed.
            time.sleep(0.1)
        raise TimeoutError("Missing authenticated VM service URI for the owned launch PID.")

    def __exit__(self, _type, _value, _traceback):
        try:
            # Only this start_new_session reader's process group is signalled.
            # Reaping the leader alone does not prove its log child is stopped.
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(self.child.pid, sig)
                except ProcessLookupError:
                    pass
                except PermissionError:
                    if sig == signal.SIGTERM:
                        self.child.terminate()
                    else:
                        self.child.kill()
                try:
                    self.child.wait(timeout=10)
                    try:
                        os.killpg(self.child.pid, 0)
                    except ProcessLookupError:
                        break
                except subprocess.TimeoutExpired:
                    if sig == signal.SIGKILL:
                        raise RuntimeError("Owned VM service log reader was not reaped.")
            else:
                raise RuntimeError("Owned VM service log reader process group remains present.")
        except Exception as cleanup_error:
            if _value is None:
                raise
            # Keep the launch/discovery/assertion error as the primary failure.
            print(f"VM service reader cleanup warning: {cleanup_error}", flush=True)
            self.stderr.write(f"\nCleanup warning: {cleanup_error}\n".encode("utf-8"))
        finally:
            self.stdout.close()
            self.stderr.close()


def _drive_once(sim: Simulator, run: Commands, phase: str, attempt: int,
                executable_name: str, previous_pids: set[int]) -> int:
    sim.support()  # Recheck the installation's Data container before launch.
    # Flutter 3.44.6 uses syslog for engine output. Start unified logging before
    # launching so the authenticated service announcement cannot be missed.
    with VMServiceLog(sim, run, phase, attempt, executable_name) as logs:
        pid = launch_pid(sim.command(
            "launch", BUNDLE, "--start-paused", "--disable-vm-service-publication",
            "--enable-checked-mode", "--verify-entry-points"))
        if pid in previous_pids:
            raise ValueError("Owned app launch reused a previous phase PID.")
        sim.support()
        uri = logs.uri(pid)
    write_json(run.evidence / f"{phase}-launch-{attempt}.json", {
        "phase": phase, "attempt": attempt, "device": sim.device,
        "pid": pid, "dataContainer": str(sim.expected_support.parent.parent),
    })
    run(["flutter", "drive", "--no-pub", "-d", sim.device,
         "--target", TARGET, "--driver", "test_driver/native_acceptance_driver.dart",
         f"--use-existing-app={uri}", "--keep-app-running"], cwd=APP, timeout=360)
    sim.support()
    return pid


def drive_phase(sim: Simulator, run: Commands, phase: str,
                executable_name: str, previous_pids: set[int]) -> tuple[str | None, int]:
    try:
        return None, _drive_once(sim, run, phase, 1, executable_name, previous_pids)
    except CommandTimedOut as error:
        _record_drive_timeout(error, phase, 1)
        reason = _sync_launch_recovery_reason(error)
        if phase != "sync" or reason is None:
            raise
        support = sim.support()
        report = contained(support / f"ios-acceptance-{phase}.json", support)
        if report.exists():
            raise
        launched = json.loads((run.evidence / f"{phase}-launch-1.json").read_text())
        uri_options = [item.split("=", 1)[1] for item in error.command
                       if item.startswith("--use-existing-app=")]
        if (len(uri_options) != 1
                or not vm_is_paused_at_start(uri_options[0], launched["pid"])):
            raise
        previous_pids = previous_pids | {launched["pid"]}

    # Retain the existing bounded recovery for an unreported sync driver
    # timeout. A reported assertion or persistence failure is never retried.
    print("Sync launch failed before a runtime report; restarting owned simulator once.",
          flush=True)
    if sim.current()["state"] != "Shutdown":
        sim.command("shutdown")
    sim.command("boot")
    sim.command("bootstatus", "-b", timeout=300)
    try:
        pid = _drive_once(sim, run, phase, 2, executable_name, previous_pids)
    except CommandTimedOut as error:
        _record_drive_timeout(error, phase, 2)
        raise
    return reason, pid


def execute(evidence: Path, run: Commands, source: str) -> dict:
    result = {"status": "failed", "sourceCommit": source, "phases": [],
              "recoveries": [], "errors": []}
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
            cwd=APP, timeout=IOS_ACCEPTANCE_BUILD_TIMEOUT_SECONDS)
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
        sim.expected_support = sim.support()
        result["dataContainer"] = str(sim.expected_support.parent.parent)
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
                recovery_reason, pid = drive_phase(sim, run, phase, executable.name, pids)
                if recovery_reason is not None:
                    result["recoveries"].append({
                        "phase": phase, "reason": recovery_reason,
                        "attempts": 2,
                    })
            except Exception:
                try:
                    collect(sim, evidence, phase)
                except Exception as error:
                    result["errors"].append(f"Failed-phase evidence: {error}")
                raise
            report = collect(sim, evidence, phase)
            pids.add(verify_report(report, phase, sim.device, source, pids, launch_pid=pid))
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
