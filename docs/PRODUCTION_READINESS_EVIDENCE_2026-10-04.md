# Production readiness evidence: 2026-10-04

This checkpoint adds local source validation. It does not assign a new readiness
score or approve a production release. The historical 81/100 assessment remains
specific to its September 24 revision.

## Rust toolchain discovery

The local source predecessor was
`686ca518a6c6858060b597d35d232f63289638ee`. Cargokit resolved the project's
`1.95.0` pin but excluded numbered releases from its installed-toolchain cache,
causing the builder to request an unnecessary installation. The fix recognizes
numbered releases, extracts names before filtering default annotations, and
normalizes CRLF in toolchain and target output. Named-channel behavior and query
error propagation remain covered.

The same [six-case regression](../apps/mobile/packages/rhttp/cargokit/build_tool/test/rustup_test.dart)
ran against the actual predecessor Git blob and the corrected class. The
predecessor passed four cases and failed both numbered-release cases; the fix
passed all six with no skips. Every Rustup command used the existing fake-command
override. No Rust installation, dependency resolution, or network request was
part of this regression.

The first run produced the expected baseline assertions but exited with Windows
status `0xC0000008`. That failed run is retained. A scoped, automatically approved
run outside the restricted native sandbox used the same source, dependencies,
arguments and environment policy, and returned baseline exit 1 and corrected
exit 0. This comparison does not establish the cause of the earlier status.

## Current-source build and remaining acceptance

The saved Android candidate came from
`64f287e35ae24f383f6f6c03fee93a574b2a169b`; its source differs from the local
predecessor in player and UI code. Its runtime observations therefore do not
establish acceptance of the current source. A fresh local Android release build
is being prepared with separately recorded generated wrappers, tools, caches,
and exact source identity. No current-source APK has been produced at this
checkpoint, and a local build will not supply hosted release attestations.

Windows UI checks remain pending at the user's request. GitHub settings remain
unchanged. GitHub authentication and publication work remain pending.

The [remaining criteria for 100](PRODUCTION_READINESS_EVIDENCE_2026-10-01.md#evidence-still-required-for-100)
still require exact integrated release verification, signing and installation
acceptance on all five platforms, physical-device and accessibility evidence,
deployed service and recovery evidence, and pilot approval.
