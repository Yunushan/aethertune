# Release Guide

## Versioning

Update `apps/mobile/pubspec.yaml`:

```yaml
version: 0.1.0+1
```

Use semantic versioning for the public version and increment the build number for every store build.

## Android release

```bash
cd apps/mobile
flutter build apk --release
flutter build appbundle --release
```

For a real Play Store/F-Droid release, configure signing keys outside the repository. Never commit keystores or passwords.

## iOS release

```bash
cd apps/mobile
flutter build ios --release
```

Open the generated iOS project in Xcode for signing, capabilities, and App Store upload.

## Desktop release

Build desktop packages on their native operating systems:

```bash
cd apps/mobile
flutter build linux --release
flutter build macos --release
flutter build windows --release
```

The GitHub Actions workflow proves debug desktop builds for Linux, macOS, and Windows. Release packaging still needs platform-specific signing, notarization, installer, or archive work.

## Server release

```bash
cd services/server
dart pub get
dart compile exe bin/server.dart -o build/aethertune-server
```

For hosted deployments, set `PORT` in the environment. The server exposes `/health` for uptime checks.

## F-Droid notes

AetherTune is MIT licensed and has no telemetry. To prepare for F-Droid:

- Avoid proprietary SDKs.
- Keep builds reproducible where possible.
- Document all network calls from provider adapters.
- Do not include copyrighted media assets.

## GitHub release checklist

- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] Desktop debug builds pass in GitHub Actions.
- [ ] `dart analyze` passes in `services/server`.
- [ ] `dart test` passes in `services/server`.
- [ ] `dart compile exe` passes in `services/server`.
- [ ] Feature matrix is current.
- [ ] Changelog is written.
- [ ] APK/AAB/IPA build instructions are verified.
- [ ] License and third-party notices are updated.
