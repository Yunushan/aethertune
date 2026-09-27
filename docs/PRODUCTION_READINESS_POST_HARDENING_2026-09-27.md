# Production Readiness — Post-Hardening Checkpoint (2026-09-27)

Scope: revision `59367dd` (main) plus the local hardening change-set recorded on
2026-09-27. This checkpoint extends `PRODUCTION_READINESS_POST_MERGE_2026-09-23.md`
and the score recorded on 2026-09-24; it documents verified improvements and the
remaining gates. Nothing here is merged policy until the change-set lands on main.

## Independent verification performed 2026-09-27

| Check | Result |
| --- | --- |
| `flutter analyze` with `strict-casts`, `strict-inference`, `strict-raw-types` | 0 issues |
| `flutter test` (full suite, twice) | 1,288 passed, 4 skipped, 0 failed both runs |
| `dart analyze --fatal-infos` (server) with the same strict modes | 0 issues |
| `dart test` (server) | 109/109 passed |
| CI policy contract tests (`scripts/ci/test_*.py`) | all pass |
| Live `verify_github_governance.py` run against GitHub | passes except two GHAS-entitled settings |

## Hardening applied

1. **OSV scanning fails closed.** All four scanner steps in `osv-scanner.yml`,
   `osv-required-context.yml`, and `osv-scan-pr-reusable.yml` now fail the job
   when the scanner exits nonzero without producing a parseable results file,
   instead of silently trusting a missing scan.
2. **Server request-body nesting is bounded.** `_readBoundedJson` now enforces
   `maxJsonNestingDepth` (64) before decoding, closing a stack-overflow denial
   of service on deeply nested bodies. Covered by five new tests in
   `services/server/test/server_json_depth_test.dart`.
3. **Maximum analyzer strictness on both packages.** `strict-casts`,
   `strict-inference`, and `strict-raw-types` are enabled for the mobile client
   and the server. Forty-four mobile findings and four server findings were
   fixed with annotation-only edits (`Map` → `Map<dynamic, dynamic>`), including
   one latent dynamic-dispatch issue in shared-playlist collaborator parsing.
4. **Dependabot coverage completed.** Added the `cargo` ecosystem for
   `apps/mobile/packages/rhttp/rust`; aligned the `setup-dart` action pin in
   `server-recovery-drill.yml` with the v1.8.1 SHA used elsewhere.
5. **Release/deployment gate unblocked.** The `production` environment now uses
   custom deployment policies exactly `{branch: main, tag: v*}` (previously the
   protected-branches-only mode excluded `v*` tags, so a production publish from
   a tag could never pass). `can_admins_bypass` is disabled, the five-minute
   wait timer and required reviewer are preserved.
6. **Monitoring environment created.** `production-monitoring` now exists with
   the `{branch: main}` policy and no reviewer or wait gates, matching the
   governance contract.
7. **Private vulnerability reporting enabled** on the repository.
8. **The weekly governance verifier now fails on exactly two settings** (both
   require GitHub Advanced Security entitlements): `secret_scanning_non_provider_patterns`
   and `secret_scanning_validity_checks`.
9. **God-file reduction, first step.** `library_store.dart` (10,980 lines) was
   split behavior-identically into `part` files: `library_store_models.dart`
   (1,332 lines of enums and data models) and `library_store_runtime.dart`
   (133 lines of private mutation helpers), leaving the `LibraryStore` class
   body at 9,521 lines. The split is byte-identical text movement verified by
   `flutter analyze` (0 issues), the 114-test library-store suite, and the
   full 1,288-test mobile suite.

## Updated score

Provisional 78/100 (up from 75 independently and 81 self-assessed on
2026-09-24): security, operations, and maintainability improved; the code,
CI, and governance configuration are release-candidate quality.

## Remaining gates to 100 (require maintainer resources)

1. Configure release signing secrets (Android keystore, Apple/notary, Windows
   PFX) and set `AETHERTUNE_PRODUCTION_RELEASES_ENABLED=true`.
2. Provide `AETHERTUNE_GOVERNANCE_TOKEN` and add an independent production
   reviewer (a second maintainer; sole-owner cannot satisfy the contract).
3. Enable the two GHAS-entitled secret-scanning settings (requires plan).
4. Deploy with TLS and collect probe/alert/restore evidence (RPO/RTO).
5. Publish a signed release and verify install/upgrade/rollback per platform.
6. Physical-device and accessibility acceptance; continue extracting cohesive
   sections from the 9,521-line `LibraryStore` class and the home-screen part
   files; expand i18n beyond the current 54-key base.
7. One flaky mobile test was observed once during a full run on 2026-09-27;
   three consecutive subsequent full runs (including one after the part-file
   split) were entirely green.
