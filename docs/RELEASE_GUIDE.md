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

## F-Droid notes

AetherTune is MIT licensed and has no telemetry. To prepare for F-Droid:

- Avoid proprietary SDKs.
- Keep builds reproducible where possible.
- Document all network calls from provider adapters.
- Do not include copyrighted media assets.

## GitHub release checklist

- [ ] `flutter analyze` passes.
- [ ] `flutter test` passes.
- [ ] Feature matrix is current.
- [ ] Changelog is written.
- [ ] APK/AAB/IPA build instructions are verified.
- [ ] License and third-party notices are updated.
