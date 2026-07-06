<h1 align="center">AetherTune</h1>

<p align="center">
  <strong>Free, open-source music workspace with mobile, desktop, and server foundations; local playback, provider plugins, queue, favorites, search, sleep timer, offline-first architecture, and privacy-first design.</strong>
</p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="status alpha" src="https://img.shields.io/badge/status-alpha-orange">
  <img alt="framework Flutter" src="https://img.shields.io/badge/flutter-Android%20%7C%20iOS%20%7C%20Desktop-02569B">
  <img alt="free open source" src="https://img.shields.io/badge/100%25-free%20%26%20open%20source-brightgreen">
  <img alt="privacy" src="https://img.shields.io/badge/telemetry-none-success">
</p>

<p align="center">
  <code>Dart 3</code> · <code>Flutter</code> · <code>Android</code> · <code>iOS</code> · <code>Linux</code> · <code>macOS</code> · <code>Windows</code> · <code>Server</code> · <code>MIT</code>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#what-is-aethertune">Overview</a> ·
  <a href="#implemented-now">Implemented Now</a> ·
  <a href="#feature-goal">Feature Goal</a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a> ·
  <a href="docs/USER_GUIDE.md">User Guide</a> ·
  <a href="docs/RELEASE_GUIDE.md">Release Guide</a> ·
  <a href="LICENSE">License</a>
</p>

---

## What is AetherTune?

**AetherTune** is a GitHub-ready project for a completely free and open-source music app, starting with a Flutter client targeting **Android, iOS, Linux, macOS, and Windows** plus a Dart server service. The project is designed to combine the best product ideas from apps such as Kreate, OpenTune, InnerTune, SimpMusic, ArchiveTune, Spotube, Echo Music, Namida, PipePipe, NewPipe, LibreTube, Musify, AuraMusic, Bloomee Tunes, Gyawun Music, Music You, Muzza, SoundPod, NouTube, Grayjay, OuterTune, ViTune, RiMusic, Harmony Music, YMusic, YouTube Music, Flow, and MetroList.

The app is intentionally **provider-based**: the player, library, queue, cache, favorites, playlists, search, and UI are open-source core features, while source adapters can be added for legal sources such as local files, self-hosted servers, Internet Archive, Radio Browser, Jellyfin, Navidrome/Subsonic, podcasts, or other official APIs.

> Important: this repository does **not** include DRM bypass, paid-service cloning, credential stealing, private API scraping, or any code intended to violate a platform's terms. You can build legal source adapters through the provider interface.

## Quick Start

```bash
git clone https://github.com/YOUR_NAME/aethertune.git
cd aethertune

# Creates mobile and desktop platform wrappers when they are not already generated.
./scripts/bootstrap_client.sh

cd apps/mobile
flutter pub get
flutter run
```

To run the server:

```bash
cd services/server
dart pub get
dart run bin/server.dart
```

To build release packages:

```bash
cd apps/mobile
flutter build apk --release
flutter build appbundle --release
flutter build ios --release
flutter build linux --release
flutter build macos --release
flutter build windows --release
```

## Implemented Now

This scaffold includes real app code, not only a README:

| Area | Implemented in this project |
|---|---|
| Mobile app | Flutter app shell for Android and iOS |
| Desktop app | Same Flutter client builds for Linux, macOS, and Windows in CI |
| Server | Dart HTTP service with `/health`, `/api/v1/info`, and catalog endpoints |
| Playback | `just_audio` playback controller for local files and URL-based streams |
| Local library | Import audio files through the native file picker |
| Persistence | Saves imported tracks, favorites, playlists, and lyrics with `shared_preferences` |
| Search | Local library filtering by title, artist, and album |
| Queue | Play current list as a queue with next/previous controls |
| Playlists | Create, rename, delete, open, and play manual playlists |
| Lyrics | Add, edit, view, and delete plain text lyrics per library track |
| Favorites | Toggle favorites per track |
| Sleep timer | Stop playback after 5, 15, 30, 60, or 90 minutes |
| Repeat/shuffle | Runtime shuffle flag and repeat-mode hook |
| Provider architecture | `MusicSourceProvider` interface for legal source adapters |
| Documentation | README, feature matrix, architecture, user guide, release guide, legal notes |
| GitHub readiness | MIT license, CI workflow, issue templates, contribution guide, security policy |
| Proof gates | CI analyzes/tests Flutter, builds desktop targets, and analyzes/tests/compiles the server |

## Feature Goal

AetherTune is designed to support the combined feature categories users expect from modern free/open music clients:

| Feature category | Target support |
|---|---|
| Local files | Library import, playback, search, favorites, folders, metadata editing roadmap |
| Streaming providers | Pluggable provider interface for legal source adapters |
| Offline | Local-first data model, offline library, cache/download manager roadmap |
| Music discovery | Home feeds, charts, moods, radio, recommendations through provider plugins |
| Lyrics | Plain text lyrics implemented; synced LRC, search, and provider lyrics roadmap |
| Playlists | Manual playlists implemented; smart playlists and import/export roadmap |
| Android integrations | Notification controls, Android Auto roadmap, MediaSession roadmap |
| iOS integrations | Control Center, lock screen, background audio, CarPlay roadmap |
| Desktop | Linux/macOS/Windows build support, desktop-specific UX polish roadmap |
| Server | Health/info/catalog API foundation, sync and remote library roadmap |
| Privacy | No telemetry, no ads, no tracking, no forced account |
| Multi-source | Local, self-hosted, open catalog, podcasts, radio, and official API providers |

For the full truth table, see [`docs/FEATURE_MATRIX.md`](docs/FEATURE_MATRIX.md). The matrix separates **implemented**, **scaffolded**, **planned**, and **not included** features so the project does not make fake “100% done” claims.

## Project Layout

```text
aethertune/
├─ apps/mobile/                 # Flutter client app for mobile and desktop
│  ├─ lib/src/domain/            # Track and provider contracts
│  ├─ lib/src/data/              # Local persistence and demo provider
│  ├─ lib/src/player/            # Playback controller
│  └─ lib/src/ui/                # App UI
├─ services/server/              # Dart HTTP server package
├─ docs/                         # Architecture, matrix, user/release/legal docs
├─ scripts/                      # Bootstrap and check scripts
├─ .github/workflows/            # GitHub Actions CI
├─ LICENSE                       # MIT license
└─ README.md                     # Landing page
```

## Why this name?

**AetherTune** = music that can come from many “air”/network/local sources while remaining transparent, open, and user-controlled.

## Non-goals

AetherTune is not a piracy tool, not a YouTube Music Premium replacement, not a DRM bypass project, and not a private API scraper. The right way to expand it is through legal, documented, or user-owned sources.

## Contributing

Pull requests are welcome. Start with [`CONTRIBUTING.md`](CONTRIBUTING.md), then check [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/API_PROVIDERS.md`](docs/API_PROVIDERS.md).

## License

AetherTune is released under the **MIT License**. See [`LICENSE`](LICENSE).
