# Production Readiness Reassessment

Assessment date: 2026-09-05.

**GitHub main: 61/100. Local working tree: provisional 69/100.**

**Broad production release is not recommended for either state.** The project is suitable for continued development and controlled alpha evaluation with disposable or separately backed-up data. A passing pipeline is useful evidence, not proof of production readiness.

## Scope and Method

- Repository: [Yunushan/aethertune](https://github.com/Yunushan/aethertune).
- Remote `main` and local HEAD both resolve to `c95f7acadacd6a5048e080ac6edd1b4143206769`, verified against GitHub during this reassessment.
- There were 43 modified or untracked paths before this report. Local persistence, cache, rate-limit, and backup changes are not part of the remotely available revision.
- The assessment covers the Flutter mobile/desktop client and optional self-hosted Dart service as one distributed product. It does not assume a mandatory hosted account service, public registration, or multiple maintainers.
- Reviewed critical persistence/download/authentication paths, deployment and workflow configuration, recovery fixtures, integration tests, documentation, and current GitHub execution evidence. Reran local analysis, tests, coverage, server compilation, and executable smoke checks.
- This is a weighted engineering judgment, not a reliability probability, certification, feature-parity percentage, or test-coverage percentage. The scores reuse the original rubric so improvements are not hidden by changing weights.
- This reassessment did not modify application code, merge PRs, change repository protections, commit, push, deploy, or fill the physical disk. Existing uncommitted changes were preserved.

The [original audit](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/PRODUCTION_READINESS_AUDIT_2026-09-05.md) records isolated defect reproductions against this same committed revision. Those findings were rechecked against HEAD source here; their reproductions were not rerun against an additional pristine checkout. Fresh local regression results apply to the modified working tree, not to HEAD.

## Weighted Score

| Area | Maximum | GitHub main | Local tree | Reason |
|---|---:|---:|---:|---|
| Product implementation | 15 | 12 | 12 | Substantial library, playback, provider, playlist, lyrics, offline, and sync implementation; not universal native acceptance or MetroList parity. |
| Data durability and recovery | 15 | 6 | 10 | Main has confirmed persistence failures. Local snapshots, recovery UI, revisions, and cache budgets materially improve safety; crash, disk-full, migration, and whole-service recovery evidence remains incomplete. |
| Security and privacy | 15 | 8 | 12 | Local path validation, streaming integrity checks, deadlines, and verified-identity rate limiting address confirmed defects. Deployed abuse tests, effective container gates, and broader security review remain necessary. |
| Automated quality assurance | 15 | 12 | 12 | Extensive passing tests and useful CI, but uneven runtime coverage, narrow integration testing, platform skips, and unfinished backup validation limit credit. |
| Device and accessibility validation | 10 | 4 | 4 | CI builds supported targets. Physical playback, lifecycle, codec, assistive-technology, and installed-upgrade acceptance is not demonstrated across them. |
| Release and distribution | 10 | 7 | 7 | Candidate packaging and verification tooling exist. Current corrected code has no demonstrated signed, notarized, installed, published production release. |
| Operations and recovery evidence | 10 | 6 | 6 | Health, readiness, metrics, deployment hardening, and recovery scripts exist. Live probes are skipped and recovery/load evidence remains limited. |
| Maintainability and documentation | 10 | 6 | 6 | Useful architecture and operator documentation; very large central modules, stale persistence descriptions, and incomplete deployment integration remain. |
| **Total** | **100** | **61** | **69** | **Local fixes earn credit only in the local column.** |

The local eight-point improvement reflects specific data-safety and security corrections, not simply the increased test count. No additional operational credit is awarded for the unfinished backup implementation.

## Priority Findings

### High: Main can report a library save that was not persisted

The committed `LibraryStore._save` sequentially writes many preference keys and ignores setter success values. The original isolated probe rejected 35 writes: adding a track returned successfully, but reloading lost it. Malformed stored JSON also escaped startup loading without setting the recoverable error state.

Sources: [committed save implementation](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L10409), [committed load boundary](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/library_store.dart#L1606). The package maintainers explicitly caution against relying on preferences for critical durable data. [Shared preferences documentation](https://pub.dev/packages/shared_preferences).

Local status: versioned, checksum-verified snapshots, queued commits, stale-writer rejection, in-memory rollback, and explicit startup recovery are implemented. Native-file tests pass on this Windows host. However, SQLite coordinates locking; it does not transactionally store the JSON snapshot. The snapshot files are flushed and renamed, but there is no demonstrated directory-metadata/power-loss durability across every supported filesystem. The disk-full test injects an exception before commit rather than exhausting storage. Large-library latency and memory have not been benchmarked against the 64 MiB snapshot limit.

Local references: [storage commit](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_storage.dart:181), [failure injection](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/library_storage_durability_test.dart:45), [save queue](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/library_store.dart:10590).

### High: Main accepts cache identifiers that escape the private directory

The committed backup loader accepts an offline record ID that is later interpolated into the destination filename. The original isolated probe imported such a record and overwrote a sentinel outside the media directory, within the application's writable area. Processing a crafted imported backup is required; this is not an unauthenticated remote server write.

Source: [committed destination construction](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L118).

Local status: IDs are rejected or mapped to portable filenames, write boundaries validate containment and links, and regression tests preserve sentinels and reject crafted imports. Four link-specific cases were skipped because this Windows host lacks symlink privileges. These local corrections must be included in a reviewed commit and verified on native targets before main should be trusted with untrusted backups.

References: [path checks](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/lib/src/data/offline_cache_paths.dart:1), [regression tests](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/test/offline_cache_safety_test.dart:56).

### Medium: Main has throttling and download resource weaknesses

The committed limiter gives each supplied bearer value its own bucket before authentication. Rotating invalid tokens bypassed the configured allowance in the original probe. The committed downloader also reads complete media into memory twice, does not bound transfer bytes while receiving them, and applies aggregate eviction only after materialization.

Sources: [committed limiter](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/services/server/lib/server.dart#L54), [committed cache verification](https://github.com/Yunushan/aethertune/blob/c95f7acadacd6a5048e080ac6edd1b4143206769/apps/mobile/lib/src/data/offline_cache_manager.dart#L151).

Local status: verified-identity limits, bounded ingress, streaming checksums, transfer deadlines, aggregate media budgets, safe replacement, resume validators, and explicit orphan/partial cleanup have regression evidence. Remaining limits include actual free-disk availability, live cache-policy changes, and foreground/background library-index coordination. Media files and their library index still do not share one transaction; failed index writes can leave orphaned media even though it is now counted and removable.

### High Release Risk: Real recovery is not demonstrated

The installed backup entry point still runs `tar` over a live directory. Excluding temporary files does not make separate authentication, library, playlist, and invitation stores one consistent point-in-time snapshot. The recovery fixture archives a synthetic JSON document and compares it after extraction; it does not boot and validate a recovered authenticated service.

References: [live backup command](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/deploy/aethertune-backup.sh:38), [recovery fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_backup_restore.sh:10), [scheduled drill](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/server-recovery-drill.yml:49).

The local Python backup helper and Dart data-directory guard are only partially integrated. The systemd service still invokes the old shell script; that script never calls the Python helper. Its sandbox only allows writing the backup directory, while the new helper needs writable lock files in the data directory. Existing deployment tests therefore do not establish that coordinated backup is deployed or works end to end.

References: [service entry point and sandbox](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/deploy/aethertune-backup.service:9), [new helper](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/deploy/aethertune-backup.py:87), [new guard](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/src/data_directory_guard.dart:1).

Acceptance needs concurrent-write snapshots, a restored compiled service, valid and revoked credentials, exact library revisions/checksums, account isolation, one-time recovery semantics, and rollback with representative data. Record recovery time and maximum data-loss objectives. A successful fixture drill is not a measured production RPO/RTO.

### Medium: Resource lifetime and capacity need deployed validation

`_readBoundedJson` caps bytes but has no body-read or total-request deadline. `HttpServer.idleTimeout` handles idle keep-alive connections after completed requests, not the lifetime of an active upload. The supplied proxy configuration does not explicitly bound request-body time. Slow authenticated uploads therefore need a tested deadline policy, particularly because active handlers participate in the new backup drain. This is a source-confirmed missing control, not a claim that production denial of service was reproduced.

References: [body reader](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/lib/server.dart:2004), [proxy](C:/Users/Yunus-Home/Downloads/aethertune-mobile/services/server/deploy/Caddyfile:1), [Dart idle timeout semantics](https://api.dart.dev/dart-io/HttpServer/idleTimeout.html).

The checked-in load test makes 80 requests using eight workers against health/readiness/info/catalog routes. The fresh executable smoke test exercises 90 requests on similarly small routes. Neither establishes capacity for sustained authenticated uploads, near-limit payloads, concurrent revision conflicts, many accounts, or the container's default memory limit. Define a representative workload and latency/error/resource targets before claiming user capacity. [Load fixture](C:/Users/Yunus-Home/Downloads/aethertune-mobile/scripts/ci/test_server_load.py:17).

### Release Blocker: Device and distribution evidence is incomplete

Only one checked-in integration-test file was found. It uses mocked preferences and checks an onboarding callback, not the complete application's real storage/audio/sync stack. The roadmap still leaves physical interruption/routing/background fixtures, Android Auto validation, acoustic transitions, and an accessibility pass open.

References: [integration test](C:/Users/Yunus-Home/Downloads/aethertune-mobile/apps/mobile/integration_test/onboarding_smoke_test.dart:10), [lifecycle acceptance](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ROADMAP.md:121), [accessibility](C:/Users/Yunus-Home/Downloads/aethertune-mobile/docs/ROADMAP.md:256).

The current main pipeline builds debug clients and unsigned iOS; this proves compilation rather than installed production behavior. The newest manual candidate release run inspected is from 2026-08-15, on `2438b8c`, before current main and all local fixes. Production Android/Windows signing, Apple signing/notarization, production metadata validation, and GitHub publication were skipped. The GitHub releases collection is empty. [Candidate run](https://github.com/Yunushan/aethertune/actions/runs/31884081107), [release listing](https://github.com/Yunushan/aethertune/releases).

No production signing identity, physical device, store acceptance, clean-install/upgrade matrix, or live service was assumed available. The earlier local Windows client build could not pass the symlink/Developer Mode prerequisite; it was not rerun here. The server executable build is independent and passed.

### Medium: Some operational safeguards exist only as configured workflows

- The newest observed operations probe and alert runs on 2026-09-05 are skipped. This is no evidence of active production monitoring or successful alert delivery. [Probe](https://github.com/Yunushan/aethertune/actions/runs/33964932840), [alert](https://github.com/Yunushan/aethertune/actions/runs/33964941799).
- The latest scheduled governance audit failed because its token was missing. The workflow reads `AETHERTUNE_GOVERNANCE_TOKEN`. [Failed audit](https://github.com/Yunushan/aethertune/actions/runs/33384426481), [configuration](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/governance-audit.yml:31).
- GitHub's branch summary confirms main is protected and lists eight required status contexts. The full protection endpoint returns 403 to this integration, so bypass/review/environment details were not verified. Do not confuse an inaccessible administration endpoint with an unprotected branch.
- Trivy uses `--exit-code 0` on push/PR; its fail-closed job runs only for schedule/manual events. Reporting vulnerabilities is not the same as preventing a vulnerable release. This does not prove there are currently high vulnerabilities. [Workflow](C:/Users/Yunus-Home/Downloads/aethertune-mobile/.github/workflows/container-scan.yml:41).

Sole-owner governance is a valid model for this project. Adding an independent collaborator, changing the 0BSD license, or bypassing failing checks would not resolve the technical readiness gaps.

## Fresh Verification

| Check | Result | Scope |
|---|---|---|
| Remote revision | Matches HEAD, `c95f7ac` | Does not include the local hardening changes. |
| Current-main GitHub CI | All six jobs successful | [Run 33869551283](https://github.com/Yunushan/aethertune/actions/runs/33869551283), 2026-09-04. |
| Flutter tests with coverage | 1,069 passed, four skipped | Modified local tree; four Windows link-privilege skips. |
| Strict Flutter analysis | No issues | `flutter analyze --no-pub`. |
| Server tests | 67 passed | Modified local tree. |
| Server analysis | Exit 0; one informational lint | Missing braces at `data_directory_guard.dart:120`; not a compilation failure. |
| Python CI tests | 93 passed, one skipped | POSIX Bash-dependent case skipped on Windows. |
| Server AOT compilation | Passed | Fresh Windows executable from modified local source. |
| Executable smoke checks | Passed | Required operations token, single-instance lock, health/readiness/metrics, and 90 requests; SIGTERM assertion skipped on Windows. |
| Git whitespace check | Passed | Only line-ending normalization notices. |

Local Flutter log: [reassessment-mobile-tests.log](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/reassessment-mobile-tests.log).

### Coverage Detail

| Module | Covered / executable lines | Coverage |
|---|---:|---:|
| Full local Flutter report | 30,824 / 41,983 | 73.42% |
| Native library snapshot storage | 133 / 140 | 95.00% |
| Library store | 4,834 / 5,126 | 94.30% |
| Offline cache manager | 312 / 352 | 88.64% |
| Library sync client | 574 / 755 | 76.03% |
| Library sync panel | 441 / 1,011 | 43.62% |
| Playback audio engine | 145 / 348 | 41.67% |
| Home screen | 3,815 / 9,810 | 38.89% |
| Video playback screen | 0 / 146 | 0.00% |

Artifact: [archived reassessment LCOV](C:/Users/Yunus-Home/Downloads/aethertune-mobile/build/readiness-audit-2026-09-05/reassessment-lcov.info). These are executable-line measurements, not branch coverage, native plugin coverage, sound-output checks, or complete feature acceptance. Widget tests deliberately use a test-only preferences storage fixture; separate tests instantiate the native file backend. The committed main report retained from the initial audit was 73.11%, not the local 73.42%.

## Strengths Worth Preserving

- Real domain implementations and broad regression coverage, rather than feature descriptions alone.
- Provider boundaries, explicit offline policies, user-controlled network actions, and platform credential storage.
- Portable sync exclusions for device paths/cache jobs, checksum validation, revision conflicts, account isolation, per-device token lifecycle, and managed recovery APIs.
- Random secret generation, hashed stored managed credentials, constant-time digest comparisons, bounded payloads, and local rate-limit regression tests.
- Pinned actions/dependencies, enforced lockfiles, SBOM/attestation/release-verification tooling, cross-platform CI, and vulnerability scanning.
- Loopback host binding, non-root container execution, a read-only root filesystem, dropped capabilities, private writable state, TLS proxy instructions, health/readiness, and operator documentation.

## Maintainability

The local `home_screen.dart` has 23,420 physical lines and `library_store.dart` has 10,980. This concentrates UI, I/O orchestration, and serialization responsibilities and makes review expensive. Extract cohesive areas as they change; a wholesale rewrite is not a production-readiness requirement. The new storage/cache helpers already move some responsibilities out.

README still describes library persistence as preferences-only, whereas the uncommitted implementation uses atomic native snapshots. Documentation should be updated alongside the final implementation, without treating implementation checkboxes or generated product illustrations as installed-device evidence.

## Prioritized Acceptance Plan

1. **Make the corrected candidate reproducible.** Review all local changes and newly added files, finish the incomplete backup integration, add its runtime tests, commit a coherent candidate, and run every required CI job on that exact revision. Do not suppress checks to improve the score.
2. **Prove user-data survival.** Test kill/restart at each migration/commit boundary, constrained storage in an isolated test environment, malformed data, stale foreground/background writers, resume interruption, and large-library performance on supported native targets. Verify recovery preserves originals and communicates data-loss choices.
3. **Prove the principal installed journeys.** Import real media, play actual audio/video, exercise codecs, interruptions, Bluetooth/headsets, lock-screen controls, background termination, sync conflicts, cache eviction, and upgrades. Record device/OS/build IDs and accessibility results, not only fake-engine assertions.
4. **Prove service recovery and abuse resistance.** Back up during writes, restore and boot the compiled service, verify managed/revoked credentials and exact snapshots, test rollback, and record recovery objectives. Exercise upload deadlines and representative sustained traffic through the real proxy with resource limits.
5. **Activate operational controls.** Repair the governance audit configuration, verify protections without weakening the sole-owner policy, validate probe/alert delivery against a real deployment, and make the chosen vulnerability policy an effective gate.
6. **Release the exact tested revision.** Complete the applicable Android/Apple/Windows signing and notarization, artifact verification, clean-machine install/upgrade checks, publication, and a controlled rollout with rollback evidence.

These are acceptance criteria for a higher reassessment, not automatic point awards. A 90+ score requires convincing native, release, and operational execution evidence. 100/100 would mean satisfying the defined rubric at that time, not a guarantee of defect-free software or complete MetroList parity.
