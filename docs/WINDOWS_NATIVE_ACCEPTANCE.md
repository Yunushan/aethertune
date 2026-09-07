# Windows Native Acceptance

This fixture builds a separate release-mode entrypoint that calls production
startup, uses real plugins and file storage, and opens the production video
screen. It uses generated WAV, H.264/MP4, VP9/WebM, APNG and invalid-file media
with an invented credential and a guest-loopback trickling HTTP source. It never
uses real accounts, libraries, provider services or host audio capture.

**Never launch the probe executable on the host.** The native Windows runner
registers its URL scheme before Dart executes, so the Dart guard alone cannot
protect a real user profile. Run it only through the marked Windows Sandbox
configuration prepared below. The guest driver independently checks its user
and marker before entering any block that could launch an app or shut down.

## Prerequisites

- The repository's pinned Flutter dependencies must already be resolved.
- Windows Sandbox must already be available; do not disable host security or
  change host virtualization settings just to make this test pass.
- Visual Studio C++/ATL tools and release CRT files are required for packaging.
- Python with Pillow and an explicitly selected FFmpeg encoder with libx264 and
  libvpx-vp9 are required only to generate/validate synthetic fixture media.
  The encoder is not shipped in app archives or executed inside the guest.
- Run from the repository root with Flutter and Python available on PATH, or
  supply their installed paths. Preserve previous evidence in separate folders.

## Build And Prepare

The following commands are for an isolated candidate, not release publication.
Check each build's exit status before continuing. The final build restores the
normal `lib/main.dart` output, avoiding a probe in the usual release directory.

```powershell
$ErrorActionPreference = 'Stop'
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$output = 'build/windows-native-candidate'
New-Item -ItemType Directory -Path $output | Out-Null
Push-Location apps/mobile
try {
  flutter build windows --release --no-pub -t integration_test/windows_native_acceptance.dart
  if ($LASTEXITCODE -ne 0) { throw 'Probe build failed' }
} finally { Pop-Location }
./scripts/ci/package_windows_zip.ps1 -BundlePath apps/mobile/build/windows/x64/runner/Release -OutputPath "$output/probe.zip"
Push-Location apps/mobile
try {
  flutter build windows --release --no-pub -t lib/main.dart
  if ($LASTEXITCODE -ne 0) { throw 'Production build failed' }
} finally { Pop-Location }
./scripts/ci/package_windows_zip.ps1 -BundlePath apps/mobile/build/windows/x64/runner/Release -OutputPath "$output/production.zip"
./scripts/ci/prepare_windows_native_sandbox.ps1 -ProbeZip "$output/probe.zip" -ProductionZip "$output/production.zip" -OutputDirectory "$output/sandbox" -FfmpegPath $ffmpeg
```

Inspect the generated `acceptance.wsb` before opening it. It maps only its
generated inputs read-only and its evidence directory writable. Networking,
clipboard, camera, microphone and printer redirection are disabled. No real
profile, repository root, credentials or media directory is mapped. Do not
interrupt an unrelated existing Sandbox session to start this fixture.

Open that `.wsb` file with Windows Sandbox. The driver runs three phases:

1. Exercise: seed legacy library/player preferences and a synthetic secure-storage
   credential; run production startup and migration; import a second WAV;
   persist a rating, favorite, playlist change and named player queue;
   decode audio; send guest-only OS media keys for
   pause/resume/next/previous; seek; decode and render both frame colors for
   H.264/MP4 and VP9/WebM; verify paused position, seek and resume; verify a
   corrupt video's visible error, repair the same source and verify real retry
   decoding/rendering. APNG is a diagnostic control: it
   must either decode/render successfully or report a visible unsupported-file
   error without retaining a spinner. It cannot replace the required MP4/WebM
   positive controls. A guest-only HTTP server then trickles a valid MP4 without
   enough media bytes for a frame. Both the normal backend's earlier error and
   the app's 30-second first-frame startup deadline are tested. The second case
   uses a real native player with its socket timeout extended to 60 seconds only
   inside the fixture; this fault injection must not change production settings.
   Once the same endpoint serves complete media, Retry must create a new HTTP
   request and pass real frame/transport checks in both cases.
   No external networking is enabled; the server binds only guest loopback and
   is closed in the fixture's cleanup path.
2. Reopen: start a separate process and verify the credential, library,
   playlist, active/named player queues and volume survived, without unintended
   autoplay or modification of the preserved legacy player settings.
3. Production: start the ordinary app archive against that guest data, require
   a window to remain alive for 15 seconds, and retain a desktop screenshot.

The guest captures module inventories, key requests/delivery records, stdout,
stderr, decoded video frames, rendered video frames and desktop screenshots.
The host generator independently decodes all 160 frames of each standard video
and checks their expected dimensions/colors before writing its manifest. The
manifest records encoder identity and media hashes; host FFmpeg decoding does
not itself validate the app's different native backend.
Each probe phase has a deadline and writes a JSON report. A failed exercise does
not prevent the independent reopen and ordinary-startup checks from running,
but any failed phase still fails the overall result. Before a failing probe
exits, it requests a screenshot from the guest driver using its owned PID and
phase. Video failures also retain bounded player-state samples, native errors,
properties and a decoder screenshot when available; this raw diagnostic path
exists only in the guarded synthetic fixture, never production diagnostics.
The driver stops its
owned process and shuts down the guest on success or failure. A host observation
timeout is not proof that the guest stopped: inspect the same Sandbox instance
and result before considering another run.

## Acceptance And Limits

Require `evidence/result.json` to report `passed`, both probe processes to exit
zero, and every expected check to appear. Independently inspect screenshots and
module inventories; verify no omitted `zlib.dll` or debug CRT was loaded. Confirm
the Sandbox instance and owned processes have stopped. Retain package and source
hashes with the logs so results cannot be attributed to a different candidate.

This proves only the tested fixture's native behavior. WAV progression is not a
measurement of physical speaker output. Two synthetic video codecs are not
coverage of all containers, profiles, hardware decoders, subtitle/audio tracks,
Internet/TLS/proxy video or all ANGLE dynamic-loading paths. The loopback control
proves one native trickling-source timeout and retry path, not every network
failure. Widget tests separately exercise a stalled native open and stalled or
failed cleanup. The UI waits at most ten seconds for prior cleanup, retains its
ownership and refuses a successor until cleanup succeeds; a timeout does not
pretend to cancel native work. Guest key delivery is
not every physical keyboard or Bluetooth device. The final startup observation
does not prove signed MSIX installation, updates, uninstall, crash recovery,
accessibility or physical power-loss durability. Those remain separate release
requirements; do not waive them because this fixture passes.
