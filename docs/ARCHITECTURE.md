# Architecture

AetherTune is a local-first Flutter client with a provider-based source layer plus a small Dart server foundation for health checks, metadata, and future sync APIs.

## Goals

- Run on Android, iOS, Linux, macOS, and Windows from one Flutter codebase.
- Provide a real server package that can be analyzed, tested, and run independently.
- Keep the player, library, queue, and UI open-source and source-agnostic.
- Allow legal source adapters without coupling the app to any single service.
- Avoid telemetry and forced accounts.
- Keep proprietary or legally risky behavior out of the core project.

## Layers

```text
UI layer
  HomeScreen, Library tab, Sources tab, Options tab, PlayerBar, TrackTile

State layer
  LibraryStore, PlayerController

Domain layer
  Track, MusicSourceProvider

Data/provider layer
  Local file import, DemoSourceProvider, PodcastRssProvider, future legal provider adapters

Platform layer
  Flutter Android/iOS/Linux/macOS/Windows wrappers, file picker, audio backend

Server layer
  Dart Shelf handler, health endpoint, app info endpoint, catalog endpoint
```

## Domain model

`Track` is provider-independent. A track may have:

- `localPath` for local files.
- `streamUrl` for legal direct streams.
- metadata only while a provider resolves playback.
- `sourceId` to trace where it came from.

## Provider contract

Every source adapter implements:

```dart
abstract interface class MusicSourceProvider {
  String get id;
  String get name;
  String get description;
  Set<MusicSourceCapability> get capabilities;
  ProviderPrivacyDisclosure get disclosure;
  Future<List<Track>> search(String query);
  Future<Uri?> resolveStream(Track track);
}
```

Adapters should not leak service-specific logic into the player or UI. They should return neutral `Track` objects and declare capabilities plus privacy/network behavior up front so cache, download, auth, and sync code can enforce provider policy.

## Playback

`PlayerController` wraps `just_audio` and provides:

- local file playback
- stream URL playback
- play/pause
- stop
- seek
- next/previous
- queue
- shuffle
- repeat mode
- sleep timer

## Persistence

`LibraryStore` currently uses `shared_preferences` for a simple JSON track store. When the app grows, migrate to a structured local database such as SQLite, Drift, Isar, or ObjectBox.

## Server

`services/server` is a Dart package with a Shelf-compatible request handler. It currently exposes:

- `GET /health`
- `GET /api/v1/info`
- `GET /api/v1/tracks`

The server is intentionally small, but it is real code with tests and CI coverage. Future server work should add authenticated sync, remote library metadata, and provider coordination without weakening the client-first privacy model.

## Future modules

Recommended packages/modules:

```text
packages/core/             Provider-neutral models and contracts
packages/provider_local/   Local library scanner/importer
packages/provider_rss/     Podcast adapter extraction from current mobile foundation
packages/provider_radio/   Radio adapter
packages/provider_jellyfin/Jellyfin adapter
packages/provider_archive/ Internet Archive adapter
packages/cache/            Offline cache/download manager
packages/lyrics/           LRC/plain lyrics parser
```
