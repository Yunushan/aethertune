# Ordinary Linux release behavior acceptance

This gate covers the ordinary installed Linux application: documented keyboard navigation, synthetic local PCM playback, and state after normal close and reopen. Native execution and independent review of the retained screenshots are required before acceptance is recorded.

## Product and executor identity

The dedicated `linux-release-behavior` workflow uses the verified nonpublishing candidate containing the accessible-control, desktop shortcut focus, runtime duration and MPRIS position/seek fixes:

- Product commit: `64f287e35ae24f383f6f6c03fee93a574b2a169b`.
- Product ref: `refs/heads/codex/readiness-linux-behavior`.
- Release run: `37149690718`, attempt `1`.
- Release bundle artifact: `11283822755`.

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

Nonpublishing candidate run 37136816470 completed with thirteen successful jobs and publication skipped. Independent verification bound all nineteen official bundle files to eighteen signed subjects, the exact source/ref/run and hosted certificate, three deterministic SBOMs and the complete Linux TAR/DEB payload and modes. The ordinary package startup test mapped sixteen runtime modules to that payload, showed onboarding for fifteen seconds, closed through WM_DELETE with exit code 0, and removed all six owned process identities plus the package and private profile. Root and an independent reviewer viewed the actual onboarding screenshot. That version of the gate pinned this verified rebuilt input; native keyboard, import, playback, two normal closes and same-profile reopen still required a passing fresh behavior result.

Fresh behavior run 37139369194 tested the verified rebuilt product with executor commit 4f568879435015c6303496539b12b38ee8d9ebd7 and a separate PR trigger SHA. All six Ctrl-digit destinations and both Alt-arrow wrap checks succeeded in the actual semantic observations and eight independently reviewed screenshots. After opening Desktop density, the observer rejected the visible Compact choice because it required ENABLED; the actual fourteen-node popup exposed Tap and Focus with unspecified enabled state. The run remains FAIL before Compact selection, import, playback, normal close and reopen. All fifty-three official artifact files, separate source identities and twelve owned cleanup outcomes were independently verified. This failed run produced no new loaded-module or normal-close receipt; the candidate startup evidence remains a separate input proof. A corrected popup contract still requires fresh native execution and review.

### Real chooser text interface

The GTK location entry is resolved from a fresh tree of the owned portal process after the native Ctrl+L chord. It must be the unique visible, focused, editable text control, and the path must match the owned media exactly before Return is sent. GNOME provides separate [Accessible.get_text](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.Accessible.get_text.html) and [Text.get_text](https://gnome.pages.gitlab.gnome.org/at-spi2-core/libatspi/method.Text.get_text.html) methods. The former obtains an interface without offsets; the latter reads a character range. The observer must explicitly invoke the Text interface method to avoid the Accessible name collision.

Behavior run 37141589677 used executor d601b16b00e6f0bcc8b4b5ef046a35951535d868 and the same verified rebuilt product. It repeated all eight keyboard checks, selected Compact through the ordinary popup, observed popup dismissal and the strict Compact setting row, and opened the real GTK picker. Independent screenshot review confirmed those states. The run remains FAIL because its text read resolved to the deprecated Accessible.get_text method and rejected the two offsets. It stopped before Return and successful import; playback, normal close and same-profile reopen were not reached. The predominantly occluded failure screenshot cannot establish a product crash or readable app state. The corrected interface call requires a fresh passing native result.

### Imported Library track selection

The ordinary Library exposes both a title filter chip and a TrackTile containing the title plus its artist, album and genre subtitle. Imported-track observation and playback selection must match the full owned-fixture track caption and require one actionable track row. A bare title chip is not the track row. Existing fresh owned-process, visible/enabled state, unique-target and native named-Tap checks remain required; duplicates must fail.

Behavior run 37142897399 used executor 2286eeeba3db4215d8c94bee8a5a5ba4e711feca and the same verified rebuilt product. Its real GTK Text read verified the exact owned WAV path, Return selected that file and the picker closed. The actual Library screenshot then showed both the filename filter chip and the imported local track row. The observer remains FAIL because its substring selector matched both actionable controls. The fourteen actual screenshots and seventy-four-node tree passed independent visual review. No track Tap, playback, normal close or same-profile reopen was reached; successful file selection and visible track metadata do not establish the complete behavior gate. The corrected track selector requires fresh native execution.

### Native seek slider selection

The native tree can flatten playback progress and volume widgets into the same content panel. The selector must bind the seek slider to the unique elapsed, remaining and Playback volume labels and their observed source order. It must distinguish the strict seek slider before the time labels from the distinct volume slider after its label, and reject extra or ambiguous sliders. Existing fresh owned-process, native state and named Increase-action checks remain required; the gate must never adjust volume as a substitute for seeking.

Behavior run 37144337735 used executor a94ad838fcc6f3d9ca6a0f0a98afc2d6cca1fc4f and the same verified rebuilt product. It completed the real file selection, observed the imported Library row, tapped that row and opened the current owned track in Now Playing. UI elapsed time progressed from one to three seconds, and Pause held four seconds across four samples over 2.7559 seconds. Independent review verified all sixty official files, seventeen actual screenshots, separate source identities and twelve owned cleanup outcomes. The run remains FAIL because its ancestor selector found both seek and volume sliders in the same flattened panel. No seek action, independent MPRIS/Pulse output check, normal close or same-profile reopen was reached. UI timing evidence alone does not establish native audio output or the complete behavior gate. The corrected seek selector requires a fresh passing native result.

### MPRIS failure diagnostics

Before rejecting a duration or seek capability, the independent MPRIS audit must retain the bounded observed length presence, scalar value and type, and CanSeek scalar value and type. Observation time and owned bus/process binding remain required. It must not save arbitrary metadata or media URLs, substitute expected values, or relax the fixture duration, capability or track identity checks.

Behavior run 37145651552 used executor 8faac78286a2030121450cf40a21c7b4dfe2ddc8 and the same verified rebuilt product. Its initial UI observer returned PASS after the complete keyboard, density, real file import, track selection, playback and seek sequence. UI pause held three seconds across four samples over 2.6778 seconds; the owned seek Increase changed elapsed time from three to twelve seconds, then playback resumed and paused at fourteen seconds. Root viewed the paused, seeked and after-seek-paused screenshots. The overall coordinator remains FAIL at its independent MPRIS fixture duration/seek capability check. That failure receipt retained the owned app binding but no observed duration or capability values, so its cause cannot be inferred from the failed predicate. All sixty-three official files, eighteen actual screenshots, separate input/source bindings and twelve owned cleanup outcomes were independently verified. The dropdown opening image did not visibly expose Compact; its subsequent ordinary Compact setting row was visible and its semantic selection was separately verified. No independent MPRIS/Pulse output acceptance, normal close, same-profile reopen or new loaded-module receipt was reached. The earlier ordinary startup proof remains separate.

Behavior run 37147144251 used executor 1b669b043129b29e8160fd57e5e980ebbd1c84f9 and the same verified product. Its initial UI observer again returned PASS: pause held four seconds across four samples over 2.7248 seconds, seek advanced from four to thirteen seconds, playback resumed to fifteen seconds and paused. The new MPRIS observation bound the actual app and imported track, read CanSeek as boolean true, and recorded that mpris:length was absent. This distinguishes the current failure from earlier unrecorded values; it does not retroactively fill them. All sixty-three official files, eighteen images, original product certificate/payload, separate executor provenance and twelve owned cleanup outcomes were independently verified. Overall behavior remains FAIL before accepted MPRIS samples, native output, normal close, reopening or new loaded-module evidence.

### Runtime MPRIS duration and position

A repeated report of the same current track index must retain its known runtime duration. Actual index changes, queue/source replacements, failed queue rollback and explicit null duration events must still clear the cache. The underlying duration event does not carry a source identity; retaining duration across a genuinely changed index would require separate source evidence. The observed missing length and the reproduced cache path must remain distinct from a fresh native acceptance result.

MPRIS Position must reflect timestamped authoritative playback state, progress only during ready playback at the actual rate, and remain stable while paused or buffering. Seek responses must use the decoder-confirmed actual position after awaiting the ordinary handler, preserve track identity, reject stale or out-of-range SetPosition requests without altering playback, and emit Seeked for confirmed discontinuities. Requested positions and an independent timer cannot substitute for decoder state or the separate owned Pulse output gate. Any product correction requires a new nonpublishing candidate and fresh acceptance; the prior 0aaa package cannot establish that correction.

### Rebuilt runtime correction candidate

Product commit 64f287e35ae24f383f6f6c03fee93a574b2a169b contains the reviewed runtime duration and MPRIS correction. Forty-two focused headless tests passed without skips, targeted analysis reported no issues, and the release formatter reported 409 files with zero changes. Old source reproduced stored Position and duration loss on a repeated current index. A separate regression through the real D-Bus method dispatcher reproduced the object-path conversion failure and passed with the corrected raw path value. Requested rate/seek values, stale tracks and queue generations cannot establish decoder confirmation.

Nonpublishing candidate run 37149690718, attempt 1, completed with thirteen successful jobs and publication skipped. The official bundle 11283822755 was downloaded and its actual 432757097 bytes matched API digest 97a3160de5b5fe38fd368483fb7c5f550d1feb94a58d1b3586046e0c0b79411a. Verification covered all nineteen files, eighteen checksums and signed subjects, seventeen manifest artifacts, three reproducible SBOMs, 38 exact Git source blobs, and complete Linux TAR/DEB payload bytes and modes. Fresh standard GitHub CLI verification retained the default TUF roots and bound the hosted certificate, source, signer, ref, workflow and run/attempt. This certifies the candidate input; it does not certify an integrated main revision or production signing/trust.

The separate ordinary startup artifact 11283711905 matched its official digest and thirteen files. Its 45 owned installed entries and sixteen mapped modules were bound to the rebuilt complete Linux payload: 43 TAR entries and 49 DEB archive/dpkg inventory entries. The owned installed snapshot excludes the four shared parent directories `opt`, `usr`, `usr/share` and `usr/share/applications`; their names remain in the complete package inventory. The owned app showed ordinary onboarding for 15.3 seconds, closed through WM_DELETE with exit 0, and the six owned processes, package and private profile were cleaned up. Root and an independent reviewer viewed the actual onboarding screenshot. Default accessibility-bus and engine teardown warnings remain retained. This starter does not establish keyboard/import/seek, independent MPRIS/Pulse output, two normal closes or same-profile reopen. Those requirements need a fresh behavior run against this exact new package. Windows UI remains pending at the user's request; earlier platform runtime receipts cannot certify this shared playback-engine correction.

## Remaining production scope

This is limited Linux evidence for requirements **3c** and the keyboard portion of **3h** in the readiness audit. Production distribution trust, physical audible output, representative codecs/providers, screen-reader and full accessibility coverage, versioned migration/upgrade/rollback, and the other platform gates remain open until their own evidence is complete.
