# Production Readiness: Current Assessment

**Superseded:** the [current reassessment](PRODUCTION_READINESS_CURRENT_2026-09-06.md)
reports 54/100 published and provisional 73/100 local, with retained native
video/persistence evidence, partial HTTP deadline remediation and an active
failing TLS-handshake cleanup regression. The
remainder of this file is the historical 12:36 UTC assessment.

Reassessed 2026-09-06, approximately 12:36 UTC.

**Published GitHub main: 55/100. Unpublished local candidate: provisional
73/100. Neither is ready for broad production distribution.**

These are weighted engineering judgments, not reliability probabilities,
security certifications, test-coverage percentages or MetroList feature parity.
Differences of a few points are approximate. A known data-loss defect or an
unverified release gate cannot be averaged away by adding more features/tests.
The appropriate local stage is controlled alpha testing with backed-up,
non-sensitive data, not reliance on it as the only copy of a music library.

## Scope And Repository State

The live GitHub branch and local HEAD both resolve to
[`c95f7acadacd6a5048e080ac6edd1b4143206769`](https://github.com/Yunushan/aethertune/commit/c95f7acadacd6a5048e080ac6edd1b4143206769).
The checkout contains substantial uncommitted implementation, test, workflow
and documentation changes. Local fixes do not improve what GitHub users obtain.

This reassessment combines targeted source inspection, retained isolated defect
reproductions, current full-suite results, a fresh ordinary Windows release
build, earlier same-day packaging/native execution and fresh GitHub reads.
It is not an exhaustive line-by-line review or an independent penetration test.
Existing application work was preserved; this reassessment updates reports,
not application code. No commit, push, merge, signing, production deployment,
credential change or repository protection change was performed.

The score evaluates the declared mobile/desktop player and optional hosted-sync
scope, not whether every feature from MetroList or other inspiration projects
exists. The feature matrix distinguishes implemented and scaffolded features;
for example, Spotify/YouTube integrations deliberately provide official
metadata-only paths, not full music-service playback. README product pictures
are explicitly illustrations, not evidence of installed-device acceptance.

## Priority Findings

### 1. High: Published library and cache paths still have data-safety defects

Retained isolated probes against archived HEAD reproduce two defects: preference
write rejection can silently lose library changes after reopening, and a crafted
imported cache identifier can write outside the private media directory. The
latter overwrote only an invented disposable sentinel in the audit; it is not
proof of remote code execution or compromise of actual user data.

The published implementations remain unchanged at the freshly checked SHA:
[library persistence](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10409),
[cache path construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L118).

Local snapshot/recovery and path-containment fixes have passing regressions,
but remain unpublished. Their presence does not prove physical power-loss
durability, all installed migrations, or safety against a hostile concurrent
process replacing filesystem entries between checks.

### 2. Medium, Published: Saved playback queues silently lose rejected saves

In the retained pre-remediation reproduction, the preference
backend rejected a named-queue write, but `createSavedQueue('Audit queue')`
returned a created queue and exposed it in memory. Reopening from the backend's
actual contents lost that queue. The observed output was:

```text
creationReportedSuccess=true; rejectedWrites=1; survivedReopen=false
```

`_saveQueueSnapshot` awaits preference setters but ignores their boolean
results. Its saved-queue collection and active queue are separate writes.
The same unsafe save implementation still exists in published HEAD. Merely
fixing the library store did not cover this separate persistence path.

Source: [published queue persistence](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/player/player_controller.dart#L1913).

Local status: the candidate now has a separate revision-checked player snapshot,
serialized saves, failure propagation, rollback to durable values, and visible
reload/previous-snapshot recovery. Migration reads the actual preference backend
and retains the original values. Named queues and the active queue commit
together; settings updates preserve other sections. Failed queue saves attempt
to stop playback and restore the durable queue; failed settings saves reapply
the durable settings. Both block further writes until explicit reload. A
rapid-reopen queue-ID collision also has a regression.

The current suite includes 25 additional tests covering store/controller/UI
behavior. Real-file tests verify pre-commit failure preserves exact bytes and
reopening, and previous recovery archives corrupt current bytes. UI tests cover
320x480 and 480x320 layouts, LTR/RTL and 3x text. These pass. Ordinary widget tests
substitute test storage; their success alone is not native migration evidence.
The expanded Windows player-migration/reopen fixture has not been executed
against this new implementation. Physical power-loss durability and installed
cross-platform migration therefore remain open.

Sources: [player state store](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/player/player_state_store.dart:51),
[controller save](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/player/player_controller.dart:2026),
[real-file regressions](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/player_state_store_test.dart:211),
[test storage substitution](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/flutter_test_config.dart:7).

### 3. High Release Gate: Native acceptance is incomplete

The earlier same-day Windows probe passed real native WAV decode/position progress,
seek and guest OS media keys for pause/resume/next/previous. It also passed
synthetic credential round-trip, production plugin startup, legacy library
migration, diagnostic cleanup, native file scanning and library mutations.

The earlier overlapping queue-load failure is corrected locally by serialized,
coalesced native queue loads, with two deterministic regressions. That native
run got beyond that failure without adding a sleep to hide it.

However, the same run **failed in the video stage**, timing out after 30 seconds
waiting for `waitUntilFirstFrameRendered` for the synthetic APNG. Native logs
show a texture created with zero width/height; no decoded/rendered pixel checks
completed. There were no captured Flutter framework exceptions. The failure
screenshot was taken after process exit and shows the guest desktop, not a
validated player UI. Reopen and ordinary-production-startup phases were not
reached in that run. The current ordinary Windows release build succeeds, but
the changed player persistence code and expanded native fixture were not run in
a new Sandbox during this reassessment. The earlier native result must not be
presented as acceptance of the exact current tree.

This establishes an incomplete/failed acceptance test, not its root cause.
The evidence does not distinguish a fixture/codec issue, Sandbox graphics
limitation, initialization race or packaging problem. In particular, it does
not prove the omitted ANGLE `zlib.dll` caused the failure or is universally safe
to omit. Investigate with decoder/error telemetry and a supported video control;
do not mark video working from a build or waive the acceptance condition.

Sources: [native report](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-windows-native-validation-2026-09-06/sandbox-verified/evidence/exercise.json),
[current first-frame check](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/integration_test/windows_native_acceptance.dart:368),
[production video startup](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/ui/video_playback_screen.dart:56).

Physical Android/iOS lifecycle, interruptions, Bluetooth, broad native codecs,
assistive technology, installed upgrades and rollback are still not established.
Native compilation, widget tests and a guest audio clock do not prove those
behaviors or actual speaker output. The published Windows CRT/hotkey startup
defects and iOS background-engine ordering defect have local fixes, not a
published, installed release with cross-platform acceptance.

### 4. Medium: Published credential/privacy safeguards need the local fixes

Retained synthetic probes found credential formats retained by published
diagnostic logging, and recovered/renamed managed server tokens could lose their
expiration. Local allowlisted diagnostic records and expiry-preservation fixes
have regressions. Already-exported diagnostics and previously issued tokens
without deadlines require separate operator review; source changes cannot erase
exports or infer historical token lifetimes.

See the source-linked reproductions in the
[earlier detailed review](PRODUCTION_READINESS_REVIEW_2026-09-06.md).
No real credentials were accessed or rotated in these audit fixtures.

### 5. Release Gate: Signed distribution has not been demonstrated

The live [releases API](https://api.github.com/repos/Yunushan/aethertune/releases)
returns an empty array. Signed/notarized workflows exist, but that is not proof
of successful clean installation, existing-user upgrade, rollback or store
acceptance on the supported platform matrix.

Earlier same-day Windows ZIP and real unsigned MSIX packaging passed, with
matching native payloads and an unchanged source bundle. Those packages predate
the current player-state changes and were not repackaged in this reassessment.
Native policy rejects additional debug CRT names, handles Turkish/English
casing consistently and validates final
native manifests. Package validation checks hashes, complete native inventory,
architecture and ZIP/MSIX consistency. Import classification is produced by
DUMPBIN during trusted packaging, not independently re-parsed by Python.
Cryptographic signature verification remains a separate Windows signing step.

The exact known upstream ANGLE zlib omission is restricted by hash, direct/delay
imports and literal-reference checks. Static checks cannot exclude constructed
dynamic DLL names, and native video acceptance is still failing. These artifacts
are unsigned candidates, not releasable signed builds.

### 6. Operations Gate: Working production monitoring and capacity are unproven

Fresh GitHub reads show the latest
[production probe](https://github.com/Yunushan/aethertune/actions/runs/34023450759)
and [alert workflow](https://github.com/Yunushan/aethertune/actions/runs/34023459924)
are **skipped**, not successful monitoring or delivery. The successful
[recovery drill](https://github.com/Yunushan/aethertune/actions/runs/34020573129)
does not establish representative off-host restoration or production RPO/RTO.

The server has authentication, account isolation, request bounds, rate limiting,
revision checks and recovery tooling. Its checked-in load smoke test makes only
80 requests with eight workers to health/readiness/info/catalog routes, not
authenticated sync writes. It is not evidence of sustained authenticated uploads,
large libraries, realistic concurrency or TLS-proxy behavior. Earlier local
compiled-server evidence passes 21 recovery checks, but explicitly excludes
production RPO/RTO and power loss. A fresh production vulnerability scan was not
performed; fail-closed scanner code and mocked scanner regressions are not a
clean scan of a release artifact.

Sources: [load smoke scope](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:17),
[controlled recovery result](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-token-expiry-2026-09-06/runtime/runtime-recovery.json).

Offline-only client distribution does not require operating the optional sync
server, but still requires the client durability and release gates above.

### 7. Medium: Test blind spots and concentrated code increase maintenance risk

Current reported client executable-line coverage is **31,370 / 42,443 = 73.91%**,
across 201 Dart files. It excludes native code, physical devices and branch
coverage. Three of 204 `lib` Dart files are absent from this LCOV: `main.dart`,
`aethertune_provider_sdk.dart` and `music_catalog_discovery_provider.dart`.
The percentage is for reported executable lines, not all product code or
behavior. The native probe is separately compiled and not part of this LCOV.

| Component | Covered / measured lines | Dart line coverage |
|---|---:|---:|
| File library backend | 132 / 136 | 97.06% |
| Library store | 4,840 / 5,126 | 94.42% |
| Player controller | 1,289 / 1,472 | 87.57% |
| Player state store | 65 / 68 | 95.59% |
| Player save recovery notice | 48 / 48 | 100.00% |
| Audio engine | 145 / 348 | 41.67% |
| Background queue runner | 2 / 60 | 3.33% |
| Video screen | 0 / 146 | 0.00% |
| Windows system media session | 0 / 77 | 0.00% |

Zero ordinary Dart coverage does not mean no native behavior ran, and high
coverage does not establish failure-path correctness. The new queue-save defect
and video timeout illustrate both limits. The home screen has 23,438 physical
lines and library store 10,980; these large responsibility clusters raise review
and regression cost. Decompose incrementally after the immediate safety gates,
not through an unrelated wholesale rewrite during release stabilization.

### 8. CI Gate: Current local formatting check fails

The exact CI-style read-only formatter command exits 1 and reports two files:
`apps/mobile/lib/src/player/player_controller.dart` and
`apps/mobile/test/library_sync_client_test.dart`. It examined 398 files with
`--output=none`; no source files were rewritten. Strict analysis and tests still
pass, but that does not mean the full CI contract is green. Apply the formatter
and rerun the gate before publishing this candidate.

Evidence: [format check](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-player-state-2026-09-06/format-check.log).

## Weighted Score

| Area | Maximum | Published main | Local candidate |
|---|---:|---:|---:|
| Product implementation | 15 | 10 | 12 |
| Data durability and recovery | 15 | 5 | 11 |
| Security and privacy | 15 | 6 | 12 |
| Automated quality assurance | 15 | 12 | 13 |
| Device and accessibility validation | 10 | 4 | 6 |
| Release engineering and distribution | 10 | 6 | 6 |
| Operations and recovery evidence | 10 | 6 | 7 |
| Maintainability and documentation | 10 | 6 | 6 |
| **Total** | **100** | **55** | **73** |

Relative to the preceding 55/72 assessment, tested local player-persistence
remediation restores one durability point. Native validation, release and
operations scores do not increase: there is no new full native acceptance,
signed install, deployment or monitoring evidence. Published main receives no
local-fix credit. The format failure is a concrete merge gate within the existing
QA deductions; it is not comparable in severity to silent data loss.

Credit is strongest for the breadth of real implementation, bounded server APIs,
secure storage integration, regression coverage, SHA-pinned workflows, release
validation tooling and operational documentation. Deductions reflect observed
defects first, then unverified critical paths. A score of 100 would mean passing
all agreed release criteria with traceable evidence for an explicitly scoped
release, not proof that software can never fail.

## Verification And Evidence

Current candidate checks:

| Check | Result |
|---|---|
| Flutter strict analysis, fatal infos | No issues |
| Full Flutter suite with coverage | 1,200 passed; 4 existing Windows symlink-privilege skips |
| Server strict analysis, fatal infos | No issues |
| Full server suite | 102 passed |
| Python CI discovery | 181 discovered; 174 passed; 7 platform skips |
| Platform-wrapper generator regressions | 11 passed |
| CI-style Dart formatting | Failed: two files need formatting; read-only check |
| Real Windows release build | Passed in 42.3 seconds; ordinary `lib/main.dart`, not launched |
| Player-state failure/reopen regressions | Passed; real file, controller and recovery UI tests included in the full suite |
| GitHub branch/releases/workflows | Same main SHA; eight required contexts; no published releases; latest probe/alert skipped |

Retained earlier same-day checks, not rerun for the new player-state code:

| Check | Result |
|---|---|
| Native Windows packaging policy | Passed, including compiled direct/delay import fixtures |
| ZIP/unsigned MSIX payload checks | Passed for earlier artifacts; native payloads match; source bundle unchanged |
| Native Windows fixture | Eight checks completed, then video first-frame timeout; overall failed |
| Compiled server recovery fixture | 21 controlled local checks passed; not off-host production recovery |

Python negative fixtures intentionally print fake failure reports. Those are
test outputs, not fresh Docker findings or production incidents. Retained
compiled-server recovery evidence includes 21 checks, but it was not rerun in
this final pass. Earlier Linux native/audio and storage interruption evidence
is useful historical evidence, not an exact-current-tree all-platform campaign.

Current suite, formatting, wrapper and build logs are under
[build/readiness-player-state-2026-09-06](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-player-state-2026-09-06).
The current ordinary executable was not installed or launched against the real
user profile. Current evidence fingerprints (SHA-256):

- LCOV: `8386ef22ddf8631685ebcdf42e84fd0bb83fa36bd32fba530e1c2f51fb92edc6`.
- Windows executable: `c0a56d6c68ecc2365f03213c864b76030e67f9222a3929c16fd2583ffca7e982`.
- Windows Dart AOT `data/app.so`: `e93113bdf65e1a3823f43a9bfd0b1324ce8026fbc35e2b37f0acef8aabd39c38`.

These fingerprints identify individual outputs; they are not a signed package
manifest or a proof of reproducible builds.

Earlier native artifacts and logs are under
[build/readiness-windows-native-validation-2026-09-06](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-windows-native-validation-2026-09-06).
`final-source-manifest.json` records 535 earlier source, dependency and test
inputs; it predates the player-state changes and is not a manifest of the
current tree or full cryptographic build provenance.

- Probe ZIP SHA-256: `d353649bed98a1046ffa7bd59900629380cc71edb36dd918cc8c53b2b53af9fe`.
- Ordinary ZIP SHA-256: `08015c22ec1f1a2d1a1035cc7d1bd068ef043c2597f715503694c23d39c7a056`.
- Unsigned MSIX SHA-256: `3b63d4822ee74295e48b7c7c96578dd8659d0b4d5359852ab55edbbb5f89c810`.

The Sandbox used only synthetic media/credentials, read-only fixture inputs and
a writable disposable evidence folder. Networking, clipboard, microphone,
camera and printer redirection were disabled. The probe was never launched on
the real user profile. The guest wrote its failed result and shut down; the
subsequent Sandbox inventory was empty. Its observed module union contains no
omitted zlib/debug CRT; that is limited to paths actually exercised.

## Order Of Work Before Production

1. Resolve the two formatting failures, review the unpublished library/player,
   cache, privacy, token, native startup and packaging fixes, then obtain green
   required CI on the exact reviewed candidate. Do not merge away failed checks.
2. Complete native player-state migration and restart acceptance for the new
   persistence path, including failed saves and recovery on installed targets.
3. Diagnose the native video timeout, complete restart/persistence acceptance,
   then exercise supported codecs and physical Android/iOS lifecycle/audio.
4. Validate signed clean installs, upgrades, rollback and assistive-technology
   workflows on each platform being advertised for production.
5. For hosted sync, demonstrate real probe/alert delivery, authenticated sustained
   load and off-host backup restoration against explicit capacity/RPO/RTO targets.

Do not close dependency updates indiscriminately or remove checks to increase
the score. The readiness-to-100 goal remains incomplete.
