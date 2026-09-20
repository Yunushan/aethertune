# Android Native Acceptance

## September 7, 2026 Result

**Android emulator acceptance passed; 100/100 production readiness is still
unproven.** This work is based on main `e25bf1718056cd889565838a9547407d61b0f733`.
It does not establish signed distribution, physical-device behavior,
installed-version upgrades, accessibility, or deployed hosted-sync safety.
The later platform TLS follow-up below adds bounded Android certificate evidence
to the original HTTP-only run.

The separate server-load PR #31 also passed all seven GitHub workflows at
`2106789975af194759a4cb06b1f78eea33d7c7a5`. Those checks do not cover these new
Android changes.

## Defect Reproduced And Fixed

A direct Windows Gradle build returned success despite Cargokit printing errors
and producing no `librhttp.so`. The resulting APK passed the old artifact verifier
but could not provide the application's native sync transport.

- The Windows batch wrapper now checks the SDK and working directory, initializes
  its metadata directory, and propagates dependency, compilation, build, and
  snapshot-retry failures instead of returning a false success.
- The Gradle task passes the SDK selected by `flutter.sdk` or `FLUTTER_ROOT` to
  the native builder. Direct Gradle builds no longer depend on a CLI-only variable.
- APK/AAB verification requires a matching `librhttp.so` for each packaged Flutter
  engine ABI, checks bounded ELF headers, and rejects duplicate ZIP entry names.
  These structural checks do not replace loading the native library or verifying
  release signatures.
- CI executes the Windows wrapper regressions and verifies the built Android APK.

The preserved broken APK SHA-256 is
`c4bdfe29086caa7abeade970ff8bfa3bec4ff93a1afc5c21ac5b548d2722f6ea`.
The new verifier rejects it with `missing required native library: lib/x86_64/librhttp.so`.

## Native Execution Evidence

The fixture used a new workspace-owned AOSP Android 35 x86_64 emulator, revision 2,
with the installed emulator 36.2.12 and WHPX acceleration. The user's existing
32-bit AVD and personal Android profile were not used. Camera and microphone
input were disabled. No real accounts, credentials or libraries were supplied.

`android_native_acceptance_test.dart` checks both the emulator property and the
explicit `AetherTune_Acceptance_` AVD name before writing any fixture state.
Its seed phase also refuses nonempty preferences or an existing library snapshot.

| Phase | Verified behavior |
|---|---|
| Seed, Android PID 2840 | Real application startup; legacy library migration to the native file snapshot; native keystore round trip; playback decoding and position progress; pause/seek/stop; production native HTTP UTF-8 upload, authorization, response status and no redirect following |
| Reopen, Android PID 3007 | Keystore value, library favorite/rating, queue and volume survived a separate process; startup did not resume playback; keystore deletion succeeded |
| Ordinary APK | Integration binary removed; clean normal-app installation and cold launch succeeded; welcome screen visually inspected at 720x1280; no app error-level logcat entries in the inspected startup window |

The initial driver invocation uninstalled its test app during default cleanup.
That run was not counted as persistence evidence. The retained seed/reopen pair
uses `--keep-app-running`, with an explicit force-stop between phases.

Retained local evidence is under `build/readiness-android-native-2026-09-07/`:
`seed.json`, `reopen.json`, driver/build logs, APKs and `normal-startup.png`.
The normal output APK was restored to the ordinary `lib/main.dart` entry point.

| APK | SHA-256 |
|---|---|
| Guarded seed | `b4ce6de161aede1a854d4821c37d182a48f3d22ea97d52bbe874df144fe3143c` |
| Guarded reopen | `ce10c99625857dc9f2c319d0f3bd185c39fe5b2f48468f0b35cd50355764585a` |
| Ordinary debug x86_64 | `68333f47f5189a79a557189ef027c0293ecab7a2c27b5110dad1706070394493` |

These debug APKs are not production release artifacts. Playback progress was
verified, not physical speaker output or Bluetooth routing. Native HTTP exercised
Android JNI initialization but did not prove certificate trust or TLS rejection.

## Repeat The Test

Use only a new disposable AVD named `AetherTune_Acceptance_API35`, with a separate
`ANDROID_AVD_HOME` and no existing app installation. Never wipe or repurpose a
personal emulator. Confirm its identity with `adb -s emulator-5580 emu avd name`.
From `apps/mobile`, with the pinned Flutter SDK, run each phase in order:

```bash
set -euo pipefail
for phase in seed reopen; do
  flutter build apk --debug --target-platform android-x64 \
    --target integration_test/android_native_acceptance_test.dart \
    --dart-define=AETHERTUNE_ANDROID_PHASE="$phase" \
    --dart-define=AETHERTUNE_ANDROID_AVD=AetherTune_Acceptance_API35
  python ../../scripts/ci/verify_android_release_artifacts.py \
    --apk build/app/outputs/flutter-apk/app-debug.apk
  flutter drive --no-pub -d emulator-5580 \
    --target integration_test/android_native_acceptance_test.dart \
    --driver test_driver/native_acceptance_driver.dart \
    --use-application-binary build/app/outputs/flutter-apk/app-debug.apk \
    --keep-app-running
  adb -s emulator-5580 exec-out run-as dev.aethertune.aethertune \
    cat "files/android-acceptance-$phase.json"
  adb -s emulator-5580 shell am force-stop dev.aethertune.aethertune
done
```

Stop on any failure and retain evidence before cleaning up the owned guest. Do
not distribute the integration APK. Rebuild the normal `lib/main.dart` target
afterward. The emulator test is currently manual, not an executed CI device gate.

The verified local Windows run used JDK 25.0.1 for Gradle 9.3.1, with a process-only
`jdk.net.unixdomain.tmpdir` pointing inside the workspace. Its Java HTTPS requests
used the existing Windows root store because Avast intercepts local HTTPS and
the installed JBR could not load its Windows trust-store provider. These were
invocation overrides, not global Java, antivirus or certificate-store changes.
Do not disable TLS validation to work around a build-machine trust failure.

## Regression Results

- Windows Cargokit wrapper: seven executable tests pass, including failing pub
  resolution, kernel compilation, native execution and snapshot-version retry.
- APK/AAB verifier: eight tests pass, including all three supported ABI layouts.
- Python CI discovery: 230 tests, 218 passed and 12 platform-specific skips.
- Focused Dart analysis and formatting pass. CI YAML parses successfully.
- Full application source tests were not rerun locally for these build/test-only
  changes. The native seed and reopen tests executed the real application.

Physical Android/iOS lifecycle and audio, signed/notarized releases, installed
upgrades and rollback, assistive-technology acceptance, deployed TLS/load/alerts,
independent-host restore and a real pilot remain open production requirements.

## Platform TLS Follow-Up: September 7, 17:27 UTC

The real application and unchanged shared production executor passed a separate
Android platform TLS test twice, in Android processes **2345** and **2479**.
Each report contains nine passing checks: home-screen startup, trusted HTTPS
UTF-8 upload/status/authorization/redirect behavior, untrusted-root rejection,
hostname rejection, no HTTP credentials reaching rejected TLS peers, three
stalled-handshake cleanup attempts, and three independent Dart-isolate requests.

The trusted root was a newly generated, two-day synthetic CA installed only in
the owned AOSP guest's **user** certificate store. The packaged verifier reads
Android's `AndroidCAStore`; no extra roots, insecure verifier, network-security
override, or application transport change was used for the positive control.
The untrusted fixture CA was never installed. This exercises the dependency's
[Android platform verifier integration](https://github.com/rustls/rustls-platform-verifier#android),
not an alternative Dart HTTP implementation.

The three handshake-stall checks use a shortened **300 ms test transfer
deadline**. Caller completion was 303-306 ms and peer-observed disconnect was
304-307 ms across the two runs. These measurements do not establish every
production deadline, normal Activity shutdown, background-engine behavior,
Internet/proxy connectivity, revocation, every Android version, or physical-device
reliability. Synthetic platform trust is not deployed hosted-sync TLS acceptance.

The successful APK SHA-256 is
`83e4b81dc014b3b99fe40ad2bc7eb69a97d4430e9cd0b58c24ea45bbc83bf42f`.
Retained local evidence is under `build/readiness-android-tls-2026-09-07/`:
`android-sync-b.json`, `android-sync-c.json`, `drive-b.log`, `drive-c.log`,
`app-sync-probe-b.apk`, and `fixture-b/cleanup.json`. Fixture private keys and
raw local debug logs are not committed or intended for publication.

Two setup failures were preserved, not counted as TLS evidence: an ADB stdin
transfer timed out, and the first app fixture wrote legacy preferences despite
an existing native snapshot. Non-PTY shell input and the production `LibraryStore`
API corrected those fixture issues. The passing runs retain all original shared
transport assertions.

### Repeat Platform TLS

Use only a newly provisioned, disposable AOSP **userdebug** AVD with the required
`AetherTune_Acceptance_` prefix. The helper requires an explicit emulator serial,
matching Android properties, a fresh output directory below this repo's `build`,
and an installed debug application. It rejects a preexisting certificate at the
generated subject-hash path. Never use this on a personal AVD or physical device.

From `apps/mobile`, with `adb`, `openssl`, Python and the pinned Flutter on PATH:

```bash
set -euo pipefail
flutter build apk --debug --target-platform android-x64 \
  --target integration_test/android_sync_transport_acceptance_test.dart \
  --dart-define=AETHERTUNE_ANDROID_AVD=AetherTune_Acceptance_API35
python ../../scripts/ci/verify_android_release_artifacts.py \
  --apk build/app/outputs/flutter-apk/app-debug.apk
adb -s emulator-5580 install -r build/app/outputs/flutter-apk/app-debug.apk
evidence="$PWD/../../build/android-tls-new-fixture"
cleanup() {
  if [[ -f "$evidence/receipt.json" ]]; then
    python ../../scripts/ci/prepare_android_sync_fixture.py cleanup \
      --adb "$(command -v adb)" --serial emulator-5580 \
      --avd AetherTune_Acceptance_API35 --output "$evidence"
  fi
}
trap cleanup EXIT
python ../../scripts/ci/prepare_android_sync_fixture.py prepare \
  --adb "$(command -v adb)" --openssl "$(command -v openssl)" \
  --serial emulator-5580 --avd AetherTune_Acceptance_API35 --output "$evidence"
flutter drive --no-pub -d emulator-5580 \
  --target integration_test/android_sync_transport_acceptance_test.dart \
  --driver test_driver/native_acceptance_driver.dart \
  --use-application-binary build/app/outputs/flutter-apk/app-debug.apk \
  --keep-app-running
adb -s emulator-5580 exec-out run-as dev.aethertune.aethertune \
  cat files/android-sync.json
```

Preserve the result before cleanup; use a different unused evidence directory
for each fixture. The helper compares the guest certificate's binary SHA-256
before removing that exact file, removes only named app fixture inputs, then
verifies that guest ADB root is disabled. Retain any cleanup failure for manual
inspection rather than deleting a mismatched certificate. The verified run
completed cleanup successfully. Rebuild the normal `lib/main.dart` APK and stop
the owned emulator afterward; never distribute the test entry point.

Eight fixture-safety regressions and focused Dart analysis/formatting pass. Full
local Python CI discovery now has **238 tests: 226 passed, 12 platform skips**.
CI runs the helper's safety regressions, not this manual emulator test. No
application or dependency runtime code changed in this TLS follow-up.
