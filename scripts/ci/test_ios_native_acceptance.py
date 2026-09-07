#!/usr/bin/env python3
"""Exercise simulator ownership, evidence validation and failure cleanup off-device."""

from __future__ import annotations

import copy
import json
from pathlib import Path
import plistlib
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, call, patch

import run_ios_native_acceptance as ios

DEVICE = "11111111-2222-4333-8444-555555555555"
CONTAINER = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
NAME = ios.PREFIX + "a" * 32
SOURCE = "1" * 40
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
PHONE = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"


def inventory() -> dict:
    return {
        "devicetypes": [{"identifier": PHONE, "productFamily": "iPhone"}],
        "runtimes": [{"identifier": RUNTIME, "version": "18.5", "isAvailable": True}],
        "devices": {RUNTIME: [{"udid": DEVICE, "name": NAME, "isAvailable": True,
                               "deviceTypeIdentifier": PHONE, "state": "Shutdown"}]},
    }


def report(phase: str, pid: int) -> dict:
    return {"status": "passed", "phase": phase, "device": DEVICE, "sourceCommit": SOURCE,
            "pid": pid, "checks": [{"name": name, "passed": True} for name in ios.CHECKS[phase]]}


class SimulatorSafetyTest(unittest.TestCase):
    def test_refuses_nonhosted_or_non_macos_before_execution(self):
        valid = {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"}
        ios.require_host("darwin", valid)
        for platform, env in [("win32", valid), ("linux", valid), ("darwin", {}),
                              ("darwin", {**valid, "RUNNER_ENVIRONMENT": "self-hosted"})]:
            with self.subTest(platform=platform, env=env), self.assertRaises(ValueError):
                ios.require_host(platform, env)

    def test_selects_available_compatible_ios_not_other_platforms(self):
        data = inventory()
        data["runtimes"] += [
            {"identifier": "com.apple.CoreSimulator.SimRuntime.tvOS-27", "version": "27", "isAvailable": True},
            {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27", "version": "27", "isAvailable": False},
        ]
        runtime, phone = ios.select_simulator(data)
        self.assertEqual(runtime["identifier"], RUNTIME)
        self.assertEqual(phone["identifier"], PHONE)

    def test_selects_newest_compatible_installed_runtime(self):
        data = inventory()
        newer = {"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26", "version": "26.0",
                 "isAvailable": True, "supportedDeviceTypes": [{"identifier": PHONE}]}
        data["runtimes"].append(newer)
        self.assertEqual(ios.select_simulator(data)[0], newer)

    def test_does_not_guess_compatibility_from_device_name(self):
        data = inventory()
        data["devices"][RUNTIME][0].pop("deviceTypeIdentifier")
        with self.assertRaisesRegex(ValueError, "compatible"):
            ios.select_simulator(data)

    def test_refuses_aliases_mismatched_or_duplicate_ownership(self):
        for device in ("booted", "all", "unavailable", DEVICE.replace("-", "")):
            with self.subTest(device=device), self.assertRaises(ValueError):
                ios.owned_device(inventory(), device, NAME)
        for name in ("Personal iPhone", ios.PREFIX + "fixture", ios.PREFIX + "b" * 32):
            with self.subTest(name=name), self.assertRaises(ValueError):
                ios.owned_device(inventory(), DEVICE, name)
        data = inventory()
        data["devices"][RUNTIME].append(copy.deepcopy(data["devices"][RUNTIME][0]))
        with self.assertRaises(ValueError):
            ios.owned_device(data, DEVICE, NAME)

    def test_container_cannot_escape_owned_guest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            data = root / DEVICE / "data"
            data.mkdir(parents=True)
            guest = {"dataPath": str(data), "udid": DEVICE}
            container = data / "Containers/Data/Application" / CONTAINER
            expected = container / "Library/Application Support"
            self.assertEqual(ios.support_directory(container, guest), expected.resolve())
            for path in (root / CONTAINER, data, container / "child", container.parent / "not-a-uuid"):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    ios.support_directory(path, guest)
            guest["udid"] = CONTAINER
            with self.assertRaisesRegex(ValueError, "dataPath"):
                ios.support_directory(container, guest)

    def test_evidence_must_stay_inside_build_not_build_itself(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "build"
            self.assertEqual(ios.contained(root / "ios", root), (root / "ios").resolve())
            for path in (root, root / "../outside"):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    ios.contained(path, root)

    def test_rejects_symlink_escape(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            build, outside = root / "build", root / "outside"
            build.mkdir()
            outside.mkdir()
            try:
                (build / "link").symlink_to(outside, target_is_directory=True)
            except OSError as error:
                self.skipTest(f"Host lacks symlink privilege: {error}")
            with self.assertRaises(ValueError):
                ios.contained(build / "link/evidence", build)

    def test_reports_require_exact_sha_phase_device_and_independent_processes(self):
        for phase in ios.PHASES:
            valid = report(phase, 123)
            self.assertEqual(ios.verify_report(valid, phase, DEVICE, SOURCE, set()), 123)
            for field, value in (("sourceCommit", "2" * 40), ("phase", "other"),
                                 ("device", CONTAINER), ("status", "failed"), ("pid", True),
                                 ("pid", 0), ("pid", "123")):
                with self.subTest(phase=phase, field=field), self.assertRaises(ValueError):
                    ios.verify_report({**valid, field: value}, phase, DEVICE, SOURCE, set())
            with self.assertRaisesRegex(ValueError, "distinct"):
                ios.verify_report(valid, phase, DEVICE, SOURCE, {123})

    def test_missing_duplicate_or_failed_check_cannot_pass(self):
        for phase in ios.PHASES:
            for change in ("missing", "duplicate", "failed", "truthy"):
                invalid = report(phase, 123)
                if change == "missing":
                    invalid["checks"].pop()
                elif change == "duplicate":
                    invalid["checks"][0] = invalid["checks"][1]
                else:
                    invalid["checks"][0]["passed"] = False if change == "failed" else "true"
                with self.subTest(phase=phase, change=change), self.assertRaises(ValueError):
                    ios.verify_report(invalid, phase, DEVICE, SOURCE, set())


class FakeCommands:
    """Model simctl state and app reports; these tests are not iOS runtime evidence."""

    def __init__(self, app: Path, failure: str | None):
        self.app, self.failure = app, failure
        self.calls = []
        self.data = inventory()
        self.container = app / "guest" / DEVICE / "data/Containers/Data/Application" / CONTAINER
        self.support = self.container / "Library/Application Support"
        self.support.mkdir(parents=True)
        self.data["devices"][RUNTIME][0]["dataPath"] = str(app / "guest" / DEVICE / "data")
        self.owned = False
        self.bundle = app / "build/ios/iphonesimulator/Runner.app"

    def __call__(self, args, **kwargs):
        self.calls.append(args)
        if args[:3] == ["xcrun", "simctl", "list"]:
            return json.dumps(self.data)
        if args[:3] == ["xcrun", "simctl", "create"]:
            self.owned = True
            self.data["devices"][RUNTIME][0]["name"] = args[3]
            if self.failure == "create-timeout":
                raise TimeoutError("Create observation expired after guest creation")
            return DEVICE
        if args[:2] == ["xcrun", "simctl"]:
            if args[3] != DEVICE or not self.owned:
                raise AssertionError("Attempted to mutate an unowned simulator")
            verb = args[2]
            if verb == "get_app_container":
                return str(self.container)
            if verb == "boot":
                self.data["devices"][RUNTIME][0]["state"] = "Booted"
            elif verb == "shutdown":
                self.data["devices"][RUNTIME][0]["state"] = "Shutdown"
            elif verb == "delete":
                if self.failure == "cleanup":
                    raise RuntimeError("delete failed")
                self.data["devices"][RUNTIME] = []
                if self.failure == "delete-timeout":
                    raise TimeoutError("Delete observation expired after completion")
            elif verb == "keychain":
                if args[4:5] != ["add-root-cert"] or not args[5].endswith("trusted-ca.pem"):
                    raise AssertionError("Wrong trust boundary")
            elif verb not in ("bootstatus", "install", "terminate"):
                raise AssertionError(f"Unexpected simctl command: {args}")
            return ""
        if args == ["flutter", "--version", "--machine"]:
            return '{"frameworkVersion":"fixture"}'
        if args == ["xcodebuild", "-version"]:
            return "Xcode fixture"
        if args[:3] == ["flutter", "build", "ios"]:
            if "lib/main.dart" in args and self.failure == "restore":
                raise RuntimeError("ordinary build failed")
            if ios.TARGET in args:
                if f"--dart-define=AETHERTUNE_ACCEPTANCE_UDID={DEVICE}" not in args:
                    raise AssertionError("Probe binary must be bound to the owned guest")
                name = self.data["devices"][RUNTIME][0]["name"]
                if f"--dart-define=AETHERTUNE_ACCEPTANCE_NAME={name}" not in args:
                    raise AssertionError("Probe binary must be bound to the fixture name")
            self.bundle.mkdir(parents=True, exist_ok=True)
            with (self.bundle / "Info.plist").open("wb") as stream:
                plistlib.dump({"CFBundleIdentifier": ios.BUNDLE, "CFBundleExecutable": "Runner"}, stream)
            (self.bundle / "Runner").write_bytes(b"fixture executable")
            return ""
        if args[:2] == ["flutter", "drive"]:
            if "--keep-app-running" not in args:
                raise AssertionError("Driver would uninstall and invalidate persistence")
            control = json.loads((self.support / "aethertune-ios-fixture/control.json").read_text())
            phase = control["phase"]
            name = self.data["devices"][RUNTIME][0]["name"]
            if control != {"phase": phase, "device": DEVICE, "fixtureName": name, "sourceCommit": SOURCE}:
                raise AssertionError("Wrong app-container control identity")
            payload = report(phase, 100 + ios.PHASES.index(phase))
            if self.failure == phase:
                payload["status"] = "failed"
            ios.write_json(self.support / f"ios-acceptance-{phase}.json", payload)
            (self.support / f"ios-acceptance-{phase}.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"x" * 1024)
            if self.failure == phase:
                raise RuntimeError("native app assertion failed")
            return ""
        raise AssertionError(f"Unexpected command: {args}")


def fake_certificates(_run, directory):
    directory.mkdir()
    for name in ("trusted-ca.pem", "trusted-leaf.pem", "trusted-leaf.key",
                 "untrusted-leaf.pem", "untrusted-leaf.key"):
        (directory / name).write_text("synthetic fixture", encoding="utf-8")


class LifecycleTest(unittest.TestCase):
    def execute_fixture(self, failure=None):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        evidence = root / "evidence"
        evidence.mkdir()
        app = root / "app"
        run = FakeCommands(app, failure)
        with patch.object(ios, "APP", app), patch.object(ios, "certificates", fake_certificates):
            result = ios.execute(evidence, run, SOURCE)
        self.assertEqual(json.loads((evidence / "result.json").read_text()), result)
        return result, run, evidence

    def test_all_phases_restore_and_exact_guest_cleanup_are_required(self):
        result, run, _ = self.execute_fixture()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["phases"], list(ios.PHASES))
        self.assertTrue(result["ordinaryOutputRestored"])
        self.assertEqual(result["cleanup"], {"status": "deleted", "device": DEVICE})
        self.assertEqual(sum(args[:3] == ["xcrun", "simctl", "terminate"] for args in run.calls), 3)

    def test_test_failure_collects_report_restores_output_and_deletes_guest(self):
        for phase in ios.PHASES:
            with self.subTest(phase=phase):
                result, _, evidence = self.execute_fixture(phase)
                self.assertEqual(result["status"], "failed")
                self.assertTrue(result["ordinaryOutputRestored"])
                self.assertEqual(result["cleanup"]["status"], "deleted")
                self.assertEqual(json.loads((evidence / f"ios-acceptance-{phase}.json").read_text())["status"], "failed")

    def test_restore_or_cleanup_failure_cannot_report_success(self):
        for failure in ("restore", "cleanup"):
            with self.subTest(failure=failure):
                result, _, _ = self.execute_fixture(failure)
                self.assertEqual(result["status"], "failed")
                self.assertTrue(result["errors"])
                self.assertEqual(result["phases"], list(ios.PHASES))

    def test_create_timeout_recovers_owned_uuid_and_removes_guest(self):
        result, _, _ = self.execute_fixture("create-timeout")
        self.assertEqual(result["status"], "failed")
        self.assertEqual(result["cleanup"], {"status": "deleted", "device": DEVICE})

    def test_delete_timeout_rechecks_authoritative_state(self):
        result, _, _ = self.execute_fixture("delete-timeout")
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["cleanup"]["status"], "deleted")

    def test_cleanup_does_not_delete_a_guest_with_changed_ownership(self):
        run = Mock(return_value=json.dumps(inventory()))
        sim = ios.Simulator(run, ios.PREFIX + "b" * 32)
        sim.device = DEVICE
        with self.assertRaisesRegex(ValueError, "ownership"):
            sim.cleanup()
        self.assertEqual(run.call_args_list, [call(["xcrun", "simctl", "list", "--json"])])


class CommandLifecycleTest(unittest.TestCase):
    def test_timeout_terminates_owned_process_group_and_reaps_leader(self):
        with tempfile.TemporaryDirectory() as temporary:
            run = ios.Commands(Path(temporary))
            child = Mock(pid=4321)
            child.wait.side_effect = [subprocess.TimeoutExpired("fixture", 1), -9]
            with (patch.object(ios.subprocess, "Popen", return_value=child) as launch,
                  patch.object(ios.os, "killpg", create=True) as kill,
                  patch.object(ios.time, "sleep"),
                  patch.object(ios.signal, "SIGKILL", 9, create=True)):
                with self.assertRaises(subprocess.TimeoutExpired):
                    run(["fixture-command"], timeout=1)
            self.assertTrue(launch.call_args.kwargs["start_new_session"])
            self.assertEqual(kill.call_args_list, [call(4321, signal.SIGTERM), call(4321, 9)])
            self.assertEqual(child.wait.call_args_list, [call(timeout=1), call(timeout=30)])

    def test_nonzero_command_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as temporary:
            child = Mock()
            child.wait.return_value = 1
            with patch.object(ios.subprocess, "Popen", return_value=child):
                with self.assertRaisesRegex(RuntimeError, "exited 1"):
                    ios.Commands(Path(temporary))(["fixture-command"])


if __name__ == "__main__":
    unittest.main()
