# Windows Native Sync Acceptance

This is a real Windows application build with a guarded test entrypoint. It calls
the normal application startup and shared sync executor, not a replacement HTTP
implementation. It complements the broader media/storage native acceptance.

## Safety And Prerequisites

Use a Windows host with Windows Sandbox, the pinned Flutter/Rust toolchains,
Visual Studio C++ build tools and OpenSSL. Never launch the acceptance executable
on the host: native URL registration occurs before the Dart guard can run.
The driver rejects profiles other than the marked disposable Sandbox account.

Only a generated input directory (read-only) and evidence directory (writable)
are mapped. Networking, clipboard, audio input and video input are disabled.
Synthetic certificates last two days and are regenerated for each fixture. Only
the guest machine certificate store receives the synthetic trusted root; no host
certificate store is touched. The guest removes it and shuts down after testing.
Using the guest machine store avoids an interactive user-root import warning.

## Run

From the repository root, substitute a new unused output directory each time:

```powershell
Push-Location apps/mobile
flutter build windows --release --no-pub --target integration_test/windows_sync_transport_acceptance.dart
Pop-Location
scripts/ci/package_windows_zip.ps1 -BundlePath apps/mobile/build/windows/x64/runner/Release -OutputPath build/sync-acceptance/probe.zip
scripts/ci/prepare_windows_sync_sandbox.ps1 -ProbeZip build/sync-acceptance/probe.zip -OutputDirectory "$PWD/build/sync-acceptance/guest-a" -OpenSslPath 'C:\Program Files\Git\usr\bin\openssl.exe'
Start-Process WindowsSandbox.exe -ArgumentList "$PWD/build/sync-acceptance/guest-a/acceptance.wsb" -WindowStyle Hidden
```

Inspect `guest-a/evidence/started.json` for the live driver stage and `result.json`
for terminal results. `wsb list --raw` is authoritative for whether the guest is
still running; a launcher process exiting does not establish guest completion.
Preserve failed runs. Do not automatically kill or restart a guest merely because
an observation timeout expires, and never stop an unrelated Sandbox instance.

After archiving the guarded probe, restore the ordinary build directory:

```powershell
Push-Location apps/mobile
flutter build windows --release --no-pub --target lib/main.dart
Pop-Location
```

## Acceptance Criteria

The contract phase requires real platform-trusted HTTPS, UTF-8 upload, status and
authorization preservation, redirect refusal, untrusted-root and hostname
rejection before HTTP credentials reach the server, repeated stalled-handshake
deadline/peer cleanup, and three independent Dart-isolate round trips.

For each TLS/header/body stall, a peer outside the application must receive
request bytes, confirm the connection and process are still alive, then observe
normal native-window close within five seconds and socket release within a
further two seconds. A forced kill, abnormal exit, missing packaged `rhttp.dll`,
or asynchronous native error is a failure. Production request deadlines remain
unchanged in these shutdown controls.

The diagnostic-only explicit-root client cannot make a failed application
certificate control pass. Driver policy tests protect fixture scope but are not
a substitute for executing the native application. These results do not certify
other operating systems, signed installation, mobile background execution,
Internet/proxy behavior, every failure mode or production readiness by themselves.
