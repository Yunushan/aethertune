# Production Readiness Audit

Assessment date: 2026-09-05.

Repository: [Yunushan/aethertune](https://github.com/Yunushan/aethertune).

Assessed revision: `c95f7acadacd6a5048e080ac6edd1b4143206769`, matching local and remote `main` when checked.

**Score: 61/100. Broad production release: not recommended yet.**

The repository has substantial working functionality, repeatable builds, and useful automated safeguards. It is suitable for continued development and controlled evaluation. Confirmed file-write and persistence defects need correction before users should trust it with their primary libraries or untrusted backup files. Device, release, and operational evidence also remains incomplete.

This is a weighted engineering assessment of the mobile/desktop application and optional self-hosted sync service as shipped together. It is not a measured reliability probability, feature-parity percentage, security certification, or test-coverage percentage. Optional public registration, a mandatory cloud account, and independent collaborators are not prerequisites for this project's intended self-hosted model.

## Scoring

| Area | Earned | Maximum | Basis |
|---|---:|---:|---|
| Product implementation | 12 | 15 | Real library, playback, provider, sync, and offline flows; native behavior and some advanced capabilities remain unverified. |
| Data durability and recovery | 6 | 15 | Versioning and explicit conflict handling exist, but failed writes are ignored, library loading lacks corruption recovery, and downloads have resource risks. |
| Security and privacy | 8 | 15 | Credential vaults, digest-based tokens, bounded payloads, hardened deployment, and scanners; confirmed cache path traversal and rate-limit bypass. |
| Automated quality assurance | 12 | 15 | 979 mobile tests, 61 server tests, successful CI, and a coverage floor; critical runtime paths have weak coverage and tests miss reproduced defects. |
| Device and accessibility validation | 4 | 10 | All claimed targets compile in CI; only a narrow Linux onboarding integration test and no recorded physical-device/accessibility acceptance matrix. |
| Release and distribution | 7 | 10 | Successful candidate packaging and signing/attestation tooling; no published release or verified production signing/notarization run. |
| Operations and recovery evidence | 6 | 10 | Health/readiness, deployment, backup, and rollback tooling; production probes skipped, governance audit fails, and recovery/load fixtures are limited. |
| Maintainability and documentation | 6 | 10 | Useful architecture, support, security, release, and feature documents; very large central modules and a few conflicting/stale statements. |
| **Total** | **61** | **100** | **Release blockers override an otherwise passing CI run.** |

## Confirmed Defects

### 1. High: Imported cache IDs can write outside the media directory

The backup loader accepts offline-cache records through `OfflineCacheEntry.fromJson`, which checks that the ID is a non-empty string but does not restrict it to a safe filename. `OfflineCacheManager.materialize` incorporates that ID into a path, then can delete the existing destination and replace it with downloaded bytes. The processing UI retains the imported ID.

Sources: [cache destination construction](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_manager.dart:118), [backup queue import](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_store.dart:5863), [cache record decoding](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/domain/offline_cache_entry.dart:82), [user-facing queue processing](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/ui/home_screen.dart:23082).

**Reproduced:** import a generated backup with an offline-cache ID containing a parent-directory component, then materialize that entry with a tiny injected download. A sentinel outside `offline_media`, but inside the isolated audit directory, was overwritten. The probe made no external request and touched no user data.

Preconditions: the user imports a crafted backup and the queued download is processed. The writable scope remains limited by the application's OS permissions. The defect is present in backup import; portable server sync deliberately strips offline jobs.

Required fix: derive filenames from a validated or hashed identifier, reject path separators/absolute paths on import, and enforce canonical destination containment at the actual write/delete boundary. Test both slash styles, absolute paths, restored jobs, and sentinel preservation.

### 2. High: Library writes can silently fail

`LibraryStore._save` awaits preference setters but ignores their boolean results. A failed storage write can therefore leave the UI reporting a successful library change. There is also no transaction across the many keys written by a save.

Sources: [save implementation](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_store.dart:10409), [track mutation](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_store.dart:1964).

**Reproduced:** an injected preferences backend rejected 35 writes. `addTracks` still returned successfully and the library showed one track. After reloading from the backing store, the track count was zero.

Required fix: propagate storage failures to the user, preserve or roll back in-memory state consistently, serialize saves, and store related library data atomically. A transactional database or a versioned atomic snapshot with recovery is preferable for library-scale data. Test rejected writes, disk-full errors, interrupted saves, and restart recovery.

### 3. High: Corrupted library data leaves startup stuck loading

`load` directly decodes persisted JSON. Its explicit `loadError` path covers a newer schema version, but malformed JSON throws before setting either `loaded` or `loadError`. The app starts loading without awaiting/catching that future and chooses its loading screen while `loaded` is false.

Sources: [JSON load](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_store.dart:1606), [provider initialization](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/ui/aethertune_app.dart:71), [loading/error UI selection](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/ui/aethertune_app.dart:358).

**Reproduced:** malformed saved track JSON produced `FormatException`, `loaded=false`, and `loadError=null`.

Required fix: catch decoding/type/storage errors at the load boundary, retain recoverable raw data, and present recovery/import/reset actions. Do not silently discard the user's library. Cover each stored section and partial migration failures.

### 4. Medium: Rotating invalid bearer tokens bypasses request throttling

The limiter keys any supplied bearer string before authentication. Each new invalid token receives a fresh allowance, so unauthenticated traffic can avoid the configured per-minute limit. Managed authentication subsequently scans stored accounts and tokens, increasing the importance of a pre-authentication bound. The supplied Caddy configuration does not add a rate limiter.

Sources: [limiter key selection](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/server.dart:54), [middleware ordering](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/server.dart:468), [managed authentication lookup](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/src/authentication.dart:369), [proxy configuration](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/deploy/Caddyfile:1).

**Reproduced:** with a two-request limit, repeated use of one invalid token returned `[401, 401, 429, 429]`; four different invalid tokens returned `[401, 401, 401, 401]`. Authentication still rejected every invalid token; this is an abuse-control bypass.

Required fix: apply a bounded unauthenticated/global or trusted-proxy client limit before authentication, then apply account/device limits to verified identities. Do not trust arbitrary forwarded headers. Test rotating tokens and bucket exhaustion through the deployed proxy path.

### 5. Medium: Offline downloads have unbounded resource exposure

The downloader does not enforce a transfer-byte cap or explicit connection/read deadline. After downloading, `materialize` reads the whole file into memory twice and runs synchronous checksums. The worker applies cache quotas only after materialization succeeds. Large podcasts, audiobooks, or unexpectedly long responses can exhaust disk/memory or stall the processing queue before eviction occurs.

Sources: [full-file verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_manager.dart:151), [download loop](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_manager.dart:363), [quota ordering](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_queue_worker.dart:85).

This is a source-confirmed resource-risk finding. An out-of-memory or disk-exhaustion test was deliberately not run on the user's machine.

Required fix: stream checksums, enforce limits while receiving bytes, reserve/check storage before and during transfer, set deadlines, and verify slow/stalled servers and large media on memory-constrained devices.

## Release and Operational Gaps

**Production signing and publication are not yet proven.** GitHub returned no published releases. The most recent manual candidate release inspected was [run 31884081107, 2026-08-15](https://github.com/Yunushan/aethertune/actions/runs/31884081107). It successfully assembled platform artifacts, but production Android signing, Apple signing/notarization, Windows signing, and GitHub publication were skipped. It also predates the assessed revision. This earns credit for working packaging, not for a completed production rollout.

**Production monitoring is inactive in the observed runs.** The [2026-09-05 probe](https://github.com/Yunushan/aethertune/actions/runs/33955681242) and associated alert workflow were skipped. The [workflow condition](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/production-ops-probe.yml:18) requires production enablement. No deployed service URL or external uptime/alert evidence was verified in this assessment.

**The latest observed scheduled governance audit failed.** [Run 33384426481, 2026-08-31](https://github.com/Yunushan/aethertune/actions/runs/33384426481) failed because its token was empty; the verifier reported that a token was required. The [workflow](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/governance-audit.yml:31) obtains it from `AETHERTUNE_GOVERNANCE_TOKEN`. Live branch-protection inspection returned 403 through the connector, so current protections and secret-scanning configuration are unverified, not assumed absent. The repository's existing sole-owner governance policy is compatible with this project's ownership model.

**Recovery evidence is narrower than a complete service recovery.** [Backup tests](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_backup_restore.sh:10) archive and compare a small synthetic `library.json`. [Rollback tests](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_rollback.sh:10) replace executable-marked text fixtures. These check useful filesystem safeguards, but do not boot a restored service, verify managed credentials and snapshot revisions, or measure RPO/RTO. The backup job also archives the live directory without a coordinated snapshot across stores; consistency during concurrent writes needs an explicit test.

**Load evidence is a smoke test.** The passing CI result is 80 requests, eight workers, and a roughly 123 ms p95 on the runner. [The test](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:17) covers health, readiness, info, and the small catalog endpoint. It does not exercise authenticated snapshot uploads, concurrent conflicts, large playlists, many accounts, or a sustained production workload. Do not extrapolate this result into user capacity or an availability SLO.

**A green container scan on a PR is not a blocking vulnerability gate.** [The main/PR Trivy job](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/container-scan.yml:41) uses exit code zero. The separate failing-on-vulnerability job runs only on scheduled/manual events and ignores unfixed issues. OSV and dependency review provide other safeguards, but container findings can be reported without blocking a merge.

## Test and Platform Evidence

The [current-main CI run](https://github.com/Yunushan/aethertune/actions/runs/33869551283) completed successfully on 2026-09-04. All six jobs passed: provenance, mobile analysis/tests, Linux, Windows, macOS, and server validation. Desktop jobs build debug binaries; macOS CI also compiles unsigned iOS. Android debug builds, Docker startup, executable smoke tests, and deployment checks passed. CodeQL and OSV workflows on the same commit also completed successfully.

I downloaded and inspected the exact CI LCOV artifact, rather than treating the coverage floor as the measured result:

| Module/scope | Covered executable lines | Line coverage |
|---|---:|---:|
| Mobile report, 190 files | 30,195 / 41,299 | 73.11% |
| Library store | 4,738 / 5,018 | 94.42% |
| Local folder scanner | 1,766 / 1,923 | 91.84% |
| Player controller | 1,145 / 1,361 | 84.13% |
| Offline cache manager | 196 / 243 | 80.66% |
| Library sync client | 574 / 755 | 76.03% |
| Library sync panel | 440 / 1,011 | 43.52% |
| Playback audio engine | 145 / 348 | 41.67% |
| Home screen | 3,815 / 9,788 | 38.98% |
| Video playback screen | 0 / 146 | 0.00% |

Coverage is based on the report's executable-line denominator, not all repository lines. `lib/main.dart` is absent from it; two export-only files are also absent. It is not branch coverage, native-platform coverage, actual audio-output validation, or proof that dependencies behave correctly. The newly reproduced library defects exist despite high line coverage in that module.

The only checked-in `integration_test` file is [onboarding_smoke_test.dart](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/integration_test/onboarding_smoke_test.dart:10), which runs on Linux, uses mocked preferences, and checks a callback. There are broader widget tests with fake playback engines, but no checked-in integration evidence for actual import/playback, background interruptions, Bluetooth/headset changes, process termination, codec behavior, or installed update/recovery flows across all supported devices.

The [roadmap](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ROADMAP.md:121) explicitly leaves physical lifecycle tests open, along with acoustic fixtures, Android Auto validation, and [accessibility acceptance](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ROADMAP.md:256). Some semantics tests exist; they do not establish an app-wide screen-reader, keyboard, text-scaling, contrast, or touch-target pass.

## Verification Performed Locally

| Check | Result |
|---|---|
| Local versus remote revision | Both matched `c95f7ac`; working tree was clean before audit artifacts. |
| Flutter/Dart version | Flutter 3.44.6 and Dart 3.12.2, matching repository CI pins. |
| `flutter test --no-pub --reporter expanded` | 979 passed, approximately 2 minutes 40 seconds. |
| `dart analyze` in server | Passed, no issues. |
| `dart test --reporter expanded` in server | 61 passed. |
| Python CI unit-test discovery | 94 discovered, 93 passed and one skipped. |
| Generated platform configuration tests | Seven passed. |
| Strict `flutter analyze --no-pub` | Exit 1 for 12 informational deprecations; no warnings/errors reported. |
| `flutter analyze --no-pub --no-fatal-infos` | Passed with the same 12 informational deprecations, matching CI policy. |
| Library audit probes | Confirmed malformed-data startup failure, ignored write failures, and cache path escape. |
| Server audit probe | Confirmed rotating invalid tokens avoids the limiter. |

The probes assert the observed defect behavior; their passing result confirms reproduction, not correctness. They are isolated under ignored build directories and are not part of the application's normal test suite.

The locked Flutter dependency graph resolved locally. Plugin setup then reported that Windows Developer Mode/symlink support was unavailable. Tests and analysis ran with `--no-pub`; no Windows system setting was changed. Native builds and signed installation were not rerun locally. Their reported build results come from GitHub CI. Server dependencies resolved with the committed lockfile enforced.

## Maintainability and Strengths

The project has a real provider boundary, platform credential vaults, explicit offline policies, revision-based sync conflicts, per-device revocation, bounded HTTP request bodies, and file-backed server persistence with serialization and atomic renames. The deployment binds privately by default and provides non-root/read-only container settings, capability removal, TLS-proxy instructions, graceful shutdown, backup verification, and operational probes. These are substantial engineering assets.

The main maintenance concern is concentrated responsibility: `home_screen.dart` contains 23,385 physical lines and `library_store.dart` 10,775. UI dialogs, network orchestration, cache processing, and library serialization span these central modules. Extract cohesive feature areas as they change, especially persistence and offline work; an unrelated wholesale rewrite is unnecessary.

Documentation distinguishes implementation from universal feature parity. However, some release text still universally requests a separate reviewer while a later section correctly supports sole-owner governance, and some feature-matrix next steps lag implemented code. Use executed evidence and acceptance criteria to update completion claims.

## Remediation Order

1. Close the cache path traversal at import and file-write boundaries; add sentinel-preservation regression tests.
2. Make library persistence failures visible and saves atomic; add corrupted-state startup recovery and failure/restart tests.
3. Bound unauthenticated request traffic and offline transfer resources; test adversarial inputs and stalled downloads.
4. Add real playback/import/sync integration tests and physical Android/iOS lifecycle fixtures, followed by desktop host and accessibility acceptance checks.
5. Restore the governance audit, validate production probe/alert configuration, and exercise recovery with real credentials/snapshots and a running restored server.
6. Build a candidate from the final corrected commit, complete signing/notarization and clean-machine installation tests, then record an approved production release.

An 80+ reassessment needs the confirmed defects fixed and evidence for the principal device/release workflows. A 90+ assessment additionally needs credible durability, load, accessibility, update, and live operational evidence. More feature checkboxes or a larger unit-test count alone will not close these gaps.

## Audit Artifacts and Limits

- [Library reproduction probes](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/library_probe_test.dart).
- [Server limiter probe](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/server_probe.dart).
- [Inspected CI coverage](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/ci-coverage/lcov.info).

This was a targeted deep code/configuration review with full existing test suites, CI/artifact inspection, and isolated defect reproduction. It was not an exhaustive line-by-line audit of every module, an external penetration test, a live-provider compatibility campaign, or a physical-device test session. No repository settings, branches, pull requests, or application source files were changed. This report and local audit artifacts were created; no changes were committed or pushed.
