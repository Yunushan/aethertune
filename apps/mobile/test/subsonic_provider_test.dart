import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/subsonic_provider.dart';
import 'package:aethertune/src/domain/music_catalog_discovery_provider.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  test('searches Subsonic servers and returns metadata-only tracks', () async {
    Uri? capturedUri;
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        capturedUri = uri;
        return _searchResponseJson;
      },
      limit: 3,
    );

    expect(provider.id, startsWith('subsonic-'));
    expect(provider.name, 'Navidrome / Subsonic');
    expect(
      provider.capabilities,
      containsAll(const <MusicSourceCapability>[
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.searchSuggestions,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.libraryBrowse,
        MusicSourceCapability.playlistMutation,
        MusicSourceCapability.artwork,
        MusicSourceCapability.offlineCache,
        MusicSourceCapability.downloads,
        MusicSourceCapability.authentication,
      ]),
    );
    expect(provider.disclosure.networkDomains, <String>[
      'music.example.test',
    ]);
    expect(provider.disclosure.requiresUserCredentials, isTrue);
    expect(provider.disclosure.cachesMedia, isTrue);
    expect(provider.disclosure.supportsDownloads, isTrue);

    final tracks = await provider.search('aether');

    expect(capturedUri, isNotNull);
    expect(capturedUri!.path, '/navidrome/rest/search3.view');
    expect(capturedUri!.queryParameters['u'], 'yunus');
    expect(capturedUri!.queryParameters['t'], _secretToken);
    expect(capturedUri!.queryParameters['s'], _fixedSalt);
    expect(capturedUri!.queryParameters.containsKey('p'), isFalse);
    expect(capturedUri!.queryParameters['v'], '1.16.1');
    expect(capturedUri!.queryParameters['c'], 'AetherTune');
    expect(capturedUri!.queryParameters['f'], 'json');
    expect(capturedUri!.queryParameters['query'], 'aether');
    expect(capturedUri!.queryParameters['artistCount'], '0');
    expect(capturedUri!.queryParameters['albumCount'], '0');
    expect(capturedUri!.queryParameters['songCount'], '3');
    expect(capturedUri!.queryParameters['songOffset'], '0');
    expect(tracks, hasLength(2));
    expect(tracks.first.title, 'Aether Session');
    expect(tracks.first.artist, 'Open Artist');
    expect(tracks.first.album, 'Self Hosted Album');
    expect(tracks.first.genre, 'Ambient');
    expect(tracks.first.duration, const Duration(seconds: 245));
    expect(tracks.first.sourceId, provider.id);
    expect(tracks.first.externalId, 'song-1');
    expect(tracks.first.streamUrl, isNull);
    expect(tracks.first.artworkUri, isNull);
    expect(tracks.first.providerArtworkId, 'cover-1');
    expect(
      await provider.resolveStream(tracks.first),
      Uri(
        scheme: 'https',
        host: 'music.example.test',
        path: '/navidrome/rest/stream.view',
        queryParameters: const <String, String>{
          'u': 'yunus',
          't': _secretToken,
          's': _fixedSalt,
          'v': '1.16.1',
          'c': 'AetherTune',
          'f': 'json',
          'id': 'song-1',
        },
      ),
    );
  });

  test('pages Subsonic search3 songs with songOffset', () async {
    final requests = <Uri>[];
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        requests.add(uri);
        return _searchResponseJson;
      },
    );

    final page = await provider.searchPage(
      'aether',
      cursor: '7',
      limit: 2,
    );

    expect(provider, isA<MusicSourceSearchPagingProvider>());
    expect(page.tracks, hasLength(2));
    expect(page.nextCursor, '9');
    expect(page.totalCount, isNull);
    expect(page.hasMore, isTrue);
    expect(requests.single.path, '/navidrome/rest/search3.view');
    expect(requests.single.queryParameters['query'], 'aether');
    expect(requests.single.queryParameters['songCount'], '2');
    expect(requests.single.queryParameters['songOffset'], '7');
    expect(requests.single.queryParameters['artistCount'], '0');
    expect(requests.single.queryParameters['albumCount'], '0');
    expect(requests.single.queryParameters['t'], _secretToken);

    await expectLater(
      provider.searchPage('aether', cursor: '-1'),
      throwsArgumentError,
    );
    await expectLater(
      provider.searchPage('aether', limit: 0),
      throwsArgumentError,
    );
    expect(requests, hasLength(1));
  });

  test('requests and parses bounded Subsonic search suggestions', () async {
    Uri? capturedUri;
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        capturedUri = uri;
        return _searchSuggestionsResponseJson;
      },
    );

    final suggestions = await provider.suggest('  aether  ', limit: 2);

    expect(provider, isA<MusicSourceSearchSuggestionProvider>());
    expect(capturedUri!.path, '/navidrome/rest/search3.view');
    expect(capturedUri!.queryParameters['query'], 'aether');
    expect(capturedUri!.queryParameters['artistCount'], '2');
    expect(capturedUri!.queryParameters['artistOffset'], '0');
    expect(capturedUri!.queryParameters['albumCount'], '2');
    expect(capturedUri!.queryParameters['albumOffset'], '0');
    expect(capturedUri!.queryParameters['songCount'], '2');
    expect(capturedUri!.queryParameters['songOffset'], '0');
    expect(capturedUri!.queryParameters['t'], _secretToken);
    expect(
      suggestions.map((suggestion) => suggestion.value),
      <String>['Aether Artist', 'Aether Album'],
    );
    expect(
      suggestions.map((suggestion) => suggestion.kind),
      <MusicSourceSearchSuggestionKind>[
        MusicSourceSearchSuggestionKind.artist,
        MusicSourceSearchSuggestionKind.album,
      ],
    );
    expect(suggestions.last.subtitle, 'Aether Artist');

    expect(await provider.suggest('   '), isEmpty);
    await expectLater(provider.suggest('aether', limit: 0), throwsArgumentError);
  });

  test('redacts salted authentication tokens from provider errors', () async {
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test'),
      username: 'demo',
      password: 'pw',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async => throw StateError('Request failed: $uri'),
    );

    await expectLater(
      provider.search('aether'),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('Navidrome / Subsonic request failed') &&
              message.contains('[redacted]') &&
              !message.contains(_pwToken) &&
              !message.contains('t=$_pwToken');
        }),
      ),
    );
  });

  test('browses Subsonic artists, albums, and playlists', () async {
    final requests = <Uri>[];
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        requests.add(uri);
        return switch (uri.path.split('/').last) {
          'getArtists.view' => _artistsResponseJson,
          'getAlbumList2.view' => _albumListResponseJson,
          'getPlaylists.view' => _playlistsResponseJson,
          _ => throw StateError('Unexpected request: $uri'),
        };
      },
    );

    final artists = await provider.browseCollections(
      MusicCatalogCollectionKind.artist,
    );
    final albums = await provider.browseCollections(
      MusicCatalogCollectionKind.album,
    );
    final playlists = await provider.browseCollections(
      MusicCatalogCollectionKind.playlist,
    );

    expect(artists.single.title, 'Open Artist');
    expect(artists.single.subtitle, '2 album(s)');
    expect(albums.single.title, 'Self Hosted Album');
    expect(albums.single.subtitle, 'Open Artist · 2024 · 2 track(s)');
    expect(playlists.single.title, 'Late Night');
    expect(playlists.single.subtitle, 'yunus · 2 track(s)');
    expect(artists.single.artworkId, 'artist-cover-1');
    expect(albums.single.artworkId, 'album-cover-1');
    expect(playlists.single.artworkId, 'playlist-cover-1');
    expect(requests[0].path, '/navidrome/rest/getArtists.view');
    expect(requests[1].path, '/navidrome/rest/getAlbumList2.view');
    expect(requests[1].queryParameters['type'], 'alphabeticalByName');
    expect(requests[1].queryParameters['size'], '500');
    expect(requests[2].path, '/navidrome/rest/getPlaylists.view');
    expect(
      requests.every(
        (request) =>
            request.queryParameters['u'] == 'yunus' &&
            request.queryParameters['t'] == _secretToken &&
            request.queryParameters['s'] == _fixedSalt &&
            !request.queryParameters.containsKey('p'),
      ),
      isTrue,
    );
  });

  test('pages Subsonic albums with documented size and offset', () async {
    final requests = <Uri>[];
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        requests.add(uri);
        return _albumListResponseJson;
      },
    );

    final page = await provider.browseCollectionsPage(
      MusicCatalogCollectionKind.album,
      offset: 7,
      limit: 1,
    );

    expect(provider.pagedCollectionKinds, <MusicCatalogCollectionKind>{
      MusicCatalogCollectionKind.album,
    });
    expect(page.collections.single.id, 'album-1');
    expect(page.nextOffset, 8);
    expect(page.totalCount, isNull);
    expect(page.hasMore, isTrue);
    expect(requests.single.path, '/navidrome/rest/getAlbumList2.view');
    expect(requests.single.queryParameters['type'], 'alphabeticalByName');
    expect(requests.single.queryParameters['size'], '1');
    expect(requests.single.queryParameters['offset'], '7');
    expect(requests.single.queryParameters['t'], _secretToken);

    await expectLater(
      provider.browseCollectionsPage(MusicCatalogCollectionKind.artist),
      throwsUnsupportedError,
    );
    await expectLater(
      provider.browseCollectionsPage(
        MusicCatalogCollectionKind.album,
        offset: -1,
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.browseCollectionsPage(
        MusicCatalogCollectionKind.album,
        limit: 0,
      ),
      throwsArgumentError,
    );
    expect(requests, hasLength(1));
  });

  test('loads documented Subsonic album discovery lists', () async {
    final requests = <Uri>[];
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        requests.add(uri);
        return _albumListResponseJson;
      },
    );

    for (final kind in provider.discoveryKinds) {
      final albums = await provider.browseDiscoveryCollections(kind, limit: 7);
      expect(albums.single.id, 'album-1');
    }

    expect(provider.discoveryKinds, <MusicCatalogDiscoveryKind>[
      MusicCatalogDiscoveryKind.recentlyAdded,
      MusicCatalogDiscoveryKind.frequentlyPlayed,
      MusicCatalogDiscoveryKind.recentlyPlayed,
      MusicCatalogDiscoveryKind.random,
    ]);
    expect(
      requests.map((request) => request.queryParameters['type']),
      <String>['newest', 'frequent', 'recent', 'random'],
    );
    expect(
      requests.every(
        (request) =>
            request.path == '/navidrome/rest/getAlbumList2.view' &&
            request.queryParameters['size'] == '7' &&
            request.queryParameters['offset'] == '0' &&
            request.queryParameters['t'] == _secretToken,
      ),
      isTrue,
    );
    expect(
      provider.capabilities,
      contains(MusicSourceCapability.recommendations),
    );
  });

  test('pages Subsonic discovery lists with the requested offset', () async {
    final requests = <Uri>[];
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        requests.add(uri);
        return _albumListResponseJson;
      },
    );

    final page = await provider.browseDiscoveryCollectionsPage(
      MusicCatalogDiscoveryKind.recentlyAdded,
      offset: 9,
      limit: 1,
    );

    expect(provider.pagedDiscoveryKinds, containsAll(provider.discoveryKinds));
    expect(page.collections.single.id, 'album-1');
    expect(page.nextOffset, 10);
    expect(page.hasMore, isTrue);
    expect(requests.single.queryParameters['type'], 'newest');
    expect(requests.single.queryParameters['offset'], '9');
    expect(requests.single.queryParameters['size'], '1');
    await expectLater(
      provider.browseDiscoveryCollectionsPage(
        MusicCatalogDiscoveryKind.random,
        offset: -1,
      ),
      throwsArgumentError,
    );
  });

  test('loads Subsonic track album and ID3 artist radio', () async {
    final requests = <Uri>[];
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        requests.add(uri);
        return uri.path.endsWith('/getSimilarSongs2.view')
            ? _similarSongs2ResponseJson
            : _similarSongsResponseJson;
      },
    );

    final trackRadio = await provider.loadRadio(
      const MusicCatalogRadioSeed(
        kind: MusicCatalogRadioSeedKind.track,
        id: ' song-1 ',
      ),
      limit: 7,
    );
    final albumRadio = await provider.loadRadio(
      const MusicCatalogRadioSeed(
        kind: MusicCatalogRadioSeedKind.album,
        id: 'album-1',
      ),
      limit: 8,
    );
    final artistRadio = await provider.loadRadio(
      const MusicCatalogRadioSeed(
        kind: MusicCatalogRadioSeedKind.artist,
        id: 'artist-1',
      ),
      limit: 9,
    );

    expect(provider, isA<MusicCatalogRadioProvider>());
    expect(
      provider.radioSeedKinds,
      MusicCatalogRadioSeedKind.values.toSet(),
    );
    expect(trackRadio.single.title, 'Radio Signal');
    expect(albumRadio.single.externalId, 'radio-song-1');
    expect(artistRadio.single.title, 'Artist Signal');
    expect(artistRadio.single.sourceId, provider.id);
    expect(
      requests.map((request) => request.path.split('/').last),
      <String>[
        'getSimilarSongs.view',
        'getSimilarSongs.view',
        'getSimilarSongs2.view',
      ],
    );
    expect(
      requests.map((request) => request.queryParameters['id']),
      <String>['song-1', 'album-1', 'artist-1'],
    );
    expect(
      requests.map((request) => request.queryParameters['count']),
      <String>['7', '8', '9'],
    );
    expect(
      requests.every(
        (request) =>
            request.queryParameters['t'] == _secretToken &&
            request.queryParameters['s'] == _fixedSalt &&
            !request.queryParameters.containsKey('p'),
      ),
      isTrue,
    );

    await expectLater(
      provider.loadRadio(
        const MusicCatalogRadioSeed(
          kind: MusicCatalogRadioSeedKind.track,
          id: '',
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.loadRadio(
        const MusicCatalogRadioSeed(
          kind: MusicCatalogRadioSeedKind.album,
          id: 'album-1',
        ),
        limit: 0,
      ),
      throwsArgumentError,
    );
    expect(requests, hasLength(3));
  });

  test('loads Subsonic artist albums, album tracks, and playlist entries',
      () async {
    final requests = <Uri>[];
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        requests.add(uri);
        return switch (uri.path.split('/').last) {
          'getArtist.view' => _artistResponseJson,
          'getAlbum.view' => _albumResponseJson,
          'getPlaylist.view' => _playlistResponseJson,
          _ => throw StateError('Unexpected request: $uri'),
        };
      },
    );

    final artist = await provider.loadCollection(
      const MusicCatalogCollection(
        id: 'artist-1',
        title: 'Open Artist',
        kind: MusicCatalogCollectionKind.artist,
      ),
    );
    final album = await provider.loadCollection(
      const MusicCatalogCollection(
        id: 'album-1',
        title: 'Self Hosted Album',
        kind: MusicCatalogCollectionKind.album,
      ),
    );
    final playlist = await provider.loadCollection(
      const MusicCatalogCollection(
        id: 'playlist-1',
        title: 'Late Night',
        kind: MusicCatalogCollectionKind.playlist,
      ),
    );

    expect(artist.collections.single.id, 'album-1');
    expect(album.tracks, hasLength(2));
    expect(album.tracks.first.title, 'Aether Session');
    expect(album.tracks.first.streamUrl, isNull);
    expect(album.tracks.first.providerArtworkId, 'cover-1');
    expect(playlist.tracks.single.title, 'Playlist Cut');
    expect(playlist.tracks.single.providerArtworkId, 'playlist-cover-1');
    expect(playlist.tracks.single.sourceId, provider.id);
    expect(requests[0].queryParameters['id'], 'artist-1');
    expect(requests[1].queryParameters['id'], 'album-1');
    expect(requests[2].queryParameters['id'], 'playlist-1');
  });

  test('creates edits and deletes Subsonic playlists with ordered song IDs',
      () async {
    final requests = <Uri>[];
    var saltIndex = 0;
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: () => 'mutation-salt-${saltIndex++}',
      requestLoader: (uri) async {
        requests.add(uri);
        return '{"subsonic-response":{"status":"ok"}}';
      },
    );

    await provider.createPlaylist(
      '  Morning Focus  ',
      trackIds: const <String>['song-1', 'song-2'],
    );
    await provider.renamePlaylist('playlist-1', 'Deep Focus');
    await provider.addPlaylistTracks(
      'playlist-1',
      const <String>['song-3', 'song-4'],
    );
    await provider.replacePlaylistTracks(
      'playlist-1',
      const <String>['song-2', 'song-1', 'song-2'],
    );
    await provider.deletePlaylist('playlist-1');
    await provider.addPlaylistTracks('playlist-1', const <String>[]);

    expect(requests.map((request) => request.path), <String>[
      '/navidrome/rest/createPlaylist.view',
      '/navidrome/rest/updatePlaylist.view',
      '/navidrome/rest/updatePlaylist.view',
      '/navidrome/rest/createPlaylist.view',
      '/navidrome/rest/deletePlaylist.view',
    ]);
    expect(requests[0].queryParameters['name'], 'Morning Focus');
    expect(
      requests[0].queryParametersAll['songId'],
      <String>['song-1', 'song-2'],
    );
    expect(requests[1].queryParameters['playlistId'], 'playlist-1');
    expect(requests[1].queryParameters['name'], 'Deep Focus');
    expect(
      requests[2].queryParametersAll['songIdToAdd'],
      <String>['song-3', 'song-4'],
    );
    expect(requests[3].queryParameters['playlistId'], 'playlist-1');
    expect(
      requests[3].queryParametersAll['songId'],
      <String>['song-2', 'song-1', 'song-2'],
    );
    expect(requests[4].queryParameters['id'], 'playlist-1');
    expect(
      requests.map((request) => request.queryParameters['s']).toSet(),
      hasLength(5),
    );
    expect(
      requests.every(
        (request) =>
            request.queryParameters.containsKey('t') &&
            !request.queryParameters.containsKey('p'),
      ),
      isTrue,
    );
    expect(
      () => provider.renamePlaylist('playlist-1', ' '),
      throwsArgumentError,
    );
    await expectLater(
      provider.addPlaylistTracks(' ', const <String>['song-1']),
      throwsArgumentError,
    );
  });

  test('loads Subsonic cover art through a salted credential request',
      () async {
    Uri? capturedUri;
    Map<String, String>? capturedHeaders;
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (_) async =>
          '{"subsonic-response":{"status":"ok"}}',
      artworkLoader: (uri, headers) async {
        capturedUri = uri;
        capturedHeaders = headers;
        return Uint8List.fromList(<int>[4, 5, 6]);
      },
    );

    final bytes = await provider.loadArtwork('cover-1', maxWidth: 256);

    expect(bytes, <int>[4, 5, 6]);
    expect(capturedUri!.path, '/navidrome/rest/getCoverArt.view');
    expect(capturedUri!.queryParameters['id'], 'cover-1');
    expect(capturedUri!.queryParameters['size'], '256');
    expect(capturedUri!.queryParameters['t'], _secretToken);
    expect(capturedUri!.queryParameters['s'], _fixedSalt);
    expect(capturedUri!.queryParameters.containsKey('p'), isFalse);
    expect(capturedUri.toString(), isNot(contains('secret')));
    expect(capturedHeaders, isEmpty);
  });

  test('handles failed responses and offline policy for user-owned media', () {
    expect(
      () => parseSubsonicSearchResponse(_failedResponseJson),
      throwsA(isA<FormatException>()),
    );

    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test'),
      username: 'demo',
      password: 'pw',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (_) async => _searchResponseJson,
    );
    final decision = OfflineMediaPolicy(<MusicSourceProvider>[
      provider,
    ]).evaluate(
      const SubsonicSong(
        id: 'song-1',
        title: 'Aether Session',
        artist: 'Open Artist',
        album: 'Self Hosted Album',
        genre: 'Ambient',
        duration: Duration(seconds: 245),
        coverArt: 'cover-1',
        suffix: 'mp3',
      ).toTrack(sourceId: provider.id),
      OfflineMediaAction.cache,
    );

    expect(decision.isAllowed, isTrue);
    expect(decision.providerId, provider.id);
  });

  test('tests credentials through the Subsonic ping endpoint', () async {
    Uri? capturedUri;
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test'),
      username: 'yunus',
      password: 'secret',
      saltGenerator: _fixedSaltGenerator,
      requestLoader: (uri) async {
        capturedUri = uri;
        return '{"subsonic-response":{"status":"ok"}}';
      },
    );

    await provider.testConnection();

    expect(capturedUri!.path, '/rest/ping.view');
    expect(capturedUri!.queryParameters['u'], 'yunus');
    expect(capturedUri!.queryParameters['t'], _secretToken);
    expect(capturedUri!.queryParameters['s'], _fixedSalt);
    expect(capturedUri!.queryParameters.containsKey('p'), isFalse);
  });
}

const _searchResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "version": "1.16.1",
    "searchResult3": {
      "song": [
        {
          "id": "song-1",
          "title": "Aether Session",
          "artist": "Open Artist",
          "album": "Self Hosted Album",
          "genre": "Ambient",
          "duration": 245,
          "coverArt": "cover-1",
          "suffix": "mp3"
        },
        {
          "id": "song-2",
          "title": "Local Cloud",
          "artist": "Server Artist",
          "album": "Self Hosted Album",
          "duration": 125
        }
      ]
    }
  }
}
''';

const _searchSuggestionsResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "searchResult3": {
      "artist": [
        {"id": "artist-1", "name": "Aether Artist"}
      ],
      "album": [
        {
          "id": "album-1",
          "name": "Aether Album",
          "artist": "Aether Artist"
        }
      ],
      "song": [
        {
          "id": "song-1",
          "title": "Aether Artist",
          "artist": "Aether Artist"
        },
        {
          "id": "song-2",
          "title": "Aether Song",
          "artist": "Second Artist"
        }
      ]
    }
  }
}
''';

const _failedResponseJson = '''
{
  "subsonic-response": {
    "status": "failed",
    "error": {
      "code": 40,
      "message": "Wrong username or password."
    }
  }
}
''';

const _similarSongsResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "similarSongs": {
      "song": [
        {
          "id": "radio-song-1",
          "title": "Radio Signal",
          "artist": "Similar Artist",
          "album": "Related Rooms",
          "genre": "Ambient",
          "duration": 210,
          "coverArt": "radio-cover-1"
        }
      ]
    }
  }
}
''';

const _similarSongs2ResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "similarSongs2": {
      "song": [
        {
          "id": "artist-radio-song-1",
          "title": "Artist Signal",
          "artist": "Related Artist",
          "album": "Artist Radio",
          "duration": 180
        }
      ]
    }
  }
}
''';

const _artistsResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "artists": {
      "index": [
        {
          "name": "O",
          "artist": [
            {
              "id": "artist-1",
              "name": "Open Artist",
              "albumCount": 2,
              "coverArt": "artist-cover-1"
            }
          ]
        }
      ]
    }
  }
}
''';

const _albumListResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "albumList2": {
      "album": [
        {
          "id": "album-1",
          "name": "Self Hosted Album",
          "artist": "Open Artist",
          "year": 2024,
          "songCount": 2,
          "coverArt": "album-cover-1"
        }
      ]
    }
  }
}
''';

const _playlistsResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "playlists": {
      "playlist": [
        {
          "id": "playlist-1",
          "name": "Late Night",
          "owner": "yunus",
          "songCount": 2,
          "coverArt": "playlist-cover-1"
        }
      ]
    }
  }
}
''';

const _artistResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "artist": {
      "id": "artist-1",
      "name": "Open Artist",
      "album": [
        {
          "id": "album-1",
          "name": "Self Hosted Album",
          "artist": "Open Artist",
          "year": 2024,
          "songCount": 2,
          "coverArt": "album-cover-1"
        }
      ]
    }
  }
}
''';

const _albumResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "album": {
      "id": "album-1",
      "name": "Self Hosted Album",
      "song": [
        {
          "id": "song-1",
          "title": "Aether Session",
          "artist": "Open Artist",
          "album": "Self Hosted Album",
          "genre": "Ambient",
          "duration": 245,
          "coverArt": "cover-1"
        },
        {
          "id": "song-2",
          "title": "Local Cloud",
          "artist": "Server Artist",
          "album": "Self Hosted Album",
          "duration": 125
        }
      ]
    }
  }
}
''';

const _playlistResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "playlist": {
      "id": "playlist-1",
      "name": "Late Night",
      "entry": [
        {
          "id": "song-3",
          "title": "Playlist Cut",
          "artist": "Open Artist",
          "album": "Self Hosted Album",
          "duration": 180,
          "coverArt": "playlist-cover-1"
        }
      ]
    }
  }
}
''';

const _fixedSalt = 'fixed-salt';
const _secretToken = '9fe6f34cac87f84c765c85e8263b63bb';
const _pwToken = 'cacf412bf59dc50063eab9ca54d52975';

String _fixedSaltGenerator() => _fixedSalt;
