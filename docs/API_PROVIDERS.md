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
5. Declare whether it reads local files, stores credentials, caches media, or supports downloads.
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
- whether media is cached
- whether downloads are allowed

## Unified provider search

`ProviderSearchCoordinator` fans out a search query to adapters that declare `metadataSearch`, skips non-search providers, ranks mixed `Track` results by playable status and metadata match quality, limits each provider contribution, resolves metadata-only results through `resolveStream` when the adapter supports it, and returns provider-specific failures without dropping successful results. The Sources tab exposes this as provider search across the demo provider, Radio Browser, and Internet Archive. Pagination, authenticated provider opt-in, local-library merging, and richer provider-specific ranking are still roadmap work.

## Offline cache and download policy

`OfflineMediaPolicy` is the shared gate for cache and download queue actions. It allows local files because they are already offline, allows provider tracks only when the adapter declares the matching `offlineCache` or `downloads` capability and matching disclosure flag, and denies provider tracks when the adapter is unknown, not permitted, not disclosed, or cannot resolve a playable stream. `OfflineCacheManager` then materializes approved direct HTTP(S) media URLs into private app storage, measures private cache usage, evicts only files under AetherTune's private offline-media directory, and updates the queue entry/local library track with a local path or a queueable evicted state. Podcast RSS enclosures and Internet Archive public files declare cache/download support; Radio Browser live streams do not.

## Podcast RSS foundation

`PodcastRssProvider` parses RSS channels and audio enclosures into provider-neutral `Track` objects, exposes the feed host in `ProviderPrivacyDisclosure`, declares cache/download permission for legal feed enclosures, and resolves enclosure URLs for playback. The Sources tab can add/remove persisted feed subscriptions, import/export OPML, load episodes, track refresh status and stale feeds, play them, resume saved episode progress, save them to the local library, queue/cache direct enclosure URLs, trim/clear private cached media from Options, and include subscriptions, refresh state, progress, and queued offline requests in backups. Background/resumable downloads and configurable cache policy are still separate roadmap work.

## Radio Browser foundation

`RadioBrowserProvider` discovers a public Radio Browser API mirror with fallback to the bundled default, searches the open Radio Browser station API, maps station JSON to provider-neutral `Track` objects, exposes the mirror and directory lookup domains in `ProviderPrivacyDisclosure`, resolves public stream URLs for playback, validates selected station stream reachability/content type, and sends Radio Browser station click accounting on playback. The Sources tab can search, filter by country, language, tag, codec, and bitrate, validate streams, play stations, and save stations. Radio Browser intentionally does not declare cache/download support for live streams; deeper codec probing and retry/backoff policy are still separate roadmap work.

## Internet Archive foundation

`InternetArchiveProvider` searches the public Internet Archive audio catalog, applies keyword, collection, subject, creator, and year filters through supported search query fields, reads item metadata, expands every playable audio file on an item into provider-neutral `Track` results, declares cache/download permission for public files, and resolves the stable `/download/{identifier}/{filename}` URL for playback. The Sources tab can search/filter public archive audio, play results, save tracks, queue/cache direct public files, and trim/clear private cached media from Options. Collection browsing pages, facet suggestion UI, resumable downloads, and configurable cache policy are still separate roadmap work.

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
