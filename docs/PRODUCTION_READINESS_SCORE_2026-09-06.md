# Production Readiness Assessment

Latest assessment: **55/100 published main; provisional 73/100 local checkout**.
The [current deep review](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/PRODUCTION_READINESS_FINAL_2026-09-06.md)
documents the local safety and player-state fixes, native video timeout,
two formatting failures and remaining release and operational acceptance gaps.
The scores and records below are historical and are superseded by that review.

## Earlier Follow-up: 2026-09-06

**Published GitHub main: 59/100. Current unpublished local tree: provisional
72/100. The project is not ready for a broad production release.**

This follow-up supersedes the local score and current-state claims in the
initial audit below; that audit is retained as a historical record of its
reproductions and failed test run. Scores are approximate weighted engineering
judgments, not reliability probabilities, test coverage, or MetroList parity.

| Area | Maximum | Published main | Current local tree |
|---|---:|---:|---:|
| Product implementation | 15 | 11 | 12 |
| Data durability and recovery | 15 | 6 | 11 |
| Security and privacy | 15 | 7 | 12 |
| Automated quality assurance | 15 | 12 | 13 |
| Device and accessibility validation | 10 | 4 | 4 |
| Release and distribution | 10 | 7 | 7 |
| Operations and recovery evidence | 10 | 6 | 7 |
| Maintainability and documentation | 10 | 6 | 6 |
| **Total** | **100** | **59** | **72** |

The two restored local points are limited to correcting the verified iOS
startup-order defect and restoring the ordinary full-suite quality gate. New
helper tests and a fresh Linux fixture do not establish mobile acceptance or
earn release, physical-device, or production-operations credit. Packaging and
release points reflect implemented safeguards, not successful distribution.

### Latest Recovery and Windows Verification

Two additional local UI defects were reproduced and fixed: the destructive
recovery confirmation overflowed at 3x text scale, and the save-failure notice
could exceed the entire available height. The dialog is now scrollable; the
notice has its own scroll area capped at half the available height. Its error
text is a semantics live region.

Five new regressions cover 320x480 and 480x320 recovery layouts in both text
directions, confirmation cancellation, labeled/minimum-size touch targets, and
a reachable, working reload action with a semantics announcement. All nine
recovery tests pass. Rendered large-text states were inspected using a real
font. These are widget/semantics tests, not Narrator, TalkBack, VoiceOver,
localization, or full-app accessibility acceptance.

The latest exact-source Windows suite passes **1,171 tests, with four existing
symlink-privilege skips**. Strict analysis with fatal infos is clean. Coverage is
**31,096/42,205 lines (73.68%)**, across 199 Dart files. All **389** files in the
new client source manifest still match after verification. Only the recovery UI
and its test differ from the earlier Linux source manifest; the dependency
lockfile was restored byte-for-byte after a tool-only formatting rewrite.

The real Windows debug app also compiled successfully with the installed Flutter
3.44.6 and Visual Studio 2026 toolchain. The initial build failed on unavailable
symlink privileges; 35 verified junctions in ignored Flutter plugin directories
allowed the ordinary build to proceed without changing Developer Mode, SDK
source, or host privileges. The 35-file debug bundle is hashed, including
`aethertune.exe` SHA-256
`f1b9726bb1ef11d1db8f442b9291dc3c9398315e4f9d56928b28d0a6ca5f9ac4`.
This is native compilation, not signed packaging or installed acceptance.

A Windows Sandbox preflight eventually produced a readiness record as
`WDAGUtilityAccount`, then shut down. Networking, clipboard, microphone, camera,
and printer redirection were disabled; only the disposable evidence folder was
mapped. The launcher is gone and the final CLI inventory is empty. This verifies
an available isolation environment, not execution of AetherTune inside it. The
app was not launched against the user's Windows profile or URL registration.

Evidence:
[build/readiness-windows-native-2026-09-06](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-windows-native-2026-09-06).
The earlier full Linux suite/native fixture below predates this UI change and
was not rerun for it. No extra readiness points are awarded for a debug build or
these narrow accessibility fixes; broader device, release, and operations gates
remain open.

### Earlier Background Startup Verification

The native generator now starts the iOS background engine before plugin and
channel-handler registration, with cleanup and an early return on startup
failure. Android disables automatic constructor registration and explicitly
registers plugins once. Generator regressions reject unsafe initialization and
missing failure cleanup. The real-I/O handoff test now initializes a binding
without replacing its loopback HTTP client with Flutter's fake client.

The earlier local shutdown work adds a ready/stop/drain protocol, serialized
foreground handoff, and native timeout/forced-termination handling. Architecture
documentation now matches that implementation. This is not a claim that the
protocol has been exercised with actual Android/iOS scheduling and plugins.

| Check | Evidence for the earlier startup candidate |
|---|---|
| Ordinary Windows Flutter suite | 1,166 passed; 4 symlink-privilege skips |
| Ordinary Linux Flutter suite | 1,170 passed; no skips |
| Strict Flutter analysis on both hosts | No issues; fatal infos enabled |
| Python CI discovery | 171 discovered; 164 passed; 7 platform skips |
| Native generator regressions | 11 passed, including initialization mutations |
| Exact generated shutdown helpers | 14 Kotlin and 14 Swift scenarios passed |
| Generated iOS AppDelegate | Swift syntax parse passed; no framework typecheck |
| Generated Android job service | Kotlin compilation against actual Flutter engine and Android API 36 declarations passed; not a full APK/plugin build |
| Real Linux app fixture | Seed, migration, reopen, credentials, native decoding and MPRIS checks passed |
| Source comparison | All 396 manifested input files matched SHA-256 between host and Linux stage |

That candidate's Dart line coverage was **31,091/42,200 (73.68%) on Windows** and
**31,093/42,200 (73.68%) on Linux**, across 199 reported files. These passing
runs replaced the initial failed run; the earlier failed logs
are retained. Native framework code and branch/end-to-end coverage are excluded.

The native Linux fixture produced decoded PCM in a private virtual sink:
1,593,694 samples, peak 5,000, RMS 566.36, and 40,564 active samples. Its reopen
image was inspected and nonblank. This is not physical acoustic, Bluetooth,
mobile background, signed installation, or full desktop acceptance evidence.

The full Android build remains unverified: Gradle failed before app compilation
with a host Java loopback/Unix-domain-socket connection error. The partial Kotlin
check used API 36, while the generated project's compile SDK floor is 37. It
checked the actual registrar's declarations, not its Java plugin-registration
bodies. No Android device was attached. Swift helper execution and source parsing
on Linux do not substitute for an iOS build or device run.

Evidence is under
[build/readiness-native-startup-2026-09-06](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-startup-2026-09-06).
The source manifest scopes only its 396 listed inputs, not every dirty repository
file or generated wrapper. The Linux test container had no host mounts, ports,
or devices. A public certificate matching this host's installed Avast TLS root
was installed only in that disposable container after hostname/chain validation;
TLS verification was not disabled and no host trust settings or private keys
were changed. No fixture processes remained at inspection, and the exact Linux
and Swift containers were removed after collecting evidence.

### Published State and Outstanding Gates

Live GitHub still reports main at
`c95f7acadacd6a5048e080ac6edd1b4143206769`, a protected branch with eight
required contexts, and no published releases. A new September 6
[backup/rollback drill](https://github.com/Yunushan/aethertune/actions/runs/34020573129)
passed; its job log exercises temporary-file fixtures, not an off-host production
restore or the unpublished local backup helper. Production probe/alert runs are
still skipped. These observations do not justify additional operations credit.

The highest-priority remaining requirements are publishing the reviewed
data-safety, path-containment, and diagnostic-privacy fixes; verifying the exact
candidate through CI; actual mobile lifecycle/audio and installed upgrade tests;
signed/notarized distribution; accessibility acceptance; and working production
monitoring with measured recovery and capacity objectives. No commit, push,
merge, signing, deployment, or protection change is claimed by this follow-up.
The readiness-to-100 goal remains incomplete.

## Initial Audit Record

Assessment date: 2026-09-06. Scope: Android, iOS, Windows, macOS and Linux
Flutter clients, plus the optional self-hosted Dart server.

**Published GitHub main: 59/100. Unpublished local working tree: provisional
70/100. Neither is ready for a broad production release.**

These are weighted engineering judgments, not reliability probabilities,
security certifications, test-coverage percentages, or MetroList feature parity.
Treat differences of a few points as approximate. Confidence is higher in the
specific findings than in the exact scores.

The local tree is materially safer, but should remain a controlled alpha using
backed-up, non-sensitive data. Its improvements do not change what users obtain
from GitHub. A passing isolated probe does not make the ordinary failing suite
green, and compiling a native helper does not validate the app on a device.

## Repository State

- Live GitHub main and local HEAD both resolve to
  `c95f7acadacd6a5048e080ac6edd1b4143206769`.
- Main's six build/test CI jobs passed. The public branch response confirms
  protection and eight required check contexts. Full administration, bypass,
  environment and secret configuration were not independently inspected.
- The live releases API returned an empty array.
- The checkout already had 61 modified tracked files and numerous untracked
  implementation, test and audit files. This assessment preserved those changes.
- This review changed no application code, original tests, workflows, repository
  settings or branches. It created this report and ignored audit artifacts only.
  No commit, push, merge, signing or deployment occurred.

Sources: [main](https://github.com/Yunushan/aethertune/tree/c95f7acadacd6a5048e080ac6edd1b4143206769),
[main CI](https://github.com/Yunushan/aethertune/actions/runs/33869551283),
[branch API](https://api.github.com/repos/Yunushan/aethertune/branches/main),
[releases](https://github.com/Yunushan/aethertune/releases).

## Findings

### 1. High: Published library writes can silently lose data

Reproduced against archived HEAD source during this assessment: a preference
backend rejected **35 writes**, but adding a track returned normally. The live
store contained one track; reopening contained zero. Related library sections
are written independently and setter results are ignored.

A separate malformed-JSON probe produced `FormatException`, `loaded=false`,
and `loadError=null`, rather than a usable recovery state.

[Published save implementation](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10409).

Local status: snapshot commits, revision conflicts, error propagation, rollback
and a recovery UI are implemented, with passing regular regressions. The
backend hash still matches retained Windows/Linux process-interruption evidence.
These fixes remain unpublished. Directory-metadata durability under power loss
and installed migration across the complete platform matrix remain unproven.

[Local backend](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/file_library_storage.dart:167).

### 2. High: Published imported cache IDs can escape the media directory

The fresh isolated probe restored a crafted cache entry and materialized it
using an injected downloader. The resulting path was outside `offline_media`
and overwrote a disposable sentinel file. No actual user file or network service
was involved. Exploitation requires importing/processing a crafted entry and is
limited by the application's filesystem permissions.

[Published path construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L118).

Local status: ID validation, portable hashed filenames, directory containment
and link rejection are implemented. Their Windows link tests remain skipped
because this host lacks the required symlink privilege. Retained earlier Linux
evidence covers those cases, but is not a fresh full-current-tree Linux run.

[Local path checks](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_paths.dart:20).

### 3. High: iOS background engine initializes channels before running

Both published and local native generators call plugin registration and
`configureOfflineCacheChannel` before `engine.run(...)`. The latter installs a
non-null message handler before the engine shell is ready. Flutter's source at
the repository's exact SDK revision asserts in that case; with assertions
disabled it returns an error connection without installing the handler.

This is a source-verified startup-order defect, not an observed physical-device
crash. It can prevent the background task's plugins/channel from working, so the
new stop/ready protocol cannot yet be credited as working iOS integration.

[Local generator](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/configure_audio_service_platforms.py:1892),
[published generator](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/scripts/configure_audio_service_platforms.py#L1604),
[pinned Flutter implementation](https://github.com/flutter/flutter/blob/ee80f08bbf97172ec030b8751ceab557177a34a6/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm#L1223).

Required: initialize/run the engine successfully before plugin/channel handler
registration, preserve startup-failure cleanup, then exercise actual background
start, expiration, cancellation and rapid foreground return on iOS. Pure Swift
shutdown-state tests do not cover this framework boundary.

### 4. Medium: Published diagnostic exports can retain credentials

Fresh probes used invented secrets and `example.invalid` addresses. Plain
`token=...` was redacted, but five other formats remained in both preference
storage and exported JSON: OAuth access/refresh tokens, Subsonic password/token
URL parameters, and a quoted JSON token field.

Exposure requires credential-bearing error text reaching the logger and local
access or an explicit export. This does not establish that real credentials have
leaked or that the app uploads diagnostics automatically.

[Published logger](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/local_diagnostic_log.dart#L158).

Local status: v2 stores allowlisted categories and source locations instead of
raw error payloads, and removes legacy reports. Its regular tests pass. Existing
exports and OS backups cannot be assumed erased by this migration.

[Local logger](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/local_diagnostic_log.dart:10).

### 5. Medium: The current local test suite is red

Fresh result: **1,165 passed, four skipped, one failed**. The failure is
`native stop reply waits for resolver file writes and saved requeue`.
It reads `TestDefaultBinaryMessengerBinding.instance` before initializing a
binding. This is a test-harness defect, not proof of a production drain failure.

[Failing test](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/offline_cache_handoff_io_test.dart:36).

An isolated wrapper initialized a test binding and reran the original tests
without editing them. Default binding initialization made the new test pass but
caused the neighboring real-HTTP test to fail because Flutter replaces HTTP with
a fake client. A binding overriding `overrideHttpClient` to false made all four
original tests pass, including the real loopback transfer.

Required: fix setup while preserving actual I/O, rerun the unmodified full-suite
command, and retain green results for the exact final candidate. The audit
wrapper is diagnostic evidence only; the repository's ordinary suite still fails.

### 6. High Release Gate: Installed-device and release evidence is incomplete

There are no published GitHub releases. Signed/notarized release workflows and
artifact checks exist, but configuration is not evidence of successful signing,
clean-machine installation, upgrades, rollback or store distribution.

The local tree adds a background shutdown handshake and portable Kotlin/Swift
state tests. Retained logs show 14 scenarios passing in each language, explicitly
excluding OS scheduling and Flutter engine acceptance. The newest iOS defect
demonstrates why that distinction matters.

Missing acceptance includes physical Android/iOS audio interruptions, Bluetooth,
background/process termination, representative codecs, installed upgrades,
Windows/macOS native behavior, and app-wide assistive-technology/text-scaling
checks. Earlier Linux real-plugin, WAV/MPRIS and virtual-audio evidence is useful
but does not establish those other targets or hardware paths.

[Release workflow](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/aethertune-release.yml:651),
[native helper test scope](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_native_background_shutdown.py).

### 7. Medium: Production operations are not demonstrated as active

The latest inspected probe and alert runs on September 6 at 04:52 UTC are
**skipped**, not successful production checks. The inspected governance audit
failed because its token argument/environment was empty. Its workflow maps that
value from `AETHERTUNE_GOVERNANCE_TOKEN`.

[Probe](https://github.com/Yunushan/aethertune/actions/runs/34012586613),
[alert](https://github.com/Yunushan/aethertune/actions/runs/34012592618),
[failed governance audit](https://github.com/Yunushan/aethertune/actions/runs/33384426481).

Main's PR/push container scan uses `--exit-code 0`; its fail-closed job is limited
to scheduled/manual runs. A green report job therefore does not prove that image
vulnerabilities are an enforced merge/release gate. The local replacement adds
fail-closed CI/release enforcement and a signed Distroless base, but is unpublished.
Its retained September 5 scan passed with zero blocking findings for that image
and database; no new container scan was run in this assessment.

[Published scan policy](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/.github/workflows/container-scan.yml),
[local gate](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/scan_server_container.py).

The server has real authentication, account isolation, rate limiting, bounded
bodies, revision conflicts and coordinated backup code. Its load smoke test sends
80 small requests with eight workers; this does not establish sustained
authenticated-upload capacity, large-account workloads or TLS-proxy limits.
Local recovery fixtures do not establish production recovery-time/recovery-point
objectives or off-host restoration under representative load.

[Load fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:17),
[request protections](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/server.dart:498).

### 8. Medium: Coverage and maintenance leave expensive blind spots

Fresh local executable-line coverage is **31,091 / 42,200 = 73.68%**, across
199 reported files. It was emitted by a run with one failing test; this is not
a passing quality gate. It excludes native framework code and is not branch or
end-to-end coverage.

| Component | Covered / measured lines | Coverage |
|---|---:|---:|
| File library backend | 132 / 136 | 97.06% |
| Library store | 4,840 / 5,126 | 94.42% |
| Player controller | 1,145 / 1,361 | 84.13% |
| Playback audio engine | 145 / 348 | 41.67% |
| Background queue runner | 2 / 60 | 3.33% |
| Video playback screen | 0 / 146 | 0.00% |
| Windows system media session | 0 / 77 | 0.00% |

The new Dart shutdown session itself reaches 100% line coverage, yet this does
not exercise iOS engine startup. A high aggregate percentage cannot substitute
for tests at these integration boundaries.

The local home screen has **23,437 physical lines** and the library store
**10,980**. Concentrated responsibilities increase review/regression cost.
Architecture text still says provider resolution is abandoned on cancellation
and iOS has no explicit handshake, while the current code now waits for the
resolver and implements a handshake. This documentation needs reconciliation,
without claiming native validation that has not occurred.

[Stale architecture section](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ARCHITECTURE.md:223),
[current resolver behavior](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_queue_worker.dart:102).

## Weighted Score

| Area | Maximum | Published main | Local tree |
|---|---:|---:|---:|
| Product implementation | 15 | 11 | 11 |
| Data durability and recovery | 15 | 6 | 11 |
| Security and privacy | 15 | 7 | 12 |
| Automated quality assurance | 15 | 12 | 12 |
| Device and accessibility validation | 10 | 4 | 4 |
| Release and distribution | 10 | 7 | 7 |
| Operations and recovery evidence | 10 | 6 | 7 |
| Maintainability and documentation | 10 | 6 | 6 |
| **Total** | **100** | **59** | **70** |

Compared with the September 5 assessment (60 main / 72 local), the newly
identified iOS engine-order defect removes one product point from each state.
The reproducibly red ordinary local suite removes one local QA point. Existing
verified safety improvements retain their credit; extra helper tests alone do
not complete native/release acceptance. Release points reflect implemented
packaging, signing and preflight safeguards, not a completed public release.

## Verification and Limits

Fresh checks in this review:

| Check | Result |
|---|---|
| Full Windows Flutter suite with coverage | 1,165 passed; 4 symlink-privilege skips; 1 test-binding failure |
| Strict Flutter analysis, fatal infos enabled | No issues |
| Server tests | 87 passed |
| Strict server analysis, fatal infos enabled | No issues |
| Python CI unit discovery | 171 discovered; 164 passed; 7 platform-specific skips |
| Native-platform generator tests | 8 passed |
| Published library defect probes | All three reproduced their expected defects |
| Published diagnostic privacy probes | Control passed; five redaction assertions failed |
| Isolated I/O-preserving binding probe | All four original handoff I/O tests passed |
| Live GitHub reads | Main SHA, six successful main CI jobs, eight required contexts, empty releases, skipped probe/alert and failed governance evidence |

The published defect probes import files extracted by `git archive HEAD`, not
the modified production files. They run with the local resolved dependency
environment, not a complete pristine platform build. Their invented inputs and
disposable sentinel use no actual credentials or user library. The three library
probes intentionally assert the vulnerable behavior; their success means the
defect was reproduced, not that the implementation is safe.

Retained evidence was read but not rerun: September 5 native storage interruption,
Linux real-plugin playback, server recovery/systemd/container fixtures, and
September 6 portable Kotlin/Swift shutdown tests. The storage backend and probe
lock hashes were rechecked and still match the retained Windows/Linux reports.
The earlier entire-client Linux manifest is not proof for the newly modified
client. The previous server runtime report also has an older backup-helper hash;
it must not be presented as an exact-current-tree rerun.

No physical-device test, installed signed build, production deployment,
live-provider compatibility campaign, fresh vulnerability scan or independent
penetration test was performed. Retained recent Linux bootstrap and Android
Gradle attempts ended with host TLS/IPC errors, not successful current-candidate
native builds. Those environment failures are not evidence of application bugs.

This was a risk-focused deep review with fresh suites, live GitHub reads and
isolated reproductions, not an exhaustive line-by-line review of every module.

## Priorities Before Release

1. Finish and publish the data-safety, cache-path and diagnostic fixes, with
   regression evidence attached to an exact reviewed commit.
2. Correct iOS background initialization and validate real Android/iOS engine
   start/stop, expiration and foreground handoff, including failure cleanup.
3. Fix test binding without disabling real HTTP coverage; get the ordinary full
   suite and required CI contexts green for the final candidate.
4. Validate installed import/playback/sync, recovery, upgrades, accessibility and
   interruptions on each supported platform; prioritize Android/iOS first.
5. Exercise signed/notarized candidate installation and rollback. Keep the
   unsigned-candidate/production distinction explicit.
6. Enable and validate the intended production probes, alerts and governance
   audit; measure realistic capacity and off-host backup restoration objectives.
7. Reconcile architecture claims and reassess with candidate-bound evidence.

More features, closing Dependabot PRs, removing checks or adding an artificial
reviewer will not resolve these findings. A sole-owner project can retain useful
checks without pretending that self-approval is an independent review.

## Evidence Location

New logs and disposable probes are under
[build/readiness-score-2026-09-06](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-score-2026-09-06).
Key files: `flutter-tests.log`, `flutter-analysis.log`, `server-tests.log`,
`server-analysis.log`, `python-tests.log`, `platform-tests.log`,
`published-defect-probes.log`, `binding-probe.log` (initial default-binding
failure), and `binding-io-probe.log` (four passing real-I/O-preserving tests).

Archived published client source SHA-256:
`b90d49d33ea7a2bd572413f64ec9aa62a1cae657d09b1e864be52277a56b7d22`.

The original failed suite remains recorded separately. No passing probe result
has been substituted for it.
