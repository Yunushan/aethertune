#!/usr/bin/env python3
"""Fail closed when the repository's production governance is not protected."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
REQUIRED_STATUS_CHECKS = (
    "Dependency provenance",
    "Flutter analyze and test",
    "Desktop build (linux)",
    "Desktop build (windows)",
    "Desktop build (macos)",
    "Server analyze and test",
    "Dependency review",
    "New OSV vulnerabilities and license violations",
)
REQUIRED_SECURITY_FEATURES = (
    ("dependabot_security_updates", "Dependabot security updates"),
    ("secret_scanning", "secret scanning"),
    ("secret_scanning_push_protection", "secret scanning push protection"),
    ("secret_scanning_non_provider_patterns", "non-provider secret scanning"),
    ("secret_scanning_validity_checks", "secret-scanning validity checks"),
)
REQUIRED_ACTION_PATTERNS = frozenset(
    {
        "aquasecurity/trivy-action@*",
        "dart-lang/setup-dart@*",
        "google/osv-scanner-action/osv-reporter-action@*",
        "google/osv-scanner-action/osv-scanner-action@*",
    }
)
CODEOWNER_PATHS = (
    "/.github/workflows/",
    "/scripts/ci/",
    "/services/server/deploy/",
)


def _enabled(value: Any) -> bool:
    return isinstance(value, dict) and value.get("enabled") is True


def _status_check_matches(contexts: set[str], required: str) -> bool:
    return required in contexts or any(
        context.startswith(f"{required} / ") or context.endswith(f" / {required}")
        for context in contexts
    )


def _codeowners_cover_sensitive_paths(codeowners: str) -> bool:
    covered: set[str] = set()
    for raw_line in codeowners.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) >= 2 and fields[1].startswith("@"):
            covered.add(fields[0])
    return set(CODEOWNER_PATHS).issubset(covered)


def verify_governance_payloads(
    branch_protection: dict[str, Any],
    environment: dict[str, Any],
    codeowners: str,
    repository_payload: dict[str, Any],
    actions_permissions: dict[str, Any],
    selected_actions: dict[str, Any],
    repository_owner: str | None = None,
) -> None:
    """Validate API responses and checked-in ownership policy without network I/O."""
    failures: list[str] = []
    security = repository_payload.get("security_and_analysis")
    if not isinstance(security, dict):
        failures.append("repository security and analysis settings are unavailable")
    else:
        for feature, label in REQUIRED_SECURITY_FEATURES:
            status = security.get(feature)
            if not isinstance(status, dict) or status.get("status") != "enabled":
                failures.append(f"repository requires {label}")

    if actions_permissions.get("enabled") is not True:
        failures.append("repository GitHub Actions are enabled")
    if actions_permissions.get("allowed_actions") != "selected":
        failures.append("repository GitHub Actions use a selected allowlist")
    if actions_permissions.get("sha_pinning_required") is not True:
        failures.append("repository GitHub Actions require full-length SHA pins")
    if selected_actions.get("github_owned_allowed") is not True:
        failures.append("repository GitHub Actions allow GitHub-owned actions")
    if selected_actions.get("verified_allowed") is not False:
        failures.append("repository GitHub Actions do not allow arbitrary verified actions")
    patterns = selected_actions.get("patterns_allowed")
    if not isinstance(patterns, list) or set(patterns) != REQUIRED_ACTION_PATTERNS:
        failures.append("repository GitHub Actions allowlist does not match pinned external actions")

    reviews = branch_protection.get("required_pull_request_reviews")
    if not isinstance(reviews, dict):
        failures.append("main requires pull-request reviews")
    else:
        if int(reviews.get("required_approving_review_count", 0)) < 1:
            failures.append("main requires at least one approving review")
        if reviews.get("require_code_owner_reviews") is not True:
            failures.append("main requires code-owner review")
        if reviews.get("dismiss_stale_reviews") is not True:
            failures.append("main dismisses stale reviews")
        if reviews.get("require_last_push_approval") is not True:
            failures.append("main requires approval after the last push")

    checks = branch_protection.get("required_status_checks")
    contexts = (
        set(checks.get("contexts", []))
        if isinstance(checks, dict) and isinstance(checks.get("contexts"), list)
        else set()
    )
    if not isinstance(checks, dict) or checks.get("strict") is not True:
        failures.append("main requires an up-to-date branch before merge")
    for required in REQUIRED_STATUS_CHECKS:
        if not _status_check_matches(contexts, required):
            failures.append(f"main is missing required check: {required}")

    if not _enabled(branch_protection.get("enforce_admins")):
        failures.append("main protection applies to administrators")
    if _enabled(branch_protection.get("allow_force_pushes")):
        failures.append("main allows force pushes")
    if _enabled(branch_protection.get("allow_deletions")):
        failures.append("main allows deletion")
    if not _codeowners_cover_sensitive_paths(codeowners):
        failures.append("CODEOWNERS does not cover all security-sensitive paths")

    rules = environment.get("protection_rules")
    reviewer_rule = next(
        (
            rule
            for rule in rules or []
            if isinstance(rule, dict) and rule.get("type") == "required_reviewers"
        ),
        None,
    )
    reviewers = reviewer_rule.get("reviewers") if isinstance(reviewer_rule, dict) else None
    if (
        not isinstance(reviewers, list)
        or not reviewers
        or reviewer_rule.get("prevent_self_review") is not True
    ):
        failures.append(
            "production environment requires an independent reviewer who cannot self-approve"
        )
    elif repository_owner and not _has_independent_reviewer(
        reviewers,
        repository_owner,
    ):
        failures.append(
            "production environment reviewers are limited to the repository owner"
        )
    if environment.get("can_admins_bypass") is not False:
        failures.append("production environment prevents administrator bypass")
    if not any(
        isinstance(rule, dict)
        and rule.get("type") == "wait_timer"
        and isinstance(rule.get("wait_timer"), int)
        and rule["wait_timer"] >= 5
        for rule in rules or []
    ):
        failures.append("production environment requires a five-minute wait timer")
    branch_policy = environment.get("deployment_branch_policy")
    if not isinstance(branch_policy, dict) or not (
        branch_policy.get("protected_branches") is True
        or branch_policy.get("custom_branch_policies") is True
    ):
        failures.append("production deployments are not restricted to approved refs")

    if failures:
        raise ValueError("; ".join(failures))


def _has_independent_reviewer(
    reviewers: list[Any],
    repository_owner: str,
) -> bool:
    """Require at least one reviewer that is not the repository owner."""
    normalized_owner = repository_owner.casefold()
    for entry in reviewers:
        if not isinstance(entry, dict):
            continue
        reviewer_type = entry.get("type")
        reviewer = entry.get("reviewer")
        if reviewer_type == "Team" and isinstance(reviewer, dict):
            return True
        if not isinstance(reviewer, dict):
            continue
        login = reviewer.get("login")
        if isinstance(login, str) and login.casefold() != normalized_owner:
            return True
    return False


def _get_json(url: str, token: str) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "aethertune-governance-audit",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"GitHub governance API returned HTTP {error.code}: {error.reason}") from error
    if not isinstance(payload, dict):
        raise RuntimeError(f"GitHub governance API returned a non-object for {url}")
    return payload


def verify_github_governance(
    repository: str,
    token: str,
    api_url: str,
    codeowners_path: Path,
    branch: str = "main",
) -> None:
    if not codeowners_path.is_file():
        raise ValueError(f"CODEOWNERS file does not exist: {codeowners_path}")
    base = api_url.rstrip("/") + "/repos/" + repository
    branch_path = urllib.parse.quote(branch, safe="")
    repository_payload = _get_json(base, token)
    owner_payload = repository_payload.get("owner")
    repository_owner = (
        owner_payload.get("login")
        if isinstance(owner_payload, dict)
        else None
    )
    if not isinstance(repository_owner, str) or not repository_owner.strip():
        raise RuntimeError("GitHub repository metadata did not include an owner login")
    protection = _get_json(f"{base}/branches/{branch_path}/protection", token)
    environment = _get_json(f"{base}/environments/production", token)
    actions_permissions = _get_json(f"{base}/actions/permissions", token)
    selected_actions = _get_json(f"{base}/actions/permissions/selected-actions", token)
    verify_governance_payloads(
        protection,
        environment,
        codeowners_path.read_text(encoding="utf-8"),
        repository_payload,
        actions_permissions,
        selected_actions,
        repository_owner=repository_owner,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY"))
    parser.add_argument("--token", default=os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN"))
    parser.add_argument("--api-url", default=os.environ.get("GITHUB_API_URL", "https://api.github.com"))
    parser.add_argument("--branch", default="main")
    parser.add_argument(
        "--codeowners",
        type=Path,
        default=ROOT / ".github" / "CODEOWNERS",
    )
    arguments = parser.parse_args()
    if not arguments.repository:
        parser.error("--repository or GITHUB_REPOSITORY is required")
    if not arguments.token:
        parser.error("--token, GITHUB_TOKEN, or GH_TOKEN is required")
    try:
        verify_github_governance(
            arguments.repository,
            arguments.token,
            arguments.api_url,
            arguments.codeowners.resolve(),
            arguments.branch,
        )
    except (OSError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from error
    print("GitHub branch and production-environment governance passed.")


if __name__ == "__main__":
    main()
