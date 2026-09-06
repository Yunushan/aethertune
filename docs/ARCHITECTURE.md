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
  Track, MusicSourceProvider, MusicSourceSearchPagingProvider,
  MusicCatalogProvider, MusicCatalogPagingProvider,
  MusicCatalogDiscoveryProvider,
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
  Dart Shelf handler, health/info/catalog/aggregate-metrics endpoints,
  privacy-preserving structured request logs, authenticated versioned library
  snapshot endpoint with checksum and optimistic revision conflict handling
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

abstract interface class MusicSourceSearchPagingProvider
    implements MusicSourceProvider {
  Future<MusicSourceSearchPage> searchPage(
    String query, {
    String? cursor,
    int limit = 20,
  });
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

abstract interface class MusicCatalogDiscoveryProvider
    implements MusicCatalogProvider {
  List<MusicCatalogDiscoveryKind> get discoveryKinds;
  Future<List<MusicCatalogCollection>> browseDiscoveryCollections(
    MusicCatalogDiscoveryKind kind, {
    int limit = 6,
  });
}

abstract interface class MusicCatalogPagingProvider
    implements MusicCatalogProvider {
  Set<MusicCatalogCollectionKind> get pagedCollectionKinds;
  Future<MusicCatalogCollectionPage> browseCollectionsPage(
    MusicCatalogCollectionKind kind, {
    int offset = 0,
    int limit = 100,
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

Adapters should not leak service-specific logic into the player or UI. They should return neutral `Track` objects and declare capabilities plus privacy/network behavior up front so cache, download, auth, and sync code can enforce provider policy. Cache and download code must pass tracks through `OfflineMediaPolicy`, which requires matching provider capability plus disclosure before any non-local media is cached or downloaded. `OfflineCacheManager` handles direct HTTP(S) media materialization into private app storage, validated resumable transfers, and cache usage/eviction under persisted app/provider limits. Foreground and headless queue workers use this same boundary; native scheduling and shutdown acceptance remain separate requirements.

Credentialed self-hosted adapters are assembled by `SelfHostedProviderStore`. Non-secret server/account metadata uses preferences, while `ProviderCredentialVault` stores only the API key or password through the operating system secure-storage backend. Static credential rotation is a separate test-before-replace transaction: the store tests the candidate, writes the vault, restores the old value on write failure, and only then invalidates provider caches. The editor never receives an existing secret, and the rotation dialog confirms the replacement and redacts it from callback errors. `ProviderSearchCoordinator` uses optional `MusicSourceSearchPagingProvider` pages with opaque cursors, so local offsets, Radio Browser/Jellyfin/Subsonic offsets, Internet Archive page numbers, and future server tokens share one UI contract. It concurrently advances successful providers, retains failed cursors and prior rows for retry, deduplicates/re-ranks the combined set, and drops non-progressing cursors. Its optional `MusicSourceSearchSuggestionProvider` fan-out is capability-gated, bounded, failure-isolated, and invoked only after the Sources UI debounce; offline mode does not call it. Jellyfin maps that extension to its documented `Search/Hints` endpoint and returns neutral artist/album/track query values. `MusicCatalogProvider` gives Jellyfin and Navidrome/Subsonic one neutral artist/album/playlist collection model, detail contract, and authenticated artwork byte boundary, so responsive UI contains no protocol-specific JSON, endpoints, or credentials. Its optional `MusicCatalogPagingProvider` extension carries explicit continuation offsets, optional totals, and per-kind support; the self-hosted browser retains earlier pages across a failed continuation, retries the same offset, rejects non-progressing pages, resets on refresh, and preserves one-shot fallback for providers or kinds without paging. `MusicCatalogDiscoveryProvider` separately exposes documented server-ordered album list kinds; the Home coordinator queries each shelf independently after explicit refresh, deduplicates and bounds results, retains playlists, and falls back to generic albums/playlists for providers without the extension. `MusicCatalogRadioProvider` declares track, artist, and album seed support for documented Instant Mix or similar-song endpoints that return playable tracks; the shared UI keeps a selected track first, deduplicates returned metadata, and routes the queue through normal runtime stream resolution. The separate `MusicPlaylistMutationProvider` contract adds create, rename, delete, append, and ordered replacement only for adapters that declare `playlistMutation`; the shared UI derives move/remove operations from ordered provider track IDs and refreshes only after a guarded write succeeds. `Track.providerArtworkId` and `providerArtworkVersion` persist only safe provider identifiers. The adapter's binary loader enforces image MIME, non-empty content, and a 10 MiB limit before a 128-entry store cache feeds `TrackArtwork`; cache entries are invalidated on account edits, rotation, or removal. Jellyfin artwork authenticates through a private header, while Subsonic requests use per-request salted tokens instead of reversible password encoding. At playback resolution, `ProviderArtworkFileCache` atomically writes validated bytes to format-aware hashed paths under the private temporary directory, prunes stale partial files, and enforces 256-file/100-MiB bounds so `audio_service` can publish a credential-free local `artUri`. Provider rotation/removal deletes only that provider's private directory. Search, browse, and radio tracks remain metadata-only. `PlayerController` resolves authenticated stream URLs and private artwork immediately before native queue loading and marks both ephemeral, so queue snapshots, library JSON, and backups cannot retain them. After rotation it stops any loaded queue, removes old ephemeral URIs, re-resolves provider tracks, and restores the active position/play state when possible; failed tracks remain metadata-only and stopped. Errors redact raw, URI-encoded, hex, and token query values, while offline mode prevents catalog, radio, and suggestion requests at the screen boundary.

## Playback

`PlayerStateStore` uses `FileLibraryStorage` under the application-support
`player` directory, independently of library snapshots. Its revision serializes
active/named queues and playback settings at one commit boundary. Legacy
migration reads the actual preference backend without resetting the shared
singleton cache or deleting the original keys. A rejected write retains the
durable values and blocks later writes until explicit reload. The controller
rolls back failed changes, and the global recovery notice exposes reload or
confirmed previous-snapshot recovery. Recovery archives current bytes and never
autoplays. File flush/rename and process-interruption evidence do not establish
directory-metadata durability during physical power loss.

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
- optional Android device-band equalizer profiles and custom gains
- optional Android loudness enhancement, independently persisted from ReplayGain
- sleep timer with optional fade-out
- Android media notification and headset controls
- iOS/macOS Control Center and lock-screen controls
- Android/iOS background music audio-session configuration

`AudioEffectsPlaybackAudioEngine` is an optional capability rather than part
of the universal playback contract. The Android factory creates separate
`AndroidEqualizer` and `AndroidLoudnessEnhancer` instances for the primary and
crossfade `AudioPlayer` pipelines because one effect instance cannot be shared
between players. Presets are logarithmically interpolated by frequency and
clamped to the gain range reported by the current device, so a persisted curve
does not assume a fixed number of bands. Settings can be queued before a source
activates; actual bands become available after activation and the same profile
is serialized across both players. `SystemMediaPlaybackEngine` forwards this
capability without advertising it on unsupported backends.

The same wrapper configuration step sets Android API 23 plus disabled auto
backup for encrypted storage, creates iOS/macOS Keychain entitlements, and is
verified by Flutter tests. Linux CI/release jobs install libsecret; Windows
release builders require the Visual C++ ATL component used by the plugin.

## Persistence

`LibraryStore` persists its 36 library/settings sections through `LibraryStorage`.
The native `FileLibraryStorage` backend writes one versioned JSON envelope with
a SHA-256 payload checksum into the application-support `library` directory.
The backend lives in `file_library_storage.dart`; the Flutter-only directory
adapter and exported API remain in `library_storage.dart`.
Pending bytes are flushed before replacement; a previous snapshot remains for
explicit recovery. Legacy `shared_preferences` library values are imported on
first load and retained unchanged rather than deleted during migration.

Within an isolate, saves are queued in call order. A SQLite exclusive transaction
coordinates access to snapshot files across isolates/processes, and expected
revision checks reject stale writers. SQLite is the lock mechanism, not the
transactional store for the JSON payload. `_save` captures each intended state;
a rejected write rolls memory back to the last committed snapshot, invalidates
dependent queued changes, and exposes a reload notice. Corrupt or unreadable
startup data produces recovery UI with retry, raw-data export, previous-snapshot
restore, import, and confirmed reset instead of silently discarding the library.

The destructive-reset dialog has a scrollable title/body so increased text size
does not displace its confirmation controls. Save failures use an independently
scrollable notice capped at half the available height, preserving the current
page below it. The error is a semantics live region. Widget layout, tap-target,
and semantics assertions do not replace installed assistive-technology testing.

Snapshots are bounded at 64 MiB, but this is not a measured large-library
performance envelope. Native Windows/Linux probes now exercise real process
termination, cross-process locking, and a 25,000-track serialized snapshot.
Linux additionally exercises real SQLite/file-write exhaustion in an isolated
8 MiB tmpfs as an unprivileged user, preserving committed data and successfully
retrying after space is freed. This is bounded filesystem exhaustion, not a
physical disk failure or power-loss simulation. Directory-metadata durability,
other filesystems/platforms, and installed migrations still need acceptance.
Cache media and the library index are separate commits; failed index writes may
leave orphaned private media, which is counted and explicitly reclaimable.

Widget tests use an explicit test-only preferences fixture because fake-async
frames do not drive native file I/O. Dedicated durability tests instantiate the
production file backend, including cross-isolate contention. Test-fixture
success must not be treated as evidence of physical storage durability. The
[native probe](../scripts/ci/library_storage_probe/README.md) imports that same
backend and requires its package versions/checksums to match the client lockfile.

Self-hosted account metadata remains in preferences, but provider API keys and
passwords use `flutter_secure_storage` through `ProviderCredentialVault` and are
excluded from library snapshots and portable JSON backups. This separate vault
boundary remains unchanged by the library migration.

### Offline cache coordination

`OfflineCacheQueueWorker.stop()` cancels the active transfer and stops the batch
before the next entry. The pass still awaits pending provider resolution because
the resolver can write artwork files before returning. A late result cannot
start materialization. This does not cancel a provider's underlying HTTP operation
unless that provider supports it. The owning foreground widget awaits the pass
before requeuing processing entries and asking the native scheduler to take over.
Paused foreground timers/rebuilds neither process work nor repeatedly replace
the scheduled native job. Resident desktop tray windows retain in-process work.

Lifecycle transitions and scheduler calls are ordered so a late schedule cannot
win over a newer resume/cancel request. Returning from a mobile pause waits for
the scheduler cancellation call and reloads the saved library before starting
another pass. On Android/iOS, cancellation requires a boolean `true` reply;
false, missing, null, and timed-out replies fail closed. The Dart background
session installs its stop handler before announcing readiness. A stop reply waits
for the current work and its `finally` cleanup, including attempted durable
requeue, to settle. This acknowledges quiescence, not successful persistence:
storage errors still require reload/recovery and snapshot conflicts still reject
concurrent changes.

The generated Android/iOS shutdown gate waits for readiness before requesting
stop, coalesces cancellation callers, and acknowledges only after graceful engine
cleanup. Its ten-second deadline returns false without treating a live engine as
stopped; the Dart caller also has a twelve-second timeout. OS-forced termination
and failed native cleanup return false to pending cancellation callers. Engine
identity and Android job-generation checks reject stale callbacks. Foreground
return prevents automatic rescheduling until a later explicit schedule request.

Android disables constructor auto-registration and registers plugins once after
the service owns the engine and cleanup gate. iOS must successfully run the
engine before registering plugins and installing channel handlers; startup
failure terminates through the same gate. Kotlin/Swift helper execution and
generated-source checks cover these contracts, but do not prove actual OS
scheduling, Flutter engine termination, or plugin resource cleanup. Installed
Android/iOS background-start, expiration, and rapid foreground-return acceptance
remain required.

Storage/platform errors are reported through Flutter diagnostics and suspend
that foreground coordinator until a lifecycle reconciliation; rebuilds do not
retry them in a loop. A failed library save is not hidden behind a second
failed attempt to mark the entry failed. Reload is required before more library
mutations. Real-file/loopback-HTTP tests cover partial-transfer cancellation,
lock release, `Range`/`If-Range` resumption, provider SHA-256 verification, and a
stale foreground writer rejected after another store commits the cached index.
Those store objects share a test process; this is not a native background-engine
or physical storage-failure test.

### Diagnostic storage

`LocalDiagnosticLog` is best-effort support telemetry retained only on the
device, separate from the durable library backend. Its v2 envelope stores
allowlisted error categories, constant descriptions, numeric codes, timestamps,
and up to 12 validated `package:`/`dart:` frame locations per event. Flutter's
`StackFrame` parser supplies the locations; raw frames, symbols, messages,
URLs, file paths, and platform details are not serialized. Unknown formats are
omitted. Forty events and a 262,144-character input bound limit retained data
and parsing; these are not promises of native crash symbolication. At most 40
capture operations may be pending. Excess events are dropped before parsing
their stacks, and a bounded `discardedReports` counter makes that loss explicit
in the saved/exported document.

Load, capture, and clear operations are serialized within the logger. Errors in
diagnostic persistence do not escape back into global error capture. Writes and
removals are checked and reloaded before reporting success. The logger removes
legacy v1 reports without reading their free-form payloads and revalidates v2
records before displaying or exporting them. A failed cleanup is visible and
retryable even with an empty in-memory log. Preferences remain best-effort; this
does not establish secure erasure of OS backups or previously exported files.
The library and credential vaults are unaffected.

## Server

`services/server` is a Dart package with a Shelf-compatible request handler. It exposes:

- `GET /health`
- `GET /ready`
- `GET /api/v1/info`
- `GET /api/v1/metrics` (aggregate process state only)
- `GET /api/v1/tracks`
- `GET /api/v1/auth/profile`
- `PATCH /api/v1/auth/profile`
- `GET /api/v1/admin/sync-accounts`
- `POST /api/v1/admin/sync-tokens`
- `DELETE /api/v1/admin/sync-tokens`
- `GET /api/v1/sync/library`
- `PUT /api/v1/sync/library`
- `DELETE /api/v1/sync/library`

The executable combines optional static credentials from
`AETHERTUNE_SYNC_USERS` with a durable managed account registry under
`AETHERTUNE_DATA_DIR/authentication`. Static configuration accepts one token,
a token list, or named device tokens per account. The operations-authenticated
managed API issues 256-bit random bearer tokens once, persists only SHA-256
digests, supports several independently revocable devices on one account, and
atomically rotates a selected token. The profile endpoint returns only the
authenticated account and current non-secret device metadata. Managed
responses explicitly advertise profile editing; authenticated `PATCH` updates
the shared display name, only that token's device label, an optional fixed-tone
initials avatar, and independent public audiences for the name and avatar
through the same copy-persist-publish transaction.
The avatar permits only six named tones or `null`, never image bytes, URLs,
paths, or arbitrary profile content, and it is returned only to the
authenticated account or operations-authorized metadata. The transaction
preserves identifiers, creation times, and token hashes while rejecting
duplicate active device names. Public
registration, password/OAuth login, and automatic client token renewal remain
roadmap work.

The server keeps only the latest checksum-verified portable snapshot per
account under `AETHERTUNE_DATA_DIR`, enforces an optimistic base revision, and
rejects local paths and device cache jobs. Separate tokens issued for the same
account resolve to that same snapshot owner.

During client **Test and save**, the Flutter sync gateway first verifies the
snapshot endpoint and then requests the authenticated profile capability. A
`404` keeps older servers compatible; a supported response must pass bounded
account/device validation before the non-secret profile is persisted beside
sync metadata. The bearer token remains only in the platform credential vault.
Options presents the account/device identity and can refresh it independently.
When the server advertises editing, the shared Flutter UI can rename the
account and current device; the validated response must retain the same account
and token IDs before it replaces persisted profile metadata and local upload
attribution. Missing capability fields default to false for older servers.
Failed vault or metadata writes restore the previous account, profile, and
token state.

Operators set a distinct `AETHERTUNE_OPS_TOKEN`, in raw or `sha256:` form, to
protect aggregate metrics and all managed credential mutations with
constant-time bearer verification. Managed administration fails closed when
operations authentication is absent. Docker and native deployment templates
supply this token separately from sync users. Structured request logs normalize
the new routes and never include account IDs, request bodies, authorization
headers, or tokens.

The server is intentionally small, but it is real code with tests and CI coverage. Future server work should add opt-in public registration or external identity integration, automatic merge/background sync, remote library metadata, and provider coordination without weakening the client-first privacy model.

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
