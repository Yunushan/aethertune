# Provider Adapter Guide

AetherTune supports source adapters through `MusicSourceProvider`.

## Good provider candidates

- Local files selected by the user.
- User-owned servers: Jellyfin, Navidrome, Subsonic-compatible servers.
- Podcast RSS feeds.
- Open radio catalogs.
- Public-domain/open-license archives.
- Official APIs with clear terms.

## Provider requirements

A provider must:

1. Be legal to use in the target countries.
2. Avoid DRM bypass and private API scraping.
3. Declare supported capabilities.
4. Clearly document network endpoints and data sent.
5. Declare whether it reads local files, stores credentials, caches metadata/media, or supports downloads.
6. Store tokens only through platform-secure storage.
7. Allow the user to remove credentials and cache.
8. Return provider-neutral `Track` objects.

## Capability and privacy disclosure

Each adapter must expose `capabilities` and `disclosure` before it can be trusted by UI, cache, sync, or download code. These fields are user-visible in the Sources tab and are enforced by `OfflineMediaPolicy` before cache/download features may act on a provider track.

Use capabilities to describe what the adapter can do, such as search, playback, playlists, lyrics, offline cache, downloads, subscriptions, recommendations, or authentication.

Use `ProviderPrivacyDisclosure` to list:

- contacted domains
- data sent to those domains
- whether credentials are required
- whether local files are read
- whether selected metadata is cached
- whether media is cached
- whether downloads are allowed

## Unified provider search

`ProviderSearchCoordinator` fans out a search query to adapters that declare `metadataSearch`, skips non-search providers, ranks mixed `Track` results by playable status and typo-tolerant metadata match quality, limits each provider contribution, resolves metadata-only results through `resolveStream` when the adapter supports it, and returns provider-specific failures without dropping successful results. The Sources tab exposes this as provider search across the local library, demo provider, Radio Browser, and Internet Archive. When offline mode is enabled, unified search uses the local library adapter only so it does not contact network providers. Pagination, authenticated provider opt-in, and richer provider-specific ranking are still roadmap work.

## Offline cache and download policy

`OfflineMediaPolicy` is the shared gate for cache and download queue actions. It allows local files because they are already offline, allows provider tracks only when the adapter declares the matching `offlineCache` or `downloads` capability and matching disclosure flag, and denies provider tracks when the adapter is unknown, not permitted, not disclosed, or cannot resolve a playable stream. Approved queue entries can be paused/resumed before processing. `OfflineCacheManager` then materializes approved direct HTTP(S) media URLs into private app storage, verifies the written bytes with a cache checksum, can export verified private cached files to a user-chosen folder, measures private cache usage, evicts only files under AetherTune's private offline-media directory to persisted app-level and provider-level cache limits when the user trims it or when new cache writes exceed those limits, and updates the queue entry/local library track with a local path, cached byte count, cached checksum, or a queueable evicted state. Podcast RSS enclosures and Internet Archive public files declare cache/download support; Radio Browser live streams do not.

## Podcast RSS foundation

`PodcastRssProvider` parses RSS channels and audio enclosures into provider-neutral `Track` objects, exposes the feed host in `ProviderPrivacyDisclosure`, declares cache/download permission for legal feed enclosures, and resolves enclosure URLs for playback. The Sources tab can add/remove persisted feed subscriptions, import/export OPML, load episodes, track refresh status and stale feeds, play them, resume saved episode progress, save them to the local library, queue/cache direct enclosure URLs with checksum-verified private writes and HTTP Range retry resume, trim/clear/quota-limit private cached media from Options, and include subscriptions, refresh state, progress, and queued offline requests in backups. Background download jobs are still separate roadmap work.

## Radio Browser foundation

`RadioBrowserProvider` discovers a public Radio Browser API mirror with fallback to the bundled default, searches the open Radio Browser station API, maps station JSON to provider-neutral `Track` objects, exposes the mirror and directory lookup domains in `ProviderPrivacyDisclosure`, resolves public stream URLs for playback, validates selected station stream reachability/content type, and sends Radio Browser station click accounting on playback. The Sources tab can search, filter by country, language, tag, codec, and bitrate, validate streams, play stations, and save stations. Radio Browser intentionally does not declare cache/download support for live streams; deeper codec probing and retry/backoff policy are still separate roadmap work.

## Internet Archive foundation

`InternetArchiveProvider` searches the public Internet Archive audio catalog, applies keyword, collection, subject, creator, and year filters through supported search query fields, reads item metadata, expands every playable audio file on an item into provider-neutral `Track` results, returns collection/subject/creator/year facets for dedicated Archive searches, declares cache/download permission for public files, and resolves the stable `/download/{identifier}/{filename}` URL for playback. The Sources tab can search/filter public archive audio, apply returned facet chips, play results, save tracks, queue/cache checksum-verified direct public files with HTTP Range retry resume, and quota-limit/trim/clear private cached media from Options. Dedicated collection detail pages and background download jobs are still separate roadmap work.

## LRCLIB lyrics foundation

`LrcLibLyricsProvider` implements the separate provider-neutral `LyricsProvider` contract against LRCLIB's documented, openly accessible `/api/search` endpoint. Search starts only from the lyrics editor, identifies AetherTune through the recommended User-Agent header, and discloses that track/artist/album-derived search terms are sent to `lrclib.net`. Results are parsed defensively, deduplicated, and ranked locally using title, artist, album, duration, and synced/plain availability. AetherTune stores only a result the user selects, together with LRCLIB's provider name, record ID, and source URI; manual edits clear that attribution. Offline mode disables the request. The API is documented as beta, currently returns at most 20 records, and has no pagination, API key, or registration requirement. AetherTune does not publish lyrics or bundle LRCLIB database content.

## Jellyfin foundation

`JellyfinProvider` targets user-owned Jellyfin servers. It builds API-key authenticated audio searches against a configured user's library, maps Jellyfin audio item metadata into provider-neutral `Track` objects, generates authenticated stream and primary artwork URLs when requested, discloses the configured server host and credential/search/item-id data sent, declares authentication/cache/download capabilities for user-owned media, and is covered by provider-specific tests plus the shared provider contract test. The provider is constructor-configured; settings UI, secure credential storage, library browse pages, playlists, and sync are still roadmap work.

## Navidrome/Subsonic foundation

`SubsonicProvider` targets user-owned Navidrome or Subsonic-compatible servers through the documented Subsonic REST API. It builds authenticated JSON requests with encoded password credentials, searches songs through `search3.view`, maps song metadata to provider-neutral `Track` objects, discloses the configured server host and credential/search/song-id data sent, declares authentication/cache/download capabilities for user-owned media, and resolves playable streams through `stream.view`. The provider is constructor-configured and tested; settings UI, secure credential storage, library browse pages, playlists, and sync are still roadmap work.

## Minimal provider

```dart
class MyProvider implements MusicSourceProvider {
  @override
  String get id => 'my-provider';

  @override
  String get name => 'My Provider';

  @override
  String get description => 'Legal source adapter.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure(
        networkDomains: <String>['api.example.com'],
        dataSent: <String>['search query'],
      );

  @override
  Future<List<Track>> search(String query) async {
    // Fetch metadata from a documented API or local source.
    return <Track>[];
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    // Return a playable URI only when allowed by the source.
    return null;
  }
}
```

## Providers not accepted in the core repo

- DRM bypass providers.
- Private paid-service API scrapers.
- Credential sharing or token theft.
- Ad-blocking modules designed specifically to violate a service's terms.
- Providers that hide network behavior from the user.
