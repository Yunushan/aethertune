"""Regression checks for the protected production operations probe workflow."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "production-ops-probe.yml"


class ProductionOpsWorkflowTest(unittest.TestCase):
    def test_is_scheduled_and_manually_dispatchable(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("name: Production operations probe", workflow)
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("schedule:", workflow)
        self.assertIn("cron: '*/15 * * * *'", workflow)
        self.assertIn("environment: production", workflow)
        self.assertIn("timeout-minutes: 5", workflow)
        self.assertIn(
            "github.ref == format('refs/heads/{0}', github.event.repository.default_branch)",
            workflow,
        )
        self.assertIn(
            "ref: ${{ github.event.repository.default_branch }}",
            workflow,
        )

    def test_is_disabled_until_production_is_explicitly_enabled(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn(
            "vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true'",
            workflow,
        )
        self.assertIn("AETHERTUNE_PRODUCTION_BASE_URL", workflow)
        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN", workflow)

    def test_fails_closed_and_runs_the_hardened_probe(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("contents: read", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("AETHERTUNE_PRODUCTION_BASE_URL is required", workflow)
        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN is required", workflow)
        self.assertIn(
            "bash services/server/deploy/aethertune-ops-probe.sh",
            workflow,
        )

    def test_persists_non_secret_probe_evidence(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("mkdir -p build/production-ops-probe", workflow)
        self.assertIn("workflow_run_id=%s", workflow)
        self.assertIn("commit=%s", workflow)
        self.assertIn("base_url_host=%s", workflow)
        self.assertIn("result=configuration-invalid", workflow)
        self.assertIn("result=passed", workflow)
        self.assertIn("result=failed", workflow)
        self.assertIn("tee build/production-ops-probe/probe.log", workflow)
        self.assertIn("if: ${{ always() }}", workflow)
        self.assertIn(
            "actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
            workflow,
        )
        self.assertIn("retention-days: 30", workflow)
        self.assertIn("if-no-files-found: error", workflow)
        self.assertIn("path: build/production-ops-probe/", workflow)


if __name__ == "__main__":
    unittest.main()
