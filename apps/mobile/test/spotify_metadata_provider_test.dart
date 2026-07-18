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

    final page = await provider.loadTopTracksPage(
      limit: 100,
      timeRange: SpotifyTopTracksTimeRange.shortTerm,
    );

    expect(requestUri!.path, '/v1/me/top/tracks');
    expect(requestUri!.queryParameters['time_range'], 'short_term');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(page.tracks.single.title, 'Top Signal');
    expect(page.tracks.single.isPlayable, isFalse);
  });

  test('loads bounded official Spotify top-artist metadata', () async {
    Uri? requestUri;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      topArtistsLoader: (uri, token) async {
        requestUri = uri;
        return '''
          {"items": [{"id": "top-artist", "name": "Aether",
          "images": [{"url": "https://i.scdn.co/image/artist"}]}]}
        ''';
      },
    );

    final artists = await provider.loadTopArtists(
      timeRange: SpotifyTopTracksTimeRange.longTerm,
      limit: 100,
    );

    expect(requestUri!.path, '/v1/me/top/artists');
    expect(requestUri!.queryParameters['time_range'], 'long_term');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(artists.single.name, 'Aether');
    expect(artists.single.artworkUri, Uri.parse('https://i.scdn.co/image/artist'));
  });

  test('loads bounded saved-episode metadata without a playable URI', () async {
    Uri? requestUri;
    String? requestToken;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      savedEpisodesLoader: (uri, token) async {
        requestUri = uri;
        requestToken = token;
        return '''
          {
            "offset": 3,
            "total": 5,
            "next": "https://api.spotify.com/v1/me/episodes?offset=4",
            "items": [{
              "added_at": "2026-07-17T12:00:00Z",
              "episode": {
                "id": "episode-id",
                "name": "Signal Episode",
                "duration_ms": 62000,
                "images": [{"url": "https://i.scdn.co/image/episode"}],
                "show": {
                  "name": "Signal Show",
                  "publisher": "Aether Radio"
                }
              }
            }]
          }
        ''';
      },
    );

    final page = await provider.loadSavedEpisodesPage(offset: 3, limit: 100);

    expect(requestUri!.path, '/v1/me/episodes');
    expect(requestUri!.queryParameters, <String, String>{
      'limit': '50',
      'offset': '3',
    });
    expect(requestToken, 'access-token');
    expect(page.offset, 3);
    expect(page.total, 5);
    expect(page.hasMore, isTrue);
    final episode = page.tracks.single;
    expect(episode.title, 'Signal Episode');
    expect(episode.artist, 'Aether Radio');
    expect(episode.album, 'Signal Show');
    expect(episode.duration, const Duration(minutes: 1, seconds: 2));
    expect(episode.artworkUri, Uri.parse('https://i.scdn.co/image/episode'));
    expect(episode.externalId, 'episode:episode-id');
    expect(episode.isPlayable, isFalse);
    expect(await provider.resolveStream(episode), isNull);
  });

  test('loads saved shows and their episode metadata without playback', () async {
    Uri? showsRequest;
    Uri? episodesRequest;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      savedShowsLoader: (uri, token) async {
        showsRequest = uri;
        return '''
          {"offset":0,"total":1,"next":null,"items":[{
            "added_at":"2026-07-17T12:00:00Z",
            "show":{
              "id":"show-id","name":"Signal Show","publisher":"Aether Radio",
              "total_episodes":2,"description":"Metadata only",
              "images":[{"url":"https://i.scdn.co/image/show"}]
            }
          }]}
        ''';
      },
      showEpisodesLoader: (uri, token) async {
        episodesRequest = uri;
        return '''
          {"offset":1,"total":2,"next":null,"items":[{
            "id":"show-episode-id","name":"Show Episode","duration_ms":125000,
            "images":[{"url":"https://i.scdn.co/image/episode"}]
          }]}
        ''';
      },
    );

    final shows = await provider.loadSavedShowsPage(limit: 99);
    final show = shows.shows.single;
    final episodes = await provider.loadShowEpisodesPage(show, offset: 1);

    expect(showsRequest!.path, '/v1/me/shows');
    expect(showsRequest!.queryParameters, <String, String>{
      'limit': '50',
      'offset': '0',
    });
    expect(show.title, 'Signal Show');
    expect(show.publisher, 'Aether Radio');
    expect(show.totalEpisodes, 2);
    expect(show.artworkUri, Uri.parse('https://i.scdn.co/image/show'));
    expect(episodesRequest!.path, '/v1/shows/show-id/episodes');
    expect(episodesRequest!.queryParameters, <String, String>{
      'limit': '20',
      'offset': '1',
    });
    final episode = episodes.tracks.single;
    expect(episode.title, 'Show Episode');
    expect(episode.artist, 'Aether Radio');
    expect(episode.album, 'Signal Show');
    expect(episode.duration, const Duration(minutes: 2, seconds: 5));
    expect(episode.artworkUri, Uri.parse('https://i.scdn.co/image/show'));
    expect(episode.isPlayable, isFalse);
  });

  test('loads bounded official Spotify followed-artist metadata', () async {
    Uri? requestUri;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      followedArtistsLoader: (uri, token) async {
        requestUri = uri;
        expect(token, 'access-token');
        return '''
          {"artists": {"total": 2,
          "next": "https://api.spotify.com/v1/me/following?after=next",
          "cursors": {"after": "next"},
          "items": [{"id": "followed-artist", "name": "Signal",
          "images": [{"url": "https://i.scdn.co/image/followed"}]}]}}
        ''';
      },
    );

    final page = await provider.loadFollowedArtistsPage(
      after: 'previous',
      limit: 100,
    );

    expect(requestUri!.path, '/v1/me/following');
    expect(requestUri!.queryParameters['type'], 'artist');
    expect(requestUri!.queryParameters['after'], 'previous');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(page.artists.single.name, 'Signal');
    expect(page.nextAfter, 'next');
    expect(page.hasMore, isTrue);
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

  test('loads bounded official Spotify new-release album metadata', () async {
    Uri? requestUri;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      newReleasesLoader: (uri, token) async {
        requestUri = uri;
        return '''
          {"albums": {"offset": 0, "total": 1, "next": null,
          "items": [{"id": "release", "name": "New Signal",
          "total_tracks": 2, "artists": [{"name": "Aether"}],
          "images": [{"url": "https://i.scdn.co/image/release"}]}]}}
        ''';
      },
    );

    final page = await provider.loadNewReleasesPage(limit: 100);

    expect(requestUri!.path, '/v1/browse/new-releases');
    expect(requestUri!.queryParameters['limit'], '50');
    expect(page.albums.single.title, 'New Signal');
    expect(page.albums.single.artworkUri, Uri.parse('https://i.scdn.co/image/release'));
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
