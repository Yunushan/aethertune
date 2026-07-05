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
3. Clearly document network endpoints.
4. Store tokens only through platform-secure storage.
5. Allow the user to remove credentials and cache.
6. Return provider-neutral `Track` objects.

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
