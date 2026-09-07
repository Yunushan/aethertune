# Production Readiness Assessment

## Publication Update: 2026-09-07

PR #20 has merged into `main` at
`e25bf1718056cd889565838a9547407d61b0f733`. Its
[post-merge CI run](https://github.com/Yunushan/aethertune/actions/runs/34125664745)
passed, along with CodeQL, OSV, and container scanning on that SHA. The findings
below describing the old `c95f7ac` main and unpublished fixes are historical;
they must not be presented as an assessment of the current main. The full
production-readiness goal remains incomplete. Passing CI does not establish
signed installation, physical-device acceptance, or deployed operations.
See [the September 7 checkpoint](PRODUCTION_READINESS_CHECKPOINT_2026-09-07.md)
for the new authenticated load/restart gate and its bounded Windows/Linux results.

## Current Decision: 2026-09-06, 18:12 UTC

**Published GitHub main: 54/100. Unpublished local candidate: 73/100,
provisional. Neither is ready for broad production distribution.**

Scope: the Android, iOS, Linux, macOS and Windows client plus optional hosted
sync. These are weighted engineering judgments, not test-coverage percentages,
security certifications, reliability probabilities or MetroList feature parity.
The main score applies to `c95f7acadacd6a5048e080ac6edd1b4143206769`, rechecked
against the GitHub API. Local fixes must not be credited to that published SHA.

### Priority Findings

1. **High, published main: silent persistence failures.** Library and queue
   saves ignore failed preference-write results. Retained failure-injection
   evidence shows an operation returning normally while its state disappears
   after reopening. Local snapshot, serialization and recovery fixes have
   regression coverage but are unpublished.
   [Published library save](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10409).
2. **High, published main: cache path escape.** Imported cache identifiers enter
   destination paths without containment validation. Malicious imported state
   can therefore write outside the intended cache directory within the user's
   filesystem permissions. Local containment fixes are unpublished.
   [Destination construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L119).
3. **Medium, published main: credential lifecycle/privacy defects.** Recovered
   managed tokens omit configured expiration; device rename also drops it.
   Local fixes preserve expiry, but previously issued indefinite tokens need an
   explicit operator decision. Retained diagnostic-sanitization findings also
   have local fixes; old diagnostic exports are not retroactively sanitized.
   [Recovery token creation](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/services/server/lib/src/authentication.dart#L591).
4. **Release gate, both candidates:** there are no published GitHub releases.
   Signed clean installation, upgrade and rollback on every advertised platform,
   physical mobile audio/lifecycle tests and full accessibility acceptance are
   not demonstrated. Passing builds and generated product illustrations do not
   establish these results.
5. **Hosted-service gate:** latest live production probe and alert jobs are
   skipped. The load smoke covers 80 requests to four public routes, not sustained
   authenticated sync. Independent-host restore and measured RPO/RTO remain
   unproven. Published PR container scanning reports findings without failing
   on vulnerabilities (`--exit-code 0`).
   [Published scan policy](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/.github/workflows/container-scan.yml#L44).

### Local Gate Now Passing

The active TLS-cleanup regression is **resolved in the current local app**,
not merely in a separate prototype. The application now uses the vendored,
patched native streaming transport, with bounded decoded responses and explicit
request cancellation. The original peer-disconnection assertion remains active.
New tests also reproduced and fixed an invalid-method native process abort.
The historical sections below saying the prototype is unintegrated or the
application still has one TLS failure are superseded by this section.

The subsequent real-application Sandbox run found a configuration regression:
omitting TLS settings selected bundled WebPKI roots, not the platform verifier
as previously assumed. A valid guest-trusted certificate failed in the actual
executor while both explicit-platform and explicit-fixture-root diagnostic
clients passed. The executor now explicitly selects platform verification;
certificate/hostname checks remain enabled. The unchanged positive and negative
controls pass in a fresh guest after this fix.

| Verification | Latest evidence |
|---|---|
| Full local Flutter suite | 1,246 passed, four existing Windows symlink-privilege skips, zero failures |
| Strict Flutter analysis | No issues, 23.1 seconds |
| Focused transport/callback/limit tests | 26 passed, including the original TLS-cleanup regression |
| Native Rust unit tests | Four passed |
| Python CI contracts | 200 discovered, 193 passed, seven platform skips |
| Exact CI formatter scope | 407 files, zero changes |
| Dart executable-line coverage | 31,530/42,549 = 74.10%; not native, branch or device coverage |
| Server suite and analysis | Retained 16:55 evidence: 102 passed, analysis clean; not rerun for transport integration |
| Windows release build | Passed; rebuilt after detecting a stale plugin registry |
| Current unsigned Windows ZIP | Runtime/native manifests and hashes passed; 32 native modules, including `rhttp.dll` |
| Integrated app in fresh Windows Sandbox | Nine contract checks passed; three normal native-close phases passed with external peer-observed cleanup |
| Native Cargo audit | 276 dependencies, zero vulnerabilities/warnings against retained 1,239-advisory database |

The first integration build's success was not accepted: inspection found that it
omitted `rhttp.dll`. Locked plugin regeneration and the second build corrected
the bundle. The ZIP verifier now rejects packages missing this required native
library. The newest ordinary ZIP includes the explicit platform-trust fix;
its SHA-256 is
`66381fd1844c20e23988bec43e875f70bc1eed29a58c9c487f083533563e2b32`.
This proves payload packaging, not application signing or installed operation.

The audit database was not freshly fetched; its retained commit is
`5a0ebedfe8bdd2e295b171f4162f8c977bcad9a5` (2026-09-02). This is a bounded native
dependency check, not a clean scan of the entire application or server image.
The generated native SBOM is an all-target Cargo lock inventory, not a claim
about the exact linked graph of every platform release.

New integrated-application Windows Sandbox evidence passes real startup, trusted
HTTPS UTF-8 upload/status/authorization and redirect handling, untrusted-root and
hostname rejection before HTTP credential delivery, three stalled TLS deadlines
and three independent Dart-isolate round trips. TLS deadlines and peer cleanup
complete in 301-302 ms. During TLS/header/body stalls, an external peer verifies
the request remains active before native window close. Process exit and peer
disconnect then complete in 138-149 ms with exit code zero, no forced kill and
the packaged `rhttp.dll` loaded. There are no recorded framework/native errors.

The first guest was stopped after authoritative inspection found an interactive
synthetic user-root import warning. Later guests use only their disposable
machine certificate store and clean it up before shutdown. Host trust stores
were untouched. Fresh Sandbox CLI inventory is empty, and only verified leftover
owned test windows were closed; no unrelated guest was stopped.

Broader retained Windows evidence has 31 media/storage exercise and seven
process-reopen checks. It predates this transport integration and is not credited
as a fresh combined acceptance run. Other platform builds, physical mobile
background/lifecycle, installed upgrade, accessibility, signed distribution and
production operations remain incomplete. Normal Windows release output was
rebuilt after the guarded probe; the user's host app profile was never launched.

### Weighted Score

| Area | Maximum | Published main | Local candidate |
|---|---:|---:|---:|
| Product implementation | 15 | 9 | 11 |
| Data durability and recovery | 15 | 5 | 11 |
| Security and privacy | 15 | 6 | 12 |
| Automated quality assurance | 15 | 12 | 13 |
| Device and accessibility validation | 10 | 4 | 7 |
| Release engineering and distribution | 10 | 6 | 6 |
| Operations and recovery evidence | 10 | 6 | 7 |
| Maintainability and documentation | 10 | 6 | 6 |
| **Total** | **100** | **54** | **73** |

The passing transport gate strengthens local evidence without an automatic
score increase: adopting a maintained native fork adds all-platform validation
and maintenance obligations. The score remains provisional until those checks
are complete. No amount of feature breadth averages away a data-loss defect or
an unmet mandatory release criterion.

### Release Decision And Next Gates

Use the local candidate only for controlled alpha evaluation with backups and
non-sensitive test data. Before public production distribution:

1. Review and publish the complete local safety fixes through green exact-commit
   CI, including native build, scanning, packaging and license inventory.
2. Exercise that exact integrated candidate on all five supported platforms,
   including native teardown, interrupted networking and real mobile lifecycle.
3. Retain signed/notarized clean-install, migration, upgrade, rollback and
   accessibility evidence for every advertised release platform.
4. For hosted sync, demonstrate real alert delivery, representative authenticated
   sustained load and independent-host recovery against explicit RPO/RTO.
5. Complete a bounded pilot/soak and retain its exact-commit evidence.

No commit, push, merge, repository-setting change, signing or production
deployment was performed. Live main ordinary CI remains green at `c95f7ac`,
but that does not validate the unpublished diff. Branch protection was not
revalidated. These results are not an exhaustive security or device audit.

Evidence: [native acceptance verification and 679 selected input hashes](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-native-acceptance-2026-09-06/verification.json),
[fresh integrated-application guest result](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-native-acceptance-2026-09-06/sandbox-d/evidence/result.json),
[before-fix certificate diagnostics](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-native-acceptance-2026-09-06/sandbox-c/evidence/certificate-diagnostics.json),
[live main CI](https://github.com/Yunushan/aethertune/actions/runs/33869551283),
[skipped production probe](https://github.com/Yunushan/aethertune/actions/runs/34043668849),
[skipped alert delivery](https://github.com/Yunushan/aethertune/actions/runs/34043671047).

## Historical Audit: 2026-09-06, 16:55 UTC

Everything below records earlier execution states. Current results and the
release decision are in the section above; earlier failure counts and statements
that application code was unchanged do not describe the subsequent integration.

**Decision: published GitHub main 54/100; unpublished local checkout 73/100,
provisional. Neither is ready for broad production distribution.** The score
covers the Android/iOS/Linux/macOS/Windows client and optional hosted-sync
service, not just CI or feature count. It is an engineering assessment, not a
reliability probability, security certification, or MetroList parity percentage.

This request was an audit only. Fresh GitHub API reads and local Git both identify
`c95f7acadacd6a5048e080ac6edd1b4143206769`. All 535 selected application, test,
script and configuration hashes still match the retained source manifest.
There are 152 modified/untracked entries; published main does not receive credit
for fixes that exist only in this working tree.

### Highest-Priority Findings

1. **High, published main:** library and queue persistence ignore failed
   preference-write results. Imported offline-cache IDs also enter destination
   paths without containment checks. Source was rechecked against HEAD; earlier
   synthetic failure/path-escape reproductions remain relevant. Local durability
   and containment fixes pass their regressions, but are unpublished.
2. **Medium, current local candidate:** the real transport regression still
   fails during stalled TLS-handshake cleanup. The caller times out, but peer
   disconnection is not observed within two seconds. This does not establish an
   infinite leak. The isolated native transport prototype is not integrated and
   earns no application-readiness credit.
3. **Medium, published main:** recovered tokens omit the configured expiration;
   renaming a device also drops it. Diagnostic sanitization misses credential
   formats. Local fixes are present, but existing indefinite tokens and old
   diagnostic exports require separate consideration.
4. **Release blockers:** no published releases were returned. Signed clean
   install, upgrade and rollback acceptance across all advertised platforms,
   physical mobile audio/lifecycle tests, and full accessibility acceptance are
   not demonstrated. Retained Windows native checks are useful bounded evidence,
   not an installed all-platform release campaign.
5. **Hosted-service blockers:** latest production probe/alert runs are skipped.
   The load smoke sends 80 requests to four public routes, not representative
   authenticated sync traffic. Off-host recovery and measured RPO/RTO remain
   unproven. Published PR container scanning is report-only (`--exit-code 0`).

### Fresh Verification For This Request

| Check | Result |
|---|---|
| Full local Flutter suite | 1,229 passed, four skips, one TLS-cleanup failure; 81 seconds |
| Strict Flutter analysis | No issues; 11.1 seconds |
| Strict server analysis and full suite | No issues; 102 tests passed |
| Python CI contracts | 180 passed, seven platform skips, 187 discovered |
| Native-wrapper generator tests | 11 passed |
| Exact CI formatter scope | 403 files, zero changes |
| Dart executable-line coverage | 31,489/42,505 = 74.08%, 201 files; suite still fails |
| Published main ordinary CI | All six jobs successful on c95f7ac |
| GitHub releases | Zero |

The four Flutter skips require Windows symbolic-link privileges. Coverage is
not branch/native/device coverage: measured audio-engine coverage is 41.67%,
background-runner coverage 3.33%, and Windows media-session coverage 0%.
Separate native evidence must be considered alongside, not replaced by, these
unit-suite figures. The retained Windows guest result has 31 exercise checks
and seven process-reopen checks; it predates the local sync transport change.

No application code, dependencies, workflow configuration, branch, repository
settings, or existing user work was changed. Native builds/Sandbox runs, signed
installation, physical devices, live vulnerability scans and production
operations were not rerun. Branch-protection settings were not revalidated.

Fresh logs and hashes: [audit verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-requested-deep-audit-2026-09-06/verification.json).
The detailed findings, weighted rubric and retained evidence follow. Older
times and intermediate outcomes below are historical, not new executions.

## Retained Detailed Assessment

Reassessed 2026-09-06 at 15:59 UTC for the explicit scoring request.
Transport feasibility follow-up: 16:40 UTC; scores and application gate unchanged.
Full automated suites were run at 15:13 UTC; all 535 selected application,
test and configuration inputs and seven test logs were reverified unchanged.
Partial application sync remediation remains at its 15:00 UTC state.
Retains native application evidence from 14:13 UTC.

**Published GitHub main: 54/100. Current unpublished local candidate: 73/100,
provisional. Neither is ready for broad production distribution.**

**Current gate status:** strict analysis and formatting pass, but the full
Flutter suite now has **1,229 passes, four skips and one failure**. The new
failing regression detects an existing TLS-handshake socket-cleanup gap.
HTTP response deadlines are fixed locally; the complete transport acceptance
gate is not green. The local score remains provisional and is not increased.

This assessment supersedes the earlier same-day score and verification summary.
The local candidate is a development/controlled-alpha candidate, with backups
and non-sensitive test data. It should not be the only copy of a user's library.

The numbers are weighted engineering judgments, not reliability probabilities,
security certifications, test coverage, or percentages of MetroList parity.
Differences of a few points are approximate. A known data-loss defect or a
failed mandatory gate cannot be averaged away by feature breadth.

## Latest Scoring Verification

The explicit scoring review leaves application code, dependencies, Git branches,
and GitHub settings unchanged. All **535 selected source/test inputs** match the
15:01 manifest. Local HEAD and the freshly queried GitHub main still identify
`c95f7acadacd6a5048e080ac6edd1b4143206769`; the worktree has **152 modified or
untracked entries**. The score does not credit those unpublished fixes to main.

Freshly executed checks for this request:

| Check | Result |
|---|---|
| Full Flutter suite with coverage | 1,229 passed, four skips, one TLS-handshake cleanup failure; 79 seconds |
| Strict Flutter analysis | Passed, no issues; 10.7 seconds |
| Strict server analysis and full tests | Passed, no issues; all 102 tests passed |
| Python CI contract discovery | 187 discovered, 180 passed, seven platform skips |
| Native-wrapper generation regressions | All 11 passed |
| Exact CI formatter scope | 403 files, zero changes |
| Current failing suite's Dart line coverage | 31,489 / 42,505 = 74.08%, across 201 files; not passing acceptance |

The four Flutter skips concern Windows symbolic-link privileges. The failed TLS
test is active and was neither suppressed nor changed. Its caller times out,
but the fixture does not observe peer disconnection within two seconds. This
is evidence of unsuccessful prompt cleanup, not a measured infinite leak.

Fresh GitHub API reads confirm all six jobs in the ordinary main CI run passed,
zero published releases, and skipped latest production probe/alert runs. Branch
protection was not revalidated in this request; the earlier unauthorized read
does not establish that protection is enabled or disabled.

Source review reconfirmed the published unchecked preference-write results,
imported cache destination construction, token-expiry omissions, and report-only
PR container scan, and their corresponding local changes. The load smoke still
targets 80 requests to four public routes with eight workers; it is not sustained
authenticated synchronization capacity testing. Widget storage uses a fixture;
the separate retained native durability results provide different, bounded
evidence and must not be conflated with the full widget suite.

Native builds, Sandbox acceptance, physical devices, signed installation,
live vulnerability scanning and real production operations were not rerun.
The retained native packages predate the current transport change. No new points
are awarded merely for repeating checks or adding an audit report.

Complete fresh logs, source comparison, result counts and log hashes:
[requested audit verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-deadlines-2026-09-06/requested-audit-verification.json).
Detailed findings, rubric and the release criteria follow below.

## Latest Isolated Transport Evidence

The follow-up investigation strengthens the diagnosis but does not fix the
application or raise its score. A standalone executable compiled from the
actual application HTTP helper reproduced failed TLS socket cleanup in a clean
Windows Sandbox on all three attempts. Callers timed out after 302-315 ms;
the peer remained connected through the following two-second observation.
A positive TLS control using a synthetic CA passed in that same guest.
Consequently, the cleanup failure is not explained solely by the host's
antivirus HTTPS interception, which affected separate host certificate tests.
Certificate validation and host trust settings were not weakened.

An isolated `rhttp` 0.18.0/Rust prototype passed six TLS cancellation/timeout
checks and certificate, hostname, redirect and authorization controls in a
second clean guest. Its upstream native lockfile, however, had two vulnerability
advisories and one unsoundness warning. Updating only the prototype's `h2`,
`quinn-proto` and `anyhow` lock entries, then rebuilding its native DLL, yielded
zero advisories/warnings with `cargo audit --deny warnings` and repeated the
passing guest controls. The isolated database contained 1,239 advisories at
commit `5a0ebedfe8bdd2e295b171f4162f8c977bcad9a5`; this is not an application
dependency scan or release attestation.

The earlier four-pass/two-fail bounded-stream prototype has been corrected:
native cancellation happens before Dart subscription cancellation, and the
subscription remains observed until its terminal event. Further testing found
two callback-lifecycle races, both reproduced as failing regressions. Limiting
native cancellation to network waits prevents an in-flight Dart callback from
returning into a dropped Rust receiver. Both regressions now pass.

The isolated source copy also adds an optional native decoded-stream byte limit.
It rejects declared oversize bodies and checks cumulative chunks before copying
them into Dart's event queue, including gzip expansion. This is deliberately a
stream-response setting, not a claim that every upstream response API is bounded.
The copy retains upstream MIT notices and the Android process-context fix from
upstream commit `9871f1c25d0cf75553af85698b9f03d38f438aed`.

Verification: **19 Dart/native tests pass twice**, all four native unit tests
pass, the complete candidate Dart library and selected probe/tests pass strict
analysis, and the selected eight Dart formatter inputs have zero changes.
The corrected test logs contain neither callback-return nor stream-post warnings.
The native lockfile is unchanged from the patched, clean 276-dependency audit.

A newly built guarded Windows release probe uses the **streaming API** and
9 MiB native limit. Its fresh clean guest passes six TLS cancellation/timeout
checks, valid-certificate decoding, untrusted-root and hostname rejection,
redirect refusal and authorization preservation. Cancellation takes 0-19 ms
after the peer accepts; native timeouts take 300 ms. Peers disconnect in every
case. The guest exits successfully with empty output logs, and its launcher has
exited. The exact accepted package and built harness source are retained; a
subsequent braces-only lint correction to the guarded harness is separate from
that accepted package. Native transport package sources did not change after
the build.

This candidate is ready for **application-integration work, not production**.
No application dependency, SDK/cache source, application code or active
regression was changed. All 535 selected application/configuration/test inputs
and the 35 existing application plugin junctions remain unchanged. A fresh
application transport recheck still reports **nine passes and one TLS-cleanup
failure**. Adoption still needs maintained source/dependency ownership, native
build and scan integration, real application request/retry contracts, engine
teardown testing, and all supported-platform validation. No score increase is
awarded for a separate prototype.

Fresh GitHub reads at 15:59 UTC reconfirm main at `c95f7ac`, all six ordinary CI
jobs successful, and zero published releases. The newest
[production probe](https://github.com/Yunushan/aethertune/actions/runs/34043668849)
and [alert run](https://github.com/Yunushan/aethertune/actions/runs/34043671047)
are again skipped. The three owned experimental Sandbox launchers have exited.
The readiness recommendation remains **54/100 published; 73/100 provisional
local**, with no broad production release recommendation.

Evidence: [original helper in a clean guest](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/sandbox-a/evidence/transport.json),
[patched prototype TLS controls](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/sandbox-c/evidence/native.json),
[remaining prototype stream failures](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/stream-c.log),
[follow-up verification manifest](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/verification.json).

Latest evidence: [stream candidate verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/native-stream-verification.json),
[repeated 19-test pass](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/native-callback-repeat.log),
[clean streaming TLS guest](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/sandbox-d/evidence/native.json),
[unchanged application's active failure](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/application-transport-still-open.log).

## Scope And Method

The assessed scope is the declared Flutter Android/iOS/Linux/macOS/Windows
player and optional Dart hosted-sync service. Offline-only distribution can
exclude server operations, but not the client safety and installation gates.
Spotify/YouTube metadata integrations are not evidence of full service playback.

GitHub API reads, reconfirmed during the 14:26-14:32 UTC audit, and local Git agree on main/HEAD:
[`c95f7acadacd6a5048e080ac6edd1b4143206769`](https://github.com/Yunushan/aethertune/commit/c95f7acadacd6a5048e080ac6edd1b4143206769).
There are 152 modified/untracked status entries at the latest audit. Important
local fixes are not part of the GitHub repository users clone.

Work performed for this reassessment: targeted source and diff review of
persistence, offline files, authentication, diagnostics, video lifecycle,
platform initialization, CI, packaging, and operations; fresh analysis and
automated suites; verification of the latest ordinary Windows release packages;
inspection of retained isolated native results and actual guest application and
video screenshots. Follow-up work fixed bounded video startup and cleanup races,
added nine widget regressions and real trickling-HTTP acceptance, and included
integration tests in all formatter gates. The latest native run finished at
14:13 UTC. Earlier failed runs remain retained as evidence.
Archived library/cache/diagnostic source used by the earlier defect probes was
rehash-checked with Git's line-ending filters against HEAD and still matches its
Git blobs. The current source review also reconfirmed the save-result, path
construction, recovery-token expiry and container-scan policy findings below.

This was not an exhaustive line-by-line audit, an independent penetration test,
a fresh all-platform device campaign, or an installed release certification.
The 13:47 assessment was read-only apart from its report/evidence; subsequent
remediation changed video lifecycle code, tests and formatter gates. The latest
readiness review leaves application code untouched: it reruns analysis, full
Flutter/server/Python suites, wrapper tests and formatting; verifies 534 selected
source hashes against the earlier acceptance manifest; and reproduces the
additional sync-response deadline defect below with real loopback HTTP. No commit, push, merge,
review-policy change, signing, production deployment, or real-profile app
launch was performed. GitHub branch-protection inspection returned HTTP 401;
earlier protection observations were not independently reconfirmed here.

## Priority Findings

### 1. High: Published library and queue saves can silently lose changes

Published library persistence awaits preference setters but ignores their
boolean results. Related sections are separate writes. The retained isolated
probe rejected 35 writes: adding a track returned normally and showed one
track in memory, but reopening showed zero. The queue probe similarly reported
successful named-queue creation after a rejected write, then lost it on reopen.
These are concrete failure-path defects, not deductions inferred from coverage.

Sources: [published library save](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10409),
[published queue save](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/player/player_controller.dart#L1913).

Local status: revision-checked library and player snapshots, serialized writes,
rollback, explicit recovery, and retained legacy values are implemented with
passing regressions. The retained 12:50 UTC Windows guest run additionally
passed real preference migration and process-restart checks for library,
playlists, active/named queues, and playback settings. The newer 13:35 UTC run
passes these again. This is stronger than
mocked widget storage, but does not prove power-loss durability or installed
migration on every supported platform.

Sources: [file commit](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/file_library_storage.dart:167),
[player state store](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/player/player_state_store.dart:51),
[native reopen evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-player-state-2026-09-06/native-sandbox-a/evidence/reopen.json).

### 2. High: Published imported cache identifiers can escape the cache folder

The published downloader constructs destination filenames directly from an
imported entry ID. The retained synthetic probe processed a crafted backup
entry and replaced a disposable sentinel outside `offline_media`. Exploitation
requires the crafted entry to be imported and processed, and is limited by the
application's filesystem permissions. This is not evidence of remote code
execution, actual user-file damage, or a compromised production system.

Source: [published destination construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L118).

Local status: validated IDs, portable hashed names, directory containment,
link rejection, and regressions are present. Four Windows tests still skip
because creating symbolic links is unavailable in the test context. A hostile
process changing filesystem entries concurrently is not fully modeled by these
checks. Do not equate passing lexical/link tests with a sandbox boundary.

Source: [local destination verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_paths.dart:64).

### 3. High: Published native startup has defects; local fixes need release acceptance

Earlier isolated Windows runs exposed missing release C++ runtimes in packages
and native-incompatible media-key payloads. Packaging/hotkey fixes remain local.
The later actual ZIP did start in a clean guest and native media keys worked.
The published iOS wrapper also initializes background plugin/channel handlers
before starting the Flutter engine; the local generator corrects the ordering.
That iOS finding is source-verified, not a physical-device crash reproduction.

Sources: [published hotkeys](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/ui/widgets/desktop_global_hotkeys.dart),
[published iOS generator](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/scripts/configure_audio_service_platforms.py#L1604),
[local native payload fix](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/ui/widgets/desktop_global_hotkeys.dart:160).

### 4. Medium: Published token-expiry and diagnostic privacy defects remain

Published recovery-token creation omits `expiresAt`; device renaming also fails
to preserve the deadline. Null expiry is accepted as indefinite authentication.
This requires an existing valid credential/recovery flow, not an unauthenticated
attacker inventing a token. Local issuance/preservation regressions pass, but
previously issued indefinite credentials need separate operator review.

The published diagnostic sanitizer misses several invented OAuth/Subsonic/JSON
credential formats in retained probes. Exposure requires credential-bearing
text to reach diagnostics and then local access or an explicit export. There
is no evidence of real secret leakage or automatic diagnostic uploading here.
Local allowlisted diagnostics and legacy cleanup do not erase past exports.

Sources: [published recovery issuance](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/services/server/lib/src/authentication.dart#L593),
[published sanitizer](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/local_diagnostic_log.dart#L158),
[local expiry preservation](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/src/authentication.dart:737),
[local diagnostic policy](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/local_diagnostic_log.dart:9).

### 5. Medium: Published sync waits are unbounded; local TLS cleanup is unresolved

The published `executeLibrarySyncHttpRequest` configures a 15-second connection timeout, but
neither waiting for response headers nor streaming the body has a response-idle
or total-operation deadline. The byte limit does not protect against a server
that stops sending data. `LibrarySyncStore._runBusy` clears its busy flag only
after the awaited operation settles; a stalled request can therefore block
subsequent sync operations until the connection closes or the process restarts.
The UI-state consequence is source-reviewed, not a separate device reproduction.

The bounded audit probe exercised the real client HTTP transport against two
disposable loopback responses: one withheld headers, the other sent an opening
JSON byte and withheld the remainder. Both were still pending after **35.012
seconds**, despite already accepting their connections. Both returned HTTP 200
only after the fixture explicitly resumed them. This confirms the missing
response deadline; the probe does not claim it observed an infinite duration.
No credentials, real sync account or external endpoint were used.

At the 14:33 assessment both files matched published HEAD. The subsequent local
transport change retains the 15-second connection bound, adds 30-second
request/header and response-idle limits and a two-minute total deadline, and
force-closes the request's client on every exit. Redirect refusal, UTF-8
validation and the response byte limit remain enforced. The store itself is
unchanged; real-HTTP settings tests now show busy-state reset, no premature
credential persistence, credential-safe errors and a successful subsequent retry.

Five new regressions failed before the deadline implementation. Nine of the ten
new tests now pass. A separate production-default real-HTTP probe observed header
expiry at **30.012 seconds**, body-idle expiry at **30.010 seconds**, and total
expiry at **120.002 seconds** while 599 chunks continued arriving. The peer
observed connection closure in all three HTTP cases.

The remaining strict regression times out the caller during a stalled TLS
handshake, but the accepted peer socket does not close within the following two
seconds. Reading the pinned Dart 3.12.2 SDK implementation confirms that its
secure connection task delegates cancellation to the underlying connection
attempt; that does not establish cancellation after TCP connection has already
completed. A separate owned-isolate experiment also observed isolate exit without
peer disconnection within five seconds. No isolate workaround, custom TLS stack,
certificate bypass, SDK edit or test skip was introduced. This remains a required
cleanup fix, not a completed transport gate or proof of an infinite observation.

Sources for this follow-up: [transport regressions](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/library_sync_transport_test.dart:14),
[strict TLS regression](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/library_sync_transport_test.dart:50),
[default deadline evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-deadlines-2026-09-06/default-deadlines.json),
[full suite failure](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-deadlines-2026-09-06/flutter-tests.log).

Sources: [HTTP transport](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_sync_client.dart:1954),
[busy-state lifecycle](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_sync_store.dart:742),
[defect evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-score-review-2026-09-06/sync-deadline-probe.json),
[reproduction fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-score-review-2026-09-06/library_sync_deadline_probe_test.dart).

### 6. Analysis And Video Pass; Complete Suite Has One Active TLS Failure

Fresh strict Flutter analysis is clean. The full suite now reports **1,229
passed, four Windows symlink-privilege skips and one TLS-cleanup failure**.
All 20 video widget tests still pass. The former protected-member warnings, tooltip cast and two
fake-async timeouts no longer occur. Retry tests now allow Dart root-zone stream
cancellation to complete, and explicitly verify old-player disposal; they do
not remove the lifecycle assertions or extend a failing timeout.

The later regressions reproduced five additional gaps before remediation:
unbounded open, accepting open before a rendered frame, missing-frame timeout,
stalled cleanup, and a source-change race that could allocate a new player
before old disposal completed. The corrected route applies a 30-second total
startup deadline through first frame and caption setup. It waits at most ten
seconds for prior disposal, retains that future across retries, and creates no
successor until disposal reports success. Cancellation ends stale UI waits;
it does not falsely claim cancellation of native work.

Sources: [video tests](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/video_playback_screen_test.dart:54),
[fresh analysis](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/fixture-analysis-b.log),
[fresh full test log](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/flutter-tests.log).

The formatter now checks **403 files with zero changes**, including integration
tests. CI, release, Makefile and local-check commands include that directory,
with a policy regression guarding every formatter command. The existing
onboarding fixture received formatting-only changes.

### 7. Native Acceptance Gate: Bounded Windows passes, wider device coverage missing

The latest 14:13 UTC Windows Sandbox run passes **31 exercise checks and seven
process-reopen checks**, followed by ordinary application startup observed for
15 seconds. It uses real native plugins and a disposable guest profile, not the
widget suite's preference-backed storage fake.

- Real WAV decode, advancing position, seek and OS media-key transport passed.
- H.264/MP4 and VP9/WebM controls decoded and rendered changing red/green frames;
  both decoded screenshots and Flutter texture pixels were checked. Pause,
  seek and resume passed for each format.
- A corrupt MP4 produced visible error/retry controls without a stuck spinner.
  Repairing the same disposable source file and activating Retry created a new
  player and passed real decode, pixel, pause, seek and resume checks.
- Unsupported APNG now produces a visible error instead of indefinite loading.
  This is correct failure handling, not a claim of APNG playback support.
- Real vault, library/playlist, active/named queue and playback-setting state
  survived process restart. No framework errors were recorded.
- A guest-loopback HTTP server trickled valid MP4 media. The default native
  backend reported an error after 5.370 seconds; the UI recovered via Retry and
  a new request, with actual decoded/rendered frames and transport checks.
- A separate real-native fault-injection case extended only the fixture's
  backend socket timeout from five to 60 seconds. With no native error event,
  the app's first-frame deadline fired after 30.075 seconds. Retry again passed
  actual HTTP, frame, pause, seek and resume checks. Production backend timeout
  settings were not changed.

The synthetic media generator independently decoded all 160 frames per standard
video control with its development-only FFmpeg tool. FFmpeg was not added to
the application package. Loaded-module evidence did not observe the excluded
debug-dependent `zlib.dll` or debug CRTs on these exercised paths. This does not
prove every codec/profile or dynamic-loading path is safe.

The first follow-up run failed a fixture expectation: it required the default
backend to wait 30 seconds, but that backend failed earlier. The final run
separately verifies the default failure and the independently fault-injected
watchdog case; it does not count an early error as proof of the app's deadline.

Sources: [final guest result](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/sandbox-b/evidence/result.json),
[exercise evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/sandbox-b/evidence/exercise.json),
[restart evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/sandbox-b/evidence/reopen.json),
[native deadline timing](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/sandbox-b/evidence/video-deadline-timeout.json),
[rendered retry](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/sandbox-b/evidence/video-deadline-retry-desktop.png).

The bounded waits do not guarantee that a malfunctioning native backend can
always release its resources. Failed/pending disposal prevents another player
on the same route; it is not a forced native termination mechanism. Loopback
HTTP does not establish Internet/TLS/proxy behavior or every stalled operation.

Physical Android/iOS background execution, interruptions, Bluetooth routing,
screen lock, power management, accessibility, and long-running playback remain
acceptance gaps. Widget sizing/RTL tests and native helper tests cannot replace
the real operating-system and assistive-technology workflows.

### 8. Distribution Gate: No demonstrated signed install/upgrade/rollback matrix

The fresh [GitHub releases API](https://api.github.com/repos/Yunushan/aethertune/releases)
returns an empty array. The retained latest ordinary Windows release build
passes, and the newest ZIP/unsigned MSIX contain the updated video route.
Fresh verification of the final probe ZIP, ordinary ZIP and unsigned MSIX
passes runtime/native inventory and hash checks. Ordinary ZIP and MSIX native
manifests match. These are unsigned candidate artifacts, not verified production
signatures. The ordinary executable was rebuilt after the probe build so the
release output directory is not left pointing at the test entrypoint.

Signing/notarization workflows and unsigned packages are useful engineering
work, not proof of signed clean installation, existing-user migration, rollback,
store acceptance, or reproducible builds. Obtain retained acceptance artifacts
for every platform actually included in the production release.

Source: [ordinary build log](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/production-b-build.log),
[fresh artifact verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06/artifact-verification.json).

### 9. Operations Gate: Monitoring, capacity, and off-host recovery lack evidence

Latest live [production probe](https://github.com/Yunushan/aethertune/actions/runs/34043668849)
and [alert delivery](https://github.com/Yunushan/aethertune/actions/runs/34043671047)
runs are skipped, not successful observation or delivery. This can be an
intentional pre-production configuration; it earns no operational acceptance
credit. The successful [recovery workflow](https://github.com/Yunushan/aethertune/actions/runs/34020573129)
does not establish restoration onto an independent host or production RPO/RTO.

The server has authentication, account isolation, body limits/deadlines, rate
limiting, optimistic revisions, and controlled recovery tests. The checked-in
load smoke sends only 80 requests with eight workers to health/readiness/info/
catalog routes. It does not exercise sustained authenticated sync uploads,
large libraries, realistic storage pressure, or TLS-proxy deployment behavior.

Published PR/push container scanning uses `--exit-code 0`; its fail-closed job
only runs on schedule/manual dispatch. A green report job is therefore not a
guarantee that HIGH/CRITICAL findings block merging. Local code strengthens this
policy, but no fresh live vulnerability scan of the current release image was
performed. Mocked scanner tests are not a clean vulnerability report.

Sources: [load test](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:17),
[published scan policy](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/.github/workflows/container-scan.yml#L45),
[controlled server recovery](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-token-expiry-2026-09-06/runtime/runtime-recovery.json).

### 10. Maintainability: Large modules and critical coverage blind spots

The home screen has 23,438 physical lines and the library store 10,980. This
concentrates responsibilities and raises review/regression cost; line count
alone does not prove a bug. Prefer incremental extraction after release-safety
fixes, not a broad stabilization-time rewrite.

The last passing full suite's Dart executable-line coverage is
**31,467 / 42,499 = 74.04%** across 201 files. The current full suite has one
failure; its generated coverage is not a passing readiness gate. Three of 204
library Dart files are absent: `main.dart`, the provider SDK
barrel, and `music_catalog_discovery_provider.dart`. Native code, branch coverage,
device behavior, and whole-product feature coverage are not represented.

| Component | Covered / measured lines | Coverage |
|---|---:|---:|
| File library backend | 132 / 136 | 97.06% |
| Library store | 4,840 / 5,126 | 94.42% |
| Player controller | 1,289 / 1,472 | 87.57% |
| Player state store | 65 / 68 | 95.59% |
| Audio engine | 145 / 348 | 41.67% |
| Video screen | 96 / 202 | 47.52% |
| Background queue runner | 2 / 60 | 3.33% |
| Windows system media session | 0 / 77 | 0.00% |

Video's line coverage comes from mocked widget tests. It is not evidence of
native video decoding; the separate Sandbox supplies that bounded evidence. Zero
ordinary Dart coverage does not erase separately observed native behavior.

## Weighted Score

| Area | Maximum | Published main | Local candidate |
|---|---:|---:|---:|
| Product implementation | 15 | 9 | 11 |
| Data durability and recovery | 15 | 5 | 11 |
| Security and privacy | 15 | 6 | 12 |
| Automated quality assurance | 15 | 12 | 13 |
| Device and accessibility validation | 10 | 4 | 7 |
| Release engineering and distribution | 10 | 6 | 6 |
| Operations and recovery evidence | 10 | 6 | 7 |
| Maintainability and documentation | 10 | 6 | 6 |
| **Total** | **100** | **54** | **73** |

The strongest credit is for real feature implementation, regression breadth,
bounded server APIs, credential-vault integration, pinned dependency/workflow
tooling, local durability remediation, and partial real native execution.
The largest deductions concern published data safety, unverified device and
distribution paths, and operational evidence.

Relative to the 13:13 UTC provisional 72 local score, QA regains one point for
clean strict analysis and a fully passing suite; native validation gains one
point for supported-format rendering, repaired-source retry and repeated real
restart acceptance. These passes do not clear physical-device, accessibility,
signed installation or operations gates. Published main receives no credit for
unpublished fixes. The 14:17 deadline/cleanup and formatter follow-up strengthens
existing QA/native credit without another point increase: signed installations,
physical devices and operational acceptance are still missing.

The 14:33 review reduces product-reliability credit by one point in each column
because the additional real HTTP probe confirms a shared, unresolved sync hang.
The earlier 55/74 figures are historical, not the current recommendation.
This small numerical change is approximate; the important new result is a
concrete failure path not detected by the otherwise passing main test suite.

The 15:00 follow-up fixes the HTTP wait/cleanup cases but exposes an unresolved
pre-HTTP TLS cleanup limitation. The provisional score is not increased while
that strict regression remains failing. No published score change is justified
by an unpublished partial fix.

## Fresh Verification

| Check | Current result |
|---|---|
| Flutter strict analysis, fatal infos | Passed: no issues |
| Full Flutter suite | 1,229 passed; 4 Windows symlink-privilege skips; 1 active TLS-cleanup failure |
| Video widget suite | All 20 included tests passed |
| Dart formatting, including integration tests | Passed: 403 files, zero changes |
| Formatter/toolchain policy | Nine tests passed with expanded integration-directory assertions |
| Measured Dart line coverage | Last passing suite: 74.04%; current failing suite is not acceptance |
| Server strict analysis | Passed in 15:13 audit; unchanged since |
| Full server suite | 102 passed in 15:13 audit; unchanged since |
| Python CI discovery | 15:13 audit: 187 discovered; 180 passed; 7 platform skips |
| Platform-wrapper regressions | 15:13 audit: 11 passed; unchanged since |
| Latest retained Windows release build | Passed; no host-profile app launch |
| Latest Windows native acceptance | 31 exercise + 7 reopen checks; ordinary window alive 15 seconds |
| Fresh Windows candidate package verification | Probe ZIP, ordinary ZIP, unsigned MSIX passed payload checks; no signature claim |
| Live GitHub main | Same c95f7ac SHA; ordinary CI jobs successful |
| Live release/operations state | No published releases; latest probe and alert skipped |
| Live branch-protection settings | Unverified this pass: HTTP 401 |
| Original real HTTP negative probe | Before fix: header/body stalls remained pending after 35 seconds |
| Production-default HTTP deadlines | Passed at 30/30/120 seconds, with peer-observed disconnects |
| TLS-handshake cleanup | Failed: timed-out caller does not promptly close accepted peer socket |

The latest local remediation evidence is in
[the sync-deadline directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-deadlines-2026-09-06).
It retains the five original regression failures, the nine-pass/one-fail focused
run, the full-suite result, the separate default-limit acceptance, and the
unsuccessful isolated TLS workaround experiment. The active TLS test was not
skipped, weakened or converted into an expected failure.

The 14:33 rerun's complete logs, LCOV and sync negative probe are in
[the score-review evidence directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-score-review-2026-09-06).
The full Flutter suite passes again in 81 seconds; coverage remains 31,467 of
42,499 measured lines (74.04%). Its fresh LCOV SHA-256 is
`f3b07c3019b7564bd6d5d64ad427c4c7a87bbced6d66ee8f6b8fa036746509b2`.
The negative probe was run separately without coverage and intentionally asserts
the existing defect. It is not included in the 1,220 passing application tests.
All retained source-manifest entries were unchanged at that 14:33 audit. The
subsequent transport change and its new tests are not in those earlier packages.
Native builds, Sandbox
acceptance, signing, containers and physical devices were not rerun in this pass.
The live main CI run has all six jobs successful:
[aethertune-ci](https://github.com/Yunushan/aethertune/actions/runs/33869551283).

The original audit remains in
[the audit evidence directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-review-final-2026-09-06).
Follow-up source hashes, tests, coverage, build/package and native evidence are in
[the deadline acceptance directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06).
Its `source-manifest.json` fingerprints 534 selected inputs after verification;
the subsequent comparison reports no changes. It is not a complete build
environment or signed provenance manifest. Fresh LCOV SHA-256:
`1a2ce2ea15d66144f99e2489728092b81bc86b29c0f4ca99c2b650b7080f0a3c`.

The latest isolated native and packaging evidence is in
[the deadline acceptance directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06).
The successful guest result identifies these exact inputs:

- Final probe ZIP: `e04495f72bf3d7350c9fdac13bd248a5861fc3e340cd1a5ae4468823a7cbf5ce`.
- Ordinary ZIP: `07e44db73be16323380c7a7d4e5e76461936b8c17839a49b47d75572105556cf`.
- Separately verified unsigned MSIX: `babdb553f970aa2dbd2e4c116a87282f5d71a2a8bf2f9317615f1b0cc072bb54`.

Some Python negative fixtures deliberately print fake failed build/scan/cleanup
reports. Their enclosing suite passes; these are not fresh Docker findings or
unclosed real processes. Earlier compiled server recovery evidence was not
rerun for this client change. Both owned follow-up Sandboxes shut down, and
final inventory was empty; no unrelated guest or real user profile was touched.

## Release Criteria

1. Review and publish the data-safety, credential/privacy, native startup, and
   packaging fixes through a green exact-commit CI run. Restore the complete
   local gate by fixing TLS-handshake cleanup; do not weaken or skip its failing
   regression merely to permit a merge. Local tests are not GitHub acceptance
   of an unpublished diff.
2. Extend the bounded native passes to installed migration/recovery,
   Internet/TLS/proxy failure behavior and physical-device audio/lifecycle tests.
3. Produce signed/notarized artifacts and verify clean install, upgrade, rollback,
   and accessibility on each advertised production platform.
4. For hosted sync, demonstrate real alert delivery, representative sustained
   authenticated load, and off-host restore against explicit capacity/RPO/RTO.
5. Retain exact-commit evidence and a bounded pilot/soak result before broad rollout.

100/100 would mean satisfying all agreed criteria for an explicitly scoped
release with traceable evidence, not proving that software can never fail.
