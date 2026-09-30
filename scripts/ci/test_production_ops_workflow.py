"""Regression checks for the unattended production operations probe workflow."""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import textwrap
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
        self.assertIn("group: production-ops-probe-${{ github.event_name }}", workflow)
        self.assertIn("environment: production-monitoring", workflow)
        self.assertNotIn("environment: production\n", workflow)
        self.assertIn("timeout-minutes: 5", workflow)
        self.assertIn(
            "github.ref == format('refs/heads/{0}', github.event.repository.default_branch)",
            workflow,
        )
        self.assertIn(
            "ref: ${{ github.sha }}",
            workflow,
        )

    def test_manual_probe_is_allowed_before_scheduled_probes_are_enabled(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn(
            "github.ref == format('refs/heads/{0}', github.event.repository.default_branch) &&\n"
            "      (github.event_name == 'workflow_dispatch' ||\n"
            "      vars.AETHERTUNE_PRODUCTION_RELEASES_ENABLED == 'true')",
            workflow,
        )
        self.assertIn("AETHERTUNE_PRODUCTION_BASE_URL", workflow)
        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN", workflow)

    def test_manual_alert_drill_requires_a_successful_probe_first(self) -> None:
        workflow = WORKFLOW.read_text(encoding="utf-8")

        self.assertIn("alert_drill:\n", workflow)
        self.assertIn("type: boolean", workflow)
        self.assertIn("default: false", workflow)
        self.assertIn(
            "if: ${{ github.event_name == 'workflow_dispatch' && inputs.alert_drill }}",
            workflow,
        )
        self.assertLess(
            workflow.index("- name: Run production operations probe"),
            workflow.index("- name: Exercise off-host alert drill"),
        )
        self.assertLess(
            workflow.index("- name: Exercise off-host alert drill"),
            workflow.index("- name: Upload production probe evidence"),
        )
        self.assertIn("result=alert-drill", workflow)
        self.assertIn("Intentional alert drill after a successful", workflow)
        self.assertIn("exit 1", workflow)

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


    def test_probe_evidence_tracks_event_commit_when_default_branch_advances(self) -> None:
        """A queued schedule/manual run must execute the source it records."""
        workflow = WORKFLOW.read_text(encoding="utf-8")
        checkout = re.search(
            r"^      - name: Checkout\n(?P<step>.*?)(?=^      - name:|\Z)",
            workflow,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(checkout)
        ref = re.search(
            r"^\s+ref: \$\{\{\s*(?P<expression>.*?)\s*\}\}$",
            checkout["step"],
            re.MULTILINE,
        )
        self.assertIsNotNone(ref)
        initialization = re.search(
            r"^      - name: Initialize production probe evidence\n"
            r"(?P<step>.*?)(?=^      - name:|\Z)",
            workflow,
            re.MULTILINE | re.DOTALL,
        )
        self.assertIsNotNone(initialization)
        script = textwrap.dedent(
            initialization["step"].split("        run: |\n", 1)[1],
        )
        git = shutil.which("git")
        bash = shutil.which("bash")
        if os.name == "nt":
            git_bash = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "Git/bin/bash.exe"
            if git_bash.is_file():
                bash = str(git_bash)
        if git is None or bash is None:
            self.skipTest("Git and Bash are required for the source-identity fixture")

        for event in ("schedule", "workflow_dispatch"):
            with self.subTest(event=event), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                environment = os.environ.copy()
                environment.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)

                def command(*arguments: str) -> str:
                    return subprocess.run(
                        [git, *arguments],
                        cwd=root,
                        env=environment,
                        check=True,
                        capture_output=True,
                        text=True,
                        timeout=10,
                    ).stdout.strip()

                command("init", "--initial-branch=main")
                policy = root / "policy.txt"
                policy.write_text("captured event policy", encoding="utf-8")
                command("add", "policy.txt")
                command(
                    "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                    "-c", "commit.gpgsign=false", "commit", "-m", "Event revision",
                )
                event_sha = command("rev-parse", "HEAD")
                policy.write_text("later default-branch policy", encoding="utf-8")
                command("add", "policy.txt")
                command(
                    "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                    "-c", "commit.gpgsign=false", "commit", "-m", "Main advanced",
                )
                self.assertNotEqual(command("rev-parse", "main"), event_sha)
                reference_values = {
                    "github.sha": event_sha,
                    "github.event.repository.default_branch": "main",
                }
                self.assertIn(ref["expression"], reference_values)
                command("checkout", "--detach", reference_values[ref["expression"]])
                environment.update(
                    GITHUB_SHA=event_sha,
                    GITHUB_RUN_ID="1",
                    GITHUB_EVENT_NAME=event,
                    GITHUB_REF="refs/heads/main",
                )
                subprocess.run(
                    [bash, "-c", script],
                    cwd=root,
                    env=environment,
                    check=True,
                    capture_output=True,
                    text=True,
                    timeout=10,
                )
                metadata = dict(
                    line.split("=", 1)
                    for line in (root / "build/production-ops-probe/metadata.txt")
                    .read_text(encoding="utf-8").splitlines()
                )
                self.assertEqual(metadata["commit"], event_sha)
                self.assertEqual(
                    command("rev-parse", "HEAD"),
                    metadata["commit"],
                    "Probe metadata must identify the executed source, even after main advances",
                )
                self.assertEqual(policy.read_text(encoding="utf-8"), "captured event policy")

if __name__ == "__main__":
    unittest.main()
