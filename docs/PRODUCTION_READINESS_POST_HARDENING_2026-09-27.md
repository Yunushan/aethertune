# Production Readiness: Historical Hardening Checkpoint (2026-09-27)

This is a historical record of the local hardening work based on main revision
59367dd. It does not establish current production acceptance or assign a new
readiness score. The later [2026-09-30 evidence checkpoint](PRODUCTION_READINESS_EVIDENCE_2026-09-30.md)
records the release and operational evidence boundaries.

## Local results reported on 2026-09-27

The original checkpoint reported the following local results. These counts
describe that historical source state and are not new verification of the
updated PR or published main.

| Check | Historical reported result |
| --- | --- |
| Flutter analysis with strict casts, inference, and raw types | 0 issues |
| Full Flutter tests, twice | 1,288 passed, 4 skipped, 0 failed per run |
| Server analysis with the same strict modes | 0 issues |
| Server tests | 109 passed |
| Library store tests after the part-file split | 114 passed |

The retained [PR #43 CI run 36346292367](https://github.com/Yunushan/aethertune/actions/runs/36346292367)
on head e95ef14 passed Flutter, desktop, and server jobs, but its dependency
provenance job failed the Dart formatting check. The native evidence upload
then failed because the preceding fixture step was skipped. This run was not
a successful overall CI result.

## Implementation changes

1. **Scanner completion and evidence checks.** The four scanner routes in
   osv-scanner.yml, osv-required-context.yml, and osv-scan-pr-reusable.yml use
   the immutable raw scanner runner introduced in PR #47. Only actual scan
   exit codes 0/1 and fresh validated JSON proceed to the existing vulnerability
   and license reporter. Runtime failures cannot pass with partial findings.
   The comparison workflow preserves the executed policy and completed base
   report while changing source checkouts.
2. **Bounded request JSON nesting.** Server request decoding rejects depth
   greater than 64 before JSON decoding. The regressions cover the boundary,
   quoted structural characters, escaped quotes, and continued server health.
3. **Strict analyzer modes.** Both packages enable strict casts, inference,
   and raw types. Explicit map annotations replace the original raw types.
4. **Dependency maintenance coverage.** Dependabot includes the native Rust
   package; the recovery workflow uses the existing setup-dart v1.8.1 pin.
5. **Library store structure.** Data models and mutation helpers moved into
   library_store_models.dart and library_store_runtime.dart part files.
   This source organization change requires behavior tests and analysis; file
   splitting by itself does not demonstrate production reliability.

## Integration and governance boundaries

On 2026-09-30 this branch integrated
[main 1572802](https://github.com/Yunushan/aethertune/commit/1572802c08d666a192c381f379edeb002bbba717),
the squash merge of PR #47, preserving its release ancestry gates, shared
playlist storage failures, player accessibility changes, signed runtime base,
strict release scan runner, and operations probe source identity checks.
The three files reported by the historical format artifact were corrected
with the CI-pinned Dart 3.12.2 formatter. The updated head requires its own
successful CI checks before merge.

The original document presented environment configuration and private
vulnerability reporting as changes made by this hardening work. Those are
external repository settings, not changes represented by this PR. No GitHub
settings are changed by this integration. Historical configuration claims are
not substituted for a successful authenticated governance run.

The checked-in verifier supports a confirmed sole-owner repository: production
requires owner approval and permits owner self-review in that mode. An
independent reviewer is required when authoritative collaborator evidence
establishes the multiple-maintainer mode. A second maintainer is not an
unconditional prerequisite for the existing sole-owner repository.

## Remaining production acceptance

100/100 remains unproven. The last historical weighted assessment was 81/100
on 2026-09-24; this checkpoint provides no new weighted assessment.

Remaining evidence includes usable governance authentication and a passing
audit, the required secret-scanning controls, platform signing and verified
signed distribution, deployed TLS probe and delivered alert evidence, measured
restore RPO/RTO, install/upgrade/rollback acceptance, and physical-device and
assistive-technology acceptance. Local tests and structural refactoring do not
complete these gates. See the later evidence checkpoint and release guide for
the concrete inventory and ownership policy.
