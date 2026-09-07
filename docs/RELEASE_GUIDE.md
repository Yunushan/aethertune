# Release Guide

## Versioning

Update `apps/mobile/pubspec.yaml`:

```yaml
version: 0.1.0+1
```

Use semantic versioning for the public version and increment the build number for every store build.
Version tags must use `vMAJOR.MINOR.PATCH` and match the `version` in
`apps/mobile/pubspec.yaml` before the release bundle is assembled.

## Android release

```bash
cd apps/mobile
flutter build apk --release
flutter build appbundle --release
```

For a real Play Store/F-Droid release, configure signing keys outside the repository. Never commit keystores or passwords. The production workflow expects the `AETHERTUNE_ANDROID_KEYSTORE_BASE64`, `AETHERTUNE_ANDROID_KEYSTORE_PASSWORD`, `AETHERTUNE_ANDROID_KEY_ALIAS`, and `AETHERTUNE_ANDROID_KEY_PASSWORD` secrets in the protected `production` environment; it fails before building if any is absent.
The tag/manual workflow reopens both outputs before upload and requires their
Android manifest, primary dex payload, and Flutter asset manifest.

## iOS release

```bash
cd apps/mobile
flutter build ios --release
```

Open the generated iOS project in Xcode for signing, capabilities, and App Store upload.

Manual and non-production tag runs include `aethertune-ios-unsigned.zip`, a
verified unsigned `.app` archive for developer inspection or local re-signing.
It is not installable on a device and is not an App Store or TestFlight
artifact. Production tag runs instead require
`AETHERTUNE_IOS_SIGNING_CERTIFICATE_BASE64`,
`AETHERTUNE_IOS_SIGNING_CERTIFICATE_PASSWORD`,
`AETHERTUNE_IOS_SIGNING_IDENTITY`,
`AETHERTUNE_IOS_PROVISIONING_PROFILE_BASE64`, and
`AETHERTUNE_IOS_EXPORT_OPTIONS_PLIST_BASE64`, then publish a signed
`aethertune-ios.ipa`.

## Desktop release

Build desktop packages on their native operating systems:

On Ubuntu/Debian builders, install the secure-storage build/runtime packages
before building:

```bash
sudo apt install libsecret-1-0 libsecret-1-dev
```

Windows builders need the Visual C++ ATL component alongside the Flutter
desktop toolchain. ZIP and MSIX packaging also require the installed Visual
Studio x64 release CRT redistributable directory. Both packagers stage app-local
runtime DLLs, validate their architecture and Microsoft signatures, and include
`aethertune-windows-runtime.json` with file versions and SHA-256 hashes. The
input Flutter bundle is not modified. An explicit `-RuntimeDirectory` can select
a controlled `VC/Redist/MSVC/<version>/x64/Microsoft.VC14*.CRT` directory; use a
runtime at least as new as the compiler toolset. Do not source DLLs from System32,
a debug runtime directory, or third-party download sites. Redistribution remains
subject to the Visual Studio license terms. App-local runtimes must be updated
with app releases; they are not serviced automatically like a centrally installed
Visual C++ Redistributable. See Microsoft's
[runtime deployment guidance](https://learn.microsoft.com/en-us/cpp/windows/redistributing-visual-cpp-files?view=msvc-170).

Windows packagers also require Visual Studio DUMPBIN. They inspect ordinary and
delay-load imports, reject debug C++ runtimes using the shared
`scripts/ci/windows_native_policy.json` policy, reject linked staging payloads,
and include `aethertune-windows-native.json`. That manifest records native PE
module imports and hashes plus Dart AOT hashes. Final artifact preflight requires
complete module coverage, x64 PE headers, matching hashes, approved omission
records, safe unambiguous archive paths, and identical native payloads between
the ZIP and MSIX. These integrity checks supplement the signing steps; they do
not independently establish cryptographic trust or installed behavior.

Only the exact reviewed, unreferenced Chromium-prefixed ANGLE `zlib.dll` is
omitted from staging. Unknown hashes, static/delay-load consumers or literal
ASCII/UTF-16 references fail packaging. Debug runtime DLLs must not be bundled
to work around that artifact. Reference scans cannot rule out every dynamic
loading path: native codec and video acceptance is still required for release.
The [Windows native acceptance procedure](WINDOWS_NATIVE_ACCEPTANCE.md) describes
the isolated fixture and its limits.

The bootstrap script creates the required iOS/macOS
Keychain entitlements. It also sets Android minimum SDK 23 and disables Android
auto backup so encrypted credential material is not restored without its key.

```bash
cd apps/mobile
flutter build linux --release
flutter build macos --release
flutter build windows --release
```

The `aethertune-release-artifacts` GitHub Actions workflow builds downloadable
desktop archives on tags or manual dispatch:

- `aethertune-linux-x64`: `aethertune-linux-x64.tar.gz`, containing the verified portable Flutter bundle
- `aethertune-linux-x64`: `aethertune-linux-x64.deb` for 64-bit Debian/Ubuntu systems
- `aethertune-macos`: `aethertune-macos.zip`, containing the validated `.app` bundle
- `aethertune-macos`: `aethertune-macos.dmg`, containing the same bundle and an Applications shortcut
- `aethertune-windows-x64`: `aethertune-windows-x64.zip`

The macOS ZIP and DMG packagers validate the app executable and Flutter asset
manifest. The ZIP reopens the archive to verify both paths, while the DMG test
mounts the volume to verify the bundle and its Applications shortcut.
Candidate/manual macOS builds are unsigned. Production macOS builds require
the Apple signing and notarization secrets, sign and notarize the app before
packaging, staple and validate the DMG, and publish a deterministic
`aethertune-macos-notarization.json` attestation. Production Windows MSIX and
portable ZIP builds use the
`AETHERTUNE_WINDOWS_SIGNING_CERTIFICATE_BASE64` and
`AETHERTUNE_WINDOWS_SIGNING_CERTIFICATE_PASSWORD` secrets and are rejected by
the publish preflight unless the executable and `AppxSignature.p7x` are
signed.

The Linux portable-archive and Debian packagers validate the executable and
Flutter asset manifest, then reopen their output to verify the executable and
payload before upload.

## Server release

```bash
cd services/server
dart pub get --enforce-lockfile
dart compile exe bin/server.dart -o build/aethertune-server
```

For hosted deployments, set `PORT` in the environment. The server exposes
`/health` for liveness and `/ready` for persistence readiness. Each CI and
release executable is started on a temporary loopback port and must return
`200` from both endpoints before it is uploaded.

The release workflow uploads native server executables as:

- `aethertune-server-linux-x64`
- `aethertune-server-macos`
- `aethertune-server-windows-x64`

After a real deployment, set the protected `production` environment variable
`AETHERTUNE_PRODUCTION_BASE_URL` to the public HTTPS service URL and store the
raw operations token as the environment secret `AETHERTUNE_OPS_PROBE_TOKEN`.
The `Production operations probe` workflow runs every 15 minutes and on manual
dispatch, uses the protected environment, and fails closed when either value
is missing. Each run uploads a 30-day, non-secret evidence artifact containing
the run ID, commit, endpoint host, timestamp, probe log, and result. Keep a
separate off-host alerting path as well; a workflow or systemd timer cannot
detect a complete GitHub or host outage by itself. The checked-in `Production
operations alert` workflow sends failed, cancelled, or timed-out probe-run
notifications to the configured HTTPS webhook. It sends only repository, run,
commit, conclusion, and run-URL metadata, never the probe token or endpoint.

## GitHub release workflow

Create a tag such as `v0.1.0` or run the `aethertune-release-artifacts`
workflow manually. Both runs assemble the following files into the
`aethertune-release-bundle` artifact with `SHA256SUMS.txt` and a deterministic
`RELEASE_MANIFEST.json` inventory:

- Android: `app-release.apk` and `app-release.aab`
- iOS: `aethertune-ios.ipa` for production tags, or `aethertune-ios-unsigned.zip` for candidate/manual inspection
- Linux desktop archive
- macOS ZIP and DMG desktop packages
- Windows desktop archive
- Linux/macOS/Windows server executables
- `aethertune-dependency-provenance`: resolved client/server dependency inventories and deterministic CycloneDX 1.5 SBOMs

A pushed `v*` tag creates the verified bundle, but publication is intentionally
disabled unless the repository variable
`AETHERTUNE_PRODUCTION_RELEASES_ENABLED` is exactly `true`. When enabled, the
publish job also targets the `production` environment; configure that
environment to allow protected branches and require a separate release
approval. Immediately before creating the immutable GitHub release, the
publish job reruns the authenticated production operations probe so a stale
scheduled result cannot mask a current outage. Production runs also require a
non-empty versioned `CHANGELOG.md`
section matching the tag plus the checked-in feature matrix, 0BSD license, and
NOTICE. Configure the repository variable only after platform signing,
notarization, installer validation, store metadata, and physical-device smoke
tests are complete. Manual dispatch remains artifact-only, so it can validate a
candidate without publishing it. Verify a
download with `sha256sum -c SHA256SUMS.txt` on Linux/macOS, or
`Get-FileHash` on Windows. `RELEASE_MANIFEST.json` identifies each artifact's
platform, kind, byte size, and SHA-256 digest without timestamps or user data;
the workflow verifies that inventory against the assembled bundle and requires
every supported-platform artifact before upload.

### Production enablement inventory

Keep production values in GitHub Actions configuration, never in the
repository. Set `AETHERTUNE_PRODUCTION_RELEASES_ENABLED=true` as a repository
variable. Set `AETHERTUNE_PRODUCTION_BASE_URL` as a `production` environment
variable and use an `https://` endpoint. The `production` environment must
have a five-minute wait timer, protected-branch restriction, and at least one
required reviewer with self-approval disabled; the approver must be a separate
human or team from the release author.

Credentialed governance and operations jobs use the default-branch policy
files; production governance and publishing additionally require a pushed
`v*` tag. Manual dispatch remains non-publishing and skips the production
governance-token check, so it cannot execute branch-local policy code with
production access.

The governance audit reads `AETHERTUNE_GOVERNANCE_TOKEN` as a repository
secret. The release and probe jobs read these secrets from the protected
`production` environment:

- Operations: `AETHERTUNE_OPS_PROBE_TOKEN`
- Alerting: repository secret `AETHERTUNE_PRODUCTION_ALERT_WEBHOOK_URL`, an
  HTTPS endpoint that accepts a JSON body with a Slack-compatible `text` field
  and the non-secret probe-run metadata
- Android: `AETHERTUNE_ANDROID_KEYSTORE_BASE64`, `AETHERTUNE_ANDROID_KEYSTORE_PASSWORD`, `AETHERTUNE_ANDROID_KEY_ALIAS`, and `AETHERTUNE_ANDROID_KEY_PASSWORD`
- Apple signing: `AETHERTUNE_APPLE_KEYCHAIN_PASSWORD`,
  `AETHERTUNE_MACOS_SIGNING_CERTIFICATE_BASE64`,
  `AETHERTUNE_MACOS_SIGNING_CERTIFICATE_PASSWORD`,
  `AETHERTUNE_MACOS_SIGNING_IDENTITY`,
  `AETHERTUNE_IOS_SIGNING_CERTIFICATE_BASE64`,
  `AETHERTUNE_IOS_SIGNING_CERTIFICATE_PASSWORD`, and
  `AETHERTUNE_IOS_SIGNING_IDENTITY`
- iOS packaging: `AETHERTUNE_IOS_PROVISIONING_PROFILE_BASE64` and
  `AETHERTUNE_IOS_EXPORT_OPTIONS_PLIST_BASE64`
- Apple notarization: `AETHERTUNE_APPLE_NOTARY_API_KEY_BASE64`,
  `AETHERTUNE_APPLE_NOTARY_KEY_ID`, and
  `AETHERTUNE_APPLE_NOTARY_ISSUER_ID`
- Windows signing: `AETHERTUNE_WINDOWS_SIGNING_CERTIFICATE_BASE64` and
  `AETHERTUNE_WINDOWS_SIGNING_CERTIFICATE_PASSWORD`

Use the GitHub Settings UI or `gh variable set` / `gh secret set` with values
read from a password manager or CI secret store. Do not put raw tokens,
keystore passwords, certificate passwords, private keys, or base64 key
material in command arguments, shell history, issue comments, or artifacts.
After configuration, run the governance audit, a protected candidate/production
workflow, the operations probe, and the device/store smoke checklist. A green
candidate run alone is not production evidence.

The SBOM artifact is generated from the exact `dart pub deps --json` graph
resolved by that workflow. It intentionally omits a timestamp, embeds the
graph SHA-256, and is regenerated byte-for-byte before upload. Pull requests
also run the GitHub Dependency Review action and fail for newly introduced
moderate-or-higher advisories. OSV's PR/merge-queue scan compares both
committed Pub lockfiles with `main`; its full scan also runs on schedule,
`main` pushes, and version tags, fails on known
vulnerabilities, and enforces the repository's SPDX license allowlist. Packages
whose license metadata is unavailable still require an explicit release-review
exception; they are not silently accepted.

After checksums are generated, the release workflow creates a signed GitHub
artifact attestation for every subject listed in `SHA256SUMS.txt`. A release
bundle is not considered verified if the OIDC-backed attestation step fails.
Production tag runs also require an annotated tag whose GitHub verification
record is valid and whose target is the workflow commit; lightweight or
unverified tags remain candidate-only.

The scheduled `Repository governance audit` workflow verifies all client,
server, and security checks, administrator enforcement, and no force-push or
deletion. Repositories with multiple direct collaborators must configure
independent production review and approved deployment refs. A repository with
only its owner in GitHub's direct-collaborator list may use an owner-approved
production environment and may omit pull-request approval requirements, while
retaining the five-minute wait and protected deployment refs. The audit also
verifies that Dependabot security updates, secret scanning, push protection,
non-provider secret scanning, and supported-token validity checks are enabled.
Production release runs also execute this audit as a blocking dependency before
assembling artifacts. Configure the repository secret
`AETHERTUNE_GOVERNANCE_TOKEN` with read access to those repository settings;
production release runs fail closed when it is missing or the settings do not
match the policy. Candidate/manual runs skip this check because they cannot
publish a GitHub release.

CI and release builds pin Flutter `3.44.6` and Dart `3.12.2`; dependency lock
files are enforced so a floating SDK or dependency resolution cannot silently
change a release build.

The repository Actions policy allows GitHub-owned actions plus only the pinned
Dart, OSV scanner, and OSV reporter actions used by these workflows. Flutter is
bootstrapped by `scripts/ci/setup_flutter.sh` and
`scripts/ci/setup_flutter.ps1` from the exact `3.44.6` Flutter release commit,
with the commit checked before use. GitHub also requires every action reference
to use a full-length commit SHA; changing the allowlist or disabling SHA
pinning is a production-governance failure.

The CI client suite publishes an LCOV report and fails below the current 70%
line-coverage floor. This is a regression guard, not a claim of complete
behavioral or physical-device coverage.

The production publish job rejects unsigned or debug markers and independently
checks Android signatures, the iOS IPA structure, the macOS code signature and
notarization attestation, and the Windows executable Authenticode and MSIX
signature evidence. This is intentionally
fail-closed: missing credentials or incomplete platform evidence cannot turn a
candidate bundle into a store release.

Pull-request CI also runs a bounded concurrent load smoke test against the
compiled loopback server and uploads its latency/status evidence. This proves
the local request path remains responsive under a small controlled burst; it is
not a substitute for load testing the deployed public service.

Native client storage acceptance runs in the existing desktop CI and release
jobs. The probe compiles the production file backend with the client's exact
locked dependency versions/checksums. It verifies process interruption, stale
writers, lock release after process death, corruption recovery, and snapshot
continuity. Linux also runs real bounded tmpfs exhaustion in a private mount
namespace, using unprivileged storage processes. Reports are retained as
`aethertune-client-storage-*` or `aethertune-release-client-storage-*` artifacts.
Failures reject the desktop job and therefore block release assembly.
See the [native probe instructions](../scripts/ci/library_storage_probe/README.md)
for local commands and scope. These checks do not replace installed native
migration, physical power-loss, playback, or mobile-device acceptance.

The Linux desktop jobs additionally run the production Flutter entry point with
real native plugins in a disposable profile:

```sh
bash scripts/ci/run_linux_native_acceptance.sh --evidence build/linux-native-local
```

Run from the repository root after generating the Linux wrapper and resolving
the enforced client lockfile. Use the pinned Flutter SDK and the workflow's
Linux build dependencies, including `build-essential`, GTK, libmpv, libsecret,
`dbus-x11`, `gnome-keyring`, `pulseaudio`, `pulseaudio-utils`, `xauth`, and `xvfb`.
The evidence destination must not already exist.

The runner creates a marked temporary HOME, private D-Bus/Secret Service,
software display, and virtual audio sink. Three separate app processes seed
synthetic legacy preferences/credentials, migrate and play generated WAV audio,
then verify library/queue/settings/credential continuity after restart. It also
checks handled missing-Documents errors, English fallback for unsupported
system locales, native MPRIS controls, and sustained decoded PCM. No personal
profile or real credential is needed. Cleanup, test, and audio failures reject
the gate; logs, JSON, and screenshots are retained as Linux acceptance artifacts.

This fixture builds a debug integration-test application. Running it in a release
job does not validate the signed release artifact, installation/upgrade path,
physical speakers, Bluetooth, other codecs, background lifecycle, accessibility,
or other operating systems. Those remain separate release acceptance items.

Container vulnerabilities are enforced in the required **Server analyze and
test** CI job, the standalone PR/push/scheduled scanner, and the Linux server
release job that gates release assembly. All use the same container gate:

```sh
python3 scripts/ci/scan_server_container.py --evidence build/container-scan-local
```

Use a new evidence directory for each run. Before building, the driver verifies
the pinned Distroless runtime with pinned Cosign and the exact publisher identity
`keyless@distroless.iam.gserviceaccount.com`, issued by
`https://accounts.google.com`. Signature or transparency verification failures
stop the gate. See the [Distroless verification instructions](https://github.com/GoogleContainerTools/distroless#how-do-i-verify-distroless-images).

The driver builds the current server and exercises that immutable image with
disposable data and loopback-only ports: readiness, real non-root identity,
read-only root/capability/resource limits, authentication, saved-state and
revocation continuity, conflicting writes, second-instance refusal, graceful
shutdown, container recreation, and missing-secret refusal. Fixture credentials
are checked for log leakage; redacted logs and runtime results are retained.
The fixture removes only its own containers and labeled volume. Cleanup errors
fail the gate rather than producing a successful summary with leftover resources.

The same image is exported and scanned with pinned Trivy without mounting the
Docker socket or source tree into the scanner. A fresh database is downloaded
and checked for age (48 hours maximum). HIGH/CRITICAL findings including unfixed
vulnerabilities, end-of-life operating systems, scanner/database errors, and
missing or mismatched evidence fail the job. JSON, SARIF when conversion
succeeds, and signature/build/runtime/scanner logs remain available as artifacts
on failure. Do not bypass a failure by ignoring unfixed packages, disabling
required checks, or reusing an old successful report.

This scan identifies the built image by digest but does not publish a container
or prove an independently rebuilt deployment is identical. Dart package coverage
still depends on the separate lockfile/SBOM/OSV gates; scanning the AOT binary is
not a substitute for dependency or application-security testing. The runtime
fixture covers local volume continuity, not physical storage failure, deployed
capacity, or migration/rollback across application schema versions. For an
explicit packaging upgrade check against a retained local image, run:

```sh
python3 scripts/ci/server_container_runtime.py \
  --image sha256:<candidate-image-id> \
  --source-image sha256:<previous-image-id> \
  --evidence build/container-upgrade-local
```

Both arguments must be complete immutable local image IDs, not mutable tags.

Dependency maintenance is configured in [`.github/dependabot.yml`](../.github/dependabot.yml)
for the Flutter client, Dart server, server container definitions, and GitHub
Actions. Keep Dependabot alerts and security updates enabled in the repository
settings; release review still needs to consider the impact of any update.

## F-Droid notes

AetherTune is 0BSD licensed and has no telemetry. To prepare for F-Droid:

- Avoid proprietary SDKs.
- Keep builds reproducible where possible.
- Document all network calls from provider adapters.
- Do not include copyrighted media assets.

## GitHub release checklist

- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] Desktop debug builds pass in GitHub Actions.
- [ ] Release artifact workflow completes.
- [ ] Download the `aethertune-release-bundle` artifact or verify the tagged GitHub Release.
- [ ] Verify downloaded files against `SHA256SUMS.txt`.
- [ ] `dart analyze` passes in `services/server`.
- [ ] `dart test` passes in `services/server`.
- [ ] `dart compile exe` passes in `services/server`.
- [ ] Feature matrix is current.
- [ ] Changelog is written.
- [ ] The production tag has a non-empty matching `CHANGELOG.md` section and the release metadata preflight passes.
- [ ] APK/AAB/IPA build instructions are verified.
- [ ] License and third-party notices are updated.
- [ ] `AETHERTUNE_PRODUCTION_RELEASES_ENABLED` is enabled only after signed-release approval.
- [ ] The protected `production` environment has an independent release approver and the required platform secrets.
- [ ] The scheduled repository governance audit passes with `AETHERTUNE_GOVERNANCE_TOKEN`.
- [ ] A signed tag release has been installed on representative Android, iOS, macOS, and Windows hosts.
- [ ] The server has been deployed behind TLS, and both public and loopback health/readiness probes pass.
- [ ] The protected production operations probe has passed from GitHub Actions and its failure notifications reach the on-call path.
- [ ] A fresh server backup has been restored into an isolated data directory and its checksum verified.
- [ ] Load, alerting, rollback, and release recovery procedures have been exercised and recorded.
