# Native Sync Transport

The shared library/account/recovery/sharing sync HTTP executor uses the maintained
`apps/mobile/packages/rhttp` source package. Existing imports from
`library_sync_client.dart` continue to expose the same executor and response
types. Other provider HTTP implementations and media playback are unchanged.

## Request Contract

- Each request owns a native client. Cancellation does not affect other requests.
- Platform certificate and hostname verification are explicitly selected. The
  dependency defaults to bundled WebPKI roots when TLS settings are omitted,
  so relying on that default would discard OS-trusted private roots. The
  application sets no certificate override, proxy, redirect following or cookie store.
- The total deadline is two minutes, including lazy FFI/client initialization.
  The request/header deadline is 30 seconds after client creation, the connect
  limit is 15 seconds, and response inactivity is bounded at 30 seconds.
- The native stream enforces a 9 MiB decoded-byte limit before copying chunks
  into Dart's event queue, including compression expansion. Dart independently
  checks cumulative size and strictly decodes UTF-8. No unbounded text/bytes
  response API is used by this executor.
- Request bodies are UTF-8 bytes. Status codes and response bodies are returned
  even for non-success statuses so existing conflict/authentication logic works.
- Cleanup signals native client cancellation, observes late headers/errors and
  stream completion, then disposes the client. Cleanup itself has a two-second
  bound; failure is reported, not treated as successful resource release.
- Errors crossing the adapter omit native request URLs and response payloads.
  Native initialization is shared per Dart isolate. A failed initialization is
  retained rather than reinitializing a possibly half-initialized bridge.

## Ownership And Updates

The upstream source revision, MIT notices and local changes are recorded in
`apps/mobile/packages/rhttp/AETHERTUNE_PATCHES.md`. AetherTune's 0BSD license does
not replace dependency licenses. Dart and Rust bridge versions are both 2.12.0,
and the bridge checks matching runtime/generated versions. Rust is pinned in
`apps/mobile/rust-toolchain.toml`; Cargokit debug/release builds and Android
verifier discovery use locked dependency resolution.

Use `scripts/ci/build_native_transport.py --install-toolchain --test` before
host Flutter tests. It produces the library in `apps/mobile/rust/target/release`,
the generated loader's development location. These outputs are ignored, not
checked-in binaries. Platform builds compile and bundle their own target library.

Dependency updates must preserve the native decoded-size limit, cancellation
callback ordering and non-panicking request validation. Regenerate bindings with
`flutter_rust_bridge_codegen` 2.12.0 whenever the FFI interface changes. A matching
bridge content hash alone does not prove an unchanged private native implementation;
rebuild and retain exact source/artifact hashes after every native-source edit.

OSV scans include the native Cargo lock in normal and release workflows. The
native CycloneDX inventory lists the locked all-target transport packages and
registry checksums; it does not claim to describe all native dependencies of the
application or the exact linked packages of any single platform binary.

The license policy includes Unicode-3.0 (the ICU4X/Unicode data dependencies)
and CDLA-Permissive-2.0 (the `webpki-root-certs` root-certificate data). Their
published license texts were reviewed against the
[Unicode-3.0](https://spdx.org/licenses/Unicode-3.0.html) and
[CDLA-Permissive-2.0](https://spdx.org/licenses/CDLA-Permissive-2.0.html) definitions.
Existing notice and redistribution requirements still apply.
The Cargo-adjacent `osv-scanner.toml` corrects only `allo-isolate` 0.1.27's
license metadata: its published `LICENSE` is Apache-2.0, while its Cargo manifest
uses `license-file` rather than an SPDX expression. The exact license hash is
recorded in that configuration. No vulnerability or package is ignored, and
`non-standard` licenses are not generally allowed. Re-review this correction
when updating that crate.

## Acceptance

The application suite includes raw HTTP/TLS cancellation, size/UTF-8 limits,
gzip expansion, upload/header/status preservation, concurrent-client isolation,
invalid-method handling and settings retry regressions. Native library tests
cover queue-side stream limits and callback cancellation ordering. Do not skip
or weaken these assertions to accept a dependency update.

An integration is not production acceptance merely because host tests pass.
The repeatable [Windows native sync acceptance](WINDOWS_SYNC_ACCEPTANCE.md)
executes the real application executor and externally observes native shutdown
without accessing a real user profile.
The resulting real Android/iOS/Linux/macOS/Windows packages still need compilation,
certificate controls, engine/background lifecycle and teardown tests, installed
upgrade/recovery, signing, and dependency/license inventory verification. Retained
prototype packages or packages built before this integration are not evidence
that the newly integrated application passed those gates.
