#!/usr/bin/env python3
"""Exercise the exact server container and optional old-image volume upgrade."""

import argparse
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import time
import uuid


IMAGE_ID = re.compile(r"sha256:[0-9a-f]{64}\Z")


def require(condition, message):
    if not condition:
        raise AssertionError(message)


class Fixture:
    def __init__(self, evidence):
        self.evidence = evidence
        self.identity = f"aethertune-runtime-{uuid.uuid4().hex}"
        self.volume = self.identity + "-data"
        self.volume_created = False
        self.containers = []
        self.credentials = [secrets.token_urlsafe(32)]
        self.port = None

    def docker(self, *arguments, check=True, timeout=45):
        result = subprocess.run(
            ["docker", *arguments], capture_output=True, text=True, timeout=timeout,
            env={**os.environ, "AETHERTUNE_OPS_TOKEN": self.credentials[0]},
        )
        if check:
            require(result.returncode == 0, f"Docker {arguments[0]} failed: {result.stderr.strip()}")
        return result

    def inspect(self, container):
        return json.loads(self.docker("inspect", container).stdout)[0]

    def create_volume(self):
        self.docker("volume", "create", "--label", f"aethertune.fixture={self.identity}", self.volume)
        self.volume_created = True

    def start(self, image, phase, *, ready=True, operations=True):
        command = [
            "create", "--name", f"{self.identity}-{phase}",
            "--label", f"aethertune.fixture={self.identity}",
            "--publish", "127.0.0.1::8080", "--init", "--read-only",
            "--cap-drop", "ALL", "--security-opt", "no-new-privileges=true",
            "--tmpfs", "/tmp:rw,noexec,nosuid,size=16m", "--memory", "256m", "--cpus", "1",
            "--health-interval", "1s", "--health-timeout", "3s", "--health-start-period", "1s",
            "--mount", f"type=volume,src={self.volume},dst=/data",
            "--env", "PORT=8080", "--env", "AETHERTUNE_DATA_DIR=/data",
            "--env", "AETHERTUNE_LISTEN_ADDRESS=0.0.0.0", "--env", "AETHERTUNE_SYNC_USERS={}",
        ]
        if operations:
            command += ["--env", "AETHERTUNE_OPS_TOKEN"]
        container = self.docker(*command, image).stdout.strip()
        require(re.fullmatch(r"[0-9a-f]{64}", container), "Docker returned an invalid container ID")
        self.containers.append((container, phase))
        self.docker("start", container)
        if not ready:
            return container
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            details = self.inspect(container)
            require(details["State"]["Running"], f"{phase}: container exited during startup; inspect its log")
            bindings = details["NetworkSettings"]["Ports"].get("8080/tcp") or []
            if bindings and details["State"].get("Health", {}).get("Status") == "healthy":
                require(len(bindings) == 1 and bindings[0]["HostIp"] == "127.0.0.1",
                        "Fixture port is not restricted to IPv4 loopback")
                self.port = int(bindings[0]["HostPort"])
                require(self.request("GET", "/ready")["status"] == "ready", "Readiness body mismatch")
                require(details["Image"] == image, "Container did not run the expected immutable image")
                settings = details["HostConfig"]
                require(settings["ReadonlyRootfs"] and "ALL" in settings["CapDrop"], "Container hardening missing")
                require("no-new-privileges=true" in settings["SecurityOpt"], "Privilege escalation was not disabled")
                require(settings["Memory"] == 256 * 1024 * 1024 and settings["NanoCpus"] == 1000000000,
                        "Container resource limits were not applied")
                return container
            time.sleep(0.1)
        raise AssertionError(f"{phase}: Docker health check did not pass before the startup deadline")

    def request(self, method, path, *, token=None, body=None, status=200):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            headers = {"content-type": "application/json"}
            if token:
                headers["authorization"] = "Bearer " + token
            connection.request(method, path, None if body is None else json.dumps(body), headers)
            response = connection.getresponse()
            data = response.read(1024 * 1024 + 1)
            require(response.status == status, f"{method} {path}: HTTP {response.status}, expected {status}")
            require(len(data) <= 1024 * 1024, "Fixture response exceeded its bound")
            return json.loads(data) if data else None
        finally:
            connection.close()

    def issue(self, name):
        value = self.request("POST", "/api/v1/admin/sync-tokens", token=self.credentials[0], status=201,
                             body={"accountId": "container-fixture", "deviceName": name})
        self.credentials.append(value["token"])
        return value

    def stop(self, container):
        self.docker("stop", "--time", "30", container, timeout=40)
        state = self.inspect(container)["State"]
        require(not state["Running"] and state["ExitCode"] == 0 and not state["OOMKilled"],
                "Server did not stop cleanly within its resource/drain budget")
        require("AetherTune server stopped." in self.docker("logs", container).stdout,
                "Server did not record graceful shutdown")

    def expect_refusal(self, container, reason, exit_code="1"):
        status = self.docker("wait", container, timeout=12).stdout.strip()
        require(status == exit_code, f"Expected startup refusal exit {exit_code}, received {status}")
        output = self.docker("logs", container)
        require(reason in output.stdout + output.stderr, "Startup failed for an unexpected reason")

    def cleanup(self):
        errors = []
        for container, phase in reversed(self.containers):
            try:
                output = self.docker("logs", container)
                log = output.stdout + output.stderr
                exposed = any(credential in log for credential in self.credentials)
                for credential in self.credentials:
                    log = log.replace(credential, "[redacted]")
                (self.evidence / f"{phase}.log").write_text(log, encoding="utf-8")
                if exposed:
                    errors.append(f"{phase}: server logged a fixture credential")
            except (OSError, AssertionError, subprocess.SubprocessError) as error:
                errors.append(str(error))
            try:
                self.docker("rm", "--force", container)
            except (OSError, AssertionError, subprocess.SubprocessError) as error:
                errors.append(str(error))
        if self.volume_created:
            try:
                details = json.loads(self.docker("volume", "inspect", self.volume).stdout)[0]
                require(details.get("Labels", {}).get("aethertune.fixture") == self.identity,
                        "Refusing to remove a volume without this fixture's ownership label")
                self.docker("volume", "rm", self.volume)
            except (OSError, AssertionError, subprocess.SubprocessError) as error:
                errors.append(str(error))
        return errors


def mutation(revision, name):
    return {"baseRevision": revision, "deviceId": "container-fixture",
            "snapshot": {"syncVersion": 1, "version": 1, "name": name,
                         "tracks": [{"id": "container-track", "title": "Container fixture"}]}}


def run(image, source_image, evidence):
    require(IMAGE_ID.fullmatch(image) and IMAGE_ID.fullmatch(source_image), "Use immutable local image IDs")
    evidence = evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=False)
    fixture = Fixture(evidence)
    checks = []
    report = {"result": "failed", "image_id": image, "source_image_id": source_image,
              "fixture": fixture.identity, "checks": checks, "source_commit": os.environ.get("GITHUB_SHA"),
              "scope": "isolated container runtime and volume continuity; not production load or schema migration"}
    try:
        fixture.create_volume()
        source = fixture.start(source_image, "source")
        fixture.request("GET", "/health")
        fixture.request("GET", "/api/v1/info")
        fixture.request("GET", "/api/v1/metrics", status=401)
        fixture.request("GET", "/api/v1/metrics", token=fixture.credentials[0])
        active, revoked = fixture.issue("Active"), fixture.issue("Revoked")
        token = active["token"]
        fixture.request("DELETE", "/api/v1/admin/sync-tokens", token=fixture.credentials[0],
                        body={"accountId": "container-fixture", "tokenId": revoked["device"]["id"]})
        fixture.request("PUT", "/api/v1/sync/library", token=token, body=mutation(0, "before-replacement"))
        expected = fixture.request("GET", "/api/v1/sync/library", token=token)
        checks += ["source_health_and_readiness", "operations_authentication", "managed_tokens_and_snapshot_write"]
        fixture.stop(source)
        checks.append("source_graceful_shutdown")

        candidate = fixture.start(image, "candidate")
        require(fixture.inspect(candidate)["Config"]["User"] == "10001:999", "Volume identity changed")
        identities = [line.split()[1:3] for line in fixture.docker("top", candidate, "-eo", "pid,uid,gid").stdout.splitlines()[1:]]
        require(identities and all(identity == ["10001", "999"] for identity in identities),
                "Running container processes did not preserve UID/GID 10001:999")
        report["process_identities"] = identities
        fixture.docker("exec", candidate, "/usr/local/bin/aethertune-healthcheck")
        invalid_probe = fixture.docker("exec", "--env", "PORT=0", candidate,
                                       "/usr/local/bin/aethertune-healthcheck", check=False)
        require(invalid_probe.returncode == 1, "Compiled health probe accepted an invalid port")
        require(fixture.request("GET", "/api/v1/sync/library", token=token) == expected,
                "Replacement did not preserve the exact saved snapshot")
        fixture.request("GET", "/api/v1/sync/library", token=revoked["token"], status=401)
        fixture.request("PUT", "/api/v1/sync/library", token=token, body=mutation(1, "after-replacement"))
        fixture.request("PUT", "/api/v1/sync/library", token=token, status=409, body=mutation(1, "stale"))
        checks += ["numeric_identity_and_resource_hardening", "compiled_health_probe", "exact_snapshot_continuity",
                   "revocation_continuity", "post_replacement_write_and_conflict"]
        competitor = fixture.start(image, "competing", ready=False)
        fixture.expect_refusal(competitor, "Another AetherTune server instance")
        checks.append("second_instance_refused")
        fixture.stop(candidate)
        checks.append("candidate_graceful_shutdown")

        restarted = fixture.start(image, "recreated")
        state = fixture.request("GET", "/api/v1/sync/library", token=token)
        require(state["revision"] == 2 and state["snapshot"]["name"] == "after-replacement",
                "Recreating the container lost its successful post-replacement write")
        fixture.request("GET", "/api/v1/sync/library", token=revoked["token"], status=401)
        checks.append("recreated_container_persistence")
        fixture.stop(restarted)
        missing_ops = fixture.start(image, "missing-operations", ready=False, operations=False)
        fixture.expect_refusal(missing_ops, "AETHERTUNE_OPS_TOKEN is required", exit_code="255")
        checks.append("missing_operations_secret_refused")
        report["result"] = "passed"
    except (OSError, ValueError, KeyError, AssertionError, subprocess.SubprocessError, http.client.HTTPException) as error:
        report["error"] = str(error)
    finally:
        report["cleanup_errors"] = fixture.cleanup()
        if report["cleanup_errors"]:
            report["result"] = "failed"
        (evidence / "runtime.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2), flush=True)
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", required=True)
    parser.add_argument("--source-image", help="Optional previous image for volume upgrade acceptance")
    parser.add_argument("--evidence", type=Path, required=True)
    arguments = parser.parse_args()
    raise SystemExit(run(arguments.image, arguments.source_image or arguments.image, arguments.evidence))
