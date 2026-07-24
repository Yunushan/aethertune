# Provider Adapter Guide

AetherTune supports source adapters through `MusicSourceProvider`.

## Provider SDK v1

Use the versioned public SDK entry point instead of importing `src/` files:

```dart
import 'package:aethertune/aethertune_provider_sdk.dart';
```

`aetherTuneProviderSdkVersion` is currently `1.0.0`. SDK v1 guarantees the
provider, catalog, discovery, radio, playlist-mutation, paging, suggestion,
privacy-disclosure, and neutral `Track` contracts exported from that entry
point. Additive capabilities can arrive in later minor versions; breaking
changes require a new major version.

Run `validateMusicSourceProviderContract(provider)` in an adapter's test
suite before registration. It verifies stable source IDs, required metadata,
network/data disclosures, credential and offline capability pairing, and the
type-ahead extension contract without issuing any network request.

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

`ProviderSearchCoordinator` fans out a search query to adapters that declare `metadataSearch`, skips non-search providers, ranks mixed `Track` results by playable status and typo-tolerant metadata match quality, resolves metadata-only results through `resolveStream` when the adapter supports it, and returns provider-specific failures without dropping successful results. `MusicSourceSearchPagingProvider` optionally returns a bounded `MusicSourceSearchPage` with an opaque next cursor and optional provider total, so offsets, page numbers, and future server tokens remain adapter-owned. Local Library and Demo slice deterministic in-memory matches; Audius, Jamendo, and Radio Browser map documented `offset`/`limit`; Internet Archive maps `page`/`rows`; Jellyfin maps `StartIndex`/`Limit` with `TotalRecordCount`; and Subsonic `search3` maps `songOffset`/`songCount`.

The Sources tab appends pages only after **Load more provider results**, deduplicates by provider plus track ID, re-ranks the complete retained set, and stops a provider that returns the same cursor. Continuation runs concurrently per provider: successful providers advance even when another fails, while prior rows and each failed provider's original cursor remain available through **Retry failed providers**. A new query or credential change invalidates stale responses. When offline mode is enabled, unified search constructs only the local-library adapter and can page those local results without contacting a network provider; turning offline mode on during an online search disables its continuation. Providers without the optional paging extension retain the bounded one-shot fallback. Richer provider-specific ranking and search facets remain roadmap work.

## Credential handling

`SelfHostedProviderStore` persists non-secret account metadata separately from `ProviderCredentialVault`. The production vault uses `flutter_secure_storage`; Android uses its configured encrypted storage with backup disabled, Apple wrappers declare Keychain entitlements, Linux builds include libsecret, and Windows uses the platform plugin backend. Sources requires HTTPS unless the user explicitly accepts an insecure-HTTP warning. The account editor never receives the saved secret. The dedicated rotation flow requires confirmation, tests the replacement credential before writing, rolls the vault back if its write fails, and redacts both old and replacement values from failures. Connection and media errors also redact raw, URI-encoded, legacy hex-encoded, and salted-token query credentials.

Authenticated providers return metadata-only `Track` objects from search and catalog browsing. Safe artwork IDs and cache tags may persist, but authenticated artwork URLs never do; the adapter returns validated bytes to a bounded memory cache. Immediately before playback, `ProviderArtworkFileCache` atomically copies those bytes to a format-aware, hashed path under AetherTune's private temporary directory for notification, lock-screen, and Control Center metadata. The cache removes stale partial files, caps itself at 256 files and 100 MiB, and deletes a provider directory when its account is removed. The resulting `file:` URI and credential-bearing stream URL are runtime-only: `Track.toJson` omits both from queue/library/backup serialization. On restart, metadata-only queue entries, streams, and artwork are resolved again from the vault. Successful static-credential rotation invalidates memory requests and the provider's private artwork files, strips previous ephemeral media URIs from queued tracks, stops the loaded native queue before replacement, and re-resolves it with the new provider instance while preserving position/play state when possible. Resolver failures leave only metadata and stopped playback. Removing an account also deletes its secret, artwork caches, and queued provider tracks. Spotify metadata search supports its own PKCE refresh flow below; cross-device credential sync is intentionally not implemented.

`MusicPlaylistMutationProvider` is separate from read-only `MusicCatalogProvider`, and adapters must also declare the `playlistMutation` capability before write controls appear. The neutral contract supports create, rename, delete, append, and ordered track replacement. Sources exposes create/rename/delete on the Playlists tab, add-to-remote-playlist from album track menus, and move/remove actions inside a playlist. Offline mode hides the network-backed catalog entirely; mutations use the same guarded/redacted credential path as reads, refresh after success, preserve the current view on failure, and never persist credentials in playlist state. Portable cross-device library snapshots can carry local playlists and safe metadata, but never provider credentials or remote provider playlist state.

`MusicCatalogDiscoveryProvider` is an optional extension for documented, server-ordered album lists. It exposes only the kinds an adapter supports and loads one bounded shelf at a time so `ProviderHomeFeedCoordinator` can deduplicate results and isolate failures per shelf. Jellyfin implements recently added albums through `/Items/Latest`; Subsonic-compatible adapters map recently added, favorite, frequently played, recently played, and random shelves to `getAlbumList2.view` types `newest`, `starred`, `frequent`, `recent`, and `random`. The Home coordinator keeps provider playlists beside these shelves and falls back to generic albums/playlists for catalog providers without the extension. Discovery runs only after the user presses refresh, remains disabled offline, and is deliberately distinct from the `recommendations` capability because these server orderings are not necessarily personalized.

`MusicCatalogPagingProvider` is an optional extension for catalog kinds with documented offset support. `MusicCatalogCollectionPage` carries the returned neutral collections, an explicit next offset, `hasMore`, and an optional server total. The self-hosted browser requests a bounded first page, appends and deduplicates only after the user chooses **Load more**, retains all prior rows and the same offset after a failed continuation, stops on empty or non-progressing pages, and resets continuation state on pull-to-refresh. Catalog providers without this extension keep the original one-shot behavior. Offline mode prevents both initial and continuation requests.

`MusicCatalogRadioProvider` is an optional extension for adapters with a documented radio, instant-mix, or similar-songs endpoint that returns playable tracks. It declares support independently for track, artist, and album seed IDs and returns metadata-only `Track` results in server order. The adapter must also declare the `recommendations` capability before self-hosted radio controls appear. Artist and album pages expose **Start radio**; eligible track menus expose the same action, keep the chosen track first, deduplicate provider results, and resolve streams only through `PlayerController` immediately before playback. Requests are bounded, disabled offline, and guarded by the same credential-redaction path as other provider reads. Empty results and failures preserve the current catalog and queue.

## Offline cache and download policy

`OfflineMediaPolicy` is the shared gate for cache and download queue actions. It allows local files because they are already offline, allows provider tracks only when the adapter declares the matching `offlineCache` or `downloads` capability and matching disclosure flag, and denies provider tracks when the adapter is unknown, not permitted, not disclosed, or cannot resolve a playable stream. Approved queue entries can be paused/resumed before processing. `OfflineCacheManager` then materializes approved direct HTTP(S) media URLs into private app storage, verifies the written bytes with a cache checksum, can export verified private cached files to a user-chosen folder, measures private cache usage, evicts only files under AetherTune's private offline-media directory to persisted app-level and provider-level cache limits when the user trims it or when new cache writes exceed those limits, and updates the queue entry/local library track with a local path, cached byte count, cached checksum, or a queueable evicted state. Podcast RSS enclosures and Internet Archive public files declare cache/download support; Radio Browser live streams do not.

## Podcast RSS foundation

`PodcastRssProvider` parses RSS channels and audio enclosures into provider-neutral `Track` objects, exposes the feed host in `ProviderPrivacyDisclosure`, declares cache/download permission for legal feed enclosures, and resolves enclosure URLs for playback. The Sources tab can add/remove persisted feed subscriptions, import/export OPML, load episodes, track refresh status and stale feeds, play them, resume saved episode progress, save them to the local library, queue/cache direct enclosure URLs with checksum-verified private writes and HTTP Range retry resume, trim/clear/quota-limit private cached media from Options, and include subscriptions, refresh state, progress, and queued offline requests in backups. Background download jobs are still separate roadmap work.

## Radio Browser foundation

`RadioBrowserProvider` discovers a public Radio Browser API mirror with fallback to the bundled default, searches the open Radio Browser station API, maps station JSON to provider-neutral `Track` objects, exposes the mirror and directory lookup domains in `ProviderPrivacyDisclosure`, resolves public stream URLs for playback, validates selected station stream reachability/content type, and sends Radio Browser station click accounting on playback. Its bounded validation read identifies Ogg, Opus, Vorbis, FLAC, WAV, MP4/AAC, AAC-LATM, MP3, WebM/Matroska, and MPEG-TS signatures without retaining media. Its dedicated search and unified provider search both page with the documented result `offset` and bounded `limit`. Mirror discovery and station-search requests retry only transient HTTP/socket/TLS/timeout errors after 250 ms and 750 ms; malformed data fails immediately. Station click accounting remains intentionally single-shot so retries cannot over-report plays. The Sources tab can search, filter by country, language, tag, codec, and bitrate, validate streams, play stations, and save stations. Radio Browser intentionally does not declare cache/download support for live streams; decoder-level validation remains roadmap work.

## Internet Archive foundation

`InternetArchiveProvider` searches the public Internet Archive audio catalog, applies keyword, collection, subject, creator, and year filters through supported search query fields, reads item metadata, expands every playable audio file on an item into provider-neutral `Track` results, returns collection/subject/creator/year facets for dedicated Archive searches, declares cache/download permission for public files, and resolves the stable `/download/{identifier}/{filename}` URL for playback. Valid file `md5` or `sha1` metadata is preserved as an algorithm-prefixed expected digest and must match the completed private cache file; mismatches are removed rather than retained. Dedicated and unified search map opaque continuation to bounded Advanced Search `page`/`rows` requests and use `numFound` for exhaustion. The Sources tab can search/filter public archive audio, apply returned facet chips, play results, save tracks, queue/cache checksum-verified direct public files with HTTP Range retry resume, and quota-limit/trim/clear private cached media from Options. Dedicated collection detail pages and background download jobs are still separate roadmap work.

## Audius open music source

`AudiusProvider` calls the documented read-only tracks search endpoint with bounded `query`, `offset`, and `limit` parameters, plus public trending-track, trending-playlist, user-search, and playlist-search endpoints. Its Artists/Albums/Playlists browser maps `is_album` collections from the bounded server order, while an explicit submitted search query selects the documented user or playlist endpoint; it rejects private/unlisted/invalid collections, deactivated users, and malformed/duplicate records. A selected artist uses the documented user-tracks endpoint, while albums/playlists use collection-tracks; each detail fetches at most the first 100 records before applying the same public non-gated/non-unlisted track policy. It rejects non-HTTPS or credential-bearing artwork; every retained track resolves only through the documented Audius stream endpoint at playback time. The source declares search, type-ahead, public collection browsing, artwork, stream resolution, and direct playback, but no credential, cache, download, account, or mutation capability. Sources displays its disclosure and public Artists/Albums/Playlists action; Home offers a user-triggered six-track trending shelf and the same collection browser. Offline mode omits the source before any request is made.

## Jamendo official music source

`JamendoProvider` uses a client ID supplied by the listener from their own Jamendo developer application. It calls the documented tracks endpoint with bounded `search`, `offset`, and `limit` parameters, maps only valid public track records to neutral `Track` objects, and accepts only credential-free HTTPS artwork and stream URLs. Configured users can also open a public **Artists** and **Albums** browser: it requests the documented artist/album endpoints with bounded `offset`/`limit`, `fullcount=true`, popular server ordering, and a submitted-only `namesearch` query, then opens the documented nested artist-track or album-track endpoint with a bounded 100-track detail load. The browser sends no query while text is merely typed and retains visible rows during pagination failures. It can fall back to Jamendo's documented stream redirect for a numeric Jamendo track ID. The client ID remains in `ProviderCredentialVault` and is excluded from preferences, backups, sync, and persisted tracks. The adapter declares direct playback but deliberately declares neither offline cache nor downloads, because Jamendo download authorization is per track and the shared policy is provider-wide. Sources exposes setup/removal, catalog browsing, type-ahead, continuation, disclosure, and offline-mode request denial. Official references: [artists](https://developer.jamendo.com/v3.0/artists), [albums](https://developer.jamendo.com/v3.0/albums), [artist tracks](https://developer.jamendo.com/v3.0/artists/tracks), and [album tracks](https://developer.jamendo.com/v3.0/albums/tracks).

On Android 5+, eligible automatic Podcast RSS and Internet Archive cache work
can continue through the app-owned, network-constrained JobScheduler service
after the app backgrounds. It schedules the next due RSS deadline, retries a
failed feed after one hour, and keeps cache retries resumable and private-cache-
only; iOS and desktop schedulers remain roadmap work.

## YouTube Data API metadata source

`YouTubeDataMetadataProvider` is an optional, metadata-only adapter for the documented YouTube Data API `search.list` endpoint. Sources accepts a user-owned, app-restricted Google Cloud API key and stores it only through `ProviderCredentialVault`; the key is excluded from regular preferences, queues, backups, and sync documents. Search sends the query and configured key to `www.googleapis.com`, returns neutral video title/channel metadata plus HTTPS thumbnail artwork, and supports the API's opaque `nextPageToken` continuation. Submitted searches also make one bounded `videos.list` request containing only the selected public video IDs to enrich duration metadata; type-ahead never makes that detail request. The adapter declares only `metadataSearch`, `searchSuggestions`, and `artwork`, returns no stream URI, and never declares playback, offline cache, downloads, authentication, playlists, or account access. The UI states these boundaries and displays the YouTube Terms URL during setup. It must not be treated as a YouTube Music or OuterTune playback provider.

Official references: [YouTube Data API search.list](https://developers.google.com/youtube/v3/docs/search/list), [YouTube Data API videos.list](https://developers.google.com/youtube/v3/docs/videos/list), [YouTube Data API reference](https://developers.google.com/youtube/v3/docs), and [YouTube Developer Policies](https://developers.google.com/youtube/terms/developer-policies).

## Spotify Web API metadata source

`SpotifyMetadataProvider` is an optional official Spotify Web API adapter for
track metadata and HTTPS artwork only. A user supplies the client ID for their
own Spotify developer app. Sources launches Spotify's Authorization Code with
PKCE flow in the system browser, listens once on an ephemeral IPv4 loopback
callback, validates the returned state, and exchanges the code without a
client secret. The app's client ID, access token, refresh token, and expiry
record are stored only through `ProviderCredentialVault`; access tokens refresh
before a search when needed, and Disconnect deletes the whole record.

The provider sends search queries and OAuth bearer tokens only to
`api.spotify.com`, lists `accounts.spotify.com` and `api.spotify.com` in its
disclosure, and returns neutral metadata-only tracks. It uses bounded
`offset`/`limit` pagination for saved tracks, episodes, shows, albums, playlists, and the
documented new-release album catalog; users can
also browse their Spotify-reported recently played track metadata through the
documented `user-read-recently-played` scope and its bounded history cursor.
The documented `user-top-read` scope additionally powers explicitly opened
top-track and top-artist metadata views for Spotify's short-, medium-, and
long-term affinity windows. Top tracks can be saved as local metadata; top
artists can only update AetherTune's existing local artist-follow list and are
never treated as Spotify remote subscriptions. The documented
`user-follow-read` scope can also list followed artist metadata with bounded
cursor pagination; it never follows or unfollows artists on Spotify.
Saved episode rows retain episode title, show, publisher, duration, and artwork
as neutral metadata; saved shows can open their documented paged episode metadata.
Neither path exposes Spotify audio, previews, or a resume position.
Every page is user-triggered, disabled in offline mode, and can only save the
returned metadata into the local library. The provider declares metadata search,
artwork, and authentication only. It does not resolve a stream, play Spotify
audio, cache/download media, write Spotify data, or use undocumented endpoints.
The user must configure the loopback redirect allowed by Spotify for their
developer app before connecting.

Official references: [Spotify authorization overview](https://developer.spotify.com/documentation/web-api/concepts/authorization), [Authorization Code with PKCE](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow), [redirect URI rules](https://developer.spotify.com/documentation/web-api/concepts/redirect_uri), [Get User's Saved Episodes](https://developer.spotify.com/documentation/web-api/reference/get-users-saved-episodes), [Get User's Saved Shows](https://developer.spotify.com/documentation/web-api/reference/get-users-saved-shows), [Get Show Episodes](https://developer.spotify.com/documentation/web-api/reference/get-a-shows-episodes), [Get Recently Played Tracks](https://developer.spotify.com/documentation/web-api/reference/get-recently-played), [Get User's Top Items](https://developer.spotify.com/documentation/web-api/reference/get-users-top-artists-and-tracks), [Get Followed Artists](https://developer.spotify.com/documentation/web-api/reference/get-followed), and [Get New Releases](https://developer.spotify.com/documentation/web-api/reference/get-new-releases).

## LRCLIB lyrics foundation

`LrcLibLyricsProvider` implements the separate provider-neutral `LyricsProvider` contract against LRCLIB's documented, openly accessible `/api/search` endpoint. Search starts only from the lyrics editor, identifies AetherTune through the recommended User-Agent header, and discloses that track/artist/album-derived search terms are sent to `lrclib.net`. Results are parsed defensively, deduplicated, and ranked locally using title, artist, album, duration, and synced/plain availability. AetherTune stores only a result the user selects, together with LRCLIB's provider name, record ID, and source URI; manual edits clear that attribution. Offline mode disables the request. The API is documented as beta, currently returns at most 20 records, and has no pagination, API key, or registration requirement. AetherTune does not publish lyrics or bundle LRCLIB database content.

## Jellyfin foundation

`JellyfinProvider` targets user-owned Jellyfin servers. Sources creates, tests, edits, removes, browses, and atomically rotates API keys for account-backed instances. Audio search and all three catalog kinds page with bounded `StartIndex`/`Limit` requests and `EnableTotalRecordCount=true`; neutral parsers use response `StartIndex` and `TotalRecordCount` to determine continuation. The adapter uses `/Artists` for artists and `/Users/{userId}/Items` with `IncludeItemTypes=MusicAlbum` or `Playlist` for top-level collections. In the self-hosted catalog, an artist, album, or playlist query is sent only after the user explicitly submits it; the same bounded request and retained-result pagination apply. Explicit Home discovery uses `/Items/Latest` filtered to `MusicAlbum` with a bounded result limit. Artist drill-down filters albums with `ArtistIds`; album drill-down requests `Audio` items with `ParentId`; playlist tracks come from `/Playlists/{playlistId}/Items`. Radio uses Jellyfin's playable Instant Mix endpoints: `/Songs/{itemId}/InstantMix`, `/Artists/{itemId}/InstantMix`, and `/Albums/{itemId}/InstantMix`, each with the account user ID, bounded limit, genre metadata, and primary images. Remote writes use `POST /Playlists` to create, `POST /Playlists/{id}` to rename or replace ordered item IDs, `POST /Playlists/{id}/Items` to append, and `DELETE /Items/{id}` to delete a playlist. Track menus read the returned `UserData.IsFavorite` state and persist a favorite with `POST /Users/{userId}/FavoriteItems/{itemId}` or remove it with `DELETE` on the same endpoint. Responses map into provider-neutral collections and metadata-only tracks. Primary image IDs/tags are safe metadata; image bytes come from `/Items/{itemId}/Images/Primary` with the API key in `X-Emby-Token`, never in the image URI exposed to Flutter. The shared binary loader requires an image MIME type, rejects empty/over-10-MiB responses, and feeds a bounded memory cache used by browse rows, library tiles, the mini-player, and Now Playing. At playback time, validated bytes also feed the private local-file bridge used by notification, lock-screen, and Control Center metadata. Authenticated stream and local artwork URIs remain ephemeral. Portable library snapshots can retain safe saved metadata, but do not transfer the Jellyfin account, API key, or remote playlist state.

Official references: [Jellyfin latest-media API](https://api.jellyfin.org/#tag/UserLibrary/operation/GetLatestMedia), [Jellyfin item-query request fields](https://typescript-sdk.jellyfin.org/interfaces/generated-client.ItemsApiGetItemsRequest.html), [Jellyfin Instant Mix API](https://typescript-sdk.jellyfin.org/functions/generated-client.InstantMixApiFactory.html), [track Instant Mix request fields](https://typescript-sdk.jellyfin.org/interfaces/generated-client.InstantMixApiGetInstantMixFromSongRequest.html), [artist Instant Mix request fields](https://typescript-sdk.jellyfin.org/interfaces/generated-client.InstantMixApiGetInstantMixFromArtistsRequest.html), [Jellyfin playlist API](https://typescript-sdk.jellyfin.org/classes/generated-client.PlaylistsApi.html), [create-playlist body](https://typescript-sdk.jellyfin.org/interfaces/generated-client.CreatePlaylistDto.html), [update-playlist body](https://typescript-sdk.jellyfin.org/interfaces/generated-client.UpdatePlaylistDto.html), [playlist delete request](https://typescript-sdk.jellyfin.org/interfaces/generated-client.LibraryApiDeleteItemRequest.html), [Jellyfin artist-query request fields](https://typescript-sdk.jellyfin.org/interfaces/generated-client.ArtistsApiGetArtistsRequest.html), and [Jellyfin image request fields](https://typescript-sdk.jellyfin.org/interfaces/generated-client.ImageApiGetItemImage2Request.html).

## MusicBrainz metadata lookup

The metadata editor exposes an explicit **Find metadata** action backed by the
public MusicBrainz recording-search API. Before the first request, the sheet
states that it contacts `musicbrainz.org` with only the displayed title,
artist, and album; it does not upload audio, hashes, file paths, or silently
scan the library. The adapter identifies AetherTune with a meaningful
User-Agent, requests JSON over HTTPS, serializes requests at MusicBrainz's
documented one-request-per-second maximum, bounds results to 25, validates
recording MBIDs, and deduplicates candidates. A result fills the existing
editable fields only after a user selects it, leaving the final save and any
embedded-file tag write under the user's control. Offline mode disables the
action entirely.

## Navidrome/Subsonic foundation

`SubsonicProvider` targets user-owned Navidrome or Subsonic-compatible servers through the documented Subsonic REST API. Sources creates, tests through `ping.view`, edits, removes, browses, and atomically rotates passwords for account-backed instances. Song search pages through `search3.view` with bounded `songCount` and `songOffset`; a full page offers continuation because that response has no total. The adapter uses `getArtists.view`, `getAlbumList2.view`, and `getPlaylists.view` for top-level collections, then `getArtist.view`, `getAlbum.view`, and `getPlaylist.view` for drill-down. Alphabetical albums page through `getAlbumList2.view` with bounded `size` and `offset`; because that response has no total, a short or empty page ends continuation. The documented artists and playlists endpoints expose no offsets and remain complete one-shot lists. Explicit Home discovery calls `getAlbumList2.view` separately with `newest`, `frequent`, `recent`, and `random`, each with a bounded size and zero offset. Track and album radio call `getSimilarSongs.view`; artist radio uses the ID3-oriented `getSimilarSongs2.view`. Navidrome supports both endpoints when its Last.fm integration is configured and returns a guarded provider error otherwise. Remote writes use `createPlaylist.view` for creation and ordered replacement, `updatePlaylist.view` for rename/append, and `deletePlaylist.view` for deletion; repeated `songId` parameters preserve order and duplicates. Track menus read each song's optional `starred` state and use documented `star.view` or `unstar.view` with the song `id` to synchronize remote favorites. Each request generates a cryptographically random salt and sends `t=md5(password+salt)` plus `s`, avoiding the protocol's reversible `p=enc:` form; tokens are redacted from failures. Parsed `coverArt` IDs are safe metadata, while `getCoverArt.view` credential URLs remain inside the adapter and yield MIME/size-validated bytes for the bounded in-app memory cache and private system-media file bridge. Parsed songs stay metadata-only until `stream.view` resolution, and both stream and local artwork URIs remain ephemeral. Portable library snapshots can retain safe saved metadata, but do not transfer the Navidrome/Subsonic account, password, or remote playlist state.

Official references: [Subsonic API](https://subsonic.org/pages/api.jsp) and [Navidrome's documented Subsonic compatibility](https://www.navidrome.org/docs/developers/subsonic-api/).

### Remote favorite scope

Self-hosted track menus synchronize track favorites, while the Albums and Artists tabs read each server's favorite state and can add or remove a server favorite. Jellyfin uses the authenticated user favorite-item endpoint for all three item types. Navidrome/Subsonic uses `id` for tracks, `albumId` for ID3 albums, and `artistId` for ID3 artists in documented `star.view` and `unstar.view` requests. These server mutations remain separate from AetherTune's local-library favorites and artist-following signals.

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
# Declarative Custom Catalogs

Sources can register a user-owned JSON catalog without downloading or executing
provider code. A catalog declares its own JSON endpoint and any additional
hosts that may serve media or artwork. HTTPS is required by default; HTTP
requires the user's explicit local-network consent. Credentials and redirect
chains are not supported.

The catalog document is bounded to 2 MiB and 500 tracks:

```json
{
  "version": 1,
  "tracks": [
    {
      "id": "night-drive",
      "title": "Night Drive",
      "artist": "Open Artist",
      "album": "City Lights",
      "genre": "Electronic",
      "durationMs": 185000,
      "streamUrl": "https://declared-media.example/audio/night-drive.mp3",
      "artworkUrl": "https://declared-media.example/art/night-drive.jpg"
    }
  ]
}
```

Track IDs must be unique and every `streamUrl` or `artworkUrl` must be an
HTTP(S) URL on the catalog host or one of the additional user-declared hosts.
Invalid documents are rejected as a whole. The adapter performs metadata
search locally against the fetched catalog and returns its declared direct
stream URL only after rechecking the provider and host boundary.
