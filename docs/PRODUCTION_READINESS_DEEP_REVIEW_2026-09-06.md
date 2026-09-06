# Production Readiness: Deep Review

Assessed 2026-09-06, 18:46 UTC.

**Published GitHub main: 54/100. Unpublished local candidate: 72/100,
provisional. Neither is ready for broad production distribution.**

The published score applies to `c95f7acadacd6a5048e080ac6edd1b4143206769`,
confirmed through the GitHub API and local Git. Scope is the advertised
Android, iOS, Linux, macOS and Windows client plus optional hosted library sync.
Local fixes are not credited to the published revision.

This is a risk-based engineering assessment, not an exhaustive line-by-line
security audit, reliability probability, test-coverage percentage or MetroList
parity score. Scores within a few points should not be treated as precise
measurements. Known data-safety defects and unmet release gates take precedence
over the numerical average.

## Priority Findings

### 1. High: Published Persistence Can Report Success Without Saving

The published library save path awaits multiple preference writes but ignores
their boolean success results. A failed write can therefore leave the in-memory
library appearing saved while reopened data is missing or inconsistent across
sections. Queue persistence has related retained findings.

Source: [published save path](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10450).

The local candidate replaces this with a versioned snapshot boundary, serialized
writes, cross-process coordination, stale-writer detection and explicit recovery.
Fresh tests exercise the real file backend, including injected pre-commit disk
failure, corruption, restart and cross-isolate writes. These are useful bounded
tests, not a proof against every power-loss or filesystem failure.

Local evidence: [file backend](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/file_library_storage.dart:42),
[durability regressions](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/library_storage_durability_test.dart:25).

### 2. High: Published Offline Cache Paths Are Not Contained

An imported cache entry ID is interpolated into a destination pathname without
validating that it remains inside the private cache. Crafted imported state can
escape that directory within the app user's filesystem permissions. This is not
a claim of unauthenticated remote code execution.

Source: [published destination construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L119).

Local ID validation, filename normalization and link/containment checks are
implemented. Their regression suite passes; four Windows link tests are skipped
because this test environment lacks the necessary symlink privileges.

Local evidence: [path policy](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_paths.dart:7),
[malicious import regressions](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/offline_cache_safety_test.dart:56).

### 3. Medium: Published Token Expiry Is Lost During Recovery And Rename

Recovery creates a managed token without applying the configured lifetime.
Renaming a device reconstructs its token without copying the existing expiry.
Both paths can defeat an operator's configured expiration policy.

Source: [published recovery token](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/services/server/lib/src/authentication.dart#L591).

The local code supplies expiry during recovery and preserves it during rename;
the fresh server suite includes these regressions. Existing indefinite tokens
still require an explicit rotation/revocation policy. Local diagnostic logging
also avoids raw error payloads; this does not sanitize previously exported logs.

Local source: [expiry handling](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/src/authentication.dart:601).

### 4. Medium: Native Build Helper Has Incomplete Lock Enforcement

The locally vendored Cargokit wrappers create a temporary Dart runner and invoke
`dart pub get --no-precompile` without enforcing a reviewed runner lockfile.
Direct build-tool dependencies are pinned, but that does not lock their entire
transitive graph. A clean build can resolve different helper dependencies.

The app lockfile and native Cargo lockfile do not close this separate build-time
graph. This is a reproducibility and provenance gap, not evidence of compromise.

Sources: [Unix wrapper](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/packages/rhttp/cargokit/run_build_tool.sh:75),
[Windows wrapper](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/packages/rhttp/cargokit/run_build_tool.cmd:80).

### 5. Low, But CI-Blocking: Current Formatter Gate Fails

The exact CI formatter command checks 409 Dart files and reports one needing
formatting: the new shared native sync acceptance helper. The command used
`--output=none`, so it did not modify the file. Strict analysis and runtime tests
pass, but the current complete CI gate cannot be described as green.

Source: [shared helper](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/integration_test/support/native_sync_transport_contracts.dart:58).

## Release And Operations Gates

- **Exact-candidate publication:** the safety fixes and native transport changes
  are uncommitted/unpublished. Published main's successful CI is not acceptance
  of this working tree. Review the complete diff and run exact-commit CI.
- **Distribution:** the GitHub releases API returned zero releases. No complete
  signed/notarized clean-install, migration, upgrade and rollback campaign was
  demonstrated across the five advertised client platforms. Signing scripts and
  unsigned payload verification are not equivalent to installed acceptance.
- **Device behavior:** physical Android/iOS background playback, interruption,
  Bluetooth/audio routes, power restrictions and accessibility acceptance remain
  incomplete. The new native transport also needs current all-platform builds
  and lifecycle tests. Feature matrix entries explicitly distinguish incomplete
  crossfade, gapless, DSP and other platform-dependent behavior from full parity.
- **Hosted service:** latest production probe and alert jobs are skipped. The
  existing load smoke performs only 80 requests across four public routes with
  eight workers; it does not demonstrate sustained authenticated library sync,
  representative data sizes or concurrent-write capacity. Independent-host
  restore, measured recovery-point/recovery-time objectives and alert delivery
  remain unproven. A successful fixture recovery drill does not establish these.
- **Published vulnerability policy:** the PR container scan uses `--exit-code 0`
  and ignores unfixed findings. Its fail-closed counterpart runs only on schedule
  or manual dispatch. Local changes strengthen this, but are unpublished and no
  fresh live container scan was run for this audit.
- **Maintainability:** the home screen has over 22,000 nonblank lines, and the
  library store nearly 10,000. Coupled UI, persistence and platform behavior
  increases regression and review risk. Address ownership boundaries gradually
  after safety stabilization, not with an unrelated wholesale rewrite.

Sources: [release listing](https://github.com/Yunushan/aethertune/releases),
[latest skipped probe](https://github.com/Yunushan/aethertune/actions/runs/34049866460),
[latest skipped alert](https://github.com/Yunushan/aethertune/actions/runs/34049868735),
[load fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:16),
[published scan](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/.github/workflows/container-scan.yml#L44).

## Fresh Verification

| Check | Result |
|---|---|
| Strict Flutter analysis | Passed; no issues, 22.9 seconds |
| Full Flutter unit/widget suite | 1,246 passed, four Windows symlink-privilege skips, zero failures; 90 seconds |
| Strict server analysis | Passed; no issues |
| Full server suite | 102 passed, zero failures |
| Python CI contract discovery | 201 discovered: 194 passed, seven platform skips |
| Native wrapper generator tests | 11 passed |
| Exact CI Dart formatter scope | Failed: one of 409 files needs formatting; no source written |
| Dart executable-line coverage | 31,530/42,549 = 74.10%, across 202 reported files |
| Published main CI | Six jobs successful at the confirmed published SHA |
| Published GitHub releases | Zero |
| Current branch protection | Not verified: API returned HTTP 401 |

The widget harness uses test storage substitutes; separate durability tests
exercise the actual file backend. Python negative fixtures deliberately emit
failed scan/build/cleanup reports while testing error handling. Those reports
are not fresh Docker results or leaked real processes.

Coverage is uneven: audio engine 41.67%, offline background runner 3.33%, and
Windows media session 0% in this ordinary Dart suite. The file backend is 97.06%
and sync transport 94.03%. These are executable-line figures, not native,
branch, acoustic, device or end-to-end coverage. Separate native evidence can
validate behavior absent from ordinary Dart coverage, but does not make it 100%.

## Retained Evidence And Limits

The earlier integrated Windows Sandbox result records nine startup/TLS/isolate
contract checks and three normal native-close phases. Certificate rejection and
hostname checks remained enabled; peer disconnection and process exit completed
without forced termination. Broader prior Windows media/storage acceptance has
31 exercise checks and seven process-reopen checks, but predates native sync
integration and is not a fresh combined-candidate result.

All 67 files in the latest Windows evidence manifest retain their recorded
hashes. Of its 679 selected input hashes, three acceptance-harness/runner/policy
files changed subsequently; application inputs in that selection remain
unchanged. Two new Linux/shared harness files are additionally fingerprinted in
this audit's 681-input manifest. The refactored native harnesses have not been
rebuilt and rerun as installed applications in this audit.

The retained Cargo audit covers 276 dependencies against the September 2
advisory database and reports zero vulnerabilities/warnings. It was not freshly
fetched and is not a current clean bill for the whole application or server.

An earlier Linux bootstrap completed successfully, but Docker's engine API is
currently unavailable. No fresh Linux native acceptance, platform build,
container scan, signed installation, physical-device session or production
operation was run here. No service was started merely to improve this score.

## Weighted Score

| Area | Maximum | Published main | Local candidate | Main reason for remaining deduction |
|---|---:|---:|---:|---|
| Product implementation | 15 | 9 | 11 | Broad implementation, incomplete platform/provider acceptance |
| Data durability and recovery | 15 | 5 | 11 | Published defects; installed recovery still unproven |
| Security and privacy | 15 | 6 | 12 | Unpublished fixes; incomplete current supply-chain/runtime audit |
| Automated quality assurance | 15 | 12 | 12 | Good regression breadth; current formatting gate fails |
| Device and accessibility validation | 10 | 4 | 7 | Partial native evidence, missing physical/mobile matrix |
| Release engineering and distribution | 10 | 6 | 6 | Pipelines exist, complete signed installed release not demonstrated |
| Operations and recovery evidence | 10 | 6 | 7 | Local fixtures improve confidence; live hosted proof missing |
| Maintainability and documentation | 10 | 6 | 6 | Large coupled modules and evidence/documentation maintenance |
| **Total** | **100** | **54** | **72** | **Not production-ready** |

Compared with the earlier provisional local 73, one QA point is withheld because
the current formatter gate now fails. This small numerical distinction matters
less than the unchanged mandatory release criteria. Local is suitable only for
controlled alpha evaluation with backups and non-sensitive test data.

## Next Acceptance Criteria

1. Resolve the formatting and build-helper lock gaps, review the local safety
   changes, and obtain green exact-commit CI without disabling checks.
2. Validate the same integrated candidate across all five client platforms,
   including native networking teardown and physical mobile audio/lifecycle.
3. Retain signed/notarized clean-install, migration, upgrade, rollback and
   accessibility evidence for every advertised release target.
4. For hosted sync, demonstrate real alert delivery, sustained authenticated load
   at an explicit capacity target, and independent-host restore against agreed
   recovery objectives.
5. Complete a bounded pilot/soak with versioned evidence and actionable defects.

No application code, dependencies, branches, repository settings or deployment
were changed during this audit. Only this report and local verification evidence
were created. The separate readiness implementation goal remains paused.

Evidence: [fresh verification manifest](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-deep-score-review-2026-09-06/verification.json),
[source/evidence comparison](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-deep-score-review-2026-09-06/retained-evidence-comparison.json),
[retained Windows guest result](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-native-acceptance-2026-09-06/sandbox-d/evidence/result.json),
[published CI](https://github.com/Yunushan/aethertune/actions/runs/33869551283).
