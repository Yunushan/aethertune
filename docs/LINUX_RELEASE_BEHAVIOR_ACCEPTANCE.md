# Ordinary Linux release behavior acceptance

This gate covers the ordinary installed Linux application: documented keyboard navigation, synthetic local PCM playback, and state after normal close and reopen. Native execution and independent review of the retained screenshots are required before acceptance is recorded.

## Product and executor identity

The dedicated `linux-release-behavior` workflow uses the verified nonpublishing candidate containing the accessible-control and desktop shortcut focus fixes:

- Product commit: `0aaaa5c52ceecb050b017abb21775d729a341419`.
- Product ref: `refs/heads/codex/readiness-linux-behavior`.
- Release run: `37136816470`, attempt `1`.
- Release bundle artifact: `11279990421`.

Preparation checks the official artifact metadata and ZIP digest, bounded archive paths, release checksums and manifest, and fresh GitHub attestation verification. It reconstructs the unchanged Linux bundle from its verified tar archive. The candidate's source-verifier hashes and Linux archive/executable hashes are retained.

The current executor checkout, trigger SHA, workflow run/attempt and driver hashes are recorded separately. The product certificate retains its actual build source/ref/run identity. This test does not create a certificate for an integrated main revision.

`product-provenance.json` with status `verified-input` establishes input verification. Runtime results, screenshots and cleanup receipts establish the subsequent native outcome.

## Native acceptance contract

The existing Debian package gate requires a non-root ephemeral GitHub-hosted Linux runner. It installs the exact package at `/opt/aethertune`, verifies the installed and loaded payload, and launches the ordinary executable.

The behavior extension owns a private profile, authenticated Xvfb display, session bus, keyring, PulseAudio null sink, real desktop portal/GTK picker and accessibility services. App and picker identities must match their retained process identities and private bus/window ownership before actions proceed. Missing or ambiguous native UI fails the test and retains diagnostics.

The initial application session must:

1. Reveal **Skip setup** through its observed ShowOnScreen action or the unique onboarding scroll container using its observed forward `ScrollUp` action, with at most four reveal actions, then complete setup through the visible, enabled ordinary button.
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

For the pinned Flutter framework, a normal vertical ListView advances through the semantic `ScrollUp` action. This follows the [exact framework action policy](https://raw.githubusercontent.com/flutter/flutter/ee80f08bbf97172ec030b8751ceab557177a34a6/packages/flutter/lib/src/widgets/scroll_position.dart) and [Linux adapter mapping](https://raw.githubusercontent.com/flutter/flutter/83675ed27633283e7fc296c8bca22e841224c096/engine/src/flutter/shell/platform/linux/fl_accessible_node.cc). The observer requires that actual capability on the unique container scoped to ordinary onboarding or Options labels, then checks fresh state before every action. It never taps an offscreen button.

### Density popup actions

The actual enabled dropdown menu items expose Tap through InkWell while leaving enabled semantics unspecified. The [pinned dropdown implementation](https://raw.githubusercontent.com/flutter/flutter/ee80f08bbf97172ec030b8751ceab557177a34a6/packages/flutter/lib/src/material/dropdown.dart) adds that InkWell only for enabled items. The [pinned Linux adapter](https://raw.githubusercontent.com/flutter/flutter/83675ed27633283e7fc296c8bca22e841224c096/engine/src/flutter/shell/platform/linux/fl_accessible_node.cc) maps unspecified enabled state to neither ENABLED nor SENSITIVE; explicit false maps to SENSITIVE without ENABLED.

The density-menu action must be bound to the just-opened Desktop density row and a unique, visible, nondefunct Popup menu containing the two ordinary Comfortable and Compact choices. Only the scoped Compact choice may use unspecified enabled state, with observed Tap and Focus capabilities. Duplicate, unrelated, hidden, defunct or explicitly disabled controls fail. The current popup must be resolved again immediately before action; PID, label, state and named-action checks remain required. Acceptance then requires the popup to close and the ordinary Desktop density row to show Compact. Global Tap and ordinary setting-row checks remain strict.

Earlier runs against the original a1 candidate are retained as failures. Runs 37128932935 and 37130268349 timed out after ordinary app launch. Diagnostic run 37131470654 reached the first semantic node traversal and retained five stacks in `states.contains`; those Python frames do not establish the C-level cause or a product fault. Run 37134370976 against the corrected 4b9 candidate completed 62 semantic tree traversals and retained the actual ordinary Welcome screenshot and 36-node tree. It failed with zero actions because the original selector requested `ScrollDown` while the onboarding list exposed only `ScrollUp`; all twelve owned processes and the private package/profile were cleaned up. This remains a failed behavior result. Run 37135431685 subsequently recorded the observed forward scroll, a visible and enabled Skip setup Tap, and arrival at Home. It then failed after sending the native Ctrl+2 chord because Library did not become selected. The two actual screenshots, action receipt, separate source identities and twelve owned cleanup outcomes were independently verified. Onboarding progress does not establish keyboard, playback, normal close or reopen acceptance; those gates still require a passing native result.

The retained-focus transition is also reproduced by a headless Flutter regression: after setup finishes, the old outer focus node receives Ctrl+2 while the desktop shortcut callback remains outside its active focus ancestry. The desktop shortcut wrapper now provides a local FocusScope for its existing initial autofocus, without imperative focus requests. The source correction passed seven headless focus regressions, including editor focus, descendant handling and modal isolation/restoration. Automatic run 37136787480 still tested the old 4b9 package and repeated the Ctrl+2 failure; its 45 retained files and all twelve cleanup outcomes were independently verified. Its executor source cannot establish acceptance of the rebuilt product.

Nonpublishing candidate run 37136816470 completed with thirteen successful jobs and publication skipped. Independent verification bound all nineteen official bundle files to eighteen signed subjects, the exact source/ref/run and hosted certificate, three deterministic SBOMs and the complete Linux TAR/DEB payload and modes. The ordinary package startup test mapped sixteen runtime modules to that payload, showed onboarding for fifteen seconds, closed through WM_DELETE with exit code 0, and removed all six owned process identities plus the package and private profile. Root and an independent reviewer viewed the actual onboarding screenshot. The gate now pins this verified rebuilt input; native keyboard, import, playback, two normal closes and same-profile reopen still require a passing fresh behavior result.

Fresh behavior run 37139369194 tested the verified rebuilt product with executor commit 4f568879435015c6303496539b12b38ee8d9ebd7 and a separate PR trigger SHA. All six Ctrl-digit destinations and both Alt-arrow wrap checks succeeded in the actual semantic observations and eight independently reviewed screenshots. After opening Desktop density, the observer rejected the visible Compact choice because it required ENABLED; the actual fourteen-node popup exposed Tap and Focus with unspecified enabled state. The run remains FAIL before Compact selection, import, playback, normal close and reopen. All fifty-three official artifact files, separate source identities and twelve owned cleanup outcomes were independently verified. This failed run produced no new loaded-module or normal-close receipt; the candidate startup evidence remains a separate input proof. A corrected popup contract still requires fresh native execution and review.

### Real chooser text interface

The GTK location entry is resolved from a fresh tree of the owned portal process after the native Ctrl+L chord. It must be the unique visible, focused, editable text control, and the path must match the owned media exactly before Return is sent. GNOME provides separate [Accessible.get_text](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.Accessible.get_text.html) and [Text.get_text](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.Text.get_text.html) methods. The former obtains an interface without offsets; the latter reads a character range. The observer must explicitly invoke the Text interface method to avoid the Accessible name collision.

Behavior run 37141589677 used executor d601b16b00e6f0bcc8b4b5ef046a35951535d868 and the same verified rebuilt product. It repeated all eight keyboard checks, selected Compact through the ordinary popup, observed popup dismissal and the strict Compact setting row, and opened the real GTK picker. Independent screenshot review confirmed those states. The run remains FAIL because its text read resolved to the deprecated Accessible.get_text method and rejected the two offsets. It stopped before Return and successful import; playback, normal close and same-profile reopen were not reached. The predominantly occluded failure screenshot cannot establish a product crash or readable app state. The corrected interface call requires a fresh passing native result.

## Remaining production scope

This is limited Linux evidence for requirements **3c** and the keyboard portion of **3h** in the readiness audit. Production distribution trust, physical audible output, representative codecs/providers, screen-reader and full accessibility coverage, versioned migration/upgrade/rollback, and the other platform gates remain open until their own evidence is complete.
