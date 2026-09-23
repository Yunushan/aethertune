# Production Readiness Checkpoint: 2026-09-23

## Decision

**Published main: provisional 75/100. Broad production release: not yet
approved.** This is a fresh weighted engineering judgment for the five client
platforms and optional self-hosted sync service, not a reliability percentage or
security certification. It supersedes the historical September 6 published-main
score. Candidate-branch changes receive no published-main credit.

Assessed published revision:
`29f79b6850d66aa33570e353e1c01a31adaad68e`. The local `main` branch has
additional merge history but the same tree as `origin/main` before the candidate
branch changes.

| Area | Earned | Maximum | Current evidence and gap |
| --- | ---: | ---: | --- |
| Product implementation | 12 | 15 | Core library, playback, provider, offline and sync paths exist; full native behavior on installed releases remains unverified. |
| Data durability and recovery | 11 | 15 | Library/player snapshots and local recovery gates exist; a custom-catalog write can still report success after storage rejection on published main, and power-loss/installed migration acceptance is missing. |
| Security and privacy | 12 | 15 | Prior cache, token and native transport fixes are published; scans pass, but deployed proxy and independent security acceptance remain open. |
| Automated quality assurance | 14 | 15 | Current-main CI, CodeQL, OSV and container scan pass, with native and authenticated-sync gates; signed release and real-device acceptance are outside these checks. |
| Device and accessibility validation | 8 | 10 | Android emulator, iOS Simulator, Linux and Windows bounded native evidence exists; physical mobile lifecycle, macOS installed runtime and assistive-technology acceptance remain open. |
| Release engineering and distribution | 5 | 10 | Platform packaging and signing gates exist, but no published signed release is recorded. Published-main assembly uses a broad artifact download pattern that includes non-distribution evidence; branch candidates exercise the corrected pattern. |
| Operations and recovery evidence | 7 | 10 | Authenticated load and compiled-service recovery drills pass locally/CI; production probe and alert runs are skipped, and independent-host restore against RPO/RTO is unproven. |
| Maintainability and documentation | 6 | 10 | Architecture and deployment guides exist; large central modules and historical score documents need care when interpreting current status. |
| **Total** | **75** | **100** | **External acceptance and release gates remain mandatory.** |

## Evidence checked

- [Current-main CI](https://github.com/Yunushan/aethertune/actions/runs/35646602120) passed all six jobs for the assessed SHA. The Linux native acceptance step, Windows/macOS compiled-server sync load and restart steps, cross-platform client-storage steps, and server recovery drill all reported success. This checkpoint reviewed its status and logs without independently inspecting its archived evidence.
- [CodeQL](https://github.com/Yunushan/aethertune/actions/runs/35646602169), [OSV](https://github.com/Yunushan/aethertune/actions/runs/35646602036) and [container scan](https://github.com/Yunushan/aethertune/actions/runs/35646601967) passed on the same SHA.
- [Candidate release #44](https://github.com/Yunushan/aethertune/actions/runs/35892996818) passed on branch commit `fccc0ba07b3633034e90877939fab2971dea30e2`. Its 19-file bundle was independently downloaded; all 18 checksum entries and the release manifest passed verification, and the APK and manifest attestations verified against that commit. The unsigned APK also passed a bounded test-signed API 35 emulator check after its 324 non-signature ZIP entries were confirmed unchanged. This is branch and emulator evidence, not a signed production release.
- [Candidate release #45](https://github.com/Yunushan/aethertune/actions/runs/35899314950) and [PR checks](https://github.com/Yunushan/aethertune/actions/runs/35899274179) passed on later branch commit `89e113d94ababa33fb65ff7cb791de6901b71380`. The exact-head [iOS Simulator acceptance](https://github.com/Yunushan/aethertune/actions/runs/35899274233) also passed its seed, reopen, and sync phases with no recovery or error. These successful runs precede the latest local changes and must be repeated on the final candidate commit.
- The bounded [iOS Simulator acceptance](https://github.com/Yunushan/aethertune/actions/runs/35643937470) passed on a preceding PR revision. [Android emulator acceptance](ANDROID_NATIVE_ACCEPTANCE.md) and the earlier [iOS evidence](IOS_NATIVE_ACCEPTANCE.md) document real native execution, with the stated device and release limits.
- The latest [governance audit](https://github.com/Yunushan/aethertune/actions/runs/35586144402) failed because `AETHERTUNE_GOVERNANCE_TOKEN` was empty. A default workflow token cannot supply the required administrative repository reads. GitHub's repository Actions settings and protected `production` environment both showed no secrets and no variables on September 23. The latest [production probe](https://github.com/Yunushan/aethertune/actions/runs/35874148994) and [alert](https://github.com/Yunushan/aethertune/actions/runs/35874185085) were skipped. The release list was empty when queried on September 23.
- The candidate branch addresses the release download pattern, custom-catalog and other client-setting save failures, lyrics credential binding, a dedicated metrics credential, ListenBrainz lifecycle races, and local supervisor probe availability. A later audit also found that the configured `production` environment admits protected branches while the release workflow deploys from `v*` tags, and that its reviewer gate would stall the scheduled operations probe. The candidate changes separate unattended monitoring from release approval, reject production-enabled manual builds, and make governance check the exact branch/tag rules; the GitHub environments still need configuration. A local compiled-server recovery drill passed 21 checks on September 23; it used a temporary server and is not off-host disaster recovery evidence.

On the current local candidate, strict Flutter and server analysis passed. The
full Flutter suite passed 1,282 tests with four existing skips before the final
ListenBrainz race guard; its 21 focused tests passed afterward. All 104 server
tests passed. Python CI discovery ran 281 tests: 267 passed and 14 platform
skips. `actionlint` and `git diff --check` passed. These are local results for
the candidate changes, not published-main or signed-release evidence.

## Gates to 100

1. Review and publish the candidate fixes through green exact-commit CI. Repeat the candidate release workflow on the final commit and inspect the assembled artifact manifest and payloads. Keep production publication gated.
2. Produce signed/notarized packages and verify clean installation, migration, upgrade, rollback and uninstallation on every advertised client platform.
3. Record physical Android/iOS audio, interruption, Bluetooth, power-management and constrained-storage checks, plus macOS/Windows/Linux installed runtime and accessibility acceptance with actual assistive technology.
4. Exercise deployed TLS/proxy authenticated sync under agreed capacity targets, independent-host restore against stated RPO/RTO, and delivered production probe/alert notifications.
5. Complete a bounded real pilot/soak and approve the exact release candidate with its traceable build, scan, installation and operational evidence.

No local unit test, emulator run or candidate archive substitutes for these final
checks. A 100/100 score means all agreed release criteria are evidenced for an
explicitly scoped release; it does not mean defect-free software.
