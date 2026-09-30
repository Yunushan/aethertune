#!/usr/bin/env python3
"""Regression checks for the production tag provenance gate."""

from __future__ import annotations

import unittest
from unittest.mock import call, patch

from verify_github_tag import (
    verify_github_tag,
    verify_main_ancestry_payload,
    verify_tag_payloads,
)


def valid_ref() -> dict[str, object]:
    return {"object": {"type": "tag", "sha": "tag-object-sha"}}


def valid_tag() -> dict[str, object]:
    return {
        "tag": "v0.1.0",
        "object": {"type": "commit", "sha": "commit-sha"},
        "verification": {"verified": True, "reason": "valid"},
    }


class VerifyGithubTagTest(unittest.TestCase):
    def test_accepts_verified_annotated_tag_pointing_to_workflow_commit(self) -> None:
        verify_tag_payloads(
            valid_ref(),
            valid_tag(),
            expected_tag="v0.1.0",
            expected_sha="commit-sha",
        )

    def test_rejects_lightweight_tag(self) -> None:
        with self.assertRaisesRegex(ValueError, "annotated Git tag"):
            verify_tag_payloads(
                {"object": {"type": "commit", "sha": "commit-sha"}},
                None,
                expected_tag="v0.1.0",
                expected_sha="commit-sha",
            )

    def test_rejects_unverified_tag(self) -> None:
        tag = valid_tag()
        tag["verification"] = {"verified": False, "reason": "unknown_key"}
        with self.assertRaisesRegex(ValueError, "not verified"):
            verify_tag_payloads(
                valid_ref(),
                tag,
                expected_tag="v0.1.0",
                expected_sha="commit-sha",
            )

    def test_rejects_tag_pointing_to_another_commit(self) -> None:
        tag = valid_tag()
        tag["object"] = {"type": "commit", "sha": "another-commit"}
        with self.assertRaisesRegex(ValueError, "workflow commit"):
            verify_tag_payloads(
                valid_ref(),
                tag,
                expected_tag="v0.1.0",
                expected_sha="commit-sha",
            )


def valid_comparison() -> dict[str, object]:
    return {
        "status": "ahead",
        "base_commit": {"sha": "commit-sha"},
        "merge_base_commit": {"sha": "commit-sha"},
    }


class ProductionTagPreflightTest(unittest.TestCase):
    def verify(self) -> None:
        verify_github_tag(
            "owner/repository",
            "v0.1.0",
            "commit-sha",
            "fixture-read-token",
            "https://api.github.com",
            require_main=True,
        )

    def test_accepts_an_ancestor_of_main_and_queries_the_exact_commit(self) -> None:
        with patch(
            "verify_github_tag._get_json",
            side_effect=[valid_ref(), valid_tag(), valid_comparison()],
        ) as get_json:
            self.verify()
        self.assertEqual(
            get_json.call_args_list,
            [
                call(
                    "https://api.github.com/repos/owner/repository/git/ref/tags/v0.1.0",
                    "fixture-read-token",
                ),
                call(
                    "https://api.github.com/repos/owner/repository/git/tags/tag-object-sha",
                    "fixture-read-token",
                ),
                call(
                    "https://api.github.com/repos/owner/repository/compare/commit-sha...main",
                    "fixture-read-token",
                ),
            ],
        )

    def test_accepts_a_tag_at_the_current_main_commit(self) -> None:
        comparison = valid_comparison()
        comparison["status"] = "identical"
        with patch(
            "verify_github_tag._get_json",
            side_effect=[valid_ref(), valid_tag(), comparison],
        ):
            self.verify()

    def test_rejects_off_main_tags_even_when_the_tag_signature_is_verified(self) -> None:
        for status in ("behind", "diverged"):
            with self.subTest(status=status):
                comparison = valid_comparison()
                comparison["status"] = status
                comparison["merge_base_commit"] = {"sha": "main-ancestor"}
                with patch(
                    "verify_github_tag._get_json",
                    side_effect=[valid_ref(), valid_tag(), comparison],
                ):
                    with self.assertRaisesRegex(ValueError, "based on main"):
                        self.verify()

    def test_rejects_comparison_not_bound_to_the_workflow_commit(self) -> None:
        for field in ("base_commit", "merge_base_commit"):
            with self.subTest(field=field):
                comparison = valid_comparison()
                comparison[field] = {"sha": "another-commit"}
                with self.assertRaisesRegex(ValueError, "based on main"):
                    verify_main_ancestry_payload(
                        comparison, expected_sha="commit-sha"
                    )

    def test_rejects_missing_or_unknown_ancestry_evidence(self) -> None:
        for comparison in (
            {},
            {"status": "ahead"},
            {**valid_comparison(), "status": "unknown"},
            {**valid_comparison(), "status": []},
            {**valid_comparison(), "status": None},
        ):
            with self.subTest(comparison=comparison):
                with self.assertRaisesRegex(ValueError, "based on main"):
                    verify_main_ancestry_payload(
                        comparison, expected_sha="commit-sha"
                    )

    def test_unverified_or_mismatched_tags_stop_before_the_ancestry_query(self) -> None:
        for failure in ("unverified", "mismatched"):
            with self.subTest(failure=failure):
                tag = valid_tag()
                if failure == "unverified":
                    tag["verification"] = {"verified": False, "reason": "unknown_key"}
                    message = "not verified"
                else:
                    tag["object"] = {"type": "commit", "sha": "another-commit"}
                    message = "workflow commit"
                with patch(
                    "verify_github_tag._get_json", side_effect=[valid_ref(), tag]
                ) as get_json:
                    with self.assertRaisesRegex(ValueError, message):
                        self.verify()
                    self.assertEqual(get_json.call_count, 2)

    def test_lightweight_tags_stop_before_tag_or_ancestry_queries(self) -> None:
        with patch(
            "verify_github_tag._get_json",
            return_value={"object": {"type": "commit", "sha": "commit-sha"}},
        ) as get_json:
            with self.assertRaisesRegex(ValueError, "annotated Git tag"):
                self.verify()
            self.assertEqual(get_json.call_count, 1)

    def test_ancestry_api_failure_stops_the_preflight(self) -> None:
        with patch(
            "verify_github_tag._get_json",
            side_effect=[valid_ref(), valid_tag(), RuntimeError("API unavailable")],
        ):
            with self.assertRaisesRegex(RuntimeError, "API unavailable"):
                self.verify()


if __name__ == "__main__":
    unittest.main()
