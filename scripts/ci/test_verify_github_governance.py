#!/usr/bin/env python3
"""Regression checks for the repository governance audit."""

from __future__ import annotations

import unittest

from verify_github_governance import (
    REQUIRED_STATUS_CHECKS,
    verify_governance_payloads,
)


CODEOWNERS = """* @Yunushan
/.github/workflows/ @Yunushan
/scripts/ci/ @Yunushan
/services/server/deploy/ @Yunushan
"""


def valid_branch_protection() -> dict[str, object]:
    return {
        "required_pull_request_reviews": {
            "required_approving_review_count": 1,
            "require_code_owner_reviews": True,
            "dismiss_stale_reviews": True,
        },
        "required_status_checks": {
            "strict": True,
            "contexts": list(REQUIRED_STATUS_CHECKS),
        },
        "enforce_admins": {"enabled": True},
        "allow_force_pushes": {"enabled": False},
        "allow_deletions": {"enabled": False},
    }


def valid_environment() -> dict[str, object]:
    return {
        "protection_rules": [{"type": "required_reviewers"}],
        "deployment_branch_policy": {
            "protected_branches": True,
            "custom_branch_policies": False,
        },
    }


class GithubGovernanceTest(unittest.TestCase):
    def test_accepts_protected_main_and_production_environment(self) -> None:
        verify_governance_payloads(
            valid_branch_protection(),
            valid_environment(),
            CODEOWNERS,
        )

    def test_rejects_missing_required_status_check(self) -> None:
        protection = valid_branch_protection()
        protection["required_status_checks"] = {
            "strict": True,
            "contexts": list(REQUIRED_STATUS_CHECKS[:-1]),
        }
        with self.assertRaisesRegex(ValueError, "missing required check"):
            verify_governance_payloads(protection, valid_environment(), CODEOWNERS)

    def test_rejects_unprotected_production_environment(self) -> None:
        environment = valid_environment()
        environment["protection_rules"] = []
        with self.assertRaisesRegex(ValueError, "independent reviewer"):
            verify_governance_payloads(
                valid_branch_protection(),
                environment,
                CODEOWNERS,
            )


if __name__ == "__main__":
    unittest.main()
