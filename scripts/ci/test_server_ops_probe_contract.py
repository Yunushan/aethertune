#!/usr/bin/env python3
"""Regression checks for the scheduled server operations probe."""

from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEPLOY = ROOT / "services" / "server" / "deploy"


class ServerOpsProbeContractTest(unittest.TestCase):
    def test_probe_is_authenticated_bounded_and_https_first(self) -> None:
        probe = (DEPLOY / "aethertune-ops-probe.sh").read_text(encoding="utf-8")

        self.assertIn("AETHERTUNE_OPS_PROBE_TOKEN", probe)
        self.assertIn("https://*|http://127.0.0.1:*|http://localhost:*", probe)
        self.assertIn("--connect-timeout 5 --max-time 15", probe)
        self.assertIn('Authorization: Bearer $ops_token', probe)
        self.assertIn("requestsTotal", probe)
        self.assertIn("requestsRateLimited", probe)
        self.assertIn("responses5xx", probe)

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
        self.assertIn("raw operations token", deploy_readme)
        self.assertIn("off-host alert", deploy_readme)


if __name__ == "__main__":
    unittest.main()
