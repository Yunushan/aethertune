# Architecture

AetherTune is a local-first Flutter client with a provider-based source layer plus an optional Dart server for health checks, catalog metadata, and authenticated portable-library snapshots.

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
  HomeScreen, Library tab, Sources tab, Options tab, responsive PlayerBar,
  NowPlayingScreen, SelfHostedBrowseScreen, TrackTile

State layer
  LibraryStore, SelfHostedProviderStore, PlayerController

Domain layer
  Track, MusicSourceProvider, MusicCatalogProvider,
  MusicPlaylistMutationProvider, LyricsProvider,
  OfflineMediaPolicy

Data/provider layer
  Local file import, LocalFolderScanner, LocalFolderWatchStore, DemoSourceProvider,
  PodcastRssProvider, RadioBrowserProvider, InternetArchiveProvider,
  JellyfinProvider, SubsonicProvider, LrcLibLyricsProvider,
  ProviderCredentialVault, ProviderArtworkFileCache,
  OfflineCacheManager, future legal provider adapters

Platform layer
  Flutter Android/iOS/Linux/macOS/Windows wrappers, file picker,
  native just_audio playlist backend plus MediaKit Linux/Windows audio backends,
  audio_service system media session on Android/iOS/macOS

Server layer
  Dart Shelf handler, health/info/catalog endpoints, authenticated versioned
  library snapshot endpoint with checksum and optimistic revision conflict handling
```

## Domain model

`Track` is provider-independent. A track may have:

- `localPath` for local files.
- `streamUrl` for legal direct streams.
- a runtime-only authenticated `streamUrl` that serialization deliberately omits.
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

abstract interface class MusicCatalogProvider implements MusicSourceProvider {
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  );
  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  );
  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  });
}
```

Lyrics adapters implement the smaller `LyricsProvider` contract and return
provider-neutral `LyricsSearchResult` records. `LrcLibLyricsProvider` contacts
the documented LRCLIB `/api/search` endpoint only after a user opens online
lyrics search, sends the visible search terms with an identifying User-Agent,
and locally ranks plain/synced candidates against track metadata and duration.
The selected text is persisted in `TrackLyrics` with provider name, provider
record ID, and source URI; manual edits clear provider attribution.

Adapters should not leak service-specific logic into the player or UI. They should return neutral `Track` objects and declare capabilities plus privacy/network behavior up front so cache, download, auth, and sync code can enforce provider policy. Cache and download code must pass tracks through `OfflineMediaPolicy`, which requires matching provider capability plus disclosure before any non-local media is cached or downloaded. `OfflineCacheManager` handles the current user-triggered direct HTTP(S) media materialization into private app storage plus private-cache usage/manual eviction and automatic post-cache pressure eviction to persisted app-level and provider-level cache limits; background jobs and resumable downloads belong behind the same boundary later.

Credentialed self-hosted adapters are assembled by `SelfHostedProviderStore`. Non-secret server/account metadata uses preferences, while `ProviderCredentialVault` stores only the API key or password through the operating system secure-storage backend. Static credential rotation is a separate test-before-replace transaction: the store tests the candidate, writes the vault, restores the old value on write failure, and only then invalidates provider caches. The editor never receives an existing secret, and the rotation dialog confirms the replacement and redacts it from callback errors. `MusicCatalogProvider` gives Jellyfin and Navidrome/Subsonic one neutral artist/album/playlist collection model, detail contract, and authenticated artwork byte boundary, so responsive UI contains no protocol-specific JSON, endpoints, or credentials. The separate `MusicPlaylistMutationProvider` contract adds create, rename, delete, append, and ordered replacement only for adapters that declare `playlistMutation`; the shared UI derives move/remove operations from ordered provider track IDs and refreshes only after a guarded write succeeds. `Track.providerArtworkId` and `providerArtworkVersion` persist only safe provider identifiers. The adapter's binary loader enforces image MIME, non-empty content, and a 10 MiB limit before a 128-entry store cache feeds `TrackArtwork`; cache entries are invalidated on account edits, rotation, or removal. Jellyfin artwork authenticates through a private header, while Subsonic requests use per-request salted tokens instead of reversible password encoding. At playback resolution, `ProviderArtworkFileCache` atomically writes validated bytes to format-aware hashed paths under the private temporary directory, prunes stale partial files, and enforces 256-file/100-MiB bounds so `audio_service` can publish a credential-free local `artUri`. Provider rotation/removal deletes only that provider's private directory. Search and browse tracks remain metadata-only. `PlayerController` resolves authenticated stream URLs and private artwork immediately before native queue loading and marks both ephemeral, so queue snapshots, library JSON, and backups cannot retain them. After rotation it stops any loaded queue, removes old ephemeral URIs, re-resolves provider tracks, and restores the active position/play state when possible; failed tracks remain metadata-only and stopped. Errors redact raw, URI-encoded, hex, and token query values, while offline mode prevents catalog requests at the screen boundary.

## Playback

`PlayerController` drives a `PlaybackAudioEngine`. The production engine uses a
lazy `just_audio` playlist. On Android, iOS, and macOS it is wrapped by
`SystemMediaPlaybackEngine`, an `audio_service` handler that publishes the
queue, current metadata/artwork, duration, position, buffering, repeat, and
shuffle state to the operating system and routes system transport commands
back to the same player. Android and iOS wrapper settings are applied and
validated by `scripts/configure_audio_service_platforms.py` whenever the
generated Flutter wrappers are bootstrapped. The file-picker dependency is
exactly pinned to the upstream AGP 9 built-in Kotlin compatible prerelease
until that migration reaches a stable package release; generated iOS projects
are pinned to its required iOS 14 minimum and verified in tests. The player
provides:

- local file playback and persistent watched-folder rescans
- stream URL playback
- play/pause
- stop
- seek
- next/previous
- queue
- responsive compact and full Now Playing surfaces
- artwork swipe navigation, live seek/time labels, favorite, lyrics, and queue actions
- shuffle
- repeat mode
- sleep timer with optional fade-out
- Android media notification and headset controls
- iOS/macOS Control Center and lock-screen controls
- Android/iOS background music audio-session configuration

The same wrapper configuration step sets Android API 23 plus disabled auto
backup for encrypted storage, creates iOS/macOS Keychain entitlements, and is
verified by Flutter tests. Linux CI/release jobs install libsecret; Windows
release builders require the Visual C++ ATL component used by the plugin.

## Persistence

`LibraryStore` currently uses `shared_preferences` for a simple JSON track store. Self-hosted account metadata also uses preferences, but provider API keys/passwords never do: they use `flutter_secure_storage` through `ProviderCredentialVault` and are excluded from JSON backups. When the app grows, migrate non-secret structured data to a database such as SQLite or Drift while preserving the vault boundary.

## Server

`services/server` is a Dart package with a Shelf-compatible request handler. It exposes:

- `GET /health`
- `GET /api/v1/info`
- `GET /api/v1/tracks`
- `GET /api/v1/sync/library`
- `PUT /api/v1/sync/library`

The sync routes are disabled until the operator supplies an
`AETHERTUNE_SYNC_USERS` JSON map of user IDs to bearer tokens. The server keeps
only the latest checksum-verified portable snapshot per user under
`AETHERTUNE_DATA_DIR`, enforces an optimistic base revision, and rejects local
paths and device cache jobs. Registration, token lifecycle, automatic sync,
and merge policies remain client/server roadmap work.

The server is intentionally small, but it is real code with tests and CI coverage. Future server work should add authenticated sync, remote library metadata, and provider coordination without weakening the client-first privacy model.

## Future modules

Recommended packages/modules:

```text
packages/core/             Provider-neutral models and contracts
packages/provider_local/   Local library scanner/importer
packages/provider_rss/     Podcast adapter extraction from current mobile foundation
packages/provider_radio/   Radio Browser adapter extraction from current mobile foundation
packages/provider_jellyfin/Jellyfin adapter
packages/provider_archive/ Internet Archive adapter
packages/cache/            Offline cache/download manager
packages/lyrics/           LRC/plain lyrics parser
```
