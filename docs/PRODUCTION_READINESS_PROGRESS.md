# Production Readiness Progress

Objective: pursue a fully evidenced 100/100 production-readiness assessment of
the mobile and desktop clients and optional self-hosted server. This is not a
claim of bug-free software or a substitute for real release acceptance.

Baseline: `c95f7ac`, assessed on 2026-09-05 at 61/100 in
[the original audit](PRODUCTION_READINESS_AUDIT_2026-09-05.md). That audit remains
a historical record. Its isolated reproduction probes intentionally assert
the former defects; the checked-in regression tests below assert correct
behavior instead.

Latest assessment (2026-09-06, updated 18:12 UTC): **GitHub main 54/100;
local working tree provisional 73/100**. Historical scores and test counts below
describe each pass at its execution time. See
[the current assessment](PRODUCTION_READINESS_CURRENT_2026-09-06.md). Fresh strict
analysis passes. The latest full Flutter suite has 1,246 passes, four platform
skips and no failures. The actual application TLS-cleanup regression now passes
after native transport integration. Dart line coverage is 74.10%.
Python CI discovery passes 193 of 200 tests with
seven skips; retained server and wrapper runs pass all 102/11 tests.
The latest isolated Windows run passes 31 exercise and seven reopen checks,
including MP4/WebM frame pixels, media keys, real persistence, repaired-file
retry and native HTTP error/deadline recovery. The
ordinary application also starts in that earlier guest. Fresh integrated sync
acceptance now passes nine contract checks and three native-close phases with
external peer-observed release in 138-149 ms. The earlier combined media/storage
campaign still predates this integration. A fresh normal Windows build and
unsigned ZIP include the platform-trust fix and pass payload verification.
All 407 formatter inputs pass; integration tests are now included in
CI, release and local formatter commands. Signed installs/upgrades, physical
devices, live operations and exact commit publication remain incomplete. No
commit, push, merge, signing or deployment was performed.

## 2026-09-06: Integrated Windows Trust And Shutdown Acceptance

The preceding turn completed package verification and the requested assessment,
so this continuation moved to the actual integrated application's native gate.
A maintained guarded harness starts the normal app and calls its actual sync
executor. A separate peer process observes native-window shutdown while TLS,
HTTP headers or a response body remain unfinished; the production request
deadlines are unchanged in those controls.

The first fixture attempt stalled at Windows's interactive user-root import
warning. Process inspection proved that condition before stopping only the
owned guest. Subsequent fixtures use the disposable guest's machine root store,
verify the synthetic chain, retain stage markers, remove the root and shut down.
The host trust stores, SDK sources and user application profile remain untouched.

The next two guests exposed a real integration bug: omitted TLS settings select
bundled WebPKI roots inside `rhttp`, contrary to the earlier platform-trust
assumption. The app rejected a valid guest-trusted certificate, while both an
explicit platform-verifier client and an explicit synthetic-root diagnostic
client accepted it. The adapter now explicitly selects platform roots without
disabling certificate or hostname validation. The diagnostic controls never
convert a failed application assertion into a pass.

Fresh guest D passes all nine application contract checks: first frame, trusted
HTTPS UTF-8 upload/status/auth/redirect behavior, untrusted-root and hostname
rejection before HTTP credential delivery, three stalled TLS deadlines with
peer cleanup at 301-302 ms, and three independent isolate requests. Native close
passes separately during TLS/header/body stalls; process exit and peer closure
take 138-149 ms, with code zero and no forced kill. Each close-phase process
loads the exact packaged `rhttp.dll`. Logs show no framework/native errors.

The normal Windows entrypoint was rebuilt after the probe and its unsigned ZIP
passes native/runtime payload verification. Fresh strict analysis is clean;
the full Flutter suite passes 1,246 tests with four existing platform skips in
77 seconds. Python discovers 200 tests, with 193 passes and seven platform skips;
407 formatter inputs have zero changes. Line coverage remains 74.10%. Five new
policy tests protect fixture isolation and explicit platform trust, and run in
CI; they are not a substitute for the native executions.

The source comparison identifies only the app transport and CI workflow as
changed prior selected inputs, plus five new selected harness/fixture/test files.
679 selected inputs and all test/package evidence are fingerprinted. The final
CLI inventory contains no guest VM; only verified leftover owned test windows
were closed, leaving the shared Sandbox backend untouched.

Scores remain 54 published and 73 provisional local. Next work must preserve
the five-platform scope: validate the new native dependency on Linux, Android,
macOS and iOS, repeat combined native acceptance for an exact release candidate,
then complete signed installation, physical-device/accessibility and operations
gates plus reviewed publication. No completion or production-release claim is made.

Evidence: [verified execution and package manifest](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-native-acceptance-2026-09-06/verification.json),
[final native guest result](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-native-acceptance-2026-09-06/sandbox-d/evidence/result.json),
[repeatable run guide](WINDOWS_SYNC_ACCEPTANCE.md).

## 2026-09-06: Application Native Transport Integration

The verified source copy is now a real path dependency under
`apps/mobile/packages/rhttp`, retaining upstream MIT notices and a patch ledger.
The application executor uses native streaming, a 9 MiB decoded-body limit,
total/header/inactivity deadlines, explicit cancellation and observed cleanup.
It preserves TLS verification, redirect refusal, proxy refusal, credential/error
handling and existing request/retry contracts. The original strict peer-close
regression was retained, not skipped or weakened.

Real integration testing found two fixture/setup issues and a native bug. Header
timing now starts after lazy client creation while the total deadline still
bounds initialization. The server fixture observes its socket sink completion
when native code rejects an oversized response before finishing the write. An
invalid HTTP method initially aborted the native process through `unwrap`;
method parsing now returns a bounded static error and the regression passes.
Related avoidable response/body-option panics were also removed.

The exact Rust 1.95.0 toolchain is declared locally. Native Cargo builds enforce
the lockfile, host test preparation runs before Flutter tests, and OSV/release
scans explicitly include the Cargo lock. A deterministic native dependency
inventory and its regression tests join the release provenance checks. This is
not yet a full linked-binary, all-platform dependency or license attestation.

Verification: 26 focused tests, four Rust unit tests, all 1,246 Flutter tests
(four existing symlink skips), clean strict analysis, 195 Python tests (seven
platform skips) and 406 unchanged formatter inputs. Native audit reports zero
vulnerabilities/warnings for 276 dependencies against the retained owned
September 2 advisory database, without a new fetch.

The first ordinary Windows build misleadingly succeeded without `rhttp.dll`
because failed initial plugin-link generation left stale CMake metadata. After
restoring only owned local plugin junctions and rerunning locked pub resolution,
the second build succeeded with the actual native DLL. The new unsigned ZIP
passes CRT and complete native payload/hash verification. A new negative
ZIP/MSIX test now requires this DLL even when a supplied manifest omits it.
No host-profile app launch, SDK/cache source change or trust-policy bypass was
used. Rust 1.95.0 was installed without changing the default toolchain.

Next gates: exact-candidate clean-guest and all-platform native build/acceptance,
engine/background teardown, certificate controls, review/publication, signed
installation/upgrade/rollback, physical devices, accessibility and demonstrated
hosted operations. The broad goal remains incomplete; scores stay 54 published
and 73 provisional local.

Evidence: [integration verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-transport-integration-2026-09-06/verification.json),
[packaged native inventory verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-transport-integration-2026-09-06/package-verification.json).

## 2026-09-06: Bounded Native Streaming Candidate

The preceding scoring turn was progress: it completed the requested audit and
identified the next transport integration gate. This follow-up makes concrete
progress on that gate without replacing the application dependency prematurely.

Waiting for native stream completion before cancelling the Dart subscription
fixes both original prototype timeout/error-contract failures. A source copy of
`rhttp` now also bounds decoded stream responses before native-to-Dart queueing,
with an optional uint32 byte limit and a typed oversized-response error. The
tests include declared and chunked oversize, gzip expansion, delayed listeners,
exact and zero limits, malformed UTF-8, and normal operation.

Two additional callback-race tests failed before remediation. Native streaming
cancellation now surrounds network waits, not in-flight Dart callbacks. Both
tests pass, and the former callback-return/stream-post warnings disappear from
two complete 19-test runs. All four native unit tests and strict candidate Dart
library/probe analysis pass. The generator is pinned to 2.12.0; its first default
Windows build hit a Rust compiler error, and the unstripped development-tool
build succeeded. Application and cached package/SDK sources were not edited.

The corrected native lockfile remains identical to the prior clean strict audit
(276 dependencies). An actual Windows release build of the guarded streaming
probe passed. Fresh Sandbox D then passed six cancellation/timeout checks and
certificate, hostname, redirect and authorization controls through the stream
API with a 9 MiB native cap. The peer observed every disconnect; cancellation
took 0-19 ms, native timeouts 300 ms. Guest exit was zero with empty output logs.
Its owned launcher has exited. The accepted harness source is retained before
a later braces-only lint fix; native transport package sources are unchanged.

The application is **not fixed yet**: its focused suite was rerun and still has
nine passes and the active TLS cleanup failure. Its 535 selected source/config/
test inputs and 35 plugin junctions are unchanged. Scores remain 54 published
and 73 provisional local, with all original device, release, accessibility,
security, operations and publication criteria intact.

Next work is application integration: maintain the patched native source and
licenses, include its locked native graph in build/scanning/provenance, wire the
real HTTP executor without changing its security/error/retry contracts, verify
engine teardown and background/native initialization, and run the exact-candidate
application suites and all supported-platform builds. Do not replace the real
TLS regression with a prototype-only pass or reduce the release scope.

Evidence: [native stream verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/native-stream-verification.json).

## 2026-09-06: TLS Isolation And Candidate Audit

The preceding explicit scoring audit was progress, not full-goal completion.
The follow-up reproduced the actual application helper's TLS cleanup defect
three times in a clean Windows Sandbox, with a passing synthetic-certificate
control. This separates the application/SDK cleanup result from host antivirus
HTTPS interception observed in separate controls. Caller deadlines work, but
the peer does not observe prompt disconnection.

An isolated native HTTP candidate passed cancellation, native timeout,
certificate trust, hostname, authorization and redirect controls. Its original
Rust lockfile had two vulnerability advisories and one unsoundness warning.
Updating only the owned prototype lockfile produced a clean strict audit and
another passing native guest run. These are feasibility results, not a change
to the application dependency graph or a clean application security scan.

The candidate's stream adapter still fails two of six strict tests: native
cancellation errors mask the expected stalled-body and total-deadline errors.
The four passing cases cover header timeout, oversized bodies, malformed UTF-8
and normal completion. This unresolved cleanup/error-contract issue prevents
adoption. Application code and all 535 selected source/test/config inputs remain
unchanged, as do the seven scoring audit logs. The active application TLS
regression remains failing and has not been skipped or weakened.

The three owned guest runs ended. No SDK source, cached package source, global
certificate trust, antivirus configuration or production account was modified.
GitHub main, six ordinary passing CI jobs, zero releases and skipped newest
production probe/alert runs were reconfirmed at 15:59 UTC. Scores stay 54/73;
the wider release, device, accessibility and operations requirements remain.

Next technical gate: resolve and verify streaming ownership/cancellation before
selecting any replacement transport, then address maintained native dependency
ownership, scanning and supported-platform integration. The current outcome is
concrete diagnostic progress, not an assertion that production is ready.

Evidence: [isolated transport verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-native-http-probe-2026-09-06/verification.json).

## 2026-09-06: Partial Sync Deadline Remediation

The preceding review was progress: a real HTTP reproduction changed the next
action from scoring to a focused network-lifecycle repair. The shared transport
now has 30-second request/header and response-idle limits and a two-minute total
deadline, retaining the existing 15-second connection limit. It force-closes its
client on every exit without changing certificate validation, redirects, UTF-8
validation or response size bounds.

Five deadline/cleanup/retry regressions failed before implementation. Nine of ten
new tests pass after it, including peer-observed HTTP disconnects and sync-store
busy/error/credential-state recovery followed by a real request retry. The full
suite has 1,229 passes, four skips and one failure. Analysis and formatting pass.

Actual production defaults were exercised separately, without shortened timeout
parameters: stalled headers expired at 30.012 seconds, an idle response body at
30.010 seconds, and continuously trickling data at 120.002 seconds (599 chunks).
Each peer observed disconnection. This is loopback HTTP evidence, not a TLS,
physical-device, signed-package or server-capacity pass.

The remaining active regression confirms that a stalled TLS handshake returns
to its caller at the deadline but does not promptly close its socket with the
pinned Dart SDK. The raw peer did not observe disconnection within two seconds.
A separate owned-isolate experiment saw isolate exit but no disconnect within
five seconds. It was not added to production. SDK source and official API review
did not identify a verified cross-platform cancellation workaround. No SDK
modification, certificate bypass, custom socket implementation, dependency change
or test suppression was introduced.

This is partial progress, not a finished transport gate. Keep the strict TLS
regression active and investigate reliable connection ownership/cancellation;
then rerun the full suite and publish only through exact-commit CI. Broader
device, signing and operational gates remain unchanged. The score is not raised.

Evidence: [sync deadlines](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-sync-deadlines-2026-09-06).

## 2026-09-06: Readiness Reassessment And Sync Deadline Finding

The explicit scoring review reran all automated suites and confirmed that the
534 selected source inputs match the latest native acceptance manifest. GitHub
main remains c95f7ac, its ordinary CI passes, releases remain empty, and the
latest production probe/alert are skipped. Application source was not changed.

A new bounded real-HTTP negative probe reproduced a shared sync transport gap:
both stalled headers and a stalled response body remained pending after 35.012
seconds, then completed when the fixture resumed. The 15-second connection
timeout is not a response deadline. Source review shows sync's busy flag remains
set while awaiting the request. This defect remains unresolved in both main and
the local candidate, reducing product reliability credit by one point each.

The next focused repair is total/idle sync-response deadlines with owned-client
cleanup and retry/busy-state regression tests. Representative authenticated
server load and physical/signed-release acceptance are still required. Retained
[audit evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-score-review-2026-09-06)
distinguishes the defect-reproducing probe from the passing application suite.

## 2026-09-06: Bounded Video Startup And Owned Cleanup

The preceding audit was progress: fresh passing suites and native evidence
changed the next action from test repair to stalled-source resilience. Nine
additional video tests now cover deadline expiry, real readiness versus open
acceptance, stale completion/error, cleanup ownership, fast source changes and
unmount. Five of the new cases failed before the fix. All 20 video tests and
the full 1,220-test Flutter suite now pass.

The route bounds startup through the first rendered frame and caption setup at
30 seconds. It cancels stale UI waits, retains disposal across retries and
source changes, and waits at most ten seconds for prior disposal. No successor
is allocated until disposal reports success; timing out is not native
cancellation and no backend force-termination guarantee is claimed.

In the successful clean guest, normal native HTTP failure became visible at
5.370 seconds. A separate real-native fault injection extended only the
fixture's socket timeout to 60 seconds and observed the app's watchdog at
30.075 seconds, without a preceding native error event. Both then retried the
same endpoint with a new request and passed decoded/rendered pixel, pause,
seek and resume checks. The first run's early-error expectation failure is
retained separately, not counted as application-deadline proof.

Final acceptance: 31 exercise checks, seven reopen checks, ordinary startup,
139 distinct observed loaded module paths with no excluded zlib/debug CRT,
and matching ordinary ZIP/unsigned MSIX payloads. Both owned guests stopped.
The source/hash, logs, frames and guest result are retained in
[deadline evidence](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-video-deadline-2026-09-06).
This strengthens the existing provisional 74/100, not another point award or a
claim that physical devices, signed installations or real operations are done.

## First Remediation Pass (2026-09-05)

Changes are local worktree changes based on the baseline, not a deployed release.

| Requirement | State and evidence |
|---|---|
| Reject imported cache path traversal | Unsafe IDs are rejected by backup record decoding and again before materialization. Regression tests cover both separators, absolute/UNC paths, control characters, and preservation of the current library on rejected import. |
| Keep cache operations inside the private directory | Canonical parent and destination checks reject links, directories, and external paths before writing, deleting, verifying, or exporting cache files. Four link regressions are implemented but skipped on this Windows host; Linux execution remains required. This is not an OS-level defense against a concurrent hostile process replacing filesystem entries between checks. |
| Support portable cache filenames | Existing short safe names remain compatible with partial downloads; long IDs and Windows device names use bounded SHA-256 filenames. Tests materialize long IDs and reserved names. |
| Bound offline transfer resources | HTTP headers and streaming byte counts enforce the smaller app/provider per-file budget. Connection/header, idle-read, and total network deadlines are explicit. File writes use awaited chunks; verification and export no longer allocate entire files in memory. Oversized downloads are rejected and partials removed. |
| Preserve existing media on failed replacement | The partial download is checked before replacement. A checksum failure leaves existing media intact. Resume responses must have matching Content-Range offsets and lengths. Existing resume/cancellation tests remain passing. |
| Prevent invalid-token throttling bypass | A connection-address ingress budget runs before authentication. Verified accounts have independent limits; invalid/anonymous traffic shares the connection-address budget. Live buckets cannot be evicted to reset allowances. Tests cover rotation, capacity exhaustion, expiry, multiple devices/accounts, and real HTTP requests spoofing forwarded headers. |
| Restore strict static analysis | Deprecated theme roles and XML namespace arguments were replaced/removed. Strict mobile analysis and server analysis report no issues. No analysis gate was weakened. |

Relevant implementation:

- `apps/mobile/lib/src/data/offline_cache_paths.dart`
- `apps/mobile/lib/src/data/offline_media_integrity.dart`
- `apps/mobile/lib/src/data/offline_cache_manager.dart`
- `apps/mobile/lib/src/data/offline_cache_queue_worker.dart`
- `apps/mobile/lib/src/data/offline_cache_pressure_enforcer.dart`
- `services/server/lib/server.dart`

Regression tests:

- `apps/mobile/test/offline_cache_safety_test.dart`
- `apps/mobile/test/offline_cache_manager_test.dart`
- `apps/mobile/test/offline_cache_queue_worker_test.dart`
- `services/server/test/server_rate_limiter_test.dart`
- `services/server/test/server_test.dart`

### Verification

- Full mobile suite after the security/resource changes: **1,008 passed,
  four skipped**. Skips are Windows symlink-privilege limitations, not passing
  evidence. Log: `build/readiness-audit-2026-09-05/mobile-remediation-tests.log`.
- After final deadline/export-name and deprecation cleanup: focused cache,
  theme, and platform suite **55 passed, four skipped**. Log:
  `build/readiness-audit-2026-09-05/focused-remediation-tests.log`.
- `flutter analyze --no-pub`: **no issues**.
- Server `dart test --reporter expanded`: **67 passed**.
- Server `dart analyze`: **no issues**.
- Python CI unit tests: **93 passed, one skipped**.

## Second Remediation Pass (2026-09-05)

Atomic library persistence and recoverable startup are now implemented locally.
This replaces the ignored per-preference write results identified in the audit;
it is not yet a released or physically validated storage migration.

| Requirement | State and evidence |
|---|---|
| Commit related library data together | All 36 existing library keys are stored in a versioned, SHA-256-checked snapshot. Pending files are flushed before replacement; a previous snapshot is retained. Legacy preferences are imported once and retained unchanged for recovery. |
| Serialize writes and reject stale writers | Saves capture their state at call time and commit in order. Revision comparison rejects stale stores; a SQLite exclusive transaction coordinates the file commit across isolates/processes. Real-file tests exercise cross-isolate writers on Windows. |
| Make unsuccessful changes visible | Storage and JSON-encoding failures reject the operation, roll memory back to the last committed snapshot, invalidate dependent queued changes, and show a persistent reload notice. Regression tests also check that an earlier valid queued save survives a later encoding failure. |
| Recover malformed startup data | Load catches parsing, type, storage, and migration errors. The recovery screen offers retry, raw-data export, previous-snapshot restore, backup import, and explicitly confirmed reset. Recovery copies are flushed before replacing damaged data. Corrupt legacy bytes remain available. |
| Avoid background writes to an unloaded library | Background cache processing rejects a library that needs recovery instead of treating it as an empty, usable store. |
| Keep UI tests honest about storage scope | Widget tests use a clearly test-only preferences fixture because fake-async frames cannot drive native file I/O. Separate tests instantiate the production file backend; widget-test success is not counted as native durability evidence. |

Implementation and regression coverage:

- `apps/mobile/lib/src/data/library_storage.dart`
- `apps/mobile/lib/src/data/library_store.dart`
- `apps/mobile/lib/src/ui/library_recovery_screen.dart`
- `apps/mobile/test/library_storage_durability_test.dart`
- `apps/mobile/test/library_recovery_screen_test.dart`
- `apps/mobile/test/support/library_storage_fixture.dart`

### Verification

- Full mobile suite before the final encoding/archive-flush adjustment:
  **1,036 passed, four skipped**. Log:
  `build/readiness-audit-2026-09-05/mobile-durability-full-tests.log`.
- Final focused native-storage and recovery-widget suite: **29 passed**.
  Cases cover pre-commit write rejection, complete snapshot preservation,
  checksum corruption, explicit recovery, legacy migration, stale writers,
  queued changes, encoding failures, and recovery layouts at 360x640/1280x800.
- Final full mobile suite with coverage after the encoding/archive-flush
  adjustment: **1,037 passed, four skipped**. Log:
  `build/readiness-audit-2026-09-05/mobile-durability-final-tests.log`.
- Final strict `flutter analyze --no-pub`: **no issues**.
- Python CI unit tests after the storage dependency change: **93 passed,
  one skipped**.
- `flutter pub get` resolved the new `sqlite3` dependency and its two additional
  transitive dependencies. Native SQLite loading was exercised by the real-file
  tests on this Windows host.
- `flutter build windows --debug --no-pub` could not proceed because Windows
  symlink support/Developer Mode is unavailable. No OS setting was changed.
  Log: `build/readiness-audit-2026-09-05/windows-durability-build.log`.

Current local LCOV evidence (not branch/native/device coverage):

| Scope | Covered executable lines | Line coverage |
|---|---:|---:|
| Full mobile report | 30,589 / 41,711 | 73.34% |
| File library storage | 133 / 140 | 95.00% |
| Library store | 4,820 / 5,107 | 94.38% |
| Recovery screen | 77 / 88 | 87.50% |
| Offline cache manager | 216 / 252 | 85.71% |
| Playback audio engine | 145 / 348 | 41.67% |
| Video playback screen | 0 / 146 | 0.00% |

Artifact: `build/readiness-audit-2026-09-05/mobile-durability-lcov.info`.
The repository's coverage checker calculated the overall percentage from this
artifact. Coverage gains do not establish physical playback correctness or
power-loss recovery, and the critical playback gaps remain visible.

### Evidence Limits

The disk-full regression injects an exception at the real pre-commit boundary;
it does not fill the user's disk. Killed-process recovery, actual full-disk
behavior, power-loss durability, directory-metadata flushing, large-library
latency/memory, and platform-specific rename behavior still need verification.
Snapshots are capped at 64 MiB, but that cap is not a proven performance envelope.
SQLite is used for locking, not for transactional storage of the snapshot bytes.
The new native dependency has not been rebuilt on Android/iOS/Linux/macOS here.
Recovery-screen localization and screen-reader acceptance also remain pending.

## Third Remediation Pass (2026-09-05)

Offline media now has aggregate admission/write checks, shared mutation locking,
validated HTTP resumption, and an explicit storage-reclamation path.

| Requirement | State and evidence |
|---|---|
| Account for actual media occupancy | Admission scans regular private files and counts completed media, retained partials, unindexed media, and old files kept during replacement. Stored byte counters cannot hide these bytes. Duplicate index paths count once. |
| Reserve space before writing | Known response lengths reserve the required peak media space before body writes; unknown-length responses check the budget before each chunk is written. Global and provider limits are checked. An object larger than its entire budget is rejected before evicting useful files. |
| Preserve controlled eviction | Only known completed cache files are automatically evicted, oldest first. Unindexed ownership is conservatively charged to the active provider's budget but never automatically deleted. Paused partials require explicit cleanup. |
| Avoid competing mutations | Managers use a SQLite exclusive lock shared by the native cache directory. Concurrent transfers, eviction, and explicit cleanup are excluded; an actual second isolate is tested while the first download holds the lock. A competing request receives a retryable busy error. Optional post-download trimming can defer without changing a completed download to failed. |
| Avoid repeated eviction/download cycles | Evicted items become paused, not queued. Tests reopen the library, verify no automatic work remains, then explicitly resume and process the entry. |
| Bind resumed bytes to the same media | Strong ETags are persisted with a hash of the resource URL and supplied through If-Range. Invalid/missing/changed partial-response validators cause a clean restart. Without a strong validator, resumption requires a provider checksum that is verified before publishing the complete object; other partials restart. |
| Keep HTTP byte semantics consistent | Requests require identity content encoding; encoded responses are rejected. Content-Range offsets, totals, and received lengths remain checked. A real cancelled localhost HTTP transfer persists its validator and resumes correctly in a new manager instance. |
| Avoid portable filename collisions | Mixed-case IDs and the reserved hash namespace use hashed filenames. Tests distinguish case variants even on case-insensitive filesystems. Existing indexed cache paths remain readable; affected legacy partial filenames are not assumed resumable. |
| Make cleanup usable | Settings usage includes partial and unindexed media. Confirmed private-cache cleanup removes those files, preserves original local files and library metadata, and clears saved references to deleted cached files even without queue records. The confirmation dialog passes at 360x640 with 100% and 200% text scaling. |

Implementation:

- `apps/mobile/lib/src/data/offline_cache_budget.dart`
- `apps/mobile/lib/src/data/offline_cache_resume.dart`
- `apps/mobile/lib/src/data/offline_cache_manager.dart`
- `apps/mobile/lib/src/data/offline_cache_pressure_enforcer.dart`
- `apps/mobile/lib/src/ui/offline_cache_maintenance_dialog.dart`

Regression evidence:

- Related library/cache suite before the last cleanup enhancement: **187 passed,
  four skipped**. Log: `build/readiness-audit-2026-09-05/cache-budget-resume-tests.log`.
- Full suite before the last cleanup enhancement: **1,064 passed, four skipped**.
  Log: `build/readiness-audit-2026-09-05/cache-budget-full-tests.log`.
- Cleanup, budget, native-lock contention, and confirmation-dialog suite after
  that enhancement: **18 passed**.
- Final full suite including cleanup: **1,069 passed, four skipped**. Log:
  `build/readiness-audit-2026-09-05/cache-budget-final-tests.log`.
- Final strict `flutter analyze --no-pub`: **no issues**.
- Final formatting verification: **16 files checked, no changes**.
- `git diff --check`: passed (only Git line-ending normalization notices).

Final local LCOV: **30,824 / 41,983 executable lines, 73.42%**. Artifact:
`build/readiness-audit-2026-09-05/cache-budget-final-lcov.info`.
The new budget helper has 82/87 covered lines; resume identity has 24/24;
the expanded cache manager has 312/352; the confirmation dialog has 9/9.
These line counts do not prove all branches, operating systems, or physical
failure modes, including those listed below. All remediation remains local,
uncommitted, and unpushed.

HTTP validator handling follows
[RFC 9110, If-Range](https://www.rfc-editor.org/rfc/rfc9110.html#name-if-range).
Locking uses the existing native SQLite dependency and its
[documented file-locking behavior](https://www.sqlite.org/lockingv3.html).
The executed contention test is cross-isolate on Windows, not a killed-process
test across every operating system.

### Evidence Limits

These are media-byte budgets, not a reservation of physical disk blocks. The
SQLite lock file, filesystem allocation overhead, and bounded resume sidecars
(at most 4 KiB each for normal generated metadata) are separate bookkeeping.
Actual disk-full, power-loss, memory-constrained device, and killed-process
testing remain necessary. Four existing link tests still require Linux or a
Windows host with symlink privileges.

The policy is captured for each transfer; lowering limits during an active
download and foreground/background library-index handoff still need integration
validation. Cache files and the library snapshot are not one filesystem
transaction: a concurrent library revision conflict or failed index save can
leave unindexed media, which is now accounted for and explicitly removable.
Unknown provider ownership is intentionally conservative and can require
cleanup before a tightly limited provider can download again.

## Fourth Remediation Pass (2026-09-05)

Server backup coordination and compiled-service recovery now have executed local
evidence. This completes the previously disconnected shell/Python integration;
it does not establish production disaster recovery or a signed release.

| Requirement | Implementation and evidence |
|---|---|
| Snapshot all stores at one request boundary | A server instance lock, legacy compatibility lock, admission lock, and active-request snapshot lock coordinate the Dart process with the Python helper. Existing handlers drain; new data requests receive retryable 503; health remains available. The Windows runtime drill holds a real incomplete upload and verifies backups do not start reading until that upload commits. |
| Deploy the coordinated implementation | Backup/restore/verify shell commands now delegate to the common Python helper. Installation instructions and CI install the helper; the systemd backup sandbox permits its data-directory lock files. Compatibility with legacy exclusive locks fails closed. |
| Validate archives before publishing a restore | Unique archive names, SHA-256 sidecars, per-file manifests, size/file/metadata bounds, portable path checks, duplicate/alias rejection, and special-file/link rejection are enforced. Restore uses a private sibling staging directory and publishes only after validation. Invalid present manifests cannot silently downgrade to legacy mode. |
| Bound active upload lifetime | JSON bodies have a 30-second total deadline, including trickling senders. Cancelled bodies cannot mutate the snapshot and release the backup fence. On dart:io, cancellation may close the socket before the logical HTTP 408 response is sent; the runtime test verifies the actual deadline, timeout log, unchanged revision, and released lock. |
| Recover an actual service | The compiled-server drill restores exact library and provider snapshots, managed identity, revoked credentials, separate accounts, conflict behavior, and one-time recovery-code state. It performs a post-restore write, kills/restarts the server, and confirms persistence and revocations. |
| Recover from a terminated backup process | The drill kills an external process holding the snapshot fence and verifies requests resume. It also confirms a legacy incompatible lock produces no published backup. |
| Require runtime recovery evidence | PR CI, scheduled recovery, and release executable jobs now execute the drill and retain evidence. Runtime or archive-test failure fails the relevant job; checks were not bypassed. |

### Verification

- Server analysis: **no issues**. Full Dart server suite: **73 passed**.
- Windows AOT server compilation: passed. Existing executable smoke checks
  passed, including rejecting a second instance and 90 requests. The SIGTERM
  assertion is explicitly skipped on Windows.
- Compiled Windows runtime recovery: **17 checks passed**, including the real
  30-second incomplete-upload deadline. The artifact records the executable and
  helper SHA-256 hashes. Earlier failed experiments are not used as passing
  evidence.
- Backup helper tests: 22 cases. Native Linux executes all 22; Windows skips two
  native symlink cases. The existing Linux shell backup/restore fixture also
  passed through the new entry points, including unsafe archive rejection.
- Full Python CI helper suite: **117 passed on Ubuntu 24.04 WSL**;
  **114 passed, three skipped on Windows**. The Windows skips are two native
  symlink cases and the existing POSIX operations-probe case; all three execute
  successfully in Linux.
- Dart formatting and Git whitespace checks passed.

Evidence:
`build/readiness-audit-2026-09-05/server-runtime-recovery-final/runtime-recovery.json`
and its redacted server logs. The measured controlled restore/validation time
is for a small local fixture, not a production RTO. Temporary runtime server
processes are terminated and awaited by the drill.

### Remaining Evidence Limits

The compiled Dart/Python lock interoperability drill has been executed on
Windows. Linux Python and shell behavior were exercised natively under WSL, but
the compiled Linux/macOS recovery jobs and actual systemd installation/restore
have not yet run on the modified source. A matching Linux Dart SDK was not
available in the inspected WSL toolchain; the Windows Flutter cache was not
repurposed or overwritten.

Process kills occur after completed service writes and while a backup lock is
held, not at every atomic-write boundary or during physical power failure.
Live rollback between differing executable/schema versions, representative
data volume, long snapshot pauses, physical disk exhaustion, fsync semantics,
network filesystems, and production RPO/RTO still need acceptance evidence.
Backups contain private state and authentication digests: checksums are not
encryption or authenticated off-host storage. Restore ownership must match the
actual service identity. All changes remain local, uncommitted, and unpushed.

## Linux Verification and Score Refresh (2026-09-05)

The Linux limitation recorded at the end of the fourth pass is now partially
closed. A checksum-verified Dart 3.12.2 SDK was prepared in the ignored build
directory with isolated HOME and PUB_CACHE. Server dependencies resolved with
`--enforce-lockfile`; 28 copied server source/test/deployment files matched the
working tree byte-for-byte.

- Linux server analysis: no issues. Full server suite: **73 passed**.
- Linux AOT compilation: passed. Executable smoke passed SIGTERM shutdown,
  second-instance rejection, health/readiness/metrics, and 90 requests.
- Compiled Linux recovery: **17 checks passed**, including native Dart/Python
  lock interoperability and the real stalled-upload deadline.
- Linux Python CI suite: **117 passed**, no skips.
- Fresh Flutter suite: **1,069 passed, four Windows link-privilege skips**.
  Strict analysis was clean; LCOV remains **30,824/41,983 (73.42%)**.

Evidence is in `build/readiness-audit-2026-09-05/server-runtime-recovery-linux`
and the `score-refresh-*.log` files beside it. Linux ran under Ubuntu 24.04 WSL2;
this is not macOS, a production systemd/container deployment, physical-device
validation, or production RPO/RTO evidence. The Windows Flutter SDK/cache was
not repurposed. No application changes were made for this score refresh.

The [current assessment](PRODUCTION_READINESS_SCORE_2026-09-05.md) is **61/100 for
unchanged GitHub main and provisional 72/100 for the local tree**. Earlier
assessments remain historical. The three-point local increase from 69 reflects
integrated recovery and executed native verification, not a claim of release
readiness. All hardening remains local, uncommitted, and unpushed.

## Deployment Ownership and Systemd Pass (2026-09-05)

A real privilege-separated regression reproduced an upgrade defect: a root
backup of a non-root data directory created missing coordination files owned by
root with mode `0600`. The next non-root process could not use those locks.
The helper now creates private files through exclusive creation, assigns only
new root-created POSIX locks to the data-directory owner/group, and preserves
existing inode ownership/permissions. Descriptor checks and no-follow opening
reject linked and special lock files.

An executable systemd fixture now runs isolated copies of the checked-in units,
changing only fixture paths and configuration. Eight runtime checks passed on
Ubuntu 24.04 WSL2/systemd 255: dynamic non-root identity and sandbox activation,
root backup of service state, restore ownership, exact snapshot recovery,
preserved revocation, successful post-restore writes, restart persistence, and
another backup after restore. The process ran with `DynamicUser=yes`,
`ProtectSystem=strict`, `NoNewPrivileges=yes`, private devices, protected home,
and restricted address families. Fixture units/state were cleaned successfully.

PR CI, the scheduled recovery drill, and Linux executable releases now require
the privilege and systemd checks. Failures fail the corresponding job; journals
are checked for fixture credentials and retained as redacted evidence. These
workflow changes have been tested locally, not executed on GitHub yet.

Verification after the lock fix:

- Linux backup helper: **24 passed**. Privilege-separated checks: **2 passed**.
- Full Linux Python CI suite as root: **125 passed**, no skips.
- Full Windows Python suite: **118 passed, seven skipped**. Skips are four
  POSIX permission/link cases, two root identity cases, and one POSIX probe.
- Compiled Windows and Linux recovery reruns: **17 checks passed on each**.
- Real systemd runtime: **eight checks passed**, no cleanup errors.

Evidence directories under `build/readiness-audit-2026-09-05`:
`systemd-runtime-first`, `server-runtime-recovery-permissions-windows`, and
`server-runtime-recovery-permissions-linux`. The updated helper SHA-256 is
`c3b8c33c17da48d9c938f6a6ca5329b9655e1078e597447ef34c152bbb736740`.
README and architecture now describe the actual local native snapshot backend,
its test fixture, and remaining physical durability limits.

This closes the Linux systemd identity/restore acceptance item for an isolated
host fixture, not a production deployment. macOS, different-version rollback,
realistic volumes, off-host recovery, physical-device/native migration, active
monitoring, and signed releases remain outstanding. No new overall score is
claimed solely for this pass; the last assessment remains a historical snapshot.
No application client behavior, repository protection, remote branch, signing
identity, or production deployment was changed in this pass.

## Container Enforcement and Executed Scan (2026-09-05)

The previous container workflow explicitly returned success for PR/push scans
and enforced findings only on scheduled/manual runs. The local changes now
enforce one shared scanner in the existing required **Server analyze and test**
job, the standalone PR/push/scheduled workflow, and the Linux release server job
required by release assembly. This does not change repository protections and
has not run on GitHub yet.

The driver builds the server, exports its immutable image, and runs the existing
digest-pinned Trivy 0.70.0 with an isolated fresh cache. It does not expose the
Docker socket, source tree, host credentials, or a writable root filesystem to
the scanner. HIGH/CRITICAL findings including unfixed entries, end-of-life OS,
database errors/age over 48 hours, mismatched image IDs, missing reports, and
scanner failures reject the candidate. Timeouts clean up only unique fixture
containers. JSON/SARIF/log artifacts remain available after a policy failure.

The real Docker Desktop Linux scan **completed and rejected the image**:

- Image ID: `sha256:4a968ff152c01d915f8ae33f9d633ed1b3bcaf848b79108e0f3283d8d005b220`.
- Debian 12.15, **106 OS packages**, **69 package findings**: 65 HIGH and four
  CRITICAL, representing **26 distinct CVE IDs** across 21 binary packages.
- Scanner database updated `2026-09-05T13:02:41Z`, freshly downloaded in the run.
- JSON and SARIF were successfully produced; exit code 1 was caused by findings.
- Evidence: `build/readiness-audit-2026-09-05/container-scan-verified/`.
- Separate network-disabled SARIF conversion passed as UID/GID `10001:10001`.
- Full Python CI suite: **138 passed on Linux**, **131 passed/seven skipped on
  Windows**. Thirteen tests cover the new scanner/CI/release contract. Edited
  workflow YAML parses successfully; `git diff --check` passes.

These are package-scanner findings, not 69 demonstrated application exploits.
For example, Debian documents that CVE-2023-45853 concerns MiniZip code not built
into the relevant Bookworm zlib binary package. CVE-2026-8376 describes a
32-bit Perl condition, whereas the scanned image is amd64. No suppressions or
exceptions were added; the remaining findings need package-level triage,
runtime minimization/updates, and exact-image functional verification. Sources:
[Debian zlib advisory](https://security-tracker.debian.org/tracker/CVE-2023-45853),
[Debian Perl advisory](https://security-tracker.debian.org/tracker/CVE-2026-8376).

An initial Docker build was interrupted; a subsequent build succeeded. The
first completed scan exposed a converter-only unsupported flag, which was
removed and verified by the fresh final run. Failed-run evidence is retained
separately, not relabeled as successful evidence. All fixture containers and
temporary image archives/caches were removed; built Docker images remain local.

At the end of this pass, the enforcement gap was fixed locally, but **that image
was not accepted by the gate**. The runtime replacement below supersedes this
package finding for the current local image. Scores remained provisional 72/100 locally and 61/100 for
unchanged GitHub main, rechecked at `c95f7acadacd6a5048e080ac6edd1b4143206769`.
No credit is added for merely introducing a gate that the candidate still fails.
No commit, push, merge, protection change, or production deployment occurred.

## Distroless Runtime and Volume Acceptance (2026-09-05)

The current Dockerfile replaces the Debian 12 runtime and its curl/package-manager
dependencies with pinned `gcr.io/distroless/cc-debian13:nonroot`. It compiles a
dedicated Dart readiness probe alongside the server. The probe uses only loopback,
ignores proxy environment settings, rejects redirects, bounds responses to 4 KiB,
and enforces a two-second total deadline. It exits zero only for the expected
HTTP 200/service/readiness JSON contract. Fourteen real-HTTP regressions cover
failure status, malformed/oversized data, stalled/dripping responses, and invalid
configuration. No shell or package manager was added to the replacement runtime.

The actual previous image ran as UID/GID `10001:999`. The replacement explicitly
preserves both numbers and creates new private `0700` data directories rather
than switching existing volumes to Distroless's default identity. The old/new
volume fixture passed **13 runtime checks**: saved snapshot and revoked-token
continuity, successful writes after replacement, stale-write rejection, duplicate
instance refusal, readiness, actual process identity/resource controls, graceful
stops, persistence after recreation, and missing-operations-secret refusal.
This changes packaging around the same service code; it does not establish
rollback across different application/schema versions.

The shared CI/release gate now verifies the exact runtime base with pinned
Cosign 3.1.3 and the Distroless publisher's exact OIDC identity before building.
It tests the immutable built image before exporting it for Trivy. Signature,
runtime, credential-log leakage, scan/evidence, and cleanup errors fail the gate.
Cleanup distinguishes successful Docker auto-removal from daemon failure or a
still-existing fixture rather than ignoring a nonzero removal result.
[Official Distroless verification](https://github.com/GoogleContainerTools/distroless#how-do-i-verify-distroless-images).

Executed results:

- Replacement image ID: `sha256:cbe28735c3b8e3ea7e3ae55873fdf64b19fd2f5daf887c792753253ca80c022a`.
- Image size: **42,967,730 bytes**, down from **97,350,624 bytes** (about 56%).
- OS inventory: Debian 13.6, **14 packages**, down from 106.
- Strict Trivy policy: **zero HIGH/CRITICAL findings**, down from 69 package
  findings. Unfixed findings remain blocking; no suppressions were introduced.
- Full signature/runtime/scan gate: passed, including a fresh rerun after cleanup
  hardening. Pinned publisher signature verified; exact-image runtime passed
  **13 checks**; JSON/SARIF valid; database freshly downloaded, updated
  `2026-09-05T13:02:41Z`; no runtime cleanup errors.
- Checked-in Compose smoke: passed with a unique project, private disposable
  volume, ephemeral loopback port, compiled health probe, operations probe, and
  read-only/non-root/capability-drop checks. The fixture no longer shares the
  default Compose project or fixed host port with an existing deployment.
- Full server suites: **87 passed on Windows and 87 on Linux**; analysis clean
  on both. The Linux copy matched all 35 relevant source/test/deployment/package
  files at verification time.
- Full Python CI helper suites: **153 passed on Linux**; **146 passed and seven
  POSIX/root-specific skips on Windows**. Twenty scanner and eight container
  runtime tests cover the new gate and fixture behavior.

Evidence under `build/readiness-audit-2026-09-05`:
`container-gate-cleanup-verified/` contains the current complete gate report,
signature/build/runtime/scanner logs, JSON/SARIF, and redacted runtime evidence;
`container-volume-upgrade-final/runtime.json` records previous/replacement image
IDs and 13 checks. Earlier failed fixture attempts are retained separately:
one needed the PID column in `docker top`; another expected exit 1 instead of
the service's actual missing-secret exit 255. Neither is relabeled as a pass.
The Compose smoke initially hit host wrapper/path-conversion problems; the
checked-in script subsequently passed without OS/Docker integration changes.

This proves local amd64 runtime acceptance and policy compliance, not absence
of every vulnerability, Dart dependency coverage, sustained deployment capacity,
other architectures, physical storage failure, or production release readiness.
The previous image remains local as upgrade evidence. No task containers or
volumes remain; unrelated Docker resources were untouched. All source changes
remain uncommitted and unpushed. The last full score remains **provisional 72/100
locally and 61/100 for the last assessed GitHub main**, pending broader acceptance
and exact-revision published CI. No merge, protection change, signing identity,
production secret, or production deployment was performed.

## Native Client Storage Failure Acceptance (2026-09-05)

The production file backend has been separated from its Flutter directory
adapter without changing snapshot format, revision/locking behavior, or the app's
exported storage API. This allows a native Dart executable to import the exact
backend directly. Its independent test-package lockfile is checked against all
21 corresponding client dependency versions, hosted origins, and archive hashes.
The verifier accepts a matching graph and rejects eight malformed/drifted graphs.
No alternative SQLite implementation or mocked storage layer is used.
Dependabot now includes the probe and client in the same multi-directory group.
The Pub groups use name patterns rather than `dependency-type`, which GitHub
does not list as supported for Pub groups. Existing schedules/PR limits are
unchanged. [GitHub configuration reference](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference#groups).

Native Windows and Linux AOT probes each passed seven process/storage checks:

- Acknowledged writes survive forced process termination and reopening.
- Killing a writer after real pending bytes are flushed leaves both current
  and previous snapshots byte-identical; uncommitted pending bytes remain.
- A stale second process waits for the held lock and then receives a conflict.
- Killing the lock holder releases the real SQLite lock and lets the waiting
  process successfully commit without accepting the killed writer's state.
- Corrupt bytes are not silently reset; explicit previous recovery archives them.
- A 25,000-track serialized fixture survives process termination and reopening.
- Killing an initial pre-commit writer permits a clean retry without treating
  unacknowledged initial data as a committed migration.

Linux additionally passed three real filesystem-exhaustion cases in a private
mount namespace and an 8 MiB tmpfs. The storage processes ran as UID/GID 65534.
Filling the filesystem to zero available blocks produced SQLite `SQLITE_FULL`
(13) before lock acquisition; filling it while paused before previous-snapshot
replacement produced file `ENOSPC` (28). A third case left only 64 KiB available,
causing an actual partial pending-file write and `ENOSPC`. Each failure preserved
both committed snapshots byte-for-byte, preserved the revision on reopening, and
allowed a successful save after the filler was removed. The host disk was not
filled, and no existing library or production directory was used.

The final 25,000-track fixture was 5,017,007 bytes. Measured save round trips were
0.250 seconds on Windows and 0.265 seconds on Linux; maximum per-probe RSS was
85,643,264 and 75,681,792 bytes respectively. These small local measurements
include protocol/serialization time and are not a UI-frame, 64 MiB capacity,
aggregate-process-memory, or low-end-device performance guarantee.

Both CI and release desktop jobs now compile and run the native probe; Linux
includes the private-namespace exhaustion cases. Failure/evidence artifacts are
retained. Eight Python tests cover process control, namespace/mount restrictions,
bounded exhaustion, cleanup/error reporting, and workflow enforcement. An older
workflow-path checker assumed every `scripts/` reference was a file; it now
accepts actual directory references while still rejecting missing scripts or
directories masquerading as executable script files, with a new regression.

Final verification:

- Full Flutter suite: **1,069 passed, four unchanged Windows link-privilege
  skips**; strict analysis clean; coverage **30,824/41,983 (73.42%)**.
- Native runtime: **seven checks passed on Windows**, **ten on Linux**, with no
  cleanup errors. Linux stage comparison: seven source/policy/lock files matched.
- Probe analysis and dependency-policy checks passed. Full Python helper suite:
  **162 passed on Linux**, **155 passed/seven skipped on Windows**.
- Edited workflow/probe YAML parsed successfully. No native test processes or
  task filesystem mounts were intentionally left running.

Evidence under `build/readiness-audit-2026-09-05`:
`client-storage-windows-final/runtime.json`, `client-storage-linux-final/runtime.json`,
`client-storage-full-flutter-tests.log`, and `client-storage-windows-python-final.log`.
The initial Linux runs failed the fixture's assumption that a completely full
filesystem would reach a file write; the actual earlier SQLite failure was then
identified and tested explicitly. Failed attempts remain separate, not relabeled.
The final backend SHA-256 is
`8d3d6bd812c1f0a37fa995ba1fc76359305e982beb9bc378c93e7cce95b88a69`.

This closes targeted native process-death and bounded Linux filesystem-full
acceptance gaps. It does not prove power-loss durability, every interruption
boundary, installed Flutter migration, real preference-plugin migration, macOS
execution, mobile-device storage, different-schema rollback, or physical disk
failure. The new GitHub jobs have not executed for a committed candidate. The
last full assessment remains provisional 72/100 locally and 61/100 for the
assessed GitHub main. No commit, push, merge, protection change, production
deployment, or OS setting change occurred.

## Diagnostic Privacy Hardening (2026-09-05)

The fresh audit reproduced five credential formats surviving the old logger's
redactor in both preferences and exported reports. Its plain-token control
passed, so the original regular tests did not reveal the problem. The synthetic
probe and its original failing log are retained. No actual credential or user
diagnostic history was read to conduct the audit or verification.

Local diagnostic format v2 now records structured metadata instead of raw
exception text: a fixed error category/description, timestamp, allowlisted
origin, numeric OS/platform code where available, and up to 12 validated Dart
package/SDK source locations. Flutter's stack parser is used; raw symbols,
native/web formats it cannot safely interpret, network URLs, local paths,
request bodies, and platform details are not retained. This preserves useful
locations and categories without attempting to enumerate every secret syntax.

The logger removes the v1 preference key without reading its free-form content.
It revalidates loaded v2 records and drops unknown/raw fields. Library and
credential keys are unchanged. Writes/removals are checked and reloaded; errors
stay inside the diagnostic boundary so they do not recursively break global
error capture. The Options screen reports clear failure truthfully and permits
retry when a legacy cleanup failed despite an empty in-memory log.

Load, capture, and clear are serialized. Forty retained entries, 12 frames per
entry, bounded input parsing, and 40 pending captures constrain logger work.
Additional burst events are dropped before stack parsing and counted in a
bounded `discardedReports` export/storage field. Clearing resets that count.
Pending work can finish without notifying a disposed listener; new captures
after disposal are ignored.

Verification on the final local source:

- **1,126 Flutter tests passed, four existing Windows link-privilege skips.**
  This includes **57 diagnostic unit tests** and **two added app-widget tests**
  for clear success/failure. Sixteen sensitive formats, real Dart format-error
  source frames, malformed/oversized/tampered records, legacy cleanup, rejected
  storage writes/removals, operation ordering, flooding, and disposal are covered.
- **Strict Flutter analysis: no issues.** Dart format check: four edited Dart
  files already formatted. No lint, test, or required CI gate was weakened.
- **The unchanged six-case audit probe now passes all six cases.** Its original
  one-pass/five-fail log remains separately available.
- Full LCOV: **30,951/42,081 executable lines (73.55%)** across 198 files.
  The diagnostic module reports **178/178 lines**; this is not branch, native
  plugin, privacy certification, or complete crash-recovery coverage.
- Windows Python helper suite: **155 passed, seven platform-specific skips**
  out of 162 discovered tests. Client offline enforced pub get passed; the
  existing `shared_preferences_platform_interface` 2.4.2 is now explicitly a
  dev dependency for the storage-failure fixture, with unchanged version/hash.
  All **21** native storage probe packages still match client provenance.

Evidence under `build/readiness-audit-2026-09-05`:
`diagnostic-final-flutter-tests.log`, `diagnostic-final-analysis.log`,
`diagnostic-privacy-probe-final.log`, `diagnostic-python-tests.log`, and the
historical `diagnostic-privacy-probe.log`. Final local logger SHA-256:
`17a2cb05c0ed5ea58f22d499be4c9d687b63a016ff6c2ddaab943252b1d1e256`.

Limits: preferences remain best-effort, and verification used mock preference
platforms and fake audio for the widget tests. Installed preference-plugin
migration remains unverified. Old exported files and OS backups are not erased,
and developer-console/OS crash logs are outside this store/export policy.
No automatic upload is introduced. The earlier native storage, server, systemd,
and container runtime tests were not rerun for this diagnostic-only change.

The concrete disclosure fix restores local security/privacy to 12/15 and the
local total to **provisional 72/100**. Other rubric categories receive no new
points. GitHub main remains **60/100** with the old logger and prior defects.
All changes remain uncommitted and unpushed; no merge, protection change,
production deployment, signing operation, or OS setting change occurred.

## Native Linux Client Acceptance (2026-09-05)

Executed the production Flutter entry point with real Linux plugins in an
isolated Ubuntu 24.04 container under WSL2, using Flutter 3.44.6/Dart 3.12.2.
The fixture has a fresh marked HOME, private D-Bus/Secret Service, Xvfb software
display, and PulseAudio null sink. It used only generated audio and synthetic
credentials. The container had four CPUs, 6 GiB RAM, and no host mounts, device
passes, or published ports. No Windows/WSL host packages or OS settings changed.

All three final app-process phases passed:

- **Seed:** real SharedPreferences persisted the legacy fixture; the real
  Secret Service stored and read a synthetic credential.
- **Migrate:** actual app startup migrated the legacy library to the production
  snapshot backend, removed old diagnostics while preserving unrelated settings
  and the credential, imported a generated WAV through the native scanner,
  saved favorite/rating/playlist changes, decoded audio, and exercised native
  MPRIS pause/play/next plus seeking. A missing Documents directory produced a
  handled cache message, not an uncaught startup error.
- **Reopen:** another process retained tracks, playlist, favorite/rating,
  selected playback queue item, and volume without autoplay. The real credential
  survived restart and was then deleted and verified absent.

The final PCM gate recorded 1,699,192 mono 22,050 Hz samples, peak 5,000,
RMS 425.27, and 24,279 samples above the active threshold. This is measured
decoded output in a private virtual sink, not physical acoustic acceptance.
Both retained 1280x720 UI images were visually checked: nonblank English/LTR
library and queue views, without incoherent overlaps. This is one desktop
viewport, not responsive or accessibility acceptance.

The native exercise exposed two application defects, both corrected locally:

1. An off-screen settings FutureBuilder started cache-directory I/O before
   mounting its error handler. A lazy Builder now starts that future when its
   row mounts; unavailable Documents storage remains an explicit handled error.
   No cache path migration or directory fallback was introduced.
2. Generated locale ordering selected Arabic for an unsupported system locale.
   An explicit English fallback now preserves normal Arabic/Turkish matching.
   Seven table cases and one actual MaterialApp regression were added. Both
   native application phases assert English/LTR under the C system locale.

The new runner and PCM verifier are wired into the existing Linux CI/release
desktop jobs with bounded deadlines, failure propagation, and always-uploaded
evidence. Eight PCM-verifier tests and a workflow contract were added; existing
timeout-count tests now distinguish job deadlines from step deadlines. No
required check, audio threshold, or analysis policy was weakened.

Final verification on matching source:

- Linux Flutter suite: **1,138 passed, no skips**; strict analysis clean.
- Windows Flutter suite: **1,134 passed, four existing link-privilege skips**.
  The corresponding four cases passed on Linux.
- Windows Python helpers: **164 passed, seven platform-specific skips** out of
  171 discovered. Four changed Dart files pass the format check.
- Both edited workflow files parse with the client's locked Dart YAML library
  (four CI jobs, eight release jobs); `git diff --check` passes.
- Windows LCOV: **30,951/42,085 executable lines (73.54%)**; Linux LCOV:
  **30,953/42,085 (73.55%)**. Native integration execution is separate evidence,
  not merged into these unit/widget coverage figures.
- **389 source, test, package, manifest, and fixture files** matched SHA-256
  between the Windows worktree and final Linux stage, with zero mismatches.

Evidence under `build/readiness-audit-2026-09-05`:
`linux-native-acceptance-final2/`, `linux-native-final-flutter-tests.log`,
`linux-native-final-analysis.log`, `linux-native-final-lcov.info`,
`native-acceptance-windows-final-tests.log`, `native-acceptance-python-final.log`,
`linux-native-final-source-manifest.json`, and
`linux-native-final-source-comparison.json`.

The retained environment record identifies the original build image; its
container subsequently received `build-essential`, and the actual package
inventory is retained separately. That overlay was included during successful
testing but was not rebuilt into the recorded image. No fixture HOME or active
application/audio/keyring/display process remained at cleanup inspection.
Defunct children remained under the container's non-reaping PID 1; stopping and
removing only the task container disposed of them. The image is retained for
reuse; unrelated Docker resources were not changed.

Failed preliminary logs remain separate. They include missing build tools,
stale generated build output, the genuine startup defect, and fixture assumptions
about locale and queue order. The queue-order failures did not establish a
production playback bug. An initial low-volume recording failed the unchanged
audio threshold; the final fixture plays at full virtual-sink volume before
testing persisted volume 0.4. No failed attempt is reported as a passing run.

This closes targeted real-plugin migration and native Linux playback gaps. It
does not prove a shipped-package upgrade, physical power loss, hardware audio,
Bluetooth, broad codec support, mobile/macOS/Windows app behavior, native sync,
background lifecycle, or accessibility. The new workflow steps remain local
and have not executed on GitHub for a committed candidate. At the 18:54 UTC
refresh main still points to `c95f7acadacd6a5048e080ac6edd1b4143206769`, has no
published releases, and its latest production probe/alert runs are skipped.

Scores remain **60/100 for GitHub main** and **provisional 72/100 locally**.
The new evidence improves confidence within the existing local credit, not the
unverified release/device/operations categories. No commit, push, merge,
protection change, signing, or production deployment occurred.

## Offline Cache Foreground Handoff (2026-09-05)

The next review found that mobile pause requeued processing work but did not
stop the foreground batch from starting its next entry. Rebuilds/timers also
lacked a foreground gate, and resuming used the foreground store's old snapshot
revision after a headless engine could have committed new data. Unawaited
platform/storage failures could escape lifecycle callbacks.

The local foreground coordinator now cancels its active worker, waits for the
pass to drain, persists the queued state, and only then asks the native scheduler
to take over. The worker stops before another entry and no longer waits on a
provider lookup after cancellation; a late result cannot materialize media and
a late error has a handler. The provider's underlying network operation is not
itself cancelled unless its implementation supports that. Disposal stops the
pass. Desktop tray operation keeps the existing in-process behavior.

Lifecycle transitions and scheduler calls are serialized. A rapid resume waits
for an in-flight schedule before issuing cancellation, then reloads saved state
before processing again. Late worker creation cannot start after pause. Paused
timers/rebuilds neither process work nor repeatedly replace the scheduled job.
A false native schedule result is reported as rejection instead of assumed
success. Platform/storage errors reach diagnostics and suspend the foreground
coordinator until lifecycle reconciliation rather than looping on rebuilds.
An existing library save error prevents another pass; a failed cached-index
write preserves the original storage exception rather than masking it with a
second failed attempt to mark the entry failed.

Fifteen new regressions cover ten widget lifecycle cases, two real queue-worker
cancellation cases, and three real-file/HTTP/storage cases. The widget fixture
injects a draining worker and a method-channel scheduler; it does not claim
native Android/iOS engine execution. The I/O fixture uses the production cache
worker, manager, SQLite-backed file storage, and a loopback HttpServer. It stops
after exactly 16,384 bytes of a 65,536-byte transfer, drains, requeues durably,
loads another store, and resumes with the expected Range and strong If-Range
validator. It verifies the final bytes and provider SHA-256, then rejects a stale
foreground write without overwriting the background result. Reloading permits
a later mutation and another successful reopen. The two stores share one test
process; process-death and full-disk evidence remain separate earlier fixtures.

The initial regression log reproduced the missing stop/drain call. Its other
initial-mount assertion did not drive a paused frame; the corrected fixture uses
a forced frame to exercise that branch. Initial I/O attempts rejected the
fixture's incorrectly unprefixed provider checksum. It was corrected to the
existing `sha256:` contract and persisted FNV checksum format; production
integrity checks and thresholds were not weakened. Failed logs are retained
separately from passing results.

The actual native cancellation boundary is still open. In particular, the iOS
handler only calls `BGTaskScheduler.cancel` for task requests; it has no explicit
active-engine shutdown handshake. Android cancellation and engine teardown also
need installed native acceptance. Snapshot conflicts and the cache lock remain
necessary safeguards while another engine is still alive. This turn does not
establish physical mobile lifecycle, all cache/index commit boundaries, live
policy changes, or power-loss safety. No signing, deployment, protection change,
commit, push, or merge occurred. The overall readiness goal remains incomplete.

Final verification at approximately 19:34 UTC:

- **1,149 Flutter tests passed on Windows**, with four existing link-privilege
  skips. **1,153 passed on Linux**, with no skips. Strict analysis is clean.
- **164 Python helper tests passed**, seven platform-specific skips out of 171
  discovered. All five changed Dart files pass the format check.
- Windows line coverage is **31,060/42,154 (73.68%)**; Linux is
  **31,062/42,154 (73.69%)**. The queue worker covers **70/72 (97.22%)** lines
  and its foreground coordinator **117/130 (90.00%)**. These are line metrics,
  not native-engine shutdown or complete branch coverage.
- The native Linux seed/migrate/reopen phases and unchanged PCM gate passed on
  the final candidate. PCM: 1,860,575 samples, peak 5,000, RMS 511.181, and 39,945
  active samples. The retained reopen image was visually checked and nonblank.
- **391 files matched SHA-256** between the final worktree and Linux stage.
  The rebuilt development image includes build-essential, unlike the earlier
  overlay-based run: `sha256:23eeeb0db75b321534f401d6069d4dadef117f92af0faf6f7233ad74c3f16e40`.
  This run used an init process; cleanup inspection found no fixture HOME or
  remaining app/audio/keyring/display process. The exact task container was
  stopped and removed, with no host mounts, ports, or devices used. No host
  packages or OS settings changed; the image and evidence remain available.

Final evidence under `build/readiness-audit-2026-09-05`:
`cache-handoff-windows-verified.log`, `cache-handoff-linux-final-tests.log`,
`cache-handoff-linux-final-run.log`, `cache-handoff-linux-lcov.info`,
`cache-handoff-native-final/`, `cache-handoff-python.log`,
`cache-handoff-source-comparison.json`, `cache-handoff-source-manifest.json`,
`cache-handoff-container.json`, and `cache-handoff-cleanup-inspection.log`.
Earlier logs describe their earlier candidates and are not relabeled as the
final source. Scores remain **provisional 72/100 locally** and **60/100 for the
last audited GitHub main**; there is no new release/device/operations credit.

## 2026-09-06: Background Shutdown and Startup Verification

The current local implementation replaces cancellation-call completion with an
explicit native ready/stop/drain protocol. Dart waits for resolver/transfer work
and its cleanup before acknowledging stop; providers can write files before
returning, so their futures must settle. Foreground pause drains and persists
before scheduling. Resume requires a true native cancellation reply before
reload and further work. Failure or timeout suspends that coordinator until
lifecycle reconciliation. The acknowledgment establishes quiescence, not that
every attempted storage operation succeeded.

Generated Kotlin/Swift gates serialize on the platform main thread, wait for
readiness, coalesce stop callers, and reject stale engine callbacks. Android also
checks job-generation identifiers. A ten-second gate deadline returns false
without claiming a live engine stopped; OS-forced termination and failed cleanup
also fail closed. The Dart caller has a separate twelve-second timeout.

The September 6 audit identified an iOS initialization-order defect in both
published and local source. The local generator now requires successful
`engine.run` before plugin/channel-handler registration and terminates on failed
startup. Android now disables constructor auto-registration and invokes its
registrant once after establishing ownership and the cleanup gate. Three new
generator tests include mutations that remove startup cleanup or move
registration before the engine runs. All eleven generator tests pass.

The audit also found the new real-I/O test missing a Flutter binding. Its binding
now preserves the real HTTP client, so both the method-channel stop test and
neighboring loopback transfer execute normally. No production test or analysis
gate was disabled. Fresh final-candidate results:

- Windows Flutter: **1,166 passed, four symlink-privilege skips**; Linux Flutter:
  **1,170 passed, no skips**. Strict analysis with fatal infos is clean on both.
- Python CI discovery: **164 passed, seven platform skips**, 171 discovered.
- Exact native helper execution: **14 Kotlin and 14 Swift scenarios passed**.
  Generated AppDelegate Swift parsing passed. Kotlin compilation of the Android
  job service passed against real Flutter engine/API 36 declarations, but this
  does not compile all generated Java plugin bodies or the target API 37 APK.
- Real Linux app seed/migrate/reopen, credential round-trip/restart/deletion,
  native decoding and MPRIS checks passed. Virtual-sink PCM: 1,593,694 samples,
  peak 5,000, RMS 566.36, 40,564 active samples. The reopen image was visually
  checked. This is not physical acoustic or installed mobile acceptance.
- Windows coverage: **31,091/42,200 (73.68%)**; Linux:
  **31,093/42,200 (73.68%)**, 199 reported Dart files. Native code is excluded.
- **396 manifested source files matched SHA-256** between the final host tree
  and Linux stage. The manifest does not cover unrelated repository files or
  generated wrappers. No fixture processes remained at inspection. Exact task
  containers were removed after evidence collection; no host mounts/devices or
  exposed ports were used. Test images and evidence were retained.

The Linux bootstrap initially rejected this host's Avast-intercepted certificate
chain. Only the matching public installed root certificate was exported and
validated against `pub.dev`; it was added to the disposable container's trust
store. Host trust/firewall settings were unchanged, no private key was exported,
and TLS verification was never disabled. The enforced-lockfile bootstrap then
passed. Android Gradle still fails before compilation on local Java loopback
IPC; process-local selector/trust options did not resolve it. No Android device
was attached, and no iOS framework build/device execution occurred.

Evidence: `build/readiness-native-startup-2026-09-06`, including ordinary full
suite logs, coverage, native fixture JSON/PNG/PCM, helper reports, partial native
compile logs, `source-manifest.json`, `linux-source-comparison.json`, and container
inspection records. Earlier failed attempts remain separate from passing logs.

The current assessment is **59/100 published main, provisional 72/100 local**.
The source-order and ordinary-suite defects account for the two restored local
points relative to the initial September 6 audit. Reconciled documentation and
helper tests do not imply completed device/release/operations requirements.
GitHub main remains `c95f7acadacd6a5048e080ac6edd1b4143206769`; the newly inspected
September 6 backup/rollback workflow passed temporary-file fixtures, while live
operations probe/alert runs remain skipped. There are no published releases.
No commit, push, merge, signing, deployment, or protection change occurred.

## 2026-09-06: Recovery Accessibility and Windows Build

The previous turn made progress by reconciling the native-startup evidence and
architecture. This continuation attempted Windows native acceptance, established
a usable isolated Windows session, compiled the actual app, and fixed two
independently reproduced recovery-layout defects. It does not complete the
installed native acceptance requirement.

At 3x text scale, the destructive reset confirmation overflowed by 420-728 pixels
on the tested small viewports. The save-failure notice overflowed by 852 pixels
in the landscape fixture. `LibraryRecoveryScreen` now uses a scrollable reset
dialog. `LibrarySaveFailureNotice` bounds its separately scrollable error area to
half the available height and exposes the error as a semantics live region.
No reset, storage, import, or persistence behavior was relaxed.

Five new regressions exercise 320x480 and 480x320 recovery layouts in both text
directions, fitting button labels, cancel-without-reset, labeled/minimum-size
tap targets, and a reachable functional reload action. All nine recovery tests
pass. Two disposable captures with Segoe UI were visually inspected at 3x scale;
the dialog warning and long save error remain scrollable rather than being
forced into the viewport. This is not an actual screen-reader or translated UI
acceptance test. The temporary capture harness uses test storage, not the native
app or real user data.

Final ordinary Windows Flutter suite: **1,171 passed, four existing link-privilege
skips**. Strict analysis with fatal infos passes. Coverage is
**31,096/42,205 lines (73.68%)**, 199 reported Dart files. All **389** manifested
client inputs match the final source. Relative to the previous Linux manifest,
only the recovery UI and its test changed. A dependency tool rewrote lockfile
formatting without changing any lines of dependency content; the recorded
baseline bytes were restored, verified by SHA-256. No dependencies were updated.
Earlier logs retain the initial layout failures, test-semantics handle-lifetime
mistake, and deprecated matcher diagnostic separately from the final green run.

Windows environment results:

- Flutter doctor reports Flutter 3.44.6/Dart 3.12.2 and Visual Studio Enterprise
  2026. No attached Android device was reported. The initial Windows app build
  stopped on missing symlink privileges before compiling.
- Flutter's pinned tool source accepts existing plugin links. Thirty-five
  junctions were created/verified only inside ignored Windows/Linux plugin build
  directories, pointing to the already-resolved SDK/package sources. No SDK
  edits, Developer Mode, elevation-policy changes, or dependencies were needed.
- The ordinary `flutter build windows --debug --no-pub` then succeeded. The
  complete 35-file debug bundle is hashed. Executable SHA-256:
  `f1b9726bb1ef11d1db8f442b9291dc3c9398315e4f9d56928b28d0a6ca5f9ac4`.
  Compilation is not proof of clean-machine runtime dependencies, installation,
  migration, native playback, secure-vault persistence, or signing.
- Windows Sandbox initially returned no readiness evidence, but later produced
  a valid `WDAGUtilityAccount` readiness file and shut down. The exact preflight
  launcher was closed; final `wsb list --raw` shows no environments. Only a
  disposable evidence folder was mapped, with network/clipboard/audio-input/
  video-input/printer access disabled. No AetherTune app ran in the user's
  Windows profile, and no production protocol registration was changed.

Evidence under `build/readiness-windows-native-2026-09-06` includes
`flutter-tests-verified.log`, `flutter-analysis-verified.log`, `lcov.info`,
`source-manifest.json`, `source-comparison.json`, `recovery-layout-before.log`,
`recovery-semantics-final.log`, the two PNG captures, `windows-build-junctions.log`,
`windows-debug-bundle.json`, `plugin-junctions.json`, and sandbox preflight/cleanup
records. The prior Linux full-suite/native evidence predates this narrow UI
change and is not relabeled as a rerun.

Next Windows acceptance work should run the actual app inside the now-confirmed
disposable environment and verify clean-machine dependencies, migration,
credential persistence, playback, and restart. The assessment remains
**provisional 72/100 local, 59/100 for the last audited published main**. No commit,
push, merge, signing, deployment, or repository-protection change occurred.

## Remaining Completion Requirements

These are still necessary; the current assessment does not justify 100/100 or a
production release. Points are based on evidence, not completed checkboxes.

1. **Prove native library durability.** The silent-save defect is corrected
   locally with atomic snapshots, rollback, and regression tests. Still exercise
   process interruption at additional boundaries, power loss and directory
   metadata, other filesystems/targets, and installed migration. Windows/Linux
   process death, a 25,000-track serialized fixture, and real bounded Linux
   filesystem exhaustion now have native evidence; they do not cover every target.
2. **Finish recovery acceptance.** Startup recovery and explicit restore/reset
   are implemented and tested locally. Expand malformed/type-invalid settings
   and interrupted migration cases, and validate native file pickers,
   localization, and accessibility on installed builds.
3. **Finish offline native acceptance.** Aggregate media budgets, serialized
   cache mutations, validated resume, and explicit reclamation now have local
   regression evidence. Dart-side handoff now has cancellation/drain, lifecycle,
   real HTTP resume, and stale-snapshot regression evidence. Native shutdown gates
   are implemented and portable helpers tested, but actual engine integration
   remains unproven. Still test process termination, live policy changes, actual
   native-engine handoff/acknowledgment, actual disk-full and constrained devices,
   and link protection across native filesystems. Current Linux link regressions
   pass. Logical media reservations
   are not proof of available physical storage or a cross-file transaction.
4. **Validate deployed abuse controls.** Exercise the actual TLS proxy,
   account/device load, snapshot conflicts, and sustained traffic. The new
   in-process ingress budget is shared behind a proxy address; configure the
   deployment and its trusted client-IP limiter accordingly.
5. **Real client acceptance.** Exercise import/playback/sync, Bluetooth and
   interruptions, background/process termination, codecs, installed updates,
   desktop host integration, Android Auto, and accessibility across supported
   targets. The new isolated Linux fixture now covers real-plugin migration,
   generated WAV decoding, MPRIS, and persisted state across process restarts.
   Record the remaining installed and physical-device evidence separately.
6. **Operational recovery.** The compiled Windows and Linux services now pass
   coordinated backup and credential/snapshot recovery with kill/restart checks.
   Linux systemd identity/restore now has isolated runtime evidence. Execute the
   matching macOS and actual deployment workflows, then test
   interrupted writes, live rollback across releases, representative workloads,
   physical storage failures, and production recovery objectives/load capacity.
7. **Active operational gates.** Repair the governance token/configuration,
   verify current repository protections, run production probes and alerts,
   and execute the now-passing local container release gate on GitHub for the
   exact committed candidate. Continue scanning as the vulnerability database
   and runtime dependencies change.
   Do not weaken sole-owner protections or invent an external reviewer.
8. **Release evidence.** Build the final corrected revision, complete required
   signing/notarization, verify clean-machine installation and upgrades, and
   publish a verified production release with live operational evidence.
9. **Maintainability and assessment.** Extract persistence/offline
   responsibilities as needed, reconcile stale acceptance claims, measure
   updated coverage, and reassess every rubric item against executed evidence.

Physical devices, deployment credentials, production URLs, and signing
identities have not been assumed available or fabricated. Work on code and
local verification can continue while those external requirements are pending.

## 2026-09-06: Token Expiration Across Recovery and Rename

The preceding deep audit was progress: its new recovery-token expiry
reproduction identified the next concrete production defect. Follow-up review
found that renaming a device also reconstructed its token without a deadline.
Both paths now preserve the policy; the internal nullable expiry parameter is
required, making omission a compile-time failure. Authenticated metadata exposes
assigned deadlines without revealing bearer values or stored digests.

The 15 new registry and HTTP-handler regressions produced six passes and nine
failures before remediation, then all passed after it. They cover default and
custom policies, explicit non-expiring tokens, exact boundaries, rename,
profile/activity writes, durable restart, legacy rotation and rejection of
expired reads/mutations. The original audit probe also passes unchanged.

Verification for the corrected candidate:

- Server: 102 tests passed; strict analysis clean.
- Client: 1,171 tests passed, four existing Windows symlink skips; strict
  analysis clean. A compatibility fixture accepts the new optional metadata.
- Python CI: 171 discovered, 164 passed, seven platform skips.
- Fresh Windows server executable compiled and passed 21 real-process recovery
  checks, including expiry preservation through rename, backup/restore and
  recovery/restart. The fixture took 35.453 seconds; its 0.609-second controlled
  restore measurement is not production RPO/RTO or power-loss evidence.
- The fixture's server and helper processes exited; no real account, device
  credential, production service or host clock was modified.

The server upgrade guide now explains how to identify and rotate/revoke stored
non-expiring credentials under an expiring policy. Legacy intent cannot be
inferred from missing deadlines, so upgrades do not silently expire ambiguous
records. The feature matrix now describes the implemented file-snapshot storage
and SQLite lock rather than the superseded preference-only backend.

Evidence:
[build/readiness-token-expiry-2026-09-06](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-token-expiry-2026-09-06).
The current local assessment is provisionally 72/100; published main remains
58/100 at `c95f7acadacd6a5048e080ac6edd1b4143206769`. This restores the local
security point lost to the audit finding; it adds no device, release or real
operations credit. No commit/push/signing/deployment occurred. Exact-candidate
CI publication, installed native acceptance, production monitoring and measured
off-host recovery remain outstanding, so the full goal stays active.

## 2026-09-06: Windows Release Startup

A real release build and a fresh Windows Sandbox reproduced two startup gates:
missing app-local C++ runtime DLLs, followed by a native hotkey argument abort.
The original ZIP exited before initialization. A runtime-only package reached
Flutter but failed with `0xc0000409 / FAST_FAIL_INVALID_ARG` in the Windows
hotkey plugin. Method-channel tests separately caught null modifiers and null
previous/next virtual-key codes. Dart exception handling cannot catch this
native process termination.

Both ZIP and MSIX packagers now stage validated, Microsoft-signed x64 release
runtime files with a version/hash manifest. Production artifact verification
checks these payloads. The input Flutter bundle remains unchanged. The desktop
media-key bindings supply empty modifier lists and explicit Win32 virtual-key
codes only on Windows, preserving the other platform mappings. The repository
notice and release guide distinguish Microsoft runtime terms from project 0BSD.
No global SDK or Pub cache files were edited.

The final ZIP displayed the actual onboarding screen and remained alive through
15 seconds of observation in another clean Sandbox without system-installed
runtime DLLs. Its runtime modules loaded from the packaged app directory.
Networking, clipboard and device input redirection were disabled; only fixture
inputs/results were mapped. The app and guest were stopped, and final inventory
contains no remaining owned app or Sandbox environment.

Verification: Windows release compile passed; actual ZIP and unsigned MSIX
packaging and runtime payload checks passed; the PowerShell runtime suite passed
its valid case and five negative cases; ZIP/MSIX regression tests passed. Strict
Flutter analysis is clean, with 1,173 passing tests and four existing Windows
symlink skips. Dart line coverage is 31,107/42,212 (73.69%). Python CI discovery
passes 166 of 173 tests with seven platform skips. Server code is unchanged from
the preceding 102-test/21-runtime-check candidate; those runs were not repeated.

The upstream ANGLE payload still includes a `zlib.dll` dependent on debug CRTs.
It has no observed direct importer in the bundle and was not loaded at startup,
but this does not rule out dynamic/video-path usage. It was not removed, and
debug runtime files were not shipped. Resolving that artifact and proving the
media paths remains necessary before release. Signed installation, upgrade,
actual key delivery, playback, lifecycle and production operations also remain
unverified by this startup fixture.

Evidence: [Windows release verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-windows-release-2026-09-06).
GitHub main was rechecked at `c95f7acadacd6a5048e080ac6edd1b4143206769` and still
contains both faulty source paths. The published score decreases from 58 to 56;
the provisional local score remains 72 because new startup evidence and the
newly identified dependency gap offset in the rubric. These are approximate
engineering scores, not certifications. No commit/push, signing, merge,
production deployment or protection change was performed. The full goal remains
incomplete, with meaningful local progress and no new blocker declaration.
