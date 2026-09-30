# Production Readiness Evidence: 2026-09-30

**100/100 remains unproven; broad production release is not approved.** The last
weighted assessment was the historical **81/100** recorded on 2026-09-24 for
`0e11952910e2915690bebbb83e07da82a872229c`. This checkpoint records newer
source and execution evidence without assigning a new score. Its scope remains
Android, iOS, Linux, macOS, and Windows clients plus the optional self-hosted
sync service.

## Revisions and verified work

Published `main` is
[`59367dd136fbda661c598d1272dcce2e3d909163`](https://github.com/Yunushan/aethertune/commit/59367dd136fbda661c598d1272dcce2e3d909163).
[Main CI run 36329374917](https://github.com/Yunushan/aethertune/actions/runs/36329374917)
passed; the reviewed CodeQL, OSV, and container scan results also passed on that
revision. These checks do not establish signed distribution or deployed service
acceptance.

[Draft PR #47](https://github.com/Yunushan/aethertune/pull/47) contains the
candidate implementation reviewed locally through
[`1744b36f1f6ec3daf940b2f7e6f3556d69cd47db`](https://github.com/Yunushan/aethertune/commit/1744b36f1f6ec3daf940b2f7e6f3556d69cd47db):

- Production release jobs verify the signed annotated tag and its ancestry from
  `main`, then governance, before jobs can access production signing credentials.
- Shared-playlist and invitation storage errors remain explicit failures;
  unreadable or malformed persisted state cannot become a successful empty or
  missing result.
- The full player adapts transport controls and its action menu to narrow
  screens. Status notices, volume values, and time labels support enlarged text;
  Queue, Lyrics, transcript, and speed/pitch actions remain available.

| Local validation at the candidate revision | Result and coverage |
| --- | --- |
| `flutter test --no-pub test/now_playing_screen_test.dart` | 17 passed: existing player behavior, 320/390px widths, 1x/3x text, LTR/RTL, labeled controls and 48px touch targets, plus compact action-sheet interactions. |
| Strict Dart analysis of the two player files | No issues. |
| Server strict analysis and full `dart test` suite | Clean analysis; 112 tests passed, including storage-failure regressions. |
| Selected release policy tests | 34 passed: `test_verify_github_tag.py` (12), `test_release_workflow.py` (8), `test_toolchain_policy.py` (9), and `test_actions_node24_contract.py` (5). |
| Formatting and `git diff --check` for the implemented changes | Passed. |

Initial hosted validation in [PR CI run 36743094850](https://github.com/Yunushan/aethertune/actions/runs/36743094850)
passed the dependency-provenance job. The server job failed its container-policy
gate because scanning found **two HIGH findings in the runtime image**.
That result is separate from the 112 passing local server unit tests; those tests
do not cover vulnerabilities in the packaged operating-system image. The original pinned runtime carried both findings in `libssl3t64`; the
additional runtime correction below still requires rebuilt-image acceptance.

Windows and macOS builds and [iOS acceptance run 36743095159](https://github.com/Yunushan/aethertune/actions/runs/36743095159)
subsequently passed on this initial revision. Flutter and Linux jobs were still
running at the next inspection. The overall CI run is not a passing result while
its container gate has failed. These results do not cover later source changes.
Later source changes require their own relevant validation and successful checks;
the local results above apply to the named revision.

An additional local commit,
[`4726257dfac2fbafb7235adb670d3cab2f34852b`](https://github.com/Yunushan/aethertune/commit/4726257dfac2fbafb7235adb670d3cab2f34852b),
binds the operations probe's checkout to the exact revision recorded in its
evidence. Its `test_production_ops_workflow.py` run discovered 14 tests: **12
passed and two existing POSIX-specific cases were skipped**. The initial hosted
checks above do not cover this later commit. This policy
validation does not establish a successful deployed probe or delivered alert.

### Additional local corrections awaiting hosted acceptance

- Runtime commit [`7800ae1`](https://github.com/Yunushan/aethertune/commit/7800ae1)
  changes the server to the official, digest-pinned
  `base-nossl-debian13:nonroot` image recommended in the
  [Distroless Dart example](https://github.com/GoogleContainerTools/distroless/commit/a381f20bb87a7b4d63cb7c7ac70931e3dd65a349).
  Dart AOT bundles its TLS implementation; the new runtime retains glibc and CA
  certificates. Exact publisher signature and transparency verification passed.
  A real Trivy 0.70.0 comparison using the same current database found the two
  HIGH findings in the original runtime and zero HIGH/CRITICAL findings in the
  replacement's seven-package inventory. This was a base-image scan, not
  rebuilt-server acceptance. Twenty-nine container policy tests and the Dart
  deployment-asset test file passed locally. Publisher, database freshness,
  end-of-life, package-inventory, built-image identity, severity, and no-suppression
  checks remain required.
- Scanner commit [`645b4ee`](https://github.com/Yunushan/aethertune/commit/645b4ee)
  invokes the immutable official OSV image's scanner binary directly and checks
  its actual process status. Only completed scan codes 0/1 proceed; Docker,
  configuration, download, and runtime errors fail even with a valid partial
  findings file. Prior JSON/SARIF files are removed, fresh JSON is validated,
  and the existing reporter retains its vulnerability and license policy.
  Fifty-one selected tests passed locally: OSV guard (19), dependency locks (10),
  release workflow (8), toolchain (9), and action pins (5). Actual scanner Docker
  execution, reporter behavior on the repository, and candidate release assembly
  remain hosted acceptance gates.

[PR #43](https://github.com/Yunushan/aethertune/pull/43), head
`e95ef14ea9e1f8df16055f3f87f8eb0138d62b7c`, is complementary hardening work.
Its client analyzer and library-part changes do not overlap the player files,
and its Flutter and iOS Simulator checks passed. Its dependency-provenance job
failed on formatting. Its implementation and documentary configuration claims
are not treated as merged or as completed release acceptance here.

## External state observed

Read-only inspection found these environment boundaries already configured:

| Environment | Observed rules |
| --- | --- |
| `production` | Exactly branch `main` and tag `v*`; five-minute wait; administrator bypass disabled; repository owner is a required reviewer; self-review is allowed. |
| `production-monitoring` | Exactly branch `main`; no reviewer or wait timer; administrator bypass disabled. |

Those settings were changed outside this checkpoint. This work made no GitHub
settings changes, in accordance with the instruction to leave settings unchanged.
Authenticated collaborator inspection confirmed one direct collaborator,
namely the repository owner. Owner approval with self-review allowed therefore
matches the verifier's confirmed sole-owner policy. `main` applies protection to
administrators, forbids force pushes and deletion, requires an up-to-date branch
and the eight expected status-check contexts, and has no required pull-request
review rule. These observed boundaries do not establish a passing full governance
audit. See the ownership modes in the
[release guide](RELEASE_GUIDE.md#production-enablement-inventory).

- The GitHub Releases API returned an empty release list. No published signed
  release is evidenced.
- The latest inspected [governance audit, run 36412681364](https://github.com/Yunushan/aethertune/actions/runs/36412681364), failed on `59367dd`. Its log reported missing governance authentication (`--token`, `GITHUB_TOKEN`, or `GH_TOKEN` required); the job's `GITHUB_TOKEN` was empty.
- A fresh authenticated, read-only evaluation using the checked-in governance
  verifier failed specifically on two required repository settings:
  **non-provider secret scanning** and **secret-scanning validity checks**.
  Its remaining policy checks produced no failures, including the confirmed
  sole-owner reviewer policy. This result does not turn the failed scheduled
  workflow into a pass or remove either outstanding security gate.
- The latest inspected [production probe, run 36707474130](https://github.com/Yunushan/aethertune/actions/runs/36707474130), and [alert, run 36707497410](https://github.com/Yunushan/aethertune/actions/runs/36707497410), were skipped on `59367dd`. A skipped workflow does not prove endpoint health or delivered alerts.
- Authenticated metadata-only inventory subsequently confirmed **zero secrets
  and zero variables** in each of repository Actions, `production`, and
  `production-monitoring`. The required governance, alert, signing, and probe
  credentials, production-enablement variable, and public base-URL variables are
  absent from those locations. Earlier HTTP 401 inventory attempts did not
  establish this result; the successful authenticated reads did. No secret
  values were read and no configuration was changed. Keep credentials in the
  intended GitHub Actions secrets and deployment secret stores.

## Evidence still required for 100

1. Integrate reviewed candidate changes with passing checks for the resulting
   exact revision, repeat release assembly and independently verify the bundle,
   checksums, manifest, and attestations. Obtain successful governance evidence,
   including a credentialed workflow run and the two required secret-scanning
   settings. The sole-owner approval policy is already confirmed; GitHub settings
   changes remain outside the authorized work.
2. Produce the five-platform release candidate with required signing and Apple
   notarization, then verify clean installation, migration, upgrade, rollback,
   and uninstallation on Android, iOS, Linux, macOS, and Windows. Retain package
   identity, versions, hashes, signing/provenance results, and observed behavior.
3. Record physical Android/iOS audio, interruption, Bluetooth, power-management,
   and constrained-storage acceptance, plus representative installed desktop
   behavior and actual assistive-technology checks. Widget, emulator, and
   Simulator checks support this work but do not establish those results.
4. Exercise the deployed HTTPS/TLS/proxy service at agreed capacity; prove restore
   on an independent host against explicit RPO/RTO targets; retain successful
   production probe evidence and independently confirm delivery of alert drills
   and failure notifications. Local recovery tests and workflow definitions do
   not establish deployed recovery or notification delivery.
5. Complete a bounded real pilot/soak and approve the exact release candidate with
   traceable build, scan, installation, accessibility, and operations evidence.

The [post-merge assessment](PRODUCTION_READINESS_POST_MERGE_2026-09-23.md)
retains the historical weighted rubric and September 24 evidence. A 100/100
assessment requires evidence for the complete agreed release scope, not a count
of green local tests.
