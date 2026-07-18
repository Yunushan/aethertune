import 'package:aethertune/src/data/spotify_metadata_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses official Spotify track metadata without a playable URI', () {
    final page = parseSpotifySearchPage('''
      {
        "tracks": {
          "offset": 20,
          "total": 22,
          "items": [
            {
              "id": "spotify-track-id",
              "name": "Northern Light",
              "duration_ms": 215000,
              "artists": [{"name": "Aether"}, {"name": "Orbit"}],
              "album": {
                "name": "Signals",
                "images": [{"url": "https://i.scdn.co/image/cover"}]
              }
            }
          ]
        }
      }
    ''');

    expect(page.offset, 20);
    expect(page.total, 22);
    final track = page.tracks.single;
    expect(track.title, 'Northern Light');
    expect(track.artist, 'Aether, Orbit');
    expect(track.album, 'Signals');
    expect(track.duration, const Duration(milliseconds: 215000));
    expect(track.artworkUri, Uri.parse('https://i.scdn.co/image/cover'));
    expect(track.isPlayable, isFalse);
    expect(track.sourceId, 'spotify-metadata');
  });

  test('uses bounded search pagination and an OAuth bearer token', () async {
    Uri? requestUri;
    String? requestToken;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      searchLoader: (uri, token) async {
        requestUri = uri;
        requestToken = token;
        return '''
          {"tracks": {"offset": 50, "total": 51, "items": [
            {"id":"id", "name":"Track", "artists":[], "album":{}}
          ]}}
        ''';
      },
    );

    final page = await provider.searchPage('  synthetic  ', cursor: '50', limit: 100);

    expect(requestToken, 'access-token');
    expect(requestUri!.queryParameters['q'], 'synthetic');
    expect(requestUri!.queryParameters['type'], 'track');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(requestUri!.queryParameters['offset'], '50');
    expect(page.nextCursor, isNull);
    expect(
      provider.capabilities.contains(MusicSourceCapability.directPlayback),
      isFalse,
    );
    expect(await provider.resolveStream(page.tracks.single), isNull);
  });

  test('loads bounded saved-track metadata without a playable URI', () async {
    Uri? requestUri;
    String? requestToken;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      savedTracksLoader: (uri, token) async {
        requestUri = uri;
        requestToken = token;
        return '''
          {
            "offset": 2,
            "total": 4,
            "next": "https://api.spotify.com/v1/me/tracks?offset=3",
            "items": [{
              "added_at": "2026-07-17T12:00:00Z",
              "track": {
                "id": "saved-track-id",
                "name": "Saved Signal",
                "duration_ms": 201000,
                "artists": [{"name": "Aether"}],
                "album": {"name": "Archive"}
              }
            }]
          }
        ''';
      },
    );

    final page = await provider.loadSavedTracksPage(offset: 2, limit: 100);

    expect(requestToken, 'access-token');
    expect(requestUri!.path, '/v1/me/tracks');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(requestUri!.queryParameters['offset'], '2');
    expect(page.offset, 2);
    expect(page.total, 4);
    expect(page.hasMore, isTrue);
    final track = page.tracks.single;
    expect(track.title, 'Saved Signal');
    expect(track.addedAt, DateTime.utc(2026, 7, 17, 12));
    expect(track.isPlayable, isFalse);
    expect(await provider.resolveStream(track), isNull);
  });

  test('loads recently played metadata with an official history cursor',
      () async {
    Uri? requestUri;
    String? requestToken;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      recentlyPlayedLoader: (uri, token) async {
        requestUri = uri;
        requestToken = token;
        return '''
          {
            "cursors": {"before": "1763380800000"},
            "items": [{
              "played_at": "2026-07-17T12:00:00Z",
              "track": {
                "id": "history-track-id",
                "name": "History Signal",
                "duration_ms": 201000,
                "artists": [{"name": "Aether"}],
                "album": {"name": "Archive"}
              }
            }]
          }
        ''';
      },
    );

    final page = await provider.loadRecentlyPlayedPage(
      before: '1763380801000',
      limit: 100,
    );

    expect(requestToken, 'access-token');
    expect(requestUri!.path, '/v1/me/player/recently-played');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(requestUri!.queryParameters['before'], '1763380801000');
    expect(page.nextBefore, '1763380800000');
    expect(page.hasMore, isTrue);
    final item = page.items.single;
    expect(item.playedAt, DateTime.utc(2026, 7, 17, 12));
    expect(item.track.title, 'History Signal');
    expect(item.track.addedAt, item.playedAt);
    expect(item.track.isPlayable, isFalse);
    expect(await provider.resolveStream(item.track), isNull);
  });

  test('loads bounded official Spotify top-track metadata', () async {
    Uri? requestUri;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      topTracksLoader: (uri, token) async {
        requestUri = uri;
        expect(token, 'access-token');
        return '''
          {"offset": 0, "total": 1, "next": null, "items": [{
            "id": "top-track", "name": "Top Signal", "artists": [{"name": "Aether"}],
            "album": {"name": "Signals"}
          }]}
        ''';
      },
    );

    final page = await provider.loadTopTracksPage(limit: 100);

    expect(requestUri!.path, '/v1/me/top/tracks');
    expect(requestUri!.queryParameters['time_range'], 'medium_term');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(page.tracks.single.title, 'Top Signal');
    expect(page.tracks.single.isPlayable, isFalse);
  });

  test('ignores malformed recently played entries', () {
    final page = parseSpotifyRecentlyPlayedPage('''
      {
        "cursors": {"before": "next"},
        "items": [
          {"played_at": "not-a-date", "track": {"id": "bad", "name": "Bad"}},
          {"played_at": "2026-07-17T12:00:00Z", "track": null}
        ]
      }
    ''');

    expect(page.items, isEmpty);
    expect(page.nextBefore, 'next');
  });

  test('loads saved albums and album tracks as non-playable metadata',
      () async {
    Uri? albumsRequest;
    Uri? tracksRequest;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      savedAlbumsLoader: (uri, token) async {
        albumsRequest = uri;
        expect(token, 'access-token');
        return '''
          {
            "offset": 1,
            "total": 3,
            "next": "https://api.spotify.com/v1/me/albums?offset=2",
            "items": [{
              "added_at": "2026-07-17T12:00:00Z",
              "album": {
                "id": "album-id",
                "name": "Signal Archive",
                "total_tracks": 2,
                "artists": [{"name": "Aether"}],
                "images": [{"url": "https://i.scdn.co/image/album"}]
              }
            }]
          }
        ''';
      },
      albumTracksLoader: (uri, token) async {
        tracksRequest = uri;
        expect(token, 'access-token');
        return '''
          {
            "offset": 0,
            "total": 2,
            "next": "https://api.spotify.com/v1/albums/album-id/tracks?offset=1",
            "items": [{
              "id": "album-track-id",
              "name": "Album Signal",
              "duration_ms": 180000,
              "artists": [{"name": "Aether"}]
            }]
          }
        ''';
      },
    );

    final albums = await provider.loadSavedAlbumsPage(offset: 1, limit: 100);

    expect(albumsRequest!.path, '/v1/me/albums');
    expect(albumsRequest!.queryParameters['offset'], '1');
    expect(albumsRequest!.queryParameters['limit'], '50');
    expect(albums.offset, 1);
    expect(albums.total, 3);
    expect(albums.hasMore, isTrue);
    final album = albums.albums.single;
    expect(album.title, 'Signal Archive');
    expect(album.artist, 'Aether');
    expect(album.totalTracks, 2);
    expect(album.artworkUri, Uri.parse('https://i.scdn.co/image/album'));

    final tracks = await provider.loadAlbumTracksPage(album, limit: 1);

    expect(tracksRequest!.path, '/v1/albums/album-id/tracks');
    expect(tracksRequest!.queryParameters['offset'], '0');
    expect(tracksRequest!.queryParameters['limit'], '1');
    expect(tracks.hasMore, isTrue);
    expect(tracks.tracks.single.album, 'Signal Archive');
    expect(tracks.tracks.single.artworkUri, album.artworkUri);
    expect(tracks.tracks.single.isPlayable, isFalse);
    expect(await provider.resolveStream(tracks.tracks.single), isNull);
  });

  test('loads read-only playlists and playlist-item metadata', () async {
    Uri? playlistsRequest;
    Uri? itemsRequest;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      playlistsLoader: (uri, token) async {
        playlistsRequest = uri;
        expect(token, 'access-token');
        return '''
          {
            "offset": 3,
            "total": 5,
            "next": "https://api.spotify.com/v1/me/playlists?offset=4",
            "items": [{
              "id": "playlist-id",
              "name": "Signal Queue",
              "description": "For focused work",
              "owner": {"display_name": "Mira"},
              "tracks": {"total": 2},
              "images": [{"url": "https://i.scdn.co/image/playlist"}]
            }]
          }
        ''';
      },
      playlistItemsLoader: (uri, token) async {
        itemsRequest = uri;
        expect(token, 'access-token');
        return '''
          {
            "offset": 0,
            "total": 2,
            "next": "https://api.spotify.com/v1/playlists/playlist-id/items?offset=1",
            "items": [
              {"item": null},
              {
                "added_at": "2026-07-17T12:00:00Z",
                "item": {
                  "id": "playlist-track-id",
                  "name": "Playlist Signal",
                  "duration_ms": 195000,
                  "artists": [{"name": "Aether"}],
                  "album": {"name": "Signals"}
                }
              }
            ]
          }
        ''';
      },
    );

    final playlists = await provider.loadSavedPlaylistsPage(
      offset: 3,
      limit: 100,
    );

    expect(playlistsRequest!.path, '/v1/me/playlists');
    expect(playlistsRequest!.queryParameters['offset'], '3');
    expect(playlistsRequest!.queryParameters['limit'], '50');
    expect(playlists.total, 5);
    expect(playlists.hasMore, isTrue);
    final playlist = playlists.playlists.single;
    expect(playlist.title, 'Signal Queue');
    expect(playlist.ownerName, 'Mira');
    expect(playlist.totalTracks, 2);
    expect(playlist.artworkUri, Uri.parse('https://i.scdn.co/image/playlist'));

    final tracks = await provider.loadPlaylistTracksPage(playlist, limit: 1);

    expect(itemsRequest!.path, '/v1/playlists/playlist-id/items');
    expect(itemsRequest!.queryParameters['offset'], '0');
    expect(itemsRequest!.queryParameters['limit'], '1');
    expect(tracks.total, 2);
    expect(tracks.hasMore, isTrue);
    expect(tracks.tracks, hasLength(1));
    expect(tracks.tracks.single.title, 'Playlist Signal');
    expect(tracks.tracks.single.isPlayable, isFalse);
    expect(await provider.resolveStream(tracks.tracks.single), isNull);
  });

  test('returns bounded official Spotify track suggestions', () async {
    Uri? requestUri;
    String? requestToken;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      searchLoader: (uri, token) async {
        requestUri = uri;
        requestToken = token;
        return '''
          {"tracks": {"offset": 0, "total": 3, "items": [
            {"id":"one","name":"Aether","artists":[{"name":"Mira"}],"album":{"name":"Signals"}},
            {"id":"two","name":"Aether","artists":[{"name":"Orbit"}],"album":{"name":"Other"}},
            {"id":"three","name":"Beyond","artists":[],"album":{}}
          ]}}
        ''';
      },
    );

    final suggestions = await provider.suggest('  aether  ', limit: 1);

    expect(requestToken, 'access-token');
    expect(requestUri!.queryParameters['q'], 'aether');
    expect(requestUri!.queryParameters['type'], 'track');
    expect(requestUri!.queryParameters['limit'], '1');
    expect(requestUri!.queryParameters['offset'], '0');
    expect(
      provider.capabilities,
      contains(MusicSourceCapability.searchSuggestions),
    );
    expect(suggestions, hasLength(1));
    expect(suggestions.single.value, 'Aether');
    expect(suggestions.single.kind, MusicSourceSearchSuggestionKind.track);
    expect(suggestions.single.subtitle, 'Mira - Signals');
    expect(await provider.suggest('   '), isEmpty);
    await expectLater(provider.suggest('aether', limit: 0), throwsArgumentError);
  });
}
