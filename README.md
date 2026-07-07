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
  <a href="#platform-preview">Platform Preview</a> ·
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

## Platform Preview

### Animated tour

<p align="center">
  <img src="docs/media/readme/aethertune-platform-tour.gif" alt="AetherTune platform tour showing Android, iOS, Windows, macOS, Linux, and server support" width="840">
</p>

These illustrated README previews introduce the supported app surfaces. The Flutter client targets Android, iOS, Linux, macOS, and Windows; CI verifies desktop build targets, release workflows package Android plus desktop artifacts, and the Dart server exposes the API foundation.

| Surface | What the preview introduces |
|---|---|
| Android | Touch-first library search, provider search, and mini player |
| iOS | Playlists, synced lyrics, history, and privacy-first sources |
| Windows | Wide desktop layout with provider search, queue, and playback controls |
| macOS | Artwork-first player, lyrics, playlists, and provider privacy |
| Linux | Local library, folders, open providers, backup, and server-friendly foundations |
| Server | Health, info, catalog, provider, and future sync API foundations |

### Mobile screenshots

| Android | iOS |
|---|---|
| <img src="docs/media/readme/aethertune-android.svg" alt="AetherTune Android preview with library search, provider search, and mini player" width="300"> | <img src="docs/media/readme/aethertune-ios.svg" alt="AetherTune iOS preview with playlists, synced lyrics, and privacy-first providers" width="300"> |
| Library search, provider search, local playback, and mini player | Playlists, synced lyrics, privacy notes, and iOS/iPadOS-ready layout |

### Desktop screenshots

| Windows | macOS | Linux |
|---|---|---|
| <img src="docs/media/readme/aethertune-windows.svg" alt="AetherTune Windows desktop preview with unified provider search and queue" width="300"> | <img src="docs/media/readme/aethertune-macos.svg" alt="AetherTune macOS desktop preview with artwork, lyrics, and provider privacy" width="300"> | <img src="docs/media/readme/aethertune-linux.svg" alt="AetherTune Linux desktop preview with local library, folders, providers, and server foundations" width="300"> |
| Unified search, queue, and mini player on a wide desktop surface | Artwork, lyrics, smart playlists, and provider privacy | Local library, folders, backup, providers, and Linux CI coverage |

### Server preview

<p align="center">
  <img src="docs/media/readme/aethertune-server.svg" alt="AetherTune server preview with health, info, catalog, provider, and sync API foundations" width="560">
</p>

The server preview covers the Dart service that ships with the repo: health checks, API info, catalog endpoints, and the foundation for provider-backed sync or remote-library features.

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
| Local library | Import audio files through the native file picker or recursive folder scanner; edit saved metadata; resolve duplicates; search, sort, suggestion chips, and browse by artist, album, genre, source, or folder |
| Persistence | Saves imported tracks, favorites, playlists, lyrics, podcast feed subscriptions, podcast refresh status, podcast episode progress, playback history, submitted search history, offline mode, and the offline cache/download queue with `shared_preferences` |
| Backup/restore | Export and restore a versioned JSON backup, including submitted search history, offline mode, and queued offline media requests, from the Options tab |
| Search | Local library filtering by title, artist, album, genre, source, folder, favorites, and local-files-only offline readiness with sortable results and suggestion chips from submitted searches, playback history, and library metadata |
| Queue | Play current list as a persistent queue with next/previous controls, reorder/remove queue items, and save it as a playlist |
| History/stats | Recently played tab with local playback history, play counts, listening recap, date ranges, JSON/CSV stats export, top tracks/artists/albums/genres, and clear action |
| Playlists | Built-in and custom rule smart playlists plus create, rename, artwork URL edit, delete, open, find within, reorder, import/export JSON/M3U/CSV, and play manual playlists |
| Lyrics | Add, edit, view, and delete plain text or LRC timestamped lyrics, including playback-linked synced highlighting |
| Favorites | Toggle favorites per track |
| Sleep timer | Stop playback after presets, a custom 1-1440 minute duration, or the current track, with optional final-30-second fade-out |
| Repeat/shuffle | Persisted shuffle flag and repeat mode |
| Provider architecture | `MusicSourceProvider` interface with capability flags, privacy/network disclosure, offline cache/download policy gates, persisted offline request queue, user-triggered private cache storage for direct media URLs, unified provider search, demo provider, Podcast RSS feeds, Radio Browser mirror discovery/search/filtering, and Internet Archive audio search/filtering |
| Documentation | README, feature matrix, architecture, user guide, release guide, legal notes |
| GitHub readiness | MIT license, CI workflow, issue templates, contribution guide, security policy |
| Proof gates | CI analyzes/tests Flutter, builds desktop targets, analyzes/tests/compiles the server, and defines tag/manual release artifacts |

## Feature Goal

AetherTune is designed to support the combined feature categories users expect from modern free/open music clients:

| Feature category | Target support |
|---|---|
| Local files | Library import, recursive folder scanner, playback, search, favorites, recently added sorting, imported-folder browsing, stored metadata editing, duplicate resolver scaffold, folder-watch roadmap, and audio tag writer roadmap |
| History/stats | Recently played, local play counts, estimated listening time, date-range filters, JSON/CSV export, and top track/artist/album/genre recap implemented; richer yearly/monthly cards and visualizations roadmap |
| Backup/restore | JSON library backup implemented; file-based import/export polish roadmap |
| Streaming providers | Pluggable provider interface with declared capabilities, permissions, network disclosure, and cache/download policy gates for legal source adapters |
| Offline | Local-first data model, offline library filter, persisted offline mode that pauses network-backed source actions and player-wide saved stream playback, per-provider cache/download policy gate, persisted cache/download queue manager, private direct-URL cache storage, and resumable/background download plus eviction roadmap |
| Music discovery | Home feeds, charts, moods, radio, recommendations through provider plugins |
| Lyrics | Plain text lyrics, LRC timestamp parsing/preview, and playback-linked synced highlighting implemented; search and provider lyrics roadmap |
| Playlists | Manual playlists, artwork URL display/editing, built-in smart playlists, custom smart rules, in-playlist search, track reordering, JSON/M3U/CSV import/export, and save-queue-as-playlist implemented; synced rules, gallery picker, generated collages, and cross-device artwork sync roadmap |
| Android integrations | Notification controls, Android Auto roadmap, MediaSession roadmap |
| iOS integrations | Control Center, lock screen, background audio, CarPlay roadmap |
| Desktop | Linux/macOS/Windows build support, desktop-specific UX polish roadmap |
| Server | Health/info/catalog API foundation, sync and remote library roadmap |
| Privacy | No telemetry, no ads, no tracking, no forced account |
| Multi-source | Local provider support plus offline-mode network pausing and saved stream playback blocking, unified provider search across legal adapters, Podcast RSS feed subscriptions/play/save/OPML/refresh status/progress resume/cache-download queue and private cache eligibility, Radio Browser mirror discovery/search/filter/play/save/click accounting with live-stream cache/download denial, and Internet Archive audio search/filter/play/save/cache-download queue and private cache eligibility with multi-file item results; self-hosted and official API providers remain roadmap |

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
