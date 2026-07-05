# Contributing to AetherTune Mobile

Thanks for helping build a free and open music app.

## Development principles

1. **User freedom first**: no telemetry, no ads, no forced accounts.
2. **Legal sources only**: do not submit code for DRM bypass, credential theft, paid-service cloning, or private API scraping.
3. **Provider isolation**: source adapters belong behind the `MusicSourceProvider` interface.
4. **Truthful README**: never mark a feature complete until it works in the app.
5. **Mobile compatibility**: every core change should be tested on Android and iOS, or clearly documented as platform-specific.

## Local setup

```bash
./scripts/bootstrap_mobile.sh
cd apps/mobile
flutter pub get
flutter test
flutter analyze
```

## Branch naming

Use clear names:

```text
feature/local-playlists
fix/sleep-timer-dispose
docs/provider-guide
```

## Commit style

Use concise conventional-style commits:

```text
feat(player): add queue persistence
fix(library): avoid duplicate imported tracks
docs(readme): update Android build steps
```

## Pull request checklist

- [ ] The code builds with `flutter analyze`.
- [ ] Tests pass with `flutter test`.
- [ ] The feature matrix is updated if a feature changed.
- [ ] No proprietary assets or copyrighted media are included.
- [ ] No terms-of-service circumvention or DRM bypass is included.
