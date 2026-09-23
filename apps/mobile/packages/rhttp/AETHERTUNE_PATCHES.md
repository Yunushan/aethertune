# AetherTune Native Transport

This maintained source copy is an application dependency. Adoption does not
establish signed-release or all-platform acceptance; see the readiness report.

Upstream: https://codeberg.org/Tienisto/rhttp
Commit: `9871f1c25d0cf75553af85698b9f03d38f438aed`
Package: `rhttp` 0.18.0. Original MIT notices remain in `LICENSE` and the Cargokit
license. Upstream example and test directories were excluded from this copy.

Local changes:

- Pin the Dart/Rust bridge pair to 2.12.0 for generated-code reproducibility.
- Enforce the bridge version check, pin Rust through the application's
  rust-toolchain.toml, and use locked Cargokit builds in debug and release.
- Expose awaitable client-wide cancellation so application cleanup need not
  wait for a request token that was never created on an early failure.
- Return errors for invalid HTTP methods and absent request-body streams instead
  of aborting the host process. Connection errors do not unwrap an absent cause.
- Android verifier discovery uses locked Cargo metadata resolution.
- Read Android Gradle's numeric `compileSdk` property; legacy display strings
  such as `android-37.0` are not integer API levels.
- Make the Windows Cargokit wrapper reject missing SDK/build directories and
  preserve failures from dependency resolution, kernel compilation, native
  builds, and snapshot-version retries. Create its metadata directory before
  writing it. A failed native build must not produce a successful Gradle result.
- Pass Flutter's configured SDK path to Cargokit for direct Gradle/Android Studio
  builds, including builds launched without a `FLUTTER_ROOT` environment variable.
- Resolve native advisories with h2 0.4.16, quinn-proto 0.11.15 and anyhow 1.0.103.
- Add optional `maxStreamResponseBytes` (uint32) for decoded stream responses.
  It rejects known oversize lengths and enforces cumulative chunk size before
  copying payloads into the Dart event queue, including decompressed bodies.
  Null retains upstream unlimited behavior; zero permits only an empty stream.
- Expose `RhttpResponseTooLargeException` without including response data or URLs.
- Limit streaming cancellation to network waits. In-flight Dart callbacks finish
  before the native task exits, preventing their return messages from targeting
  a cancelled callback receiver.

The limit covers stream-response calls only, not text/bytes response APIs.
Adoption requires the application to set the limit and continue checking UTF-8,
HTTP status, redirects, certificates, deadlines and cleanup. The application
must not assume that a Dart-only limit bounds native event-queue allocations.

Bindings are generated with `flutter_rust_bridge_codegen` 2.12.0. Its Windows
build needs `CARGO_PROFILE_RELEASE_STRIP=none` with the tested Rust 1.95.0;
the initial default-stripped build hit a compiler internal error. This setting
is for the development generator, not a production native-library requirement.
