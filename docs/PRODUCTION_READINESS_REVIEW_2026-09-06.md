# Production Readiness Review

Latest: **55/100 published main; provisional 73/100 local candidate**. The
[current final assessment](PRODUCTION_READINESS_FINAL_2026-09-06.md) supersedes
the historical records below and includes local queue-save remediation,
the native video timeout, 1,200 passing Flutter tests, two formatting failures
and the revised weighted breakdown. Historical statements below that a local
defect is still unfixed must not be read as the latest candidate status.

## Earlier Reassessment

2026-09-06, approximately 10:55 UTC. **Published main: 56/100; unpublished
local candidate: provisional 72/100. Neither is ready for broad production.**
The weighted table under the Windows follow-up below remains the current
breakdown. These are engineering judgments, not reliability probabilities,
security certifications, test coverage, or MetroList feature-parity percentages.
Blocking data-safety and release requirements cannot be averaged away.

GitHub main was freshly rechecked at
[`c95f7ac`](https://github.com/Yunushan/aethertune/commit/c95f7acadacd6a5048e080ac6edd1b4143206769).
Its ordinary CI jobs are green and branch protection lists eight required
contexts. The releases API still returns no published releases. The latest
[production probe](https://github.com/Yunushan/aethertune/actions/runs/34023450759)
and [alert delivery](https://github.com/Yunushan/aethertune/actions/runs/34023459924)
are skipped; the successful
[recovery drill](https://github.com/Yunushan/aethertune/actions/runs/34020573129)
does not establish an off-host production restore or representative capacity.

### Priority Findings

1. **High, published:** library preference writes ignore failure results and
   update related sections independently. Retained isolated probes reproduce
   silent loss on reopening. The local snapshot/recovery fix is unpublished.
2. **High, published:** a crafted imported cache identifier can escape the media
   directory when processed. The reproduced write used disposable fixture files;
   it is not demonstrated remote code execution. Local containment is unpublished.
3. **High, published:** Windows packaging omits release C++ runtimes and media-key
   registration sends native-incompatible payloads. Local clean-Sandbox startup
   exposed and fixed both defects. Published source still has those paths.
   The published iOS generator also installs handlers before engine startup;
   that ordering defect is source-verified, not a physical-device reproduction.
4. **Medium, published:** recovered/renamed server tokens can lose expiration,
   and diagnostics do not redact several credential formats. Local fixes and
   regressions exist but are unpublished. Already-issued non-expiring tokens
   require operator review; the code change cannot infer their intended lifetime.
5. **Release gate, both:** signed installations, existing-user upgrades,
   representative native codecs, physical-device background audio/interruptions,
   Bluetooth routing and accessibility acceptance remain incomplete. Passing
   debug builds or widget tests do not establish these behaviors.
6. **Operations gate, server:** working production monitoring/alert delivery,
   realistic authenticated sustained load and off-host backup restoration are
   not demonstrated. Offline-only distribution does not need server operations,
   but still needs the client data-safety and platform release gates.

Detailed source references and retained reproductions follow in the earlier
audit records. Local remediation is distinguished from published behavior there.

### Newly Reviewed Local Packaging Gaps

The packaging work has advanced since the startup-only artifact described below.
It now proposes omitting only the exact known ANGLE debug `zlib.dll`, after
hash, import-table, delay-load and literal-reference checks. Its native fixture
tests passed, but **the changed package has not completed native audio/video
acceptance**. Literal/reference scans cannot prove that no runtime path constructs
a DLL name dynamically. The earlier Sandbox screenshot validates the earlier
package, not this new omission policy. No extra release credit is awarded.

Two additional incomplete safeguards were confirmed during this review:

- **Medium:** the debug-runtime expression misses actual installed SDK filenames
  including `vcruntime140_1d.dll`, `msvcp140_1d.dll` and `msvcp140_2d.dll`.
  Evaluating those names against the current expression returned false, while
  `vcruntime140d.dll` and `ucrtbased.dll` returned true. Those names were checked
  against the installed Visual Studio `debug_nonredist` directory. Extend the
  policy and its regressions before claiming comprehensive debug-CRT rejection.
  This does not establish that the current release bundle loads those missed DLLs.
  Source: [debug DLL policy](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/windows_native_dependencies.ps1:4).
- **Medium:** final Python artifact verification checks the runtime manifest,
  but does not require or validate the newly generated native module manifest.
  Its existing accepted fixtures contain no native manifest. The package-stage
  audit and final artifact validation therefore do not yet form one verified
  chain. This is distinct from cryptographic signature verification, which is
  intentionally performed in the Windows signing steps.
  Source: [artifact verification](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/verify_windows_release_artifacts.py:98).

### Evidence Freshness

- Fresh Python CI discovery: **173 tests, 166 passed, seven platform skips**.
  Printed failure reports in negative mocked fixtures are expected test output,
  not fresh live Docker scans or production incidents.
- Rehashed all **583 listed inputs** from the retained Windows verification
  manifest: six existing packaging/workflow files changed; none of its listed
  client or server inputs changed. New native-policy files are additional work
  and are not covered by that earlier manifest.
- Retained ordinary Flutter evidence: **1,173 passed, four Windows
  symlink-privilege skips**, strict analysis clean. Recomputed LCOV totals:
  **31,107 / 42,212 executable Dart lines, 73.69%**. Native code, physical devices,
  branch coverage and whole-product behavior are outside that percentage.
- Retained server evidence: **102 passing tests** and **21 compiled-process
  recovery checks**. These are prior same-day results, not fresh full-suite runs
  during this reassessment.
- The actual earlier unsigned Windows ZIP started in a clean Sandbox; it proves
  startup only. No new native runtime, signed install, physical device campaign,
  live provider credential flow or independent security assessment ran here.

This reassessment changed only this report and ran read-only review/test checks.
Existing code changes were preserved. No commit, push, merge, approval-policy
change, release signing or production deployment was performed. The separate
readiness-to-100 goal remains incomplete.

## Windows Release Verification Follow-up

2026-09-06, approximately 10:28 UTC: **published main: 56/100; unpublished local
checkout: provisional 72/100. Neither is ready for a broad production release.**
This is the current assessment; the earlier records below are historical.
The score is a weighted engineering judgment, not test coverage or a guarantee.

Two previously untested Windows startup defects were reproduced and fixed
locally. Both faulty source paths are still present on published main
`c95f7acadacd6a5048e080ac6edd1b4143206769`, rechecked through GitHub during this
follow-up. The runtime tests used the local candidate, not a separately rebuilt
published-main executable.

1. The Windows ZIP omitted `msvcp140.dll`, `vcruntime140.dll` and
   `vcruntime140_1.dll`. A fresh Windows Sandbox with none of these installed
   exited before the app registered its URL scheme or created a window. The
   ZIP and MSIX packagers now stage the Visual Studio x64 release CRT, check PE
   architecture and Microsoft signatures, and record versions and SHA-256 hashes.
   Source bundles are not modified. Production artifact preflight now checks
   runtime manifests, required files, hashes and certificate-table presence;
   actual signature verification remains in the Windows signing/packaging steps.
   See [ZIP packaging](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/package_windows_zip.ps1)
   and [runtime validation](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/windows_runtime.ps1).
2. Adding the runtime revealed a second process termination,
   `0xc0000409 / FAST_FAIL_INVALID_ARG`, in `hotkey_manager_windows_plugin.dll`.
   Our native payload sent null modifiers; the pinned plugin assumes a list.
   A new method-channel regression also found null previous/next Windows key
   codes because the plugin's lookup no longer covers them in the pinned Flutter
   key map. The three media bindings now use empty modifier lists and explicit
   Win32 media virtual-key codes only on Windows. Other platforms retain their
   existing lookup. No plugin cache or Flutter SDK source was edited.
   See [media-key bindings](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/ui/widgets/desktop_global_hotkeys.dart).

The final actual ZIP opened a nonblank AetherTune onboarding window in a fresh
Windows 11 Sandbox, remained alive for the 15-second observation period, and
created only guest-profile app data. Its loaded-module list confirms the three
runtime DLLs were loaded from the app directory. The guest had networking,
clipboard, camera, microphone and printer redirection disabled. The screenshot
was visually inspected. The fixture stopped its app and shut down the guest;
the final Sandbox inventory and owned-process list are empty. This establishes
startup only, not playback, OS media-key delivery, accessibility, update/rollback,
graceful shutdown or signed MSIX installation.

**A further release dependency issue remains open:** the upstream ANGLE bundle
from `media_kit_libs_windows_video 1.0.11` includes `zlib.dll` importing
`VCRUNTIME140D.dll` and `ucrtbased.dll`. No other root bundle DLL directly imports
`zlib.dll`, and it was not loaded during this startup test. Dynamic loading and
other media paths have not been ruled out, so the file was not removed or
replaced. Debug runtimes were not bundled. Resolve the upstream payload and
exercise video/codec paths before treating this Windows artifact as releasable.
Microsoft documents that debug C++ runtime DLLs are not redistributable;
release runtime deployment also remains subject to its terms:
[debug deployment guidance](https://learn.microsoft.com/en-us/cpp/windows/preparing-a-test-machine-to-run-a-debug-executable?view=msvc-170),
[release deployment guidance](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170).

Verification in this follow-up:

- Flutter strict analysis: clean; full ordinary suite: **1,173 passed, four
  existing Windows symlink-privilege skips**. New native-channel and non-Windows
  serialization regressions pass. The retained pre-fix run fails on null
  modifiers; the intermediate run fails on a null native key code.
  Reported Dart line coverage is **31,107 / 42,212 (73.69%)**, not whole-product
  coverage or evidence of native/device behavior.
- Windows release build: passed. ZIP and real unsigned MSIX packaging passed;
  runtime payload/hash checks passed for both actual artifacts.
- PowerShell runtime validation: valid payload plus five negative cases passed.
  ZIP/MSIX packaging regressions verify required runtime entries and unchanged
  input bundles.
- Python CI suite: **173 discovered, 166 passed, seven platform skips**.
- Prior exact-source server evidence remains **102 passing tests** and **21
  compiled-process recovery checks**; server source did not change here and
  those suites were not rerun during this packaging/hotkey follow-up.

Final ZIP SHA-256:
`4adc4f9ca14fee1c4b12d2c9903fe0e50605201958dab8bb6d750d6cbd4d013b`.
Final unsigned MSIX SHA-256:
`29760bd44aff5537687f7223bf1b827a0f8c1fe15ecb0854f74c06e3f07d66a2`.
Before/after ZIPs, debugger output, logs, screenshots, hashes and cleanup records
are retained in [the Windows release evidence directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-windows-release-2026-09-06).

### Current Weighted Score

| Area | Maximum | Published main | Local checkout |
|---|---:|---:|---:|
| Product implementation | 15 | 10 | 12 |
| Data durability and recovery | 15 | 6 | 11 |
| Security and privacy | 15 | 6 | 12 |
| Automated quality assurance | 15 | 12 | 13 |
| Device and accessibility validation | 10 | 4 | 5 |
| Release engineering and distribution | 10 | 6 | 6 |
| Operations and recovery evidence | 10 | 6 | 7 |
| Maintainability and documentation | 10 | 6 | 6 |
| **Total** | **100** | **56** | **72** |

Published main loses one product point for the startup-crashing hotkey contract
and one release point for the dependency packaging failures. Locally, the new
clean-environment startup evidence adds one validation point; the unresolved
native payload issue removes one release point, leaving the overall score
unchanged. Other categories retain the preceding audit's credit. The precision
of individual point changes should not be overinterpreted.

Remaining gates include publishing/reviewing the local safety fixes, required
CI on that exact candidate, the native dependency issue above, signed clean
installs and upgrades across platforms, physical-device audio/lifecycle tests,
real monitoring/alert delivery, representative load, and off-host recovery.
No commit, push, merge, signing, production deployment or protection change was
performed. The readiness-to-100 goal is still incomplete.

## Token-Expiry Remediation Follow-up

2026-09-06, approximately 09:52 UTC: **published main remains 58/100; the
unpublished local checkout is provisionally 72/100. Neither is production-ready.**
This follow-up supersedes the local score and unfixed-local-expiry statement in
the initial audit below; that audit is preserved as historical evidence.

The audit's recovery defect is now fixed locally. Further inspection reproduced
the same expiration loss when a device was renamed, including HTTP 200 after
the original deadline and after registry restart. Both issuance and rename now
preserve the configured policy, and every internal token constructor must
explicitly provide its nullable expiration. Authenticated token metadata now
includes an assigned `expiresAt`; raw bearer values and digests remain excluded
from account listing.

Fifteen new regressions cover default and custom lifetimes, the exact expiry
boundary, persisted restarts, explicit no-expiry settings, profile/activity
updates, renaming, legacy-token rotation, and HTTP rejection for expired profile
reads, sync reads and profile mutations. Before the fix, six passed and nine
failed: eight expiration-enforcement assertions and one missing-metadata
assertion. All 15 now pass. The original three-case audit probe also passes.

The ordinary server suite now passes **102 tests**, with strict analysis clean.
The client accepts the additional optional metadata field; its ordinary suite
passes **1,171 tests, four existing Windows symlink-privilege skips**, and strict
analysis is clean. Python CI discovery passes 164 of 171 tests, with seven
platform skips. No client production source or dependency changed in this step.

A freshly compiled Windows server passed the expanded real-process recovery
drill in 35.453 seconds. Its 21 checks include default expiry assignment, rename
preservation, snapshot/credential backup restoration, recovery expiry surviving
rename and restart, revocation, account isolation, body deadlines, backup fences,
and credential-free logs. The controlled restore/validation portion took 0.609
seconds; this fixture measurement is **not** a production recovery objective.
It validates deadline persistence; exact expiry boundaries are exercised with
the controllable-clock registry/HTTP-handler tests, not by changing the host
clock or waiting a year in the compiled-service fixture.

The executable SHA-256 is
`d59b61e8db97985726acbcf9ea5cacfb2a6dacccfbf728dbcbf2e6843254cebe`.
The fixture's backup helper SHA-256 is
`c3b8c33c17da48d9c938f6a6ca5329b9655e1078e597447ef34c152bbb736740`.
This is an uncommitted candidate, so its runtime report deliberately has no
claimed source commit. Evidence and final source hashes are under
[the token-expiry evidence directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-token-expiry-2026-09-06).
All matching server/helper processes had exited at final inspection.

Previously persisted missing deadlines cannot be reconstructed reliably:
legitimate legacy or deliberately non-expiring credentials have the same
representation. No real credentials were changed. The
[upgrade procedure](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/README.md)
requires operators using an expiring policy to review, rotate or revoke affected
non-expiring credentials through the existing authenticated API. Future issuance
fixes do not retroactively revoke those credentials. The feature matrix's stale
shared-preferences persistence description was also corrected.

Local security credit returns from 11/15 to 12/15; other category scores remain
unchanged. No release, device or production-operations credit is added for this
focused fix. GitHub main was rechecked and is still
`c95f7acadacd6a5048e080ac6edd1b4143206769`; neither expiry fix nor the other local
safety work is published. Required CI on a reviewed candidate, installed native
acceptance, signing, real monitoring, load and off-host recovery remain open.
No commit, push, merge, signing, production deployment or protection change was
performed. The readiness-to-100 goal remains incomplete.

## Initial Audit Record

Assessment: 2026-09-06, approximately 09:35 UTC. Scope: the Android, iOS,
Windows, macOS and Linux clients, plus the optional self-hosted Dart server.

**Published GitHub main: 58/100. Current unpublished local checkout: provisional
71/100. Neither is ready for a broad production release.**

These are weighted engineering judgments, not reliability probabilities,
test-coverage percentages, security certifications, or MetroList feature parity.
Confidence is higher in the concrete findings than in differences of a few
points. A critical release gate remains blocking regardless of the total score.

This review supersedes the previous 59/100 published and 72/100 local assessment.
The one-point reduction in each security score reflects a newly reproduced
account-recovery token-expiration defect present in both versions. Existing
green suites and previously verified improvements retain their credit.

## Findings

### 1. High: Published library saves can silently lose data

A fresh isolated probe rejected 35 preference writes. Adding a track still
returned normally; the in-memory library contained one track, but reopening
contained zero. Another probe fed malformed stored JSON: loading threw a
FormatException while `loaded=false` and `loadError=null`, so recovery was not
represented by the store's error state.

The published implementation writes related sections independently and ignores
the boolean results of preference setters. This is a reproduced persistence
failure, not an inference from a coverage score.

Source: [published library save](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10409).

Local status: a revision-checked snapshot backend, write-error handling,
rollback, recovery UI and regression tests are implemented but unpublished.
The backend flushes pending file contents and renames them; directory-metadata
durability during actual power loss and installed migration across the full
platform matrix remain unproven. Process-interruption tests are useful but do
not establish those stronger guarantees.

Source: [local snapshot commit](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/file_library_storage.dart:167).

### 2. High: Published cache identifiers can escape the media directory

The fresh probe imported a crafted offline-cache entry and processed it with an
injected downloader. Its output escaped `offline_media` and replaced a disposable
sentinel. No actual user files, provider requests or credentials were involved.
The attack requires a crafted imported entry to be processed and is bounded by
the application's filesystem permissions; it is not demonstrated remote code
execution.

Source: [published destination construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L118).

Local status: identifier validation, portable hashed filenames, path containment
and link rejection exist and pass ordinary regressions. Four Windows symlink
tests skip because the host lacks creation privileges. Earlier Linux tests
exercise link cases, but were not rerun in this assessment.

Source: [local containment checks](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_paths.dart:20).

### 3. High: Published iOS background startup installs handlers too early

The published generator registers plugins and configures the background
channel before `engine.run`. Flutter's implementation at the exact pinned SDK
revision asserts when a non-null handler is installed before engine setup;
without assertions it returns an error connection instead of installing it.
This is a source-verified framework-ordering defect, not a device-observed crash.

Sources: [published initialization](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/scripts/configure_audio_service_platforms.py#L1604),
[pinned Flutter engine](https://github.com/flutter/flutter/blob/ee80f08bbf97172ec030b8751ceab557177a34a6/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterEngine.mm#L1223).

Local status: startup is guarded before registration, with failure cleanup and
11 passing generator regressions. Actual iOS background start, expiration,
cancellation and foreground handoff still need device acceptance. Native helper
tests do not exercise UIKit, Flutter plugins or OS scheduling.

Source: [local initialization](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/configure_audio_service_platforms.py:1894).

### 4. Medium: Recovered server tokens bypass the expiration policy

**New, reproduced, and still unfixed locally and on published main.** Normal
`issueToken` assigns `expiresAt` from `_tokenLifetime`; `redeemRecoveryCode`
constructs a token without that field. Authentication treats a null expiration
as non-expiring. The server executable supplies a default lifetime of 365 days
and supports an operator-configured shorter lifetime, but recovery bypasses it.

A fresh three-case audit probe configured a one-hour lifetime. The normal-token
control expired correctly. Recovered tokens remained authenticated at the
one-hour boundary both in memory and after reopening the persisted registry:
one control passed, two security assertions failed. The authentication file
matches the HEAD Git blob after normal checkout filtering, confirming the same
source is published.

This requires a valid recovery code; it does not allow an unauthenticated
outsider to invent a token. It creates unexpectedly indefinite access if a
recovered bearer token is subsequently compromised. Old devices are correctly
revoked and the recovery code is consumed, which limits but does not remove the
expiration defect.

Required: apply the configured expiration when issuing recovered tokens; add
boundary, restart, default-policy and explicit-no-expiry regressions; decide
how to revoke or reissue already-created non-expiring recovered credentials.
Fixing only future issuance will not change previously persisted tokens.

Sources: [recovery issuance](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/src/authentication.dart:593),
[normal issuance](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/src/authentication.dart:507),
[expiry check](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/src/authentication.dart:386),
[server configuration](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/bin/server.dart:33).

### 5. Medium: Published diagnostic exports can preserve credentials

Fresh invented-secret probes reconfirmed five unsupported redaction formats:
OAuth access/refresh tokens, Subsonic password/token URL parameters and a quoted
JSON token. They remained in preferences and exported diagnostics. The plain
token control was redacted correctly.

Exposure requires credential-bearing error text to reach diagnostics, followed
by local access or explicit export. This is not evidence of real credentials
having leaked or of automatic diagnostic uploads.

Source: [published sanitizer](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/local_diagnostic_log.dart#L158).

Local status: version 2 stores allowlisted categories and source locations,
omits raw payloads and removes legacy reports. Current regressions pass, but the
fix is unpublished. Previously exported files or OS backups are outside that
migration's deletion guarantees.

Source: [local diagnostic policy](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/local_diagnostic_log.dart:9).

### 6. Release Gate: Installed-platform acceptance is incomplete

The live releases API returned no published releases. Signing, notarization,
checksums, provenance and artifact preflight code exist; Windows scripts also
invoke real signature verification after signing. Their presence earns release
engineering credit, not proof that distribution works.

Missing evidence includes signed clean-machine installations, upgrades with
existing libraries and credentials, uninstall/rollback behavior, physical
Android/iOS background audio and interruptions, Bluetooth routing, representative
codecs, and app-wide assistive-technology acceptance. Windows runtime dependency
completeness remains unverified; this review did not establish a missing-DLL bug.

Earlier retained evidence proves a Windows debug compile and a Linux native
storage/playback fixture. It does not establish signed release acceptance. The
earlier Linux fixture predates two recovery UI/test changes. The exact-source
Windows unit/widget suite is current. No fresh native build or device campaign
was performed in this audit.

Sources: [published releases](https://github.com/Yunushan/aethertune/releases),
[release workflow](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/aethertune-release.yml:394),
[release acceptance requirements](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/RELEASE_GUIDE.md:153).

### 7. Medium: Real production operations and capacity are not demonstrated

The September 6 09:01 UTC production probe and alert runs are skipped. A
successful backup/rollback drill at 07:58 UTC exercises temporary-file fixtures,
checksum/tamper checks, link rejection and a local executable swap. It is not an
off-host production restore or measured recovery under representative load.
An inspected August 31 governance audit failed; it is older than current main
and should not be described as a freshly failed current-commit check.

The load fixture performs 80 requests with eight workers against four small
health/info/catalog routes, not sustained authenticated snapshot uploads. It
does not establish capacity, long-running memory behavior, reverse-proxy limits,
or recovery-time/recovery-point objectives.

Published PR/push container scanning uses `--exit-code 0`; the fail-closed job is
scheduled/manual only. Therefore a green reporting scan does not establish an
enforced container-vulnerability merge gate. The local tree adds fail-closed
CI/release scanning and a pinned Distroless runtime, but is unpublished. No new
vulnerability database scan or penetration test was performed in this audit.

Sources: [production probe](https://github.com/Yunushan/aethertune/actions/runs/34023450759),
[production alert](https://github.com/Yunushan/aethertune/actions/runs/34023459924),
[recovery drill](https://github.com/Yunushan/aethertune/actions/runs/34020573129),
[older governance audit](https://github.com/Yunushan/aethertune/actions/runs/33384426481),
[published container scan](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/.github/workflows/container-scan.yml),
[load fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:17).

### 8. Medium: Integration blind spots and concentrated code increase risk

Fresh Flutter executable-line coverage is 31,096/42,205, or **73.68%**, across
199 reported Dart files. This exceeds the local 70% CI floor but excludes native
framework code and is not branch, end-to-end or feature-parity coverage.

| Component | Covered / measured lines | Coverage |
|---|---:|---:|
| File library backend | 132 / 136 | 97.06% |
| Library store | 4,840 / 5,126 | 94.42% |
| Player controller | 1,145 / 1,361 | 84.13% |
| Playback audio engine | 145 / 348 | 41.67% |
| Background queue runner | 2 / 60 | 3.33% |
| Video playback screen | 0 / 146 | 0.00% |
| Windows system media session | 0 / 77 | 0.00% |

Zero unit-suite coverage is not proof that a feature is broken. It identifies
where platform acceptance evidence matters especially strongly. Widget tests
inject a preference-backed storage fixture; separate file-backend and native
tests are necessary to establish real persistence behavior.

The home screen is 23,437 physical lines and the library store is 10,980.
Concentrated responsibilities increase review and regression cost. The feature
matrix still describes library persistence as shared-preferences JSON although
the local production factory now creates FileLibraryStorage. Broad refactoring
is not a prerequisite to fixing release blockers, but documentation and focused
ownership boundaries need attention.

Sources: [test storage injection](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/flutter_test_config.dart:7),
[production storage factory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_storage.dart:14),
[stale feature entry](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/FEATURE_MATRIX.md:49).

## Weighted Score

| Area | Maximum | Published main | Local checkout |
|---|---:|---:|---:|
| Product implementation | 15 | 11 | 12 |
| Data durability and recovery | 15 | 6 | 11 |
| Security and privacy | 15 | 6 | 11 |
| Automated quality assurance | 15 | 12 | 13 |
| Device and accessibility validation | 10 | 4 | 4 |
| Release engineering and distribution | 10 | 7 | 7 |
| Operations and recovery evidence | 10 | 6 | 7 |
| Maintainability and documentation | 10 | 6 | 6 |
| **Total** | **100** | **58** | **71** |

The strongest areas are implemented product breadth, ordinary automated tests,
local storage regressions, bounded server APIs, secure-token generation and
release safeguards. The weakest are proven installed-platform behavior,
production operations, published data safety and the newly found expiration
policy gap. Code and workflow configuration earn partial credit; only execution
evidence can close the remaining acceptance gates.

## Verification Performed

| Fresh check | Result |
|---|---|
| Full ordinary Windows Flutter suite | 1,171 passed, four symlink-privilege skips |
| Strict Flutter analysis, fatal infos | Clean |
| Dart server suite | 87 passed |
| Strict server analysis, fatal infos | Clean |
| Python CI discovery | 171 discovered: 164 passed, seven platform skips |
| Native-platform generator regressions | 11 passed |
| Recovery-token audit | Normal expiry control passed; two recovery-expiry assertions failed |
| Archived published client probes | Three library/path defects reproduced; privacy control passed and five redaction assertions failed |
| Coverage policy | 73.68%, above the 70% configured floor |
| Current source manifest | All 543 listed inputs unchanged during the audit |
| GitHub main | c95f7acadacd6a5048e080ac6edd1b4143206769, same as local HEAD |
| Main CI | Six jobs successful in the September 4 main run |
| Branch and releases | Protected, eight required contexts; no published releases returned |

Main CI source: [verified run](https://github.com/Yunushan/aethertune/actions/runs/33869551283).

The archived client probes use main source with the local resolved dependency
environment, not a pristine full native build of main. Four relevant archived
files match the published Git blobs after newline filtering and match every
source line; their raw byte hashes differ because of checkout line endings.
The library probes assert the reproduced unsafe behavior, so their passing
status means reproduction, not safety. The failing audit probes are outside the
ordinary suites and must not be confused with an ordinary CI regression.

The 543-file manifest scopes client/server/scripts/workflow inputs, not every
generated platform wrapper or ignored build artifact. Earlier same-day client
verification also has a matching 389-input manifest. Retained native/Linux and
recovery evidence was reviewed, not rerun wholesale. No physical-device test,
signed installation, live provider credential flow, production deployment,
independent security assessment or new container scan occurred.

## Required Before Release

1. Fix recovery-token expiration and add durable regression coverage, including
   a policy for tokens already issued without expiration.
2. Review and publish the existing library durability, cache containment,
   diagnostic privacy and native-startup fixes. Run required CI on that exact
   candidate commit; local uncommitted fixes do not protect GitHub consumers.
3. Run installed import/playback/sync/recovery/upgrade acceptance on every target
   claimed by the release. Prioritize Android/iOS background audio, interruption
   handling and rapid foreground return; verify real desktop media sessions.
4. Produce and validate signed/notarized packages on clean target machines,
   including native runtime prerequisites and existing-user upgrades.
5. Exercise working monitoring and alert delivery, enforce vulnerability policy,
   and measure realistic authenticated load and off-host backup restoration.
6. Complete keyboard/screen-reader/text-scaling checks, reconcile stale docs and
   reassess against the exact release candidate and its retained evidence.

Until these gates close, keep the project in a controlled alpha with backed-up,
non-sensitive test data. More features or higher aggregate coverage alone do not
make it production-ready. The optional server's operations requirements do not
apply to an offline-only installation, but its client/platform gates still do.

## Artifacts and Changes

Fresh evidence: [audit directory](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-20260906-122937).
It contains complete suite logs, the synthetic recovery-token probe, persisted
fixture registries, coverage by file, LCOV and source manifests.

This was an audit, not remediation. No application source, original tests,
dependencies, workflow configuration, branch, repository settings or production
service were changed. Existing uncommitted work was preserved. Only audit
documents and ignored evidence/probe artifacts were added or updated. No commit,
push, merge, signing or deployment was performed.
