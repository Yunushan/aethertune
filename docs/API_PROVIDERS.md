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

Each adapter must expose `capabilities` and `disclosure` before it can be trusted by UI, cache, sync, or download code. These fields are user-visible in the Sources tab.

Use capabilities to describe what the adapter can do, such as search, playback, playlists, lyrics, offline cache, downloads, subscriptions, recommendations, or authentication.

Use `ProviderPrivacyDisclosure` to list:

- contacted domains
- data sent to those domains
- whether credentials are required
- whether local files are read
- whether media is cached
- whether downloads are allowed

## Podcast RSS foundation

`PodcastRssProvider` parses RSS channels and audio enclosures into provider-neutral `Track` objects, exposes the feed host in `ProviderPrivacyDisclosure`, and resolves enclosure URLs for playback. The Sources tab can add/remove persisted feed subscriptions, import/export OPML, load episodes, play them, save them to the local library, and include subscriptions in backups. Episode progress, refresh policy, and offline cache are still separate roadmap work.

## Radio Browser foundation

`RadioBrowserProvider` searches the open Radio Browser station API, maps station JSON to provider-neutral `Track` objects, exposes the selected API mirror in `ProviderPrivacyDisclosure`, and resolves public stream URLs for playback. The Sources tab can search, play, and save stations. Mirror discovery, station click accounting, richer browse filters, stream validation, and cache policy are still separate roadmap work.

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
