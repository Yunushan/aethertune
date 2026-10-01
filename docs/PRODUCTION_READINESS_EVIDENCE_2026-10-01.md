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
all integrity checks retained. Its result requires independent verification.

Earlier successful bundles cover earlier revisions. They do not establish
release assembly, checksums, manifest, or attestations for this exact main.
Any subsequent source correction requires its own relevant acceptance.

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
syntax and diff checks passed. Existing Ubuntu CI registration and its
compiled-server probe still require acceptance at the committed revision.
This prepared correction is not credited as deployed operations evidence.

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

No connected physical Android or Apple device was available. An owned Android
emulator can support bounded candidate acceptance once a verified APK exists.
Emulator preparation is not installation or physical audio evidence. Existing
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
