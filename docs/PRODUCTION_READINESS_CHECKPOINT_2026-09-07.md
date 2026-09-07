# Production Readiness Checkpoint: 2026-09-07

## Decision

**100/100 remains unproven.** This is a bounded progress checkpoint, not a fresh
whole-product score or production release approval. The preceding goal turn
produced useful evidence by identifying dependency-update failures. This turn
revalidated the repository, moved onto merged main, and added an executable
authenticated-sync acceptance gate. The full original scope remains the five
client platforms plus optional hosted sync.

## Authoritative Repository State

PR #20 was merged at `e25bf1718056cd889565838a9547407d61b0f733`.
The [main CI run](https://github.com/Yunushan/aethertune/actions/runs/34125664745),
[CodeQL](https://github.com/Yunushan/aethertune/actions/runs/34125664639),
[OSV scan](https://github.com/Yunushan/aethertune/actions/runs/34125664467), and
[container scan](https://github.com/Yunushan/aethertune/actions/runs/34125664541)
all report success for that exact SHA. The older assessment's statements that
the safety fixes remain unpublished no longer describe current main.

New changes are on `codex/authenticated-sync-load`, based on that merged main.
They add a compiled-server load fixture, behavioral regressions, mandatory CI
and server-release steps, and documentation. They do not modify application or
server production code, dependency constraints, or repository protections.

## New Runtime Evidence

The previous public-route smoke remains enabled. The additional fixture creates
independent managed accounts and two credentials per account. Both devices race
different snapshots at the same base revision; exactly one must commit and the
other must return the winning revision/checksum as a conflict. Each cycle then
checks exact account-specific snapshot content and metadata. After a forced
process stop, both credentials must still read the acknowledged snapshot.
Finally, hitting the default account rate limit must also limit its second
device while a different account and the health endpoint remain available.

| Measurement | Windows | Linux (WSL Ubuntu 24.04) |
|---|---:|---:|
| Configured workload duration | 65 seconds | 180 seconds |
| Accounts / devices | 4 / 8 | 8 / 16 |
| Tracks per snapshot | 1,000 | 5,000 |
| Completed cycles per account | 23 | 60 |
| Committed writes | 92 | 480 |
| Expected conflicting writes | 92 | 480 |
| Workload requests | 368 | 1,920 |
| Requests including setup/restart/rate checks | 518 | 2,098 |
| Workload p95 latency | 47 ms | 383.972 ms |
| Workload maximum latency | 63 ms | 617.772 ms |
| Transport or semantic failures | 0 | 0 |
| Restart, account isolation, shared rate limits | Passed | Passed |

These are paced synthetic workloads on this machine with different parameters,
not a platform performance comparison or a production capacity estimate. The
Linux workload sent 526,012,480 bytes of synthetic request bodies. Both services
used newly compiled executables, loopback HTTP, random synthetic credentials,
default production rate limits, and owned temporary data. No deployed service,
real user library, token, trust store, or signing identity was used. The fixture
kills and waits for each owned process and removes its temporary state.

Evidence retained locally:

- `build/readiness-auth-load-2026-09-07/windows-final/authenticated-sync-load.json`
- `build/readiness-auth-load-2026-09-07/linux-extended/authenticated-sync-load.json`

Windows executable SHA-256:
`d59b61e8db97985726acbcf9ea5cacfb2a6dacccfbf728dbcbf2e6843254cebe`.
Linux executable SHA-256:
`95b1c53d0e35639d5931c4df077c2c74d1331ed56ce47d78138281563767296e`.
The reports contain selected source input hashes, all rechecked after execution.
Their `source_commit` is null for these local runs; the hashes identify the
working inputs, not signed build provenance. GitHub execution supplies the
tested checkout SHA through `SOURCE_COMMIT_SHA`.

## Regression Verification

- New load-gate suite: 13 tests pass on both Windows and Linux. Negative cases
  reject two winners, lost writes, wrong-account data, incorrect checksums,
  missing rate limits, metadata payload leakage, truncated/oversized/malformed
  responses, and a slow-trickling response that would evade an idle timeout.
- Windows Python CI discovery: 229 tests, 217 passed and 12 platform skips.
- Both modified workflow files parse successfully with the Linux YAML parser.
- `git diff --check` passes. No Dart changes were made; the whole Flutter/server
  test suites were not rerun locally. The cited main CI covers the unchanged
  application/server source, not the new unpublished Python/workflow changes.

CI runs the 65-second default fixture and retains its JSON. Release workflows
run it for Linux, Windows, and macOS before uploading server executables. These
workflow additions are not yet evidence of their execution on GitHub or macOS.

## Completion Audit: Still Open

1. Execute and review exact-commit CI for the new gate; repeat native acceptance
   for release candidates on all five advertised client platforms.
2. Demonstrate signed/notarized clean installation, installed migration,
   upgrades, rollback, and assistive-technology acceptance on supported targets.
3. Complete physical Android/iOS lifecycle, interrupted playback, Bluetooth,
   power-management, and constrained-storage acceptance.
4. Exercise authenticated sync through the deployed TLS proxy under an agreed
   workload and capacity target, including abuse controls and storage pressure.
   The new loopback gate does not prove these conditions.
5. Verify actual production probe/alert delivery and restore on an independent
   host against explicit RPO/RTO, followed by a bounded real pilot/soak.
6. Reassess the full rubric against current evidence before assigning a new
   whole-product score. Passing tests cannot substitute for missing acceptance.

These external acceptance requirements remain unverified, not waived or
fabricated. Meaningful work remains available, so the goal is still active.

## Follow-Up: Cross-Platform PR Acceptance

The initial PR #31 Linux CI execution of the authenticated load gate passed in
[run 34140900614](https://github.com/Yunushan/aethertune/actions/runs/34140900614).
Review then found that Windows/macOS would only execute the gate at release
time. CI now also compiles the current locked server and executes the existing
fixture in the Windows and macOS desktop matrix jobs, with separate retained
evidence. Linux continues using the server job; no duplicate Linux load run or
additional signing/deployment step was added.

A regression test first failed on the absent PR steps, then passed with them.
Local Python discovery now passes 218 of 230 tests with 12 platform skips; the
edited YAML and embedded Bash steps validate. The runtime fixture and production
server code are unchanged from the hash-identified local runs above. Execution
of the new macOS/Windows CI steps remains pending, not assumed successful.
