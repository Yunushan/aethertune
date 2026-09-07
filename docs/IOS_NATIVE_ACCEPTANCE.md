# iOS Native Acceptance

## Scope and Status

The `iOS native acceptance` workflow runs the real Flutter app in a newly created
iPhone Simulator on a GitHub-hosted macOS runner. It tests native keychain,
file-backed library storage, preferences, decoder/player and Rust TLS transport.
It does not replace physical-device audio/lifecycle, accessibility, signed
installation, upgrade/rollback or deployed hosted-sync acceptance.

**Bounded native acceptance passed on 2026-09-07.**
[Run 34154001516](https://github.com/Yunushan/aethertune/actions/runs/34154001516)
tested PR head `42101c5a3e0d1d5e3a8db88d18240b049bbf6fa9` through GitHub's
merge commit `52e8e6bb8355c4d4f6dc287c4a32387f3aea9136`, using Flutter 3.44.6,
Dart 3.12.2, Xcode 26.6 and an iPhone SE (3rd generation) on iOS 26.5.
The downloaded artifact hash was verified, the reports and driver logs inspected,
and all three 375 x 667 screenshots visually checked: the application and restored
player are nonblank, with no error screen or overlapping controls.

| Phase | Process | Passed checks |
| --- | ---: | ---: |
| Seed | 94440 | 6 |
| Reopen | 96833 | 6 |
| Sync | 98403 | 10 |

All 22 checks passed with distinct processes and the same installed binary.
TLS stall callers returned in 304 ms and peers disconnected in 304-305 ms.
`result.json` reports no errors, ordinary-output restoration, and deletion of
the owned guest `9CD26E9F-5931-4C7A-8223-97C3A2A34D79`.
Artifact SHA-256:
`4f5311465cadfed16272ee0e7c001f1097d96c319a1c5918486059f06280b9e1`.
Probe executable SHA-256:
`4f1a1b3b13440ab8241f9cfd16c9199992c07a24661c2f8d2f325259abff2c39`.
All eight PR workflows also passed on that head. This is exact-candidate
Simulator evidence, not a passing signed release, a production deployment, or
a 100/100 readiness claim. Later code changes require fresh validation.

### Failures Resolved Before Acceptance

The first hosted run built and installed the probe on iOS 26.5 with Xcode 26.6,
then rejected missing fixture identity before touching the library. The pinned
Dart runtime returns an empty `Platform.environment` on iOS, so environment-based
control could not work. The follow-up uses a JSON receipt in the owned app
container, checked against the compiled guest UUID, fixture name, source commit
and native application-support path. A physical-device container cannot satisfy
that path check. The failed run restored ordinary output and deleted its guest.

Passing the launcher and control-parser tests did not establish native runtime
acceptance. The first-run failure evidence is retained at:
[run 34149732012](https://github.com/Yunushan/aethertune/actions/runs/34149732012),
artifact SHA-256 `e6c4f5a59cfd507844bcff97416fd9579f506e639cbc6c7d3311e88c22713f9b`.

The second run passed the seed keychain, startup, library and playback checks,
then caught `MissingPluginException` for background-cache cancellation. The
generated AppDelegate still registered channels through its launch-time window,
which is nil under the pinned Flutter SDK's scene lifecycle. Registration now
uses `didInitializeImplicitFlutterEngine`, and audio-route presentation resolves
the calling engine's current view controller. This follows Flutter's
[scene migration guidance](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).
Each phase explicitly requires native cancellation acknowledgment as well.
Second-run evidence: [run 34151934490](https://github.com/Yunushan/aethertune/actions/runs/34151934490),
artifact SHA-256 `be961729275085144872e6ecbfb367f7248a410aa9d5435a1a461e8dadc4990e`.
The run restored ordinary output and deleted its guest. The third run above
verified the corrected wrapper, including native cancellation acknowledgment
in each process; the missing handler was not suppressed or mocked.

## Execution

The workflow uses the repository-pinned Flutter SDK and existing platform
bootstrap, then runs:

```sh
python3 scripts/ci/test_ios_native_acceptance.py
python3 scripts/ci/run_ios_native_acceptance.py --evidence build/ios-native-acceptance
```

The evidence directory must be new and contained in the checkout's `build`
directory. The launcher deliberately refuses Windows, Linux, personal Macs and
self-hosted runners. Do not spoof the hosted-runner environment to bypass this
guard. Installed runtime inventory determines the available compatible iPhone;
the exact runtime, type, UUID, Xcode version and Flutter SDK are retained.

One probe app is built and installed with the owned simulator's UUID/name and
source commit compiled into the binary. Before each launch the host writes only
the fixture control receipt, not library/preferences/keychain state. The same
binary executes three times, without uninstalling or clearing its data between
phases:

| Phase | Required behavior |
| --- | --- |
| Seed | Fresh preferences/storage/keychain; native key round trip; actual app startup; persisted library; synthetic WAV decode, progressing position, pause, seek and stop; persistent checkpoint |
| Reopen | A different process restores keychain, favorites, rating, queue/current track and volume without autoplay; real key deletion succeeds |
| Sync | A third process runs the existing strict native TLS contracts: platform-trusted UTF-8/auth/status/redirect, wrong-host and unknown-root rejection before HTTP credentials, three stalled TLS cleanups and three independent isolate requests |

Each phase records its exact source commit, simulator ID, process ID, named
checks and a PNG of the rendered app. Every phase also requires an acknowledged
native background-work cancellation before accessing the library. The launcher checks all required names,
success values and identities; missing/duplicate checks and reused process IDs
fail. A PNG signature check detects missing/corrupt output but is not a substitute
for inspecting the rendered evidence for a blank or broken screen.

## Isolation and Cleanup

Only a newly created random `AetherTune_Acceptance_...` simulator may be mutated.
Every simulator operation rechecks its UUID and name. Existing devices are read
only for compatible runtime metadata. No `all`, `booted` or `unavailable` alias is
accepted for mutating operations. App-container paths must resolve inside this
simulator's data directory, including checks for symlink/path escape.

Two synthetic two-day CA/leaf pairs are generated locally. Only the trusted CA
is installed, using `simctl keychain <owned-UUID> add-root-cert`; host keychains
and trust stores are untouched. The app still uses the production platform
verifier, with certificate and hostname validation enabled. The fixture supplies
no application TLS bypass or production credentials. CA private keys never enter
the app container. Synthetic keys stay below the private fixture directory and
are excluded from artifact upload.

After execution or failure, the launcher rebuilds ordinary `lib/main.dart` output
and shuts down/deletes only the owned simulator. Its deletion removes all guest
fixture data and test trust. Command timeouts terminate the owned process group;
create/delete observation failures are reconciled against fresh simulator
inventory. Any cleanup or ordinary-output restoration failure prevents a passing
result. Workflow cancellation can interrupt cleanup; the GitHub-hosted disposable
runner remains the final isolation boundary, never a personal device.

## Evidence

The workflow uploads `aethertune-ios-native-<run-id>` with top-level JSON, PNG and
command logs, not the nested certificate/key directory. Inspect `result.json`,
all three phase reports, screenshots and command errors together. Only a complete
passed result with the expected commit and successful cleanup establishes this
bounded Simulator acceptance. A passing build, missing artifact, cancelled job,
or launcher unit test does not.

The Python lifecycle tests simulate command state and app reports, including
test failures, stale ownership, delayed create/delete observations, failed
restoration and failed cleanup. These are regression tests of the launcher,
explicitly not fabricated runtime results.

Apple documents the guest root-certificate command in
[Become a Simulator expert](https://developer.apple.com/videos/play/wwdc2020/10647/).
The launcher uses an exact owned UUID instead of the example's `booted` alias.
