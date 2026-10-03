# Ordinary Linux release behavior acceptance

This gate covers the ordinary installed Linux application: documented keyboard navigation, synthetic local PCM playback, and state after normal close and reopen. Native execution and independent review of the retained screenshots are required before acceptance is recorded.

## Product and executor identity

The dedicated `linux-release-behavior` workflow uses the verified nonpublishing candidate containing the accessible-control fixes:

- Product commit: `4b9a309856ab028efc45d8a434ccaabda014e9c0`.
- Product ref: `refs/heads/codex/readiness-linux-behavior`.
- Release run: `37130672909`, attempt `1`.
- Release bundle artifact: `11277216890`.

Preparation checks the official artifact metadata and ZIP digest, bounded archive paths, release checksums and manifest, and fresh GitHub attestation verification. It reconstructs the unchanged Linux bundle from its verified tar archive. The candidate's source-verifier hashes and Linux archive/executable hashes are retained.

The current executor checkout, trigger SHA, workflow run/attempt and driver hashes are recorded separately. The product certificate retains its actual build source/ref/run identity. This test does not create a certificate for an integrated main revision.

`product-provenance.json` with status `verified-input` establishes input verification. Runtime results, screenshots and cleanup receipts establish the subsequent native outcome.

## Native acceptance contract

The existing Debian package gate requires a non-root ephemeral GitHub-hosted Linux runner. It installs the exact package at `/opt/aethertune`, verifies the installed and loaded payload, and launches the ordinary executable.

The behavior extension owns a private profile, authenticated Xvfb display, session bus, keyring, PulseAudio null sink, real desktop portal/GTK picker and accessibility services. App and picker identities must match their retained process identities and private bus/window ownership before actions proceed. Missing or ambiguous native UI fails the test and retains diagnostics.

The initial application session must:

1. Reveal **Skip setup** through its observed ShowOnScreen action or the unique onboarding scroll container, with at most four reveal actions, then complete setup through the visible, enabled ordinary button.
2. Show the desktop rail and exercise `Ctrl+1` through `Ctrl+6`, then `Alt+Left` and `Alt+Right`.
3. Select **Desktop density → Compact** through the ordinary Options UI.
4. Import the owned 180-second PCM WAV through the real file picker. Library and player state must be created by the application.
5. Observe the imported track, duration, advancing elapsed position, stable position while paused, seeking and resumed progression. Native MPRIS ownership and state must belong to the installed application. An uncorked output stream from that process must be active on the owned PulseAudio null sink; this establishes output routing without a physical-audio claim.
6. Close through the native window-close protocol and exit with code `0`.

The second session uses the same installed payload and profile with a distinct process identity. It must retain completed setup, the imported track/queue and Compact density, then close normally with code `0`. Automatic playback and restoration of a short track's elapsed position are outside this contract.

Final evidence must establish removal of the exact package and private profile, absence of recorded helper/application identities, and disposal of private services and mounts. The document portal may keep its package-provided `fusermount3` helper alive for automatic unmount. Only the verified child of the owned document service, with the exact binary, user and fixture mountpoint, is tracked. Read-only privilege may inspect that one child; the gate sends it no signals. Profile removal must wait until the helper and owned portal mounts are absent. Failure or forced termination cannot establish a normal-close pass.

## Execution and evidence

The workflow checks out the exact pinned product source for input verification and the current driver checkout for execution. Preparation uses:

```sh
python3 scripts/ci/prepare_linux_release_behavior.py \
  --product-source build/linux-release-behavior/product-source \
  --output build/linux-release-behavior/input
```

The workflow uploads preparation proof and `input/product-provenance.json`, plus the native `acceptance` directory under `build/linux-release-behavior`. Retained failures remain part of the evidence. Review the actual phase screenshots, semantic observations, native transport samples, state records, two normal-exit receipts and final cleanup before recording scoped acceptance.

## Observer diagnostics and fresh state

The observer retains flushed stage checkpoints and thirty-second stack-frame traces. Each tree call checks the owned process generations and the 150-second phase deadline before and after it runs. The coordinator's 180-second child timeout remains the outer bound for a stuck native call; a checkpoint or cleanup result cannot establish acceptance.

The AT-SPI client permits only state caching. Every node and immediate action validation clears that node's cache before reading its current native states. Subsequent flag membership examines that state snapshot; names, children and actions remain uncached. GNOME's [state-set implementation](https://raw.githubusercontent.com/GNOME/at-spi2-core/AT_SPI2_CORE_2_52_0/atspi/atspi-stateset.c) and [accessible cache implementation](https://raw.githubusercontent.com/GNOME/at-spi2-core/AT_SPI2_CORE_2_52_0/atspi/atspi-accessible.c) explain why a `NONE` mask can cause membership checks to issue additional native refresh calls. Native execution must still confirm the correction.

Earlier runs against the original a1 candidate are retained as failures. Runs 37128932935 and 37130268349 timed out after ordinary app launch. Diagnostic run 37131470654 reached the first semantic node traversal and retained five stacks in `states.contains`; those Python frames do not establish the C-level cause or a product fault. The corrected candidate's native outcome is recorded separately.

## Remaining production scope

This is limited Linux evidence for requirements **3c** and the keyboard portion of **3h** in the readiness audit. Production distribution trust, physical audible output, representative codecs/providers, screen-reader and full accessibility coverage, versioned migration/upgrade/rollback, and the other platform gates remain open until their own evidence is complete.
