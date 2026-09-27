# Production Readiness After PR #40: 2026-09-24

## Decision

**Published main: provisional 81/100. Broad production release: not yet
approved.** This is a weighted engineering assessment of the Android, iOS,
Linux, Windows, and macOS clients plus the optional self-hosted sync service.
It is not a reliability percentage or security certification. It supersedes
the earlier [75/100 checkpoint](PRODUCTION_READINESS_CHECKPOINT_2026-09-23.md)
for published main.

Assessed main revision: `0e11952910e2915690bebbb83e07da82a872229c`, the
merge of [PR #40](https://github.com/Yunushan/aethertune/pull/40). Its Git tree
matches the fully checked PR head
`0d7fc2bcdd3798d927373b615de7a56371ef0723`.

| Area | Earned | Maximum | Evidence and remaining gap |
| --- | ---: | ---: | --- |
| Product implementation | 12 | 15 | Core library, playback, provider, offline, and sync paths exist; installed release behavior remains unverified. |
| Data durability and recovery | 13 | 15 | Client settings and queues now reject failed writes and preserve durable state; power-loss and installed migration checks remain. |
| Security and privacy | 13 | 15 | Dedicated metrics credential, stricter token binding, scans, and proxy/rate-limit fixes are merged; deployed proxy and independent security acceptance remain. |
| Automated quality assurance | 14 | 15 | PR CI, CodeQL, OSV, container scan, and native iOS acceptance passed; signed-release and real-device gates remain. |
| Device and accessibility validation | 8 | 10 | Bounded emulator, Simulator, Linux, and Windows checks exist; physical mobile, installed macOS, and assistive-technology checks remain. |
| Release engineering and distribution | 7 | 10 | Nonpublishing release assembly produced a verified 17-artifact bundle with checksums and attestations; no signed or notarized published release exists. |
| Operations and recovery evidence | 7 | 10 | Local compiled-server recovery and load drills pass; deployed TLS/probe/alert and independent-host RPO/RTO restore remain unproven. |
| Maintainability and documentation | 7 | 10 | Release, monitoring, and governance guidance improved; central modules and historical score documents still require care. |
| **Total** | **81** | **100** | **External release and acceptance evidence remains mandatory.** |

## Evidence checked

- All required [PR #40 checks](https://github.com/Yunushan/aethertune/pull/40/checks) passed on the merged tree. [iOS Simulator acceptance](https://github.com/Yunushan/aethertune/actions/runs/35910866997) recorded seed, reopen, and sync with no recovery or errors; ordinary output was restored and its owned Simulator was deleted.
- The final [nonpublishing candidate](https://github.com/Yunushan/aethertune/actions/runs/35910895270) passed on PR head `0d7fc2b`. Its separately downloaded bundle passed independent verification of all 18 SHA-256 entries, the 17-artifact manifest, and APK/manifest GitHub attestations against that exact source digest and the pinned release workflow signer. The publish job was skipped.
- The final unsigned APK was byte-for-byte identical to an earlier candidate. A locally test-signed copy of that candidate retained all 324 non-signature ZIP entries and passed API 35 emulator clean install, synthetic WAV import, playback progress, and track retention after relaunch. A checksum-matched unsigned Windows portable EXE also started in an isolated profile. These are bounded checks, not production signing, store installation, physical-device audio, or upgrade/rollback acceptance.
- Merged-main [CI](https://github.com/Yunushan/aethertune/actions/runs/35915307011), [CodeQL](https://github.com/Yunushan/aethertune/actions/runs/35915307098), [OSV](https://github.com/Yunushan/aethertune/actions/runs/35915306970), and [container scanning](https://github.com/Yunushan/aethertune/actions/runs/35915306927) all passed on the exact merge commit `0e11952910e2915690bebbb83e07da82a872229c`.
- GitHub had no published release, repository or production secrets/variables, or `production-monitoring` environment when checked after the merge. The `production` environment still admitted protected branches only, excluding the release workflow's `v*` tags. Governance and production probe/alert runs therefore have no successful deployed evidence.

## Gates to 100

1. Configure the exact `production` main-branch and `v*` tag rules, create the `production-monitoring` main-only environment, supply the separate governance, signing, and metrics-only monitoring credentials, then pass the governance audit.
2. Produce signed/notarized packages and verify clean installation, migration, upgrade, rollback, and uninstallation on every advertised client platform.
3. Record physical Android/iOS audio, interruption, Bluetooth, power-management, and constrained-storage checks, plus representative installed desktop and assistive-technology acceptance.
4. Exercise the deployed TLS/proxy service under agreed capacity targets, prove independent-host restore against stated RPO/RTO, and confirm delivered production probe and alert notifications.
5. Complete a bounded real pilot/soak and approve the exact release candidate with its traceable build, scan, installation, and operational evidence.

A 100/100 assessment means all agreed criteria are evidenced for an explicitly
scoped release. It does not mean defect-free software.
