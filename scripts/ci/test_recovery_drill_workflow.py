"""Regression checks for the scheduled server recovery drill workflow."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "server-recovery-drill.yml"
CI_WORKFLOW = ROOT / ".github" / "workflows" / "aethertune-ci.yml"


class RecoveryDrillWorkflowTest(unittest.TestCase):
    def test_is_manual_and_scheduled(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("name: Server recovery drill", workflow)
        self.assertIn("workflow_dispatch:", workflow)
        self.assertIn("schedule:", workflow)
        self.assertIn("cron: '23 3 * * 0'", workflow)

    def test_is_read_only_and_bounded(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("permissions:\n  contents: read", workflow)
        self.assertIn("timeout-minutes: 15", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn(
            "SOURCE_COMMIT_SHA: ${{ github.event.pull_request.head.sha || github.sha }}",
            workflow,
        )
        self.assertIn(
            "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
            workflow,
        )

    def test_runs_both_recovery_contracts_and_uploads_evidence(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("bash scripts/ci/test_server_backup_restore.sh", workflow)
        self.assertIn("bash scripts/ci/test_server_rollback.sh", workflow)
        self.assertIn("backup_restore_status=${PIPESTATUS[0]}", workflow)
        self.assertIn("rollback_status=${PIPESTATUS[0]}", workflow)
        self.assertIn("result=passed", workflow)
        self.assertIn("result=failed", workflow)
        self.assertIn("workflow_commit=%s", workflow)
        self.assertIn("source_commit=%s", workflow)
        self.assertIn("if: ${{ always() }}", workflow)
        self.assertIn("retention-days: 90", workflow)
        self.assertIn("if-no-files-found: error", workflow)
        self.assertIn("path: build/server-recovery-drill/", workflow)

    def test_pull_request_ci_executes_the_same_evidence_drill(self) -> None:
        workflow = CI_WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("name: Run server recovery evidence drill", workflow)
        self.assertIn("name: Upload server recovery evidence", workflow)
        self.assertIn(
            "SOURCE_COMMIT_SHA: ${{ github.event.pull_request.head.sha || github.sha }}",
            workflow,
        )
        self.assertIn("retention-days: 30", workflow)
        self.assertIn("bash scripts/ci/test_server_backup_restore.sh", workflow)
        self.assertIn("bash scripts/ci/test_server_rollback.sh", workflow)
        self.assertIn("workflow_commit=%s", workflow)
        self.assertIn("source_commit=%s", workflow)
        self.assertIn("path: build/server-recovery-drill/", workflow)

    def test_runtime_recovery_failure_fails_both_workflows(self) -> None:
        for path in (WORKFLOW, CI_WORKFLOW):
            with self.subTest(path=path):
                workflow = path.read_text(encoding="utf-8")
                self.assertIn('python3 scripts/ci/test_server_backup.py', workflow)
                self.assertIn('python3 scripts/ci/server_recovery_runtime.py', workflow)
                self.assertIn('--executable services/server/build/aethertune-server', workflow)
                self.assertIn('runtime_status=${PIPESTATUS[0]}', workflow)
                self.assertIn('"$runtime_status" -ne 0', workflow)
                self.assertIn('"$backup_unit_status" -ne 0', workflow)
                self.assertIn('dart compile exe bin/server.dart', workflow)
                self.assertIn('dart pub get --enforce-lockfile', workflow)

    def test_privilege_and_systemd_failures_fail_both_workflows(self) -> None:
        for path in (WORKFLOW, CI_WORKFLOW):
            with self.subTest(path=path):
                workflow = path.read_text(encoding='utf-8')
                self.assertIn('sudo -n python3 scripts/ci/test_server_backup_privileges.py', workflow)
                self.assertIn('python3 scripts/ci/server_systemd_runtime.py', workflow)
                for status in ('backup_privileges_status', 'systemd_status'):
                    self.assertIn(f'{status}=${{PIPESTATUS[0]}}', workflow)
                    self.assertIn(f'"${status}" -ne 0', workflow)
                    self.assertIn(f"printf '{status}=%s", workflow)


if __name__ == "__main__":
    unittest.main()
