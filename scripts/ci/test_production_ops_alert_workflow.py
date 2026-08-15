"""Regression checks for the off-host production probe alert workflow."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "production-ops-alert.yml"


class ProductionOpsAlertWorkflowTest(unittest.TestCase):
    def test_listens_for_completed_probe_runs(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("name: Production operations alert", workflow)
        self.assertIn("workflow_run:", workflow)
        self.assertIn("- Production operations probe", workflow)
        self.assertIn("- completed", workflow)
        self.assertIn("conclusion != 'success'", workflow)
        self.assertIn("conclusion != 'skipped'", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("timeout-minutes: 2", workflow)

    def test_requires_https_webhook_and_sends_non_secret_evidence(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn(
            "AETHERTUNE_PRODUCTION_ALERT_WEBHOOK_URL",
            workflow,
        )
        self.assertIn("must use HTTPS", workflow)
        self.assertIn("PROBE_REPOSITORY", workflow)
        self.assertIn("PROBE_RUN_ID", workflow)
        self.assertIn("PROBE_RUN_URL", workflow)
        self.assertIn("PROBE_SHA", workflow)
        self.assertIn("curl --fail-with-body", workflow)
        self.assertIn("Content-Type: application/json", workflow)
        self.assertNotIn("actions/checkout", workflow)


if __name__ == "__main__":
    unittest.main()
