# Contributing to AetherTune

Thanks for helping build a free and open music app.

## Development principles

1. **User freedom first**: no telemetry, no ads, no forced accounts.
2. **Legal sources only**: do not submit code for DRM bypass, credential theft, paid-service cloning, or private API scraping.
3. **Provider isolation**: source adapters belong behind the `MusicSourceProvider` interface.
4. **Truthful README**: never mark a feature complete until it works in the app.
5. **Platform compatibility**: every core change should be tested on the affected mobile, desktop, or server target, or clearly documented as platform-specific.

## Local setup

```bash
./scripts/bootstrap_client.sh
./scripts/check.sh
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

- [ ] Client analysis passes with `flutter analyze`.
- [ ] Client tests pass with `flutter test`.
- [ ] Server analysis passes with `dart analyze`.
- [ ] Server tests pass with `dart test`.
- [ ] Desktop CI builds remain green for Linux, macOS, and Windows when client behavior changes.
- [ ] The feature matrix is updated if a feature changed.
- [ ] No proprietary assets or copyrighted media are included.
- [ ] No terms-of-service circumvention or DRM bypass is included.
