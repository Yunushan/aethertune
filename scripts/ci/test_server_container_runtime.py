#!/usr/bin/env python3
"""Exercise fixture isolation, cleanup, hardening checks, and gate integration."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import server_container_runtime as runtime
import scan_server_container as scanner


IMAGE = "sha256:" + "a" * 64
CONTAINER = "b" * 64


def completed(output="", code=0):
    return subprocess.CompletedProcess([], code, output, "")


def healthy():
    return {"Image": IMAGE, "State": {"Running": True, "Health": {"Status": "healthy"}},
            "NetworkSettings": {"Ports": {"8080/tcp": [{"HostIp": "127.0.0.1", "HostPort": "12345"}]}},
            "HostConfig": {"ReadonlyRootfs": True, "CapDrop": ["ALL"],
                           "SecurityOpt": ["no-new-privileges=true"],
                           "Memory": 256 * 1024 * 1024, "NanoCpus": 1000000000}}


class ContainerRuntimeTest(unittest.TestCase):
    def test_requires_immutable_image_ids_before_creating_any_fixture(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(runtime.Fixture, "create_volume") as create:
            with self.assertRaises(AssertionError):
                runtime.run("server:latest", IMAGE, Path(directory) / "evidence")
            create.assert_not_called()

    def test_container_is_loopback_only_limited_and_uses_unique_volume(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = runtime.Fixture(Path(directory))
            with patch.object(fixture, "docker", side_effect=[completed(CONTAINER), completed()]) as docker, \
                    patch.object(fixture, "inspect", return_value=healthy()), \
                    patch.object(fixture, "request", return_value={"status": "ready"}):
                self.assertEqual(fixture.start(IMAGE, "candidate"), CONTAINER)
            command = docker.call_args_list[0].args
            self.assertIn("127.0.0.1::8080", command)
            self.assertIn(f"type=volume,src={fixture.volume},dst=/data", command)
            self.assertIn("--read-only", command)
            self.assertIn("no-new-privileges=true", command)
            self.assertIn("AETHERTUNE_OPS_TOKEN", command)
            self.assertNotIn(fixture.credentials[0], " ".join(command))
            self.assertEqual(fixture.port, 12345)

    def test_rejects_public_binding_or_missing_runtime_limits(self):
        changes = [
            ("NetworkSettings", {"Ports": {"8080/tcp": [{"HostIp": "0.0.0.0", "HostPort": "12345"}]}}),
            ("Image", "sha256:wrong"),
            ("HostConfig", {**healthy()["HostConfig"], "ReadonlyRootfs": False}),
            ("HostConfig", {**healthy()["HostConfig"], "Memory": 0}),
        ]
        for key, value in changes:
            with self.subTest(key=key, value=value), tempfile.TemporaryDirectory() as directory:
                fixture = runtime.Fixture(Path(directory))
                details = healthy()
                details[key] = value
                with patch.object(fixture, "docker", side_effect=[completed(CONTAINER), completed()]), \
                        patch.object(fixture, "inspect", return_value=details), \
                        patch.object(fixture, "request", return_value={"status": "ready"}), \
                        self.assertRaises(AssertionError):
                    fixture.start(IMAGE, "candidate")

    def test_stop_rejects_oom_or_forced_shutdown(self):
        for code, oom in ((137, False), (0, True)):
            with self.subTest(code=code, oom=oom), tempfile.TemporaryDirectory() as directory:
                fixture = runtime.Fixture(Path(directory))
                with patch.object(fixture, "docker", return_value=completed()), \
                        patch.object(fixture, "inspect", return_value={"State": {
                            "Running": False, "ExitCode": code, "OOMKilled": oom}}), \
                        self.assertRaises(AssertionError):
                    fixture.stop(CONTAINER)

    def test_cleanup_redacts_credentials_and_removes_only_owned_resources(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = runtime.Fixture(Path(directory))
            fixture.containers = [(CONTAINER, "candidate")]
            fixture.volume_created = True
            calls = []

            def docker(*args, **kwargs):
                calls.append(args)
                if args[0] == "logs":
                    return completed(fixture.credentials[0])
                if args[:2] == ("volume", "inspect"):
                    return completed(json.dumps([{"Labels": {"aethertune.fixture": fixture.identity}}]))
                return completed()

            with patch.object(fixture, "docker", side_effect=docker):
                errors = fixture.cleanup()
            self.assertIn("logged a fixture credential", errors[0])
            self.assertEqual((Path(directory) / "candidate.log").read_text(), "[redacted]")
            self.assertIn(("rm", "--force", CONTAINER), calls)
            self.assertIn(("volume", "rm", fixture.volume), calls)

    def test_cleanup_refuses_volume_with_wrong_ownership_label(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = runtime.Fixture(Path(directory))
            fixture.volume_created = True
            with patch.object(fixture, "docker", return_value=completed('[{"Labels": {}}]')) as docker:
                errors = fixture.cleanup()
            self.assertIn("ownership label", errors[0])
            self.assertEqual(docker.call_count, 1)

    def test_startup_failure_still_writes_failed_evidence(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "evidence"
            with patch.object(runtime.Fixture, "create_volume"), \
                    patch.object(runtime.Fixture, "start", side_effect=AssertionError("not healthy")), \
                    patch.object(runtime.Fixture, "cleanup", return_value=[]):
                self.assertEqual(runtime.run(IMAGE, IMAGE, evidence), 1)
            self.assertEqual(json.loads((evidence / "runtime.json").read_text())["error"], "not healthy")

    def test_shared_scan_runs_exact_image_acceptance(self):
        source = (scanner.ROOT / "scripts/ci/scan_server_container.py").read_text()
        self.assertIn('"scripts/ci/server_container_runtime.py"', source)
        self.assertIn('"--image", image_id', source)
        self.assertIn('evidence / "runtime.log", 300', source)
        compose_test = (scanner.ROOT / "scripts/ci/test_server_compose.sh").read_text()
        self.assertIn('--project-name "$project"', compose_test)
        self.assertIn("uuid.uuid4().hex", compose_test)
        self.assertIn("/usr/local/bin/aethertune-healthcheck", compose_test)


if __name__ == "__main__":
    unittest.main()
