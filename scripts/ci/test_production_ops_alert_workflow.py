"""Regression checks for the off-host production probe alert workflow."""

from pathlib import Path
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "production-ops-alert.yml"
MARKER = "fixture-webhook-private-sentinel"
WEBHOOK = 'https://alerts.example.invalid/hook/' + MARKER + r'"\suffix?token=+/=&next=%22'
PROBE = {
    "PROBE_CONCLUSION": "failure",
    "PROBE_REPOSITORY": "fixture/ordinary-probe",
    "PROBE_RUN_ID": "123",
    "PROBE_RUN_URL": "https://example.invalid/probe/123",
    "PROBE_SHA": "a" * 40,
}


def workflow_fragment(name: str) -> str:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    step = re.search(
        r"^      - name: " + re.escape(name) + r"\n(?P<step>.*?)(?=^      - name:|\Z)",
        workflow,
        re.MULTILINE | re.DOTALL,
    )
    if step is None:
        raise AssertionError("Expected alert workflow step is missing")
    return textwrap.dedent(step["step"].split("        run: |\n", 1)[1])


def observe_alert(webhook: str = WEBHOOK, *, status: int = 200, curl_exit: int = 0):
    """Execute both exact shell fragments with a fake curl; no network is used."""
    bash = shutil.which("bash")
    git_bash = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git/bin/bash.exe"
    if os.name == "nt" and git_bash.is_file():
        bash = str(git_bash)
    if bash is None:
        raise unittest.SkipTest("Bash is required for the exact workflow-fragment fixture")
    with tempfile.TemporaryDirectory(prefix="aethertune alert argv ") as directory:
        fixture = Path(directory)
        script = fixture / "workflow.sh"
        script.write_text(
            workflow_fragment("Validate alert configuration")
            + "\n" + workflow_fragment("Send off-host alert"),
            encoding="utf-8", newline="\n",
        )
        fake = fixture / "fake-curl.py"
        fake.write_text(textwrap.dedent(r'''
            import json, os, re, sys
            from pathlib import Path
            root = Path(os.environ["ALERT_TEST_DIR"])
            arguments = (root / "argv").read_bytes().decode().split("\0")[:-1]
            configuration = (root / "stdin").read_text(encoding="utf-8")
            if "--config" in arguments:
                assert arguments[arguments.index("--config") + 1] == "-"
                lines = configuration.splitlines()
                assert len(lines) == 1, "Unexpected curl configuration directive"
                assert lines[0].startswith('url = ')
                quoted = lines[0][len('url = '):]
                # The producer may use only curl's quote/backslash escapes.
                assert re.fullmatch(r'"(?:[^"\\]|\\["\\])*"', quoted)
                url = json.loads(quoted)
            else:
                url = arguments[-1]
            payload = json.loads(arguments[arguments.index("--data") + 1])
            (root / "request.json").write_text(json.dumps({"url": url, "payload": payload}))
            # A receiver/transport diagnostic may repeat private URL data.
            print("Receiver diagnostic: " + url, file=sys.stderr)
            if "--output" not in arguments or arguments[arguments.index("--output") + 1] != "/dev/null":
                print("Receiver response: " + url)
            if "--write-out" in arguments:
                assert arguments[arguments.index("--write-out") + 1] == "%{http_code}"
                print(os.environ["ALERT_TEST_HTTP_STATUS"], end="")
            raise SystemExit(int(os.environ["ALERT_TEST_CURL_EXIT"]))
        '''), encoding="utf-8", newline="\n")
        wrapper = fixture / "curl"
        wrapper.write_text(textwrap.dedent(r'''#!/usr/bin/env bash
            set -euo pipefail
            printf '%s\0' "$@" > "$ALERT_TEST_DIR/argv"
            cat > "$ALERT_TEST_DIR/stdin"
            python3 "$ALERT_TEST_DIR/fake-curl.py"
        '''), encoding="utf-8", newline="\n")
        wrapper.chmod(0o700)
        environment = os.environ.copy()
        environment.update(PROBE, ALERT_WEBHOOK_URL=webhook,
                           ALERT_TEST_DIR=fixture.as_posix(),
                           ALERT_TEST_PYTHON=Path(sys.executable).as_posix(),
                           ALERT_TEST_HTTP_STATUS=str(status), ALERT_TEST_CURL_EXIT=str(curl_exit))
        completed = subprocess.run(
            [bash, "--noprofile", "--norc", "-c", textwrap.dedent('''
                set -euo pipefail
                fixture_directory="$ALERT_TEST_DIR"
                if command -v cygpath >/dev/null 2>&1; then
                  fixture_directory="$(cygpath -u "$fixture_directory")"
                fi
                export PATH="$fixture_directory:$PATH"
                test "$(command -v curl)" = "$fixture_directory/curl"
                python3() { "$ALERT_TEST_PYTHON" "$@"; }
                export -f python3
                exec "$BASH" "$fixture_directory/workflow.sh"
            ''')], env=environment, input="", capture_output=True, text=True,
            check=False, timeout=15,
        )
        arguments = ((fixture / "argv").read_bytes().decode().split("\0")[:-1]
                     if (fixture / "argv").exists() else [])
        request = (json.loads((fixture / "request.json").read_text())
                   if (fixture / "request.json").exists() else None)
        return completed, arguments, request


class ProductionOpsAlertWorkflowTest(unittest.TestCase):
    def test_listens_for_completed_probe_runs(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        for contract in ("name: Production operations alert", "workflow_run:",
                         "- Production operations probe", "- completed",
                         "conclusion != 'success'", "conclusion != 'skipped'",
                         "contents: read", "timeout-minutes: 2"):
            self.assertIn(contract, workflow)
        self.assertNotIn("actions/checkout", workflow)

    def test_requires_https_webhook_and_sends_non_secret_evidence(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")
        self.assertIn("AETHERTUNE_PRODUCTION_ALERT_WEBHOOK_URL", workflow)
        self.assertIn("must use HTTPS", workflow)
        self.assertIn("Content-Type: application/json", workflow)
        self.assertIn('conclusion=os.environ["PROBE_CONCLUSION"]', workflow)
        self.assertIn('repository=os.environ["PROBE_REPOSITORY"]', workflow)
        self.assertNotIn("--fail-with-body", workflow)

    def assert_private(self, completed, arguments) -> None:
        self.assertNotIn(MARKER, "\0".join(arguments))
        self.assertNotIn(MARKER, completed.stdout + completed.stderr)

    def test_exact_fragment_delivers_escaped_webhook_without_argv_or_log_exposure(self) -> None:
        completed, arguments, request = observe_alert()
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(request["url"], WEBHOOK)
        self.assertEqual(request["payload"], {
            "text": "AetherTune production operations probe failure: fixture/ordinary-probe run 123",
            "repository": PROBE["PROBE_REPOSITORY"], "run_id": PROBE["PROBE_RUN_ID"],
            "run_url": PROBE["PROBE_RUN_URL"], "commit": PROBE["PROBE_SHA"],
            "conclusion": PROBE["PROBE_CONCLUSION"],
        })
        self.assert_private(completed, arguments)
        self.assertEqual(arguments[0], "--disable")
        self.assertIn("--fail", arguments)
        self.assertEqual(arguments[arguments.index("--max-time") + 1], "15")
        self.assertEqual(arguments[arguments.index("--proto") + 1], "=https")
        self.assertNotIn("--location", arguments)
        self.assertNotIn("-L", arguments)
        completed, arguments, request = observe_alert(status=204)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(request["url"], WEBHOOK)
        self.assert_private(completed, arguments)

    def test_delivery_errors_fail_closed_without_receiver_or_transport_secrets(self) -> None:
        for exit_code, status in ((7, 0), (22, 503)):
            with self.subTest(exit_code=exit_code, status=status):
                completed, arguments, request = observe_alert(status=status, curl_exit=exit_code)
                self.assertEqual(completed.returncode, exit_code)
                self.assertEqual(request["url"], WEBHOOK)
                self.assert_private(completed, arguments)

    def test_redirects_and_unexpected_status_fail_without_following(self) -> None:
        for status in (0, 302, 307, 500):
            with self.subTest(status=status):
                completed, arguments, _ = observe_alert(status=status)
                self.assertNotEqual(completed.returncode, 0)
                self.assertNotIn("--location", arguments)
                self.assertNotIn("-L", arguments)
                self.assert_private(completed, arguments)

    def test_empty_non_https_or_injected_configuration_fails_before_curl(self) -> None:
        for url in ("", "http://example.invalid/" + MARKER, "https:///" + MARKER,
                    WEBHOOK + '\nurl = "https://other.invalid"', WEBHOOK + "\r",
                    WEBHOOK + "\t", WEBHOOK + " ", "https://[invalid]/" + MARKER,
                    "https://example.invalid:invalid/" + MARKER):
            with self.subTest(url=url):
                completed, arguments, request = observe_alert(url)
                self.assertNotEqual(completed.returncode, 0)
                self.assertEqual(arguments, [])
                self.assertIsNone(request)
                self.assert_private(completed, arguments)


if __name__ == "__main__":
    unittest.main()
