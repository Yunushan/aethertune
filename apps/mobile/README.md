# AetherTune Client App

This is the Flutter client package for AetherTune mobile and desktop targets.

## Platform Preview

<p align="center">
  <img src="../../docs/media/readme/aethertune-platform-tour.gif" alt="AetherTune platform tour showing Android, iOS, Windows, macOS, Linux, and server support" width="760">
</p>

The client targets **Android**, **iOS**, **Windows**, **macOS**, and **Linux** from the same Flutter codebase. The Dart server lives in `../../services/server`; its API preview is shown in the repository root README.

| Android | iOS |
|---|---|
| <img src="../../docs/media/readme/aethertune-android.svg" alt="AetherTune Android preview with library search, provider search, and mini player" width="300"> | <img src="../../docs/media/readme/aethertune-ios.svg" alt="AetherTune iOS preview with playlists, synced lyrics, and privacy-first providers" width="300"> |
| Touch-first library search, provider search, local playback, and mini player | Playlists, synced lyrics, history, privacy notes, and iOS/iPadOS-ready layout |

| Windows | macOS | Linux |
|---|---|---|
| <img src="../../docs/media/readme/aethertune-windows.svg" alt="AetherTune Windows desktop preview with unified provider search and queue" width="300"> | <img src="../../docs/media/readme/aethertune-macos.svg" alt="AetherTune macOS desktop preview with artwork, lyrics, and provider privacy" width="300"> | <img src="../../docs/media/readme/aethertune-linux.svg" alt="AetherTune Linux desktop preview with local library, folders, providers, and server foundations" width="300"> |
| Unified search, queue, and playback controls on a wide desktop surface | Artwork, lyrics, smart playlists, and provider privacy | Local library, folders, backup, open providers, and Linux CI coverage |

For the full project introduction, release artifacts, and server overview, see the repository-level [README](../../README.md).

## Run

```bash
flutter pub get
flutter run
```

The repository-level script `../../scripts/bootstrap_client.sh` generates Android, iOS, Linux, macOS, and Windows platform wrappers if they are missing.
