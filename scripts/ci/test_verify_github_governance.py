#!/usr/bin/env python3
"""Regression checks for the repository governance audit."""

from __future__ import annotations

import unittest
from pathlib import Path
from typing import Any
from unittest.mock import patch

from verify_github_governance import (
    REQUIRED_ACTION_PATTERNS,
    REQUIRED_SECURITY_FEATURES,
    REQUIRED_STATUS_CHECKS,
    verify_github_governance,
    verify_governance_payloads as _verify_governance_payloads,
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
            "protected_branches": False,
            "custom_branch_policies": True,
        },
    }


def valid_production_policies() -> dict[str, object]:
    return {
        "total_count": 2,
        "branch_policies": [
            {"type": "branch", "name": "main"},
            {"type": "tag", "name": "v*"},
        ],
    }


def valid_monitoring_environment() -> dict[str, object]:
    return {
        "can_admins_bypass": False,
        "protection_rules": [{"type": "branch_policy"}],
        "deployment_branch_policy": {
            "protected_branches": False,
            "custom_branch_policies": True,
        },
    }


def valid_monitoring_policies() -> dict[str, object]:
    return {
        "total_count": 1,
        "branch_policies": [{"type": "branch", "name": "main"}],
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


def verify_governance_payloads(*args: Any, **kwargs: Any) -> None:
    """Exercise the audit with valid deployment policy fixtures by default."""
    kwargs.setdefault("production_branch_policies", valid_production_policies())
    kwargs.setdefault("monitoring_environment", valid_monitoring_environment())
    kwargs.setdefault("monitoring_branch_policies", valid_monitoring_policies())
    _verify_governance_payloads(*args, **kwargs)


def valid_payloads() -> tuple[Any, ...]:
    return (
        valid_branch_protection(),
        valid_environment(),
        CODEOWNERS,
        valid_repository_payload(),
        valid_actions_permissions(),
        valid_selected_actions(),
    )


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

    def test_rejects_protected_branches_only_for_tag_release(self) -> None:
        environment = valid_environment()
        environment["deployment_branch_policy"] = {
            "protected_branches": True,
            "custom_branch_policies": False,
        }
        payloads = list(valid_payloads())
        payloads[1] = environment
        with self.assertRaisesRegex(ValueError, "selected branch and tag policies"):
            verify_governance_payloads(*payloads)

    def test_rejects_missing_or_wrongly_typed_release_ref(self) -> None:
        for policies in (
            {
                "total_count": 1,
                "branch_policies": [{"type": "branch", "name": "main"}],
            },
            {
                "total_count": 2,
                "branch_policies": [
                    {"type": "branch", "name": "main"},
                    {"type": "branch", "name": "v*"},
                ],
            },
            {
                "total_count": 2,
                "branch_policies": [
                    {"name": "main"},
                    {"type": "tag", "name": "v*"},
                ],
            },
            {
                "total_count": 3,
                "branch_policies": valid_production_policies()["branch_policies"],
            },
            {
                "total_count": 3,
                "branch_policies": [
                    {"type": "branch", "name": "main"},
                    {"type": "tag", "name": "v*"},
                    {"type": "branch", "name": "*"},
                ],
            },
        ):
            with self.subTest(policies=policies):
                with self.assertRaisesRegex(ValueError, "main branch and v\\* tag rule"):
                    verify_governance_payloads(
                        *valid_payloads(), production_branch_policies=policies
                    )

    def test_rejects_missing_environment_policy_data(self) -> None:
        with self.assertRaisesRegex(ValueError, "main branch and v\\* tag rule"):
            _verify_governance_payloads(*valid_payloads())

    def test_rejects_monitoring_review_or_wait_gate(self) -> None:
        for gate in ("required_reviewers", "wait_timer", "custom"):
            environment = valid_monitoring_environment()
            environment["protection_rules"] = [{"type": gate}]
            with self.subTest(gate=gate):
                with self.assertRaisesRegex(ValueError, "no reviewer, wait, or app gate"):
                    verify_governance_payloads(
                        *valid_payloads(), monitoring_environment=environment
                    )

    def test_rejects_monitoring_tag_or_unrestricted_policy(self) -> None:
        for policies in (
            {
                "total_count": 1,
                "branch_policies": [{"type": "tag", "name": "main"}],
            },
            {
                "total_count": 1,
                "branch_policies": [{"type": "branch", "name": "*"}],
            },
            {"total_count": 0, "branch_policies": []},
        ):
            with self.subTest(policies=policies):
                with self.assertRaisesRegex(ValueError, "exactly a main branch rule"):
                    verify_governance_payloads(
                        *valid_payloads(), monitoring_branch_policies=policies
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

    def test_accepts_sole_owner_policy(self) -> None:
        protection = valid_branch_protection()
        protection.pop("required_pull_request_reviews")
        environment = {
            **valid_environment(),
            "protection_rules": [
                {
                    "type": "required_reviewers",
                    "prevent_self_review": False,
                    "reviewers": [
                        {"type": "User", "reviewer": {"login": "Yunushan"}}
                    ],
                },
                {"type": "wait_timer", "wait_timer": 5},
            ],
        }
        verify_governance_payloads(
            protection,
            environment,
            CODEOWNERS,
            valid_repository_payload(),
            valid_actions_permissions(),
            valid_selected_actions(),
            repository_owner="Yunushan",
            direct_collaborators=[{"login": "Yunushan"}],
        )

    def test_rejects_owner_policy_when_another_collaborator_exists(self) -> None:
        protection = valid_branch_protection()
        protection.pop("required_pull_request_reviews")
        with self.assertRaisesRegex(ValueError, "main requires pull-request reviews"):
            verify_governance_payloads(
                protection,
                valid_environment(),
                CODEOWNERS,
                valid_repository_payload(),
                valid_actions_permissions(),
                valid_selected_actions(),
                repository_owner="Yunushan",
                direct_collaborators=[
                    {"login": "Yunushan"},
                    {"login": "another-collaborator"},
                ],
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
        with (
            patch("verify_github_governance._get_json") as get_json,
            patch("verify_github_governance._get_list") as get_list,
        ):
            get_json.side_effect = [
                {
                    "owner": {"login": "Yunushan"},
                    **valid_repository_payload(),
                },
                valid_branch_protection(),
                owner_environment,
                valid_production_policies(),
                valid_monitoring_environment(),
                valid_monitoring_policies(),
                valid_actions_permissions(),
                valid_selected_actions(),
            ]
            get_list.return_value = [{"login": "Yunushan"}]
            with self.assertRaisesRegex(ValueError, "allow owner approval"):
                verify_github_governance(
                    "Yunushan/aethertune",
                    "test-token",
                    "https://api.github.com",
                    ROOT / ".github" / "CODEOWNERS",
                )
            self.assertEqual(get_json.call_count, 8)
            get_list.assert_called_once()

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
