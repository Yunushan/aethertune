# Production Readiness Evidence: 2026-10-01

**100/100 remains unproven; broad production release is not approved.** The last
weighted assessment is the historical **81/100** recorded on September 24 for
`0e11952910e2915690bebbb83e07da82a872229c`. This checkpoint records subsequent
evidence without assigning a new score. Scope remains Android, iOS, Linux,
macOS, and Windows clients plus the optional self-hosted sync service.

## Integrated source and hosted acceptance

Published `main`, observed at the start of this checkpoint, was
[`5b3e5fb2ee502bf9eddd6618b72303dc2939e573`](https://github.com/Yunushan/aethertune/commit/5b3e5fb2ee502bf9eddd6618b72303dc2939e573).
PRs [#43](https://github.com/Yunushan/aethertune/pull/43),
[#44](https://github.com/Yunushan/aethertune/pull/44),
[#45](https://github.com/Yunushan/aethertune/pull/45),
[#46](https://github.com/Yunushan/aethertune/pull/46), and
[#47](https://github.com/Yunushan/aethertune/pull/47) were squash merged after
required checks passed. Their temporary branches and managed worktrees were
removed. The September 30 checkpoint retains the earlier implementation history;
its statements about unmerged changes and outstanding hosted acceptance are
historical.

The final PR #43 head was `4add9777d5aa4493139fc1cc24f88d4470c194de`.
Its 17 check results were terminal: 16 successful and the secondary Trivy SARIF
result neutral. All eight required checks passed. The
[CI run 36766546443](https://github.com/Yunushan/aethertune/actions/runs/36766546443)
ran all 23 OSV guard regressions on Ubuntu without skips, including the symlink
regression. Raw OSV, CodeQL, and rebuilt-container policy checks passed.

[Native iOS acceptance run 36766546408](https://github.com/Yunushan/aethertune/actions/runs/36766546408)
passed all 23 runtime checks across seed, reopen, and sync phases. The executed
GitHub merge revision `3d8b6fbb92f8a839cdcbdef9fba0e8d82a03ebd6` and published
main have the same tree, `63dfef3becb17d1de6a6134b197fc6dab9843c0c`.
Independent artifact inspection verified one unchanged application data container,
three distinct matching process IDs, persisted preferences/library/queue settings,
keychain behavior, native playback, and trusted/rejected TLS behavior. There were
no assertion recoveries. The owned Simulator was deleted and ordinary app output
restored. Artifact `11123252770` has digest
`sha256:c5e8bc6dc8a14122f27449831e38a75b7ef061fa1c369e3243500177ab3937c2`.
This is hosted Simulator evidence with synthetic media and a guest CA; it does
not establish physical-device, distribution-signing, or upgrade acceptance.

## Release assembly on published main

[Candidate run 36894678686](https://github.com/Yunushan/aethertune/actions/runs/36894678686)
was dispatched on exact main `5b3e5fb2`. Production enablement is absent. The run
uses candidate mode and skips production signing and publication.

Attempt 1 failed and did not assemble a verified bundle:

- Android job `110478728213` failed installing CMake 3.22.1 because the downloaded
  archive was not a ZIP archive. No APK from this failed build is accepted.
- Linux job `110478728214` failed the storage probe's SQLite integrity check.
  For sqlite3 3.5.2, `libsqlite3.x64.linux.so` had SHA-256
  `251411414ea3b05b045c0aa93c75fe77713d11f732b97c8f375987307a90f003`, rather than
  the pinned `b17729184e5a2818055ecbddd5ed6642521bfe6e56aafa472330e483c0e2e0d2`.
  The integrity gate remains enforced; the unexpected download is not accepted.

Independent fresh publisher downloads subsequently matched the original SQLite
SHA-256 and Google CMake repository XML checksum/size; the CMake ZIP passed
validation of all 2,990 entries. No tracked pin defect was established. The bad
runner payloads were not retained, so their exact cause is unproven. One bounded
retry of the failed jobs was initiated on the same run and exact revision, with
all integrity checks retained. Attempt 2 succeeded on the same exact revision.

Independent verification of attempt 2 passed: 19 files, 17 manifest artifacts,
18 checksum entries, three deterministic SBOMs, and exact committed lockfile
comparisons. Bundle artifact `11180522356` has size 432,690,478 bytes and digest
`sha256:6a1270f6cdb0d97b20ea118e36bc2cf334f36241d5a856f9056ea41c146fb9ef`.
The APK SHA-256 is
`d97b57bb6508e0742e735f87f768776b12773b42472464d150075201a55592cd`; the manifest
SHA-256 is `81f3465596fbff66939ba7bd1c86d48f1c9c12531412d2f8f7d4b10a435399cc`.
APK and manifest attestations verified against the exact release workflow on
`refs/heads/main`, with both signer and source digest equal to `5b3e5fb2`.
Both attestation statements match all 18 locally verified checksum subjects and
identify this run's second attempt. Ten successful jobs were inherited from
attempt 1; Android, Linux, and assembly executed on attempt 2. Production signing
and publication remained skipped. This is a verified nonpublishing bundle for
main `5b3e5fb2`; subsequent source corrections need their own relevant acceptance.

## Operations probe correction prepared for review

A synthetic reproduction found the raw metrics token in curl's process
arguments, contrary to the deployment runbook. The correction supplies the
Authorization header through stdin and rejects empty, carriage-return, and
newline credentials before HTTP. HTTPS/loopback scope, bounded requests,
distinct metrics credentials, and response validation remain enforced.

Real curl and owned loopback HTTP regressions verified valid primary/fallback
credentials, rejected wrong credentials, and absence of the token from captured
curl arguments and probe output. All three new behavioral methods ran locally
without skips. The combined probe and operations-workflow suites discovered 17
tests: 15 passed and two existing POSIX-only cases skipped on Windows. The new
behavioral tests reproduced the original defect before the correction. Bash
syntax and diff checks passed.

[Draft PR #53](https://github.com/Yunushan/aethertune/pull/53) carries this correction.
At head `eebb94c3262603452a4ebdcfb481aff971c289ad`, the
[Ubuntu server job](https://github.com/Yunushan/aethertune/actions/runs/36899148858/job/110493626128)
passed all nine probe contract tests without skips, strict analysis, 117 Dart
tests, and authenticated probes against both the compiled server and container.
Native compile, systemd verification, load/restart, and recovery gates also
passed. Final-head required checks still gate integration. These controlled
fixture results do not establish deployed operations acceptance.

## Ordinary Android candidate acceptance

An owned API 35 x86_64 emulator exercised the ordinary release APK from verified
run `36894678686`, without instrumenting or rebuilding the application. The
fixture-signed derivative had SHA-256
`01fb85e6c77d22f89d12b5348ca42e2395097071fabf7289ac78bafad29d6cd5`; all 324
non-signature payload entries matched the attested original APK. This is fixture
signing, not production signing.

The retained local `build/readiness-2026-10-01/android/result.json` reports 25
scoped checks passed, including provenance, clean installation, onboarding,
synthetic WAV import/playback/pause/seek, favorite/offline/volume/queue persistence
across fresh application processes (`2758` then `5867`), uninstall, and cleanup.
The fixture ran through the ordinary UI. Unloaded `0:00 of 0:00` after reopening
does not establish cursor restoration.

Two findings prevent full Android playback/system-media acceptance:

- Play at the completed 20-second track did not rewind. Explicit seek to the
  start followed by Play worked; replay after completion is not passed.
- Native logs repeatedly reported `You must specify an icon resource id to build
  a CustomAction` while audio_service published playback state. Metadata and
  queue existed, but the observed system media session was inactive/NONE after
  completion. System-media controls are not passed.

These findings require source correction and execution of a new exact-source
release APK with resource shrinking retained. The application was uninstalled;
owned emulator/ADB processes and ports were closed and fixture private keys
removed. This run does not establish physical audio, production signing,
versioned upgrade/rollback, or broader lifecycle/accessibility acceptance.

[Draft PR #54](https://github.com/Yunushan/aethertune/pull/54) carries a prepared
correction at `1584b7fb9091be08bb94d49a7eff850084016760`. Exact-source
[candidate run 36906007502](https://github.com/Yunushan/aethertune/actions/runs/36906007502)
targets that head. Replay and system-media runtime acceptance still require
the fresh candidate; both original findings and unproven cursor restoration
remain recorded. Local source tests do not establish that acceptance.

## Ordinary Windows candidate acceptance

An owned, marked Windows Sandbox guest exercised the ordinary MSIX from
verified release run `36894678686`, attempt 2, artifact `11180522356`, on exact
source `5b3e5fb2ee502bf9eddd6618b72303dc2939e573`. The original MSIX SHA-256 is
`b341de7563c7798fcf321ce1910625fa13554291d972e5e056a7521db7eb1473`.
Identity remained `AetherTune`, publisher `CN=AetherTune`, version `0.1.0.0`,
architecture `x64`. Certificate creation, test signing, and test trust occurred
only inside the guest; the private key was not exported.

The fixture-signed derivative had SHA-256
`47fa8b4d6875f6e132a4e57f197e73d094e727aba575d4aaae95c7a632cdd049`.
Guest checks and an independent host ZIP comparison preserved 54 of the 55
original entries byte for byte, including the manifest, block map, and every
application payload entry. The only changed original entry was
`[Content_Types].xml`, which gained only the two signature metadata declarations.
Only `AppxSignature.p7x` and `AppxMetadata/CodeIntegrity.cat` were added; both
signatures verified with the same disposable guest certificate. No application
was rebuilt or instrumented, and no version or publisher identity changed.

The guest lifecycle passed clean installation, installed AUMID activation,
15 seconds of continuous window survival, graceful application close, and
uninstall of exact package `AetherTune_0.1.0.0_x64__78pqjtf8hq8py`.
The installed ordinary EXE SHA-256 matched the original bundle:
`c959822a9acc34430a45616aa933b8134abc7a77168b237a21166451f750680c`.
The retained screenshot was reviewed and shows normal "Welcome to AetherTune"
onboarding. Package registration, application processes, install directory,
package app data, and legacy protocol registration were all absent after
uninstall; guest certificate cleanup reported no failures.

The raw host coordinator remains **failed**: its disconnected modern Sandbox
UI did not exit within 45 seconds after the guest finished. The official CLI
stopped exact owned session `dc98548b-0605-4273-b2db-e10d55dc114d` with exit 0 and
confirmed it absent. Only the recorded owned UI process was then force-stopped,
with its path and start time checked. Final read-only inspection found all
recorded helper/UI processes absent, no Sandbox session/VM processes, and an
empty official session inventory. Automatic Sandbox UI shutdown is not passed.

The retained local
`build/readiness-2026-10-01/windows-install/verification-summary.json` preserves
the guest pass, raw host failure, earlier pre-install fixture failures, payload
comparison, screenshot, and final cleanup observations. Host trust/settings
were unchanged. This proves only the stated ordinary lifecycle under guest
test trust; it does not establish production signing, SmartScreen or Store
trust, versioned upgrade/rollback, accessibility, physical audio, or deployed
service acceptance.

## External state observed on October 1

Authenticated metadata-only inspection found zero Actions secrets and variables
at repository scope and in `production`, `production-monitoring`, and `candidate`.
No secret values were read. No GitHub settings were changed.

The sole-owner governance mode remains confirmed: the repository owner is the
only direct collaborator, and owner approval with self-review allowed matches
the checked-in policy. Main protection, environment branch/tag boundaries,
wait/reviewer rules, administrator enforcement, and selected action policies
passed the read-only evaluation. The full evaluation failed specifically on
**non-provider secret scanning** and **secret-scanning validity checks**, which
remain disabled. The latest inspected
[governance workflow 36412681364](https://github.com/Yunushan/aethertune/actions/runs/36412681364)
failed for missing authentication; its required governance secret is absent.
GitHub settings changes remain outside the authorized work.

The latest inspected [production probe 36871917974](https://github.com/Yunushan/aethertune/actions/runs/36871917974)
and [alert run 36871942286](https://github.com/Yunushan/aethertune/actions/runs/36871942286)
were skipped on main `5b3e5fb2`. All 697 available runs of each workflow lacked
completed, non-skipped execution. Production and monitoring deployment inventories
were empty, and no configured public service endpoint was discoverable. These
results do not establish deployed health or receiver-confirmed notification delivery.

No connected physical Android or Apple device was available. The owned emulator
acceptance above covers only its stated checks and retains its two findings. Existing
candidate package versions are Android `0.1.0`/code `1` and Windows `0.1.0.0`;
same-version replacement cannot prove a versioned upgrade or rollback.

## Evidence still required for 100

1. Successful assembly and independent checksum, manifest, SBOM, and attestation
   verification for the exact integrated revision; successful credentialed
   governance and the two required security controls.
2. Required signing and Apple notarization for all five client platforms, with
   exact identities/hashes and clean install, migration, versioned upgrade,
   rollback, and uninstall acceptance.
3. Physical Android/iOS audio, interruptions, Bluetooth, power, and storage tests;
   representative installed desktop behavior and actual assistive-technology tests.
4. Deployed HTTPS/proxy acceptance at agreed capacity/SLO targets, independent-host
   restore measured against explicit RPO/RTO targets, successful production probes,
   and independently confirmed alert/failure-notification delivery.
5. A bounded real pilot/soak and approval of the exact release candidate, traceable
   to build, scan, installation, accessibility, and operations evidence.

The [historical weighted assessment](PRODUCTION_READINESS_POST_MERGE_2026-09-23.md)
and [release guide](RELEASE_GUIDE.md#production-enablement-inventory) retain the
rubric and release requirements. Passing local tests does not satisfy missing
signed, physical, deployed, or operational acceptance.
