"""Regression checks for the bounded server load smoke test."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts" / "ci" / "test_server_load.sh"
LOAD_TEST = ROOT / "scripts" / "ci" / "test_server_load.py"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-ci.yml"


class ServerLoadContractTest(unittest.TestCase):
    def test_load_runner_starts_a_loopback_server_and_writes_evidence(self) -> None:
        script = SCRIPT.read_text(encoding="utf-8")

        self.assertIn("AETHERTUNE_LISTEN_ADDRESS=127.0.0.1", script)
        self.assertIn("test_server_load.py", script)
        self.assertIn("load-evidence.json", script)
        self.assertIn("kill \"$server_pid\"", script)

    def test_load_test_is_bounded_and_rejects_non_success_responses(self) -> None:
        load_test = LOAD_TEST.read_text(encoding="utf-8")

        self.assertIn("ThreadPoolExecutor", load_test)
        self.assertIn("MAX_WORKERS = 8", load_test)
        self.assertIn("REQUESTS_PER_ROUTE = 20", load_test)
        self.assertIn("MAX_REQUEST_SECONDS = 2.0", load_test)
        self.assertIn('"/health", "/ready", "/api/v1/info", "/api/v1/tracks"', load_test)
        self.assertIn('"result": "passed" if not failures else "failed"', load_test)
        self.assertIn("return 0 if not failures else 1", load_test)

    def test_ci_runs_and_uploads_the_load_evidence(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("name: Run bounded server load smoke test", workflow)
        self.assertIn("bash scripts/ci/test_server_load.sh", workflow)
        self.assertIn("name: Upload server load evidence", workflow)
        self.assertIn("aethertune-server-load-${{ github.run_id }}", workflow)
        self.assertIn("retention-days: 30", workflow)
        self.assertIn("path: build/server-load/", workflow)


if __name__ == "__main__":
    unittest.main()
