#!/usr/bin/env python3
"""Regression checks for the repository governance audit."""

from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

from verify_github_governance import (
    REQUIRED_ACTION_PATTERNS,
    REQUIRED_SECURITY_FEATURES,
    REQUIRED_STATUS_CHECKS,
    verify_github_governance,
    verify_governance_payloads,
)


CODEOWNERS = """* @Yunushan
/.github/workflows/ @Yunushan
/scripts/ci/ @Yunushan
/services/server/deploy/ @Yunushan
"""
ROOT = Path(__file__).resolve().parents[2]


def valid_branch_protection() -> dict[str, object]:
    return {
        "required_pull_request_reviews": {
            "required_approving_review_count": 1,
            "require_code_owner_reviews": True,
            "dismiss_stale_reviews": True,
            "require_last_push_approval": True,
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
        "can_admins_bypass": False,
        "protection_rules": [
            {
                "type": "required_reviewers",
                "prevent_self_review": True,
                "reviewers": [
                    {"type": "User", "reviewer": {"login": "release-approver"}}
                ],
            },
            {"type": "wait_timer", "wait_timer": 5},
        ],
        "deployment_branch_policy": {
            "protected_branches": True,
            "custom_branch_policies": False,
        },
    }


def valid_repository_payload() -> dict[str, object]:
    return {
        "security_and_analysis": {
            feature: {"status": "enabled"}
            for feature, _ in REQUIRED_SECURITY_FEATURES
        },
    }


def valid_actions_permissions() -> dict[str, object]:
    return {
        "enabled": True,
        "allowed_actions": "selected",
        "sha_pinning_required": True,
    }


def valid_selected_actions() -> dict[str, object]:
    return {
        "github_owned_allowed": True,
        "verified_allowed": False,
        "patterns_allowed": sorted(REQUIRED_ACTION_PATTERNS),
    }


class GithubGovernanceTest(unittest.TestCase):
    def test_accepts_protected_main_and_production_environment(self) -> None:
        verify_governance_payloads(
            valid_branch_protection(),
            valid_environment(),
            CODEOWNERS,
            valid_repository_payload(),
            valid_actions_permissions(),
            valid_selected_actions(),
        )

    def test_accepts_workflow_and_job_status_check_name(self) -> None:
        protection = valid_branch_protection()
        protection["required_status_checks"] = {
            "strict": True,
            "contexts": [
                f"{check} / osv-scan"
                if check == "New OSV vulnerabilities and license violations"
                else check
                for check in REQUIRED_STATUS_CHECKS
            ],
        }
        verify_governance_payloads(
            protection,
            valid_environment(),
            CODEOWNERS,
            valid_repository_payload(),
            valid_actions_permissions(),
            valid_selected_actions(),
        )

    def test_rejects_missing_required_status_check(self) -> None:
        protection = valid_branch_protection()
        protection["required_status_checks"] = {
            "strict": True,
            "contexts": list(REQUIRED_STATUS_CHECKS[:-1]),
        }
        with self.assertRaisesRegex(ValueError, "missing required check"):
            verify_governance_payloads(
                protection,
                valid_environment(),
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
            )

    def test_rejects_review_without_last_push_approval(self) -> None:
        protection = valid_branch_protection()
        protection["required_pull_request_reviews"] = {
            "required_approving_review_count": 1,
            "require_code_owner_reviews": True,
            "dismiss_stale_reviews": True,
            "require_last_push_approval": False,
        }
        with self.assertRaisesRegex(ValueError, "last push"):
            verify_governance_payloads(
                protection,
                valid_environment(),
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
            )

    def test_rejects_unprotected_production_environment(self) -> None:
        environment = valid_environment()
        environment["protection_rules"] = []
        with self.assertRaisesRegex(ValueError, "independent reviewer"):
            verify_governance_payloads(
                valid_branch_protection(),
                environment,
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
            )

    def test_rejects_environment_admin_bypass(self) -> None:
        environment = valid_environment()
        environment["can_admins_bypass"] = True
        with self.assertRaisesRegex(ValueError, "administrator bypass"):
            verify_governance_payloads(
                valid_branch_protection(),
                environment,
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
            )

    def test_rejects_environment_without_reviewer_details(self) -> None:
        environment = valid_environment()
        environment["protection_rules"] = [
            {"type": "required_reviewers", "prevent_self_review": False},
            {"type": "wait_timer", "wait_timer": 5},
        ]
        with self.assertRaisesRegex(ValueError, "cannot self-approve"):
            verify_governance_payloads(
                valid_branch_protection(),
                environment,
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
            )

    def test_rejects_repository_owner_as_the_only_production_reviewer(self) -> None:
        with self.assertRaisesRegex(ValueError, "limited to the repository owner"):
            verify_governance_payloads(
                valid_branch_protection(),
                {
                    **valid_environment(),
                    "protection_rules": [
                        {
                            "type": "required_reviewers",
                            "prevent_self_review": True,
                            "reviewers": [
                                {"type": "User", "reviewer": {"login": "Yunushan"}}
                            ],
                        },
                        {"type": "wait_timer", "wait_timer": 5},
                    ],
                },
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
                repository_owner="yunushan",
            )

    def test_network_audit_fetches_repository_owner_before_review_check(self) -> None:
        owner_environment = {
            **valid_environment(),
            "protection_rules": [
                {
                    "type": "required_reviewers",
                    "prevent_self_review": True,
                    "reviewers": [
                        {"type": "User", "reviewer": {"login": "Yunushan"}}
                    ],
                },
                {"type": "wait_timer", "wait_timer": 5},
            ],
        }
        with patch("verify_github_governance._get_json") as get_json:
            get_json.side_effect = [
                {
                    "owner": {"login": "Yunushan"},
                    **valid_repository_payload(),
                },
                valid_branch_protection(),
                owner_environment,
                valid_actions_permissions(),
                valid_selected_actions(),
            ]
            with self.assertRaisesRegex(ValueError, "limited to the repository owner"):
                verify_github_governance(
                    "Yunushan/aethertune",
                    "test-token",
                    "https://api.github.com",
                    ROOT / ".github" / "CODEOWNERS",
                )
            self.assertEqual(get_json.call_count, 5)

    def test_rejects_environment_without_wait_timer(self) -> None:
        environment = valid_environment()
        environment["protection_rules"] = [{"type": "required_reviewers"}]
        with self.assertRaisesRegex(ValueError, "five-minute wait timer"):
            verify_governance_payloads(
                valid_branch_protection(),
                environment,
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
            )

    def test_rejects_disabled_repository_security_feature(self) -> None:
        repository = valid_repository_payload()
        security = repository["security_and_analysis"]
        assert isinstance(security, dict)
        security["secret_scanning_push_protection"] = {"status": "disabled"}
        with self.assertRaisesRegex(ValueError, "push protection"):
            verify_governance_payloads(
                valid_branch_protection(),
                valid_environment(),
                CODEOWNERS,
                repository,
                valid_actions_permissions(),
                valid_selected_actions(),
            )

    def test_rejects_unpinned_or_unrestricted_actions(self) -> None:
        permissions = valid_actions_permissions()
        permissions["sha_pinning_required"] = False
        with self.assertRaisesRegex(ValueError, "full-length SHA pins"):
            verify_governance_payloads(
                valid_branch_protection(),
                valid_environment(),
                CODEOWNERS,
                valid_repository_payload(),
                permissions,
                valid_selected_actions(),
            )


if __name__ == "__main__":
    unittest.main()
