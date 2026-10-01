#!/usr/bin/env python3
"""Regression checks for the scheduled server operations probe."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPLOY = ROOT / "services" / "server" / "deploy"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-ci.yml"
RUNTIME_PROBE = ROOT / "scripts" / "ci" / "test_server_ops_probe_runtime.sh"



def observe_probe(
    token: str, *, token_variable: str = "AETHERTUNE_OPS_PROBE_TOKEN"
) -> tuple[subprocess.CompletedProcess[str], list[str], list[tuple[str, str | None]]]:
    """Run real curl through an argv observer against an owned HTTP fixture."""
    bash = shutil.which("bash")
    git_bash = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git/bin/bash.exe"
    if os.name == "nt" and git_bash.is_file():
        bash = str(git_bash)
    if bash is None or shutil.which("curl") is None:
        raise unittest.SkipTest("Bash and curl are required for the real HTTP probe fixture")

    expected_token = r'fixture-metrics-token+/=."\\suffix'
    requests: list[tuple[str, str | None]] = []
    responses = {
        "/health": {"service": "aethertune-server", "status": "ok"},
        "/ready": {"service": "aethertune-server", "status": "ready"},
        "/api/v1/metrics": {
            "service": "aethertune-server",
            "requestsTotal": 3,
            "requestsRateLimited": 0,
            "responses5xx": 0,
        },
    }

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            authorization = self.headers.get("Authorization")
            requests.append((self.path, authorization))
            status = 200
            payload = responses[self.path]
            if self.path == "/api/v1/metrics" and authorization != f"Bearer {expected_token}":
                status = 401
                payload = {"error": "Unauthorized"}
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, format: str, *args: object) -> None:
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="aethertune probe argv ") as directory:
            fixture = Path(directory).resolve()
            if fixture.parent != Path(tempfile.gettempdir()).resolve():
                raise RuntimeError("Probe fixture escaped the temporary directory")
            capture = fixture / "curl-argv"
            wrapper = fixture / "curl"
            wrapper.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "printf '%s\\0' \"$@\" >> \"$AETHERTUNE_PROBE_TEST_ARGV\"\n"
                "exec \"$AETHERTUNE_PROBE_TEST_REAL_CURL\" \"$@\"\n",
                encoding="utf-8",
                newline="\n",
            )
            wrapper.chmod(0o700)
            environment = os.environ.copy()
            for name in ("AETHERTUNE_OPS_PROBE_TOKEN", "AETHERTUNE_METRICS_TOKEN", "AETHERTUNE_OPS_TOKEN"):
                environment.pop(name, None)
            environment.update({
                token_variable: token,
                "AETHERTUNE_PROBE_TEST_DIR": fixture.as_posix(),
                "AETHERTUNE_PROBE_TEST_ARGV": capture.as_posix(),
                "AETHERTUNE_PROBE_TEST_PYTHON": Path(sys.executable).as_posix(),
                "AETHERTUNE_PROBE_TEST_SCRIPT": (DEPLOY / "aethertune-ops-probe.sh").as_posix(),
                "AETHERTUNE_PROBE_TEST_URL": f"http://127.0.0.1:{server.server_port}",
            })
            completed = subprocess.run(
                [bash, "--noprofile", "--norc", "-c", textwrap.dedent("""
                    set -euo pipefail
                    fixture_directory="$AETHERTUNE_PROBE_TEST_DIR"
                    if command -v cygpath >/dev/null 2>&1; then
                      fixture_directory="$(cygpath -u "$fixture_directory")"
                    fi
                    AETHERTUNE_PROBE_TEST_REAL_CURL="$(command -v curl)"
                    export AETHERTUNE_PROBE_TEST_REAL_CURL
                    export PATH="$fixture_directory:$PATH"
                    test "$(command -v curl)" = "$fixture_directory/curl"
                    python3() { "$AETHERTUNE_PROBE_TEST_PYTHON" "$@"; }
                    export -f python3
                    exec "$BASH" "$AETHERTUNE_PROBE_TEST_SCRIPT" "$AETHERTUNE_PROBE_TEST_URL"
                """)],
                env=environment, capture_output=True, text=True, check=False, timeout=20,
            )
            arguments = (
                capture.read_bytes().decode("utf-8").split("\0")[:-1]
                if capture.exists() else []
            )
            return completed, arguments, requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        if thread.is_alive():
            raise RuntimeError("Probe HTTP fixture did not stop")


class ServerOpsProbeContractTest(unittest.TestCase):

    def test_metrics_credentials_are_authenticated_without_argv_or_output_exposure(self) -> None:
        token = r'fixture-metrics-token+/=."\\suffix'
        for variable in ("AETHERTUNE_OPS_PROBE_TOKEN", "AETHERTUNE_METRICS_TOKEN"):
            with self.subTest(token_variable=variable):
                completed, arguments, requests = observe_probe(token, token_variable=variable)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                self.assertIn("AetherTune operational probe passed:", completed.stdout)
                self.assertEqual(requests, [
                    ("/health", None), ("/ready", None),
                    ("/api/v1/metrics", f"Bearer {token}"),
                ])
                self.assertNotIn(token, "\0".join(arguments))
                self.assertNotIn(token, completed.stdout + completed.stderr)

    def test_incorrect_metrics_credentials_fail_without_exposure(self) -> None:
        token = "fixture-rejected-metrics-token"
        completed, arguments, requests = observe_probe(token)
        self.assertNotEqual(completed.returncode, 0)
        self.assertNotIn("operational probe passed", completed.stdout)
        self.assertIn(("/api/v1/metrics", f"Bearer {token}"), requests)
        self.assertNotIn(token, "\0".join(arguments))
        self.assertNotIn(token, completed.stdout + completed.stderr)

    def test_empty_and_line_break_credentials_are_rejected_before_http(self) -> None:
        marker = "fixture-only-header-injection"
        for token in ("", marker + "\r", marker + "\n", marker + "\r\nX-Fixture: injected"):
            with self.subTest(token=token):
                completed, arguments, requests = observe_probe(token)
                self.assertEqual(completed.returncode, 2)
                self.assertEqual(arguments, [])
                self.assertEqual(requests, [])
                self.assertNotIn(marker, completed.stdout + completed.stderr)

    def test_probe_rejects_misrouted_success_responses(self) -> None:
        bash = shutil.which("bash")
        if os.name == "nt" or bash is None or shutil.which("curl") is None:
            self.skipTest("A POSIX Bash and curl runtime is unavailable on this host")

        responses = {
            "/health": {"service": "aethertune-server", "status": "ok"},
            "/ready": {"service": "aethertune-server", "status": "ready"},
            "/api/v1/metrics": {
                "service": "aethertune-server",
                "requestsTotal": 1,
                "requestsRateLimited": 0,
                "responses5xx": 0,
            },
        }

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                body = json.dumps(responses[self.path]).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            probe_path = DEPLOY / "aethertune-ops-probe.sh"
            environment = os.environ.copy()
            environment["AETHERTUNE_OPS_PROBE_TOKEN"] = "fixture-only-token"

            def probe() -> subprocess.CompletedProcess[str]:
                return subprocess.run(
                    [bash, str(probe_path), f"http://127.0.0.1:{server.server_port}"],
                    capture_output=True,
                    check=False,
                    env=environment,
                    text=True,
                    timeout=20,
                )

            self.assertEqual(probe().returncode, 0)
            for endpoint, payload in (
                ("/health", {"service": "another-service", "status": "ok"}),
                ("/health", {"service": "aethertune-server", "status": "stale"}),
                ("/ready", {"service": "aethertune-server", "status": "not_ready"}),
            ):
                with self.subTest(endpoint=endpoint, payload=payload):
                    original = responses[endpoint]
                    responses[endpoint] = payload
                    self.assertNotEqual(probe().returncode, 0)
                    responses[endpoint] = original
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_probe_is_authenticated_bounded_and_https_first(self) -> None:
        probe = (DEPLOY / "aethertune-ops-probe.sh").read_text(encoding="utf-8")

        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN", probe)
        self.assertIn("https://*|http://127.0.0.1:*|http://localhost:*", probe)
        self.assertIn(
            "BASE_URL must not contain credentials, query parameters, or fragments.",
            probe,
        )
        self.assertIn("--connect-timeout 5 --max-time 15", probe)
        self.assertNotIn('AETHERTUNE_OPS_TOKEN:-', probe)
        self.assertIn("requestsTotal", probe)
        self.assertIn("requestsRateLimited", probe)
        self.assertIn("responses5xx", probe)

    def test_probe_rejects_unsafe_urls_before_network_access(self) -> None:
        bash = shutil.which("bash")
        if os.name == "nt" or bash is None:
            self.skipTest("A POSIX Bash runtime is unavailable on this host")

        probe_path = DEPLOY / "aethertune-ops-probe.sh"
        environment = os.environ.copy()
        environment["AETHERTUNE_OPS_PROBE_TOKEN"] = "test-secret"

        for base_url in (
            "https://user:test-secret@example.test",
            "https://example.test/path?token=test-secret",
            "https://example.test/path#fragment",
        ):
            with self.subTest(base_url=base_url):
                result = subprocess.run(
                    [bash, str(probe_path), base_url],
                    capture_output=True,
                    check=False,
                    env=environment,
                    text=True,
                )

                self.assertEqual(result.returncode, 2)
                self.assertIn(
                    "BASE_URL must not contain credentials, query parameters, or fragments.",
                    result.stderr,
                )
                self.assertNotIn(
                    "test-secret",
                    result.stdout + result.stderr,
                )

    def test_systemd_probe_runs_as_a_bounded_local_timer(self) -> None:
        service = (DEPLOY / "aethertune-ops-probe.service").read_text(
            encoding="utf-8"
        )
        timer = (DEPLOY / "aethertune-ops-probe.timer").read_text(encoding="utf-8")

        self.assertIn("EnvironmentFile=/etc/aethertune/server.env", service)
        self.assertIn(
            "ExecStart=/usr/local/libexec/aethertune-ops-probe.sh http://127.0.0.1:8080",
            service,
        )
        self.assertIn("NoNewPrivileges=yes", service)
        self.assertIn("ProtectSystem=strict", service)
        self.assertIn("RestrictAddressFamilies=AF_INET AF_INET6", service)
        self.assertIn("OnBootSec=2min", timer)
        self.assertIn("OnUnitActiveSec=5min", timer)
        self.assertIn("RandomizedDelaySec=30s", timer)
        self.assertIn("Persistent=true", timer)

    def test_env_example_documents_probe_secret_boundary(self) -> None:
        env_example = (DEPLOY / "server.env.example").read_text(encoding="utf-8")
        deploy_readme = (DEPLOY / "README.md").read_text(encoding="utf-8")

        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN=", env_example)
        self.assertIn("raw metrics token", deploy_readme)
        self.assertIn("off-host alert", deploy_readme)

    def test_runtime_probe_is_exercised_against_the_compiled_server(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")
        runtime_probe = RUNTIME_PROBE.read_text(encoding="utf-8")

        self.assertTrue(RUNTIME_PROBE.is_file())
        self.assertIn("test_server_ops_probe_runtime.sh", workflow)
        self.assertIn("AETHERTUNE_OPS_TOKEN", runtime_probe)
        self.assertIn("AETHERTUNE_METRICS_TOKEN", runtime_probe)
        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN", runtime_probe)
        self.assertIn("/ready", runtime_probe)
        self.assertIn("aethertune-ops-probe.sh", runtime_probe)


if __name__ == "__main__":
    unittest.main()
