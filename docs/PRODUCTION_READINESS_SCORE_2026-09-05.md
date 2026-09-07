# Production Readiness Score: Current Assessment

Assessment date: 2026-09-05. Latest score review at 19:53 UTC, including live
GitHub checks and fresh Windows Flutter/server tests and strict analysis.
Earlier Linux offline-cache handoff verification completed at approximately
19:34 UTC and remains separately identified evidence.

Updated the same day with systemd ownership/recovery, Distroless runtime,
volume-continuity, and executed container-gate follow-ups recorded in
[the progress log](PRODUCTION_READINESS_PROGRESS.md). This refresh rechecked
GitHub main, CI, releases, local source, coverage, and retained runtime evidence.
Local fixes remain uncommitted and unpushed.

Native-client follow-ups passed Windows/Linux process-death acceptance,
bounded Linux filesystem exhaustion, and actual Flutter/Linux startup,
preference migration, secure-storage continuity, WAV decoding, and MPRIS
controls across app processes. These close specific gaps below without
claiming installed-release, physical-device, or power-loss safety.

**GitHub main: 60/100. Current local working tree: provisional 72/100.**

**Neither state is recommended for a broad production release yet.** The local
tree is materially safer and is suitable for controlled alpha evaluation with
separate backups and non-sensitive fixtures. It is not the code currently
available from GitHub main. The diagnostic disclosure below is fixed locally,
but remains in main. Previously exported reports and OS backups are not cleaned
by the fix and should not be assumed safe to share.

The 17:05 audit reduced the previous scores to 60/100 main and 71/100 local after
reproducing diagnostic-secret disclosure. The verified local fix restores that
one security/privacy point only to the local tree. Main remains unchanged.
Earlier reports remain historical records; their observations about incomplete
local backup integration no longer describe the current code.

## Scope and Method

- Repository: [Yunushan/aethertune](https://github.com/Yunushan/aethertune).
- GitHub main and local HEAD matched `c95f7acadacd6a5048e080ac6edd1b4143206769`
  at this refresh. Main was checked through the live GitHub API, not inferred
  from a screenshot. Its six main CI jobs still pass and its releases list is
  empty. The worktree includes numerous modified and untracked implementation,
  test, workflow, and report files; it is not a reproducible published revision.
- Scope: the Flutter Android/iOS/Linux/macOS/Windows client and optional
  self-hosted Dart server, including data safety, security, tests, releases,
  deployment, recovery, monitoring, and maintenance.
- Reviewed committed and modified persistence/cache/authentication paths,
  backup coordination, runtime recovery tests, deployment assets, CI/release
  policies, integration tests, coverage, and outstanding acceptance items.
- Freshly reran the full Windows Flutter suite and coverage, strict Flutter
  analysis, Windows server analysis/tests, and Python CI tests. Separately ran
  six isolated diagnostic privacy checks: the original control passed and five
  cases failed, reproducing the defect. After local hardening, the unchanged
  six-case probe passes, as do the expanded regular diagnostic regressions and
  final full Flutter suite. Server/native runtime evidence was not rerun during
  this diagnostic-only follow-up.
- The latest follow-up reran the full Flutter suite on Windows and Linux, plus
  strict Linux Flutter analysis. It executed a three-process real-plugin native
  Linux fixture and a measured PCM gate. The latest offline-cache handoff fix
  also has lifecycle, real-file/HTTP resume, and stale-writer regressions. A final
  SHA-256 comparison of 391
  source, test, package, manifest, and fixture files found no mismatches between
  the worktree and tested Linux stage. Server/runtime/systemd/container results
  remain earlier same-day evidence, not reruns during this client follow-up.
  The native client backend and probe lockfile hashes also still match the
  previous Windows/Linux process and disk-full reports.
- Linux verification used Dart 3.12.2 in an isolated build directory, with a
  separate package cache and enforced server lockfile. The official SDK archive
  checksum was verified during preparation. The initial 28-file comparison was
  repeated after the runtime change across 35 source/test/deployment/package
  files: no mismatch at verification time.
- Linux runtime tests use WSL2 and disposable local data. Follow-up work also
  executed an isolated systemd identity/recovery fixture, real Docker image
  signature/runtime/scan gates, and an old-image/new-image volume fixture.
  None is a production deployment or physical-device acceptance.
- The scoring pass did not change application code. Subsequent local hardening
  changed backup tooling, the container runtime/readiness probe, diagnostic
  privacy/storage behavior, native cache-error handling, locale fallback,
  foreground cache handoff, and
  CI/release enforcement as recorded in the
  progress log. No commit, push, merge, production deployment, repository
  protection change, or production secret activation occurred.

Scores are weighted engineering judgments, not reliability probabilities,
test-coverage percentages, security certifications, or MetroList feature parity.
A small difference in points should not be treated as a measured improvement
in failure probability. Confidence is higher in the concrete findings than in
the precise numeric score.

### Latest Score Review

The user's renewed request was an assessment, not authorization to continue
implementation or publish changes. This review changed only this report and
generated test/coverage evidence. Existing application changes were preserved;
no commit, push, merge, deployment, or repository-setting change was performed.

- Reconfirmed live main at `c95f7acadacd6a5048e080ac6edd1b4143206769`, eight
  required branch check contexts, passing main CI, and an empty releases API.
- Rechecked the latest operations runs: the 19:10 UTC production probe and
  alert were skipped. The latest governance audit remains failed.
- Fresh Windows Flutter execution: **1,149 passed, four skipped**. Strict
  Flutter analysis reports no issues. Coverage remains **31,060 / 42,154
  executable lines (73.68%)**.
- Fresh Windows server execution: **87 passed**; strict Dart analysis reports
  no issues. Python CI helpers: **171 discovered, 164 passed, seven skipped**.
  The separate native-platform generator test suite also passed.
- Rehashed all **391 files** in the earlier Linux source manifest: zero
  mismatches. The storage backend and native probe lockfile hashes also match
  the retained process-death/exhaustion evidence. Linux native, container,
  systemd, and recovery fixtures were **not rerun** during this score review.
- Re-read committed persistence, cache destination construction, and diagnostic
  redaction, plus current snapshot locking, rate limiting, background runner,
  cancellation, provider artwork materialization, and release/operations gates.
  The distinctions and blockers below remain applicable. No additional points
  are warranted solely because unchanged tests pass again.

## Score Breakdown

| Area | Maximum | GitHub main | Local tree | Principal limit |
|---|---:|---:|---:|---|
| Product implementation | 15 | 12 | 12 | Broad implementation, but incomplete native journey acceptance. |
| Data durability and recovery | 15 | 6 | 11 | Local snapshots, native client process-death tests, and service recovery work; power loss and installed migration remain unproven. |
| Security and privacy | 15 | 7 | 12 | Diagnostic disclosure is fixed locally but remains in main. Local path/rate-limit/resource fixes and signed-base container gate pass; deployed abuse testing and committed CI enforcement remain. |
| Automated quality assurance | 15 | 12 | 13 | Extensive tests, native storage recovery, and real Linux PCM/MPRIS acceptance; playback coverage and the complete platform matrix remain weak. |
| Device and accessibility validation | 10 | 4 | 4 | Compilation and widget tests are not physical playback, lifecycle, or assistive-technology acceptance. |
| Release and distribution | 10 | 7 | 7 | Candidate packaging exists; no verified published production release of the corrected tree. |
| Operations and recovery evidence | 10 | 6 | 7 | Coordinated runtime recovery demonstrated locally; production monitoring, capacity, and recovery objectives are not. |
| Maintainability and documentation | 10 | 6 | 6 | Useful documentation and new helpers, but large central modules and acceptance-evidence maintenance remain. |
| **Total** | **100** | **60** | **72** | **Local improvements are not credited to unpublished main.** |

The previous local increase from 69 to 72 credited integrated data recovery,
cross-process/platform verification, and executed operational recovery. Those
credits remain. The diagnostic follow-up restores the single local privacy
point deducted at 17:05 because the reproduced disclosure is now closed with
persisted/exported-output and legacy-cleanup regressions, not merely because
the test count increased.
No points were added for unsigned release configuration, skipped monitoring,
or unexecuted device tests. The latest Linux native fixture strengthens evidence
within the existing local credit; it does not complete the release/device
categories or make unpublished changes part of main.

## Highest-Priority Findings

### 1. High: Main still contains data-loss and unsafe cache-write defects

The committed library save ignores preference setter results and writes related
state across many independent keys. The original isolated audit rejected 35
writes: the UI-side mutation succeeded, but reloading lost the track. Malformed
stored JSON also left startup without a usable recovery state. These findings
were previously reproduced; this assessment rechecked their committed source
without rerunning a second pristine checkout.

Sources: [main save](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10409)
and [main load](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L1606).
The package documentation also warns that preferences do not guarantee durable
critical-data writes. [Official shared_preferences documentation](https://pub.dev/packages/shared_preferences).

Main also interpolates imported offline-cache IDs into destination paths. The
original disposable-data probe overwrote a sentinel outside the media folder
after importing and processing a crafted backup. This requires user import and
processing, and remains limited to the application's filesystem permissions.
[Committed destination construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L118).

Local status: atomic versioned snapshots, save failure propagation/rollback,
recoverable startup, path validation, and portable filenames have passing
regressions. **They must be committed, reviewed, and validated on the exact
candidate before main can receive that credit.**

### 2. High: Client durability still needs installed and power-loss acceptance

The new storage writes/flushed pending files, retains a previous snapshot,
compares revisions, and serializes writers with SQLite. SQLite supplies the
lock; the JSON payload is not itself stored in a SQLite transaction. No
directory-metadata/power-loss guarantee has been established across supported
filesystems. The original widget/unit test injects an exception at the pre-commit
boundary. A subsequent native executable now imports the exact backend and has
passed seven process/storage checks on Windows and Linux: acknowledged and
pending commit death, stale writers, lock release after death, explicit archived
recovery, a 25,000-track fixture, and interrupted initial commit/retry.

References: [snapshot commit](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/file_library_storage.dart:167),
[failure injection](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/library_storage_durability_test.dart:45),
and [native runtime](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/client_storage_runtime.py).

Three additional Linux cases used an isolated 8 MiB tmpfs and unprivileged
storage processes. Real SQLite-full and file `ENOSPC` errors, including a partial
pending write, preserved current/previous bytes and allowed a retry after freeing
space. The 25,000-track snapshot was about 5 MB; measured local save round trips
were 0.250 seconds on Windows and 0.265 seconds on Linux. This is backend evidence,
not installed UI performance or a physical full-disk/power-loss simulation.

Real Linux preference-plugin migration now passes in the isolated native app
fixture, including legacy diagnostic cleanup and preserved unrelated settings
and secure storage across restarts. Still required: interrupted migration,
more commit boundaries, directory metadata/power loss, installed upgrades,
the complete native client matrix, and representative low-end-device
latency/memory. The new CI/release
storage jobs are local changes and have not run on GitHub for a committed revision.

Cache media and library index changes also do not form a single transaction.
Failed index saves may leave orphaned media; the new implementation counts and
explicitly cleans it. A subsequent local handoff fix now drains the foreground
batch before requeuing/scheduling and reloads saved state on resume. Lifecycle
tests and a real 64 KiB loopback transfer verify cancellation, validated resume,
cache-lock release, and rejection of a stale foreground snapshot after another
store commits. These are Dart-side/widget and same-process I/O checks, not
actual Android/iOS background-engine acceptance. The iOS cancel handler has no
explicit active-engine shutdown handshake; native quiescence, live policy
changes, and interrupted cache/index boundaries remain outstanding. Media-byte
budgets are not physical disk reservations.

The latest source review makes that remaining boundary concrete: foreground
resume awaits `cancel()` and then reloads the library, but the generated iOS
handler only cancels the scheduled request and immediately replies. It does
not wait for an active headless engine to stop. The Android stop callback
destroys its engine without a Dart-side drain acknowledgment. Separately, the
queue worker races provider resolution against cancellation with `Future.any`;
the underlying resolver can still finish a private artwork-file write after
the worker's pass has returned. These are source-confirmed coordination gaps,
not a newly reproduced claim of data loss in the hardened local snapshot
backend. A graceful stop/acknowledgment protocol must cover all in-flight side
effects, fail safely on timeout, and be tested on the actual native wrappers.
Do not treat the existing mocked channel tests as proof of engine shutdown.

References: [foreground resume](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/ui/widgets/offline_cache_foreground_worker.dart:153),
[iOS cancellation template](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/configure_audio_service_platforms.py:1555),
[Android stop template](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/configure_audio_service_platforms.py:1428),
[resolver cancellation race](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_queue_worker.dart:107),
and [artwork materialization](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/self_hosted_provider_store.dart:535).

### 3. Release Blocker: Installed and physical-device journeys remain unproven

Main's only checked-in integration test uses mocked preferences and verifies an
onboarding callback. It does not drive real import, audio/video, secure storage,
sync, and native background behavior as one installed application.
[Integration test](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/integration_test/onboarding_smoke_test.dart:10).

The new uncommitted Linux integration fixture runs the production entry point
with real plugins in three separate processes. It passes legacy preference
migration, native scanning, saved library/queue state, Secret Service credential
continuity/deletion, generated WAV playback, seeking, and MPRIS pause/play/next.
The latest virtual sink captured sustained decoded PCM (peak 5,000; 39,945 active
samples). Both native screenshots were visually checked at 1280x720.
[Native fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/integration_test/linux_native_acceptance_test.dart:30),
[audio evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/cache-handoff-native-final/audio.json).

This is a debug integration build in an isolated Ubuntu container with Xvfb,
software rendering, a private keyring, and virtual audio. It is not an installed
release, a UI-driven file-picker test, physical sound output, native sync,
representative codec coverage, or hardware/background lifecycle acceptance.
The same exercise found and fixed a local unhandled missing-Documents future
and incorrect unsupported-locale fallback; both now pass native regressions.

The roadmap still explicitly leaves physical acoustic/lifecycle fixtures,
Android Auto validation, and accessibility acceptance open.
[Lifecycle scope](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ROADMAP.md:121),
[accessibility scope](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ROADMAP.md:256).

Acceptance must record device/OS/build IDs for actual playback, representative
codecs, interruptions, Bluetooth/headsets, lock-screen controls, background
termination, offline resumption, sync conflicts, clean installation, upgrade,
keyboard navigation, screen readers, and large text. A passing fake audio-engine
test is not sound-output evidence. Features outside the intended release scope
can be explicitly excluded rather than represented as accepted.

### 4. Release Blocker: No corrected production release is demonstrated

The live GitHub releases API returned an empty collection. The inspected
candidate run from 2026-08-15 successfully packaged artifacts, but Android and
Windows production signing, Apple signing/notarization, production provenance
checks, and publication were skipped. That run predates current main and all
local hardening.
[Candidate run](https://github.com/Yunushan/aethertune/actions/runs/31884081107),
[release listing](https://github.com/Yunushan/aethertune/releases).

The current main CI passed all six jobs on 2026-09-04. This is valid compilation
and test evidence for main, not for the uncommitted native storage and backup
changes. [Main CI](https://github.com/Yunushan/aethertune/actions/runs/33869551283).

### 5. Medium: Main diagnostic exports can disclose credentials; fixed locally

The main version of `LocalDiagnosticLog` redacts a small set of unquoted key/value patterns before
saving ordinary preferences and exporting JSON. It misses `access_token`,
`refresh_token`, Subsonic URL parameters `p` and `t`, and quoted JSON token
fields. Main's source remains unchanged.
[Committed redactor](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/local_diagnostic_log.dart#L158),
[committed persistence](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/local_diagnostic_log.dart#L107).

**Reproduced in the 17:05 audit:** one plain `token=...` control was redacted;
five synthetic credential formats remained in both saved diagnostics and the
exported document. The isolated probe uses the production logger with mock
preferences, invented secrets, and `example.invalid` URLs. It makes no network
request and uses no real credentials. The old regular tests only exercised the
narrow supported syntax and therefore still passed.
[Probe](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/diagnostic_privacy_probe_test.dart),
[result](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/diagnostic-privacy-probe.log).

Exposure requires an error or stack trace containing such a value to reach the
logger, followed by local access or an explicit diagnostic export. This is not
evidence that live provider credentials were leaked or that diagnostics are
automatically uploaded.

**Local remediation, verified at 17:47 UTC:** diagnostic v2 does not serialize
raw error text, request/response payloads, network URLs, local paths, or raw
stack symbols. It retains constant error categories/descriptions, numeric
codes, timestamps, and up to 12 validated Dart package/SDK source locations.
The previous v1 diagnostic key is removed without reading its payload. Related
library/credential preferences remain untouched. Storage failures are visible,
clear results are verified before success is reported, and failed cleanup is
retryable even when the in-memory log is empty. Capture operations are
serialized and capped at 40 pending events, with an explicit discarded count.
[Local logger](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/local_diagnostic_log.dart:9),
[regressions](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/local_diagnostic_log_test.dart).

The unchanged six-case audit probe now passes. The regular suite includes 57
diagnostic tests and two added app-widget clear-result tests. The diagnostic
follow-up passed 1,126 tests with four existing skips; the latest handoff follow-up
passes 1,149 on Windows and 1,153 on Linux, with strict analysis clean.
[Final probe](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/diagnostic-privacy-probe-final.log).
The diagnostic regressions use synthetic data and mock preference platforms.
The later native Linux fixture also verifies real-plugin legacy cleanup across
processes, while preserving unrelated preferences and a keyring credential.
Neither proves a shipped-package upgrade, secure erasure of prior exports/OS
backups, developer-console redaction, or native crash symbolication.

### 6. Medium: Recovery improved, but deployment and capacity remain unproven

The current shell entry points now use the coordinated Python helper. The
systemd backup sandbox permits its lock files. Native Windows evidence retained
from the previous pass and fresh Linux execution each pass 17 runtime checks:
active-write draining, exact restored library/provider state, separate accounts,
revoked credentials, one-time recovery codes, post-restore writes, and process
kill/restart behavior. An actual stalled upload reaches the 30-second deadline
without changing the snapshot or retaining the backup lock.
[Runtime drill](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/server_recovery_runtime.py:1).

This closes the previous report's incomplete backup-integration finding.
Follow-ups also passed eight isolated Linux systemd runtime checks and fixed
the reproduced root-created lock ownership defect. An old-image/new-image
container volume fixture passed 13 checks with UID/GID `10001:999`, exact saved
state, revocation, conflicts, graceful shutdown, and persistence after container
recreation. This is a packaging change with the same service code, not a
different application/schema version. Remaining acceptance includes macOS,
production host/container deployment, interrupted write boundaries, and rollback
between different release/schema versions.

The Linux fixture's 0.096-second controlled restore/validation measurement is
for tiny disposable data. It is not a production recovery-time objective.
Representative volume, backup pause duration, off-host restore, and recovery
point/time objectives still need measurement.

Current load fixtures exercise 80 or 90 small requests. They do not establish
sustained authenticated upload capacity, many-account scaling, near-limit
payload behavior, or container memory/CPU headroom through the actual TLS proxy.
[Load fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:17).

### 7. Medium: Operational policies are not all effective runtime gates

- The latest observed production probe and alert runs on 2026-09-05 were
  skipped at 19:10 UTC. No successful production monitoring or alert delivery
  was established.
  [Probe](https://github.com/Yunushan/aethertune/actions/runs/33986296241),
  [alert](https://github.com/Yunushan/aethertune/actions/runs/33986298774).
- The inspected governance audit remains failed; the previous log inspection
  identified a missing `AETHERTUNE_GOVERNANCE_TOKEN`.
  [Audit](https://github.com/Yunushan/aethertune/actions/runs/33384426481).
- The current branch API confirms protection and eight required check contexts.
  Full administration/bypass/environment settings have not been verified by
  this integration. Missing administration access is not evidence of absent
  protection.
- Committed main still has a report-only PR/push Trivy job and no container
  release dependency. Locally, the shared gate now fails the required server
  CI job and Linux server release job on signature, runtime, scan/evidence, or
  cleanup failures. The first real scan rejected the former image with **65
  HIGH and four CRITICAL package findings** (26 distinct CVEs). Replacing that
  runtime with pinned Distroless Debian 13 reduced the OS inventory from 106 to
  14 packages. The replacement passed the unchanged policy with **zero
  HIGH/CRITICAL findings**, valid publisher signature, and 13 exact-image runtime
  checks. No findings were suppressed. This is not an application-security
  certification; OSV/dependency review remain separate controls for Dart
  dependencies not recoverable from the AOT binary. The local workflow has not
  executed on GitHub for a committed candidate.
  [Scanner](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/scan_server_container.py),
  [current gate evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/container-gate-cleanup-verified/summary.json),
  [historical rejected image](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/container-scan-verified/summary.json).

The project's sole-owner model is valid. Adding a collaborator, relaxing checks,
or changing the license is not required to address these technical gaps.

### 8. Medium: Maintenance and documentation drift remain

Large central UI/store files concentrate multiple responsibilities and make
review expensive. Current `home_screen.dart` has 23,437 physical lines and
`library_store.dart` has 10,980. Extract cohesive responsibilities as they change; a wholesale
rewrite is not required for readiness. Local README and architecture have now
been corrected to describe the snapshot backend and its verification limits;
keeping broad feature claims aligned with installed acceptance remains ongoing.
[README](C:/Users/Yunus-Home/Downloads/aethertune-mobile/README.md:149),
[architecture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ARCHITECTURE.md:180).

## Verification Evidence

The final Flutter suites, strict Linux Flutter analysis, real-plugin Linux
fixture, and Windows Python helpers were executed after the offline-cache
handoff fix. Windows/Linux server, systemd, container, backend process-death/storage,
and isolated diagnostic-probe results are retained earlier same-day evidence.
The 19:53 score review additionally reran the Windows Flutter and server suites,
both strict analyzers, Python CI helpers, and platform-generator tests, as
recorded above. It did not repeat the Linux or container runtime fixtures.

| Check | Result | Limit |
|---|---|---|
| Full Windows Flutter suite with coverage | 1,149 passed, four skipped | Final local source; Windows link-privilege skips remain. |
| Full Linux Flutter suite with coverage | 1,153 passed, no skips | Final matching source in an isolated container. |
| Strict Flutter analysis | No issues | Final cache-handoff source on Linux. |
| Real Linux native application | Three process phases plus PCM gate passed | Real preferences, keyring, file storage, WAV decode and MPRIS; virtual audio/display, not installed-release or physical-device acceptance. |
| Offline-cache handoff regressions | 15 added tests passed | Ten widget lifecycle cases, two worker cancellation cases, three real-file/HTTP cases; not actual mobile engine shutdown. |
| Native Linux server analysis | No issues | Dart 3.12.2, isolated copy/cache. |
| Native Linux server tests | 87 passed in runtime follow-up | Current server source, enforced lockfile. |
| Windows server analysis/tests | No issues; 87 passed in this refresh | Includes 14 readiness-probe regressions. |
| Native Linux AOT compilation | Passed | x86-64 executable under WSL2. |
| Linux executable smoke | Passed | SIGTERM drain, second-instance rejection, health/readiness/metrics, 90 requests. |
| Linux compiled-service recovery | 17 checks passed | Disposable data on Linux local temporary filesystem. |
| Linux Python CI suite | 162 passed in client-storage follow-up | Includes root/non-root cases skipped on Windows. |
| Windows Python CI suite | 164 passed, seven skipped in the handoff follow-up | 171 discovered; POSIX/root-specific skips. |
| Isolated diagnostic privacy probe | Six passed after local fix | The unchanged probe previously had five failures; synthetic data only. |
| Diagnostic regression coverage | 57 unit tests and two added app-widget tests passed | Included in the full suite; mock preferences/fake audio, not installed acceptance. |
| Dependency alignment | 21 probe packages match client versions/origins/hashes | Offline enforced client pub get passed; existing preference interface dependency declared for tests without a version change. |
| Linux systemd recovery fixture | Eight runtime checks passed | Isolated WSL2 fixture, not a production host. |
| Docker signature/runtime/Trivy gate | Passed; zero HIGH/CRITICAL; 14 OS packages | Exact local amd64 image, fresh DB, valid signature/JSON/SARIF; no suppressions. |
| Old-image/new-image volume acceptance | 13 runtime checks passed | Same service code, different runtime packaging; no schema rollback claim. |
| Checked-in Compose smoke | Passed | Isolated project/volume, ephemeral loopback port, compiled probe and hardening checks. |
| Native Windows client storage | Seven checks passed | Production backend and locked SQLite; not installed Flutter. |
| Native Linux client storage | Ten checks passed | Seven process/storage checks plus three real bounded exhaustion cases. |

The retained Windows recovery evidence also records 17 successful checks; it was
not rerun during this score refresh. The prior Windows client build was blocked
by the host's symlink/Developer Mode prerequisite. No OS setting was changed.
No physical devices, production TLS endpoint, production container deployment,
physical disk exhaustion/failure, signing identity, or published release was
assumed available. The Linux filesystem-full test used only a disposable tmpfs.

### Coverage Is Not Readiness

| Local Flutter scope | Covered / executable lines | Coverage |
|---|---:|---:|
| Overall (Windows) | 31,060 / 42,154 | 73.68% |
| Overall (Linux) | 31,062 / 42,154 | 73.69% |
| Native snapshot backend | 131 / 136 | 96.32% |
| Flutter storage directory adapter | 2 / 4 | 50.00% |
| Library store (latest Windows run) | 4,840 / 5,126 | 94.42% |
| Offline cache manager | 312 / 352 | 88.64% |
| Offline cache queue worker | 70 / 72 | 97.22% |
| Offline cache foreground coordinator | 117 / 130 | 90.00% |
| Library sync client | 574 / 755 | 76.03% |
| Playback audio engine | 145 / 348 | 41.67% |
| Home screen (Windows) | 3,832 / 9,814 | 39.05% |
| Local diagnostic log | 178 / 178 | 100.00% |
| Video playback screen | 0 / 146 | 0.00% |

These are executable-line counts, not branch, native-plugin, acoustic, or
complete application coverage. Widget tests deliberately use a test-only
preferences fixture; separate tests instantiate the production file backend.
The native three-process fixture uses real plugins but its execution is not
merged into this unit/widget LCOV report.
The 70% CI floor is satisfied, but it cannot compensate for weak coverage of a
music application's core playback paths.

## Release Acceptance Order

1. Review and commit the complete local hardening candidate, including new
   files and the now-tested diagnostic privacy fix, then pass all required
   cross-platform CI on that exact revision.
2. Validate client data survival, interrupted migration, constrained storage,
   foreground/background writers, and representative large libraries.
3. Record installed real-media, lifecycle, sync, codec, and accessibility
   acceptance across the platforms actually included in the release.
4. Validate deployed restore ownership/permissions, different-version rollback,
   representative load, off-host backups, and measurable recovery objectives.
5. Repair operational audit configuration; demonstrate probe and alert delivery
   and an effective vulnerability policy without weakening required checks.
6. Sign/notarize, verify, install/upgrade, and publish the exact accepted build
   through a controlled rollout with a tested rollback path.

These are acceptance criteria, not automatic point awards. A 90+ assessment
requires compelling native, release, and operational evidence. Even 100/100
would mean satisfying this defined rubric at that time, not defect-free software
or 100% MetroList feature parity.

## Evidence Files

- `build/readiness-audit-2026-09-05/score-review-flutter-tests.log`
- `build/readiness-audit-2026-09-05/score-review-flutter-analysis.log`
- `build/readiness-audit-2026-09-05/score-review-server-tests.log`
- `build/readiness-audit-2026-09-05/score-review-server-analysis.log`
- `build/readiness-audit-2026-09-05/score-review-python-tests.log`
- `build/readiness-audit-2026-09-05/score-review-platform-tests.log`
- `build/readiness-audit-2026-09-05/score-refresh-flutter-tests.log`
- `build/readiness-audit-2026-09-05/score-refresh-server-tests.log`
- `build/readiness-audit-2026-09-05/score-refresh-python-tests.log`
- `build/readiness-audit-2026-09-05/diagnostic_privacy_probe_test.dart`
- `build/readiness-audit-2026-09-05/diagnostic-privacy-probe.log`
- `build/readiness-audit-2026-09-05/diagnostic-privacy-probe-final.log`
- `build/readiness-audit-2026-09-05/diagnostic-final-flutter-tests.log`
- `build/readiness-audit-2026-09-05/diagnostic-final-analysis.log`
- `build/readiness-audit-2026-09-05/diagnostic-python-tests.log`
- `build/readiness-audit-2026-09-05/score-refresh-mobile-tests.log`
- `apps/mobile/coverage/lcov.info`
- `build/readiness-audit-2026-09-05/score-refresh-linux-server-tests.log`
- `build/readiness-audit-2026-09-05/score-refresh-linux-python-tests.log`
- `build/readiness-audit-2026-09-05/linux-verification/sdk-evidence.json`
- `build/readiness-audit-2026-09-05/server-runtime-recovery-linux/runtime-recovery.json`
- `build/readiness-audit-2026-09-05/server-runtime-recovery-final/runtime-recovery.json`
- `build/readiness-audit-2026-09-05/container-gate-cleanup-verified/summary.json`
- `build/readiness-audit-2026-09-05/container-gate-cleanup-verified/runtime/runtime.json`
- `build/readiness-audit-2026-09-05/container-volume-upgrade-final/runtime.json`
- `build/readiness-audit-2026-09-05/distroless-windows-python-tests.log`
- `build/readiness-audit-2026-09-05/client-storage-windows-final/runtime.json`
- `build/readiness-audit-2026-09-05/client-storage-linux-final/runtime.json`
- `build/readiness-audit-2026-09-05/client-storage-full-flutter-tests.log`
- `build/readiness-audit-2026-09-05/linux-native-acceptance-final2/`
- `build/readiness-audit-2026-09-05/linux-native-final-flutter-tests.log`
- `build/readiness-audit-2026-09-05/linux-native-final-analysis.log`
- `build/readiness-audit-2026-09-05/linux-native-final-lcov.info`
- `build/readiness-audit-2026-09-05/native-acceptance-windows-final-tests.log`
- `build/readiness-audit-2026-09-05/native-acceptance-python-final.log`
- `build/readiness-audit-2026-09-05/linux-native-final-source-comparison.json`
- `build/readiness-audit-2026-09-05/linux-native-final-source-manifest.json`
- `build/readiness-audit-2026-09-05/linux-native-final-container.json`
- `build/readiness-audit-2026-09-05/linux-native-final-packages.log`
- `build/readiness-audit-2026-09-05/cache-handoff-windows-verified.log`
- `build/readiness-audit-2026-09-05/cache-handoff-linux-final-tests.log`
- `build/readiness-audit-2026-09-05/cache-handoff-linux-final-run.log`
- `build/readiness-audit-2026-09-05/cache-handoff-linux-lcov.info`
- `build/readiness-audit-2026-09-05/cache-handoff-native-final/`
- `build/readiness-audit-2026-09-05/cache-handoff-python.log`
- `build/readiness-audit-2026-09-05/cache-handoff-source-comparison.json`
- `build/readiness-audit-2026-09-05/cache-handoff-source-manifest.json`

Linux executable SHA-256:
`4698695a94ca8e1fc5e5058efff4fe2df376191fe620f8251f704f6ad8ac701b`.
Backup helper SHA-256:
`c3b8c33c17da48d9c938f6a6ca5329b9655e1078e597447ef34c152bbb736740`.
Accepted local container image ID:
`sha256:cbe28735c3b8e3ea7e3ae55873fdf64b19fd2f5daf887c792753253ca80c022a`.
The runtime artifact correctly leaves sourceCommit unset: this is modified local
source, not a clean published commit. These ignored build artifacts should be
replaced by retained CI artifacts when a reproducible candidate is published.
