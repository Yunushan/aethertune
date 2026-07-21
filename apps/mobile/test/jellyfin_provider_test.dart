import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/jellyfin_provider.dart';
import 'package:aethertune/src/domain/music_catalog_discovery_provider.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  test('searches Jellyfin libraries and returns metadata-only tracks', () async {
    Uri? capturedUri;
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      limit: 3,
      requestLoader: (uri) async {
        capturedUri = uri;
        return _jellyfinItemsJson;
      },
    );

    expect(provider.capabilities, JellyfinProvider.defaultCapabilities);
    expect(provider.disclosure.requiresUserCredentials, isTrue);
    expect(provider.disclosure.cachesMedia, isTrue);
    expect(provider.disclosure.supportsDownloads, isTrue);
    expect(provider.disclosure.networkDomains, <String>[
      'media.example.test',
    ]);

    final tracks = await provider.search(' aether ');

    expect(capturedUri!.path, '/jellyfin/Users/user-1/Items');
    expect(capturedUri!.queryParameters['api_key'], 'api-secret');
    expect(capturedUri!.queryParameters['Recursive'], 'true');
    expect(capturedUri!.queryParameters['IncludeItemTypes'], 'Audio');
    expect(capturedUri!.queryParameters['SearchTerm'], 'aether');
    expect(capturedUri!.queryParameters['Fields'], contains('Genres'));
    expect(capturedUri!.queryParameters['Fields'], isNot(contains('ImageTags')));
    expect(capturedUri!.queryParameters['StartIndex'], '0');
    expect(capturedUri!.queryParameters['Limit'], '3');
    expect(capturedUri!.queryParameters['EnableTotalRecordCount'], 'true');

    expect(tracks, hasLength(1));
    final track = tracks.single;
    expect(track.title, 'Sea Glass');
    expect(track.artist, 'Mira Sol, Yunus Bay');
    expect(track.album, 'Blue Rooms');
    expect(track.genre, 'Ambient');
    expect(track.duration, const Duration(seconds: 245));
    expect(track.sourceId, provider.id);
    expect(track.externalId, 'song-1');
    expect(track.streamUrl, isNull);
    expect(track.artworkUri, isNull);
    expect(track.providerArtworkId, 'song-1');
    expect(track.providerArtworkVersion, 'image-tag');

    final streamUri = await provider.resolveStream(track);
    expect(streamUri!.path, '/jellyfin/Audio/song-1/stream');
    expect(streamUri.queryParameters['api_key'], 'api-secret');
    expect(streamUri.queryParameters['UserId'], 'user-1');
    expect(streamUri.queryParameters['static'], 'true');
  });

  test('pages Jellyfin searches with server totals', () async {
    final requests = <Uri>[];
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        requests.add(uri);
        return _jellyfinSearchPageJson;
      },
    );

    final page = await provider.searchPage(
      ' glass ',
      cursor: '3',
      limit: 1,
    );

    expect(provider, isA<MusicSourceSearchPagingProvider>());
    expect(page.tracks.single.title, 'Sea Glass');
    expect(page.nextCursor, '4');
    expect(page.totalCount, 5);
    expect(page.hasMore, isTrue);
    expect(requests.single.path, '/jellyfin/Users/user-1/Items');
    expect(requests.single.queryParameters['SearchTerm'], 'glass');
    expect(requests.single.queryParameters['StartIndex'], '3');
    expect(requests.single.queryParameters['Limit'], '1');
    expect(
      requests.single.queryParameters['EnableTotalRecordCount'],
      'true',
    );

    await expectLater(
      provider.searchPage('glass', cursor: 'invalid'),
      throwsArgumentError,
    );
    await expectLater(
      provider.searchPage('glass', limit: 0),
      throwsArgumentError,
    );
    expect(requests, hasLength(1));
  });

  test('requests and parses bounded Jellyfin search suggestions', () async {
    Uri? capturedUri;
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        capturedUri = uri;
        return _jellyfinSearchHintsJson;
      },
    );

    final suggestions = await provider.suggest(' mira ', limit: 3);

    expect(provider, isA<MusicSourceSearchSuggestionProvider>());
    expect(
      provider.capabilities,
      contains(MusicSourceCapability.searchSuggestions),
    );
    expect(capturedUri!.path, '/jellyfin/Search/Hints');
    expect(capturedUri!.queryParameters['api_key'], 'api-secret');
    expect(capturedUri!.queryParameters['SearchTerm'], 'mira');
    expect(capturedUri!.queryParameters['UserId'], 'user-1');
    expect(
      capturedUri!.queryParameters['IncludeItemTypes'],
      'Audio,MusicAlbum,MusicArtist',
    );
    expect(capturedUri!.queryParameters['Limit'], '3');
    expect(
      suggestions.map((suggestion) => suggestion.value),
      <String>['Mira Sol', 'Blue Rooms', 'Sea Glass'],
    );
    expect(
      suggestions.map((suggestion) => suggestion.kind),
      <MusicSourceSearchSuggestionKind>[
        MusicSourceSearchSuggestionKind.artist,
        MusicSourceSearchSuggestionKind.album,
        MusicSourceSearchSuggestionKind.track,
      ],
    );
    expect(suggestions.last.subtitle, 'Mira Sol');

    await expectLater(
      provider.suggest('mira', limit: 0),
      throwsArgumentError,
    );
  });

  test('redacts authenticated request URLs from provider errors', () async {
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async => throw StateError('Request failed: $uri'),
    );

    await expectLater(
      provider.search('glass'),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('Jellyfin request failed') &&
              message.contains('[redacted]') &&
              !message.contains('api-secret');
        }),
      ),
    );
  });

  test('browses Jellyfin artists, albums, and playlists', () async {
    final requests = <Uri>[];
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        requests.add(uri);
        if (uri.path.endsWith('/Artists')) {
          return _jellyfinArtistsJson;
        }
        return switch (uri.queryParameters['IncludeItemTypes']) {
          'MusicAlbum' => _jellyfinAlbumsJson,
          'Playlist' => _jellyfinPlaylistsJson,
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

    expect(artists.single.id, 'artist-1');
    expect(artists.single.title, 'Mira Sol');
    expect(artists.single.subtitle, '12 track(s)');
    expect(albums.single.id, 'album-1');
    expect(albums.single.subtitle, 'Mira Sol · 2025 · 8 item(s)');
    expect(playlists.single.id, 'playlist-1');
    expect(playlists.single.itemCount, 4);
    expect(artists.single.artworkId, 'artist-1');
    expect(artists.single.artworkVersion, 'artist-image-tag');
    expect(albums.single.artworkId, 'album-1');
    expect(playlists.single.artworkId, 'playlist-1');
    expect(requests[0].path, '/jellyfin/Artists');
    expect(requests[0].queryParameters['UserId'], 'user-1');
    expect(requests[0].queryParameters['IncludeItemTypes'], 'Audio');
    expect(requests[0].queryParameters.containsKey('Recursive'), isFalse);
    expect(requests[1].path, '/jellyfin/Users/user-1/Items');
    expect(requests[1].queryParameters['IncludeItemTypes'], 'MusicAlbum');
    expect(requests[2].queryParameters['IncludeItemTypes'], 'Playlist');
    expect(
      requests.every(
        (request) =>
            !(request.queryParameters['Fields'] ?? '').contains('ImageTags'),
      ),
      isTrue,
    );
    expect(
      requests.every(
        (request) => request.queryParameters['api_key'] == 'api-secret',
      ),
      isTrue,
    );
  });

  test('pages Jellyfin artists albums and playlists with server totals',
      () async {
    final requests = <Uri>[];
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        requests.add(uri);
        if (uri.path.endsWith('/Artists')) {
          return _jellyfinArtistPageJson;
        }
        return switch (uri.queryParameters['IncludeItemTypes']) {
          'MusicAlbum' => _jellyfinAlbumPageJson,
          'Playlist' => _jellyfinPlaylistPageJson,
          _ => throw StateError('Unexpected request: $uri'),
        };
      },
    );

    final artists = await provider.browseCollectionsPage(
      MusicCatalogCollectionKind.artist,
      offset: 2,
      limit: 1,
    );
    final albums = await provider.browseCollectionsPage(
      MusicCatalogCollectionKind.album,
      offset: 2,
      limit: 1,
    );
    final playlists = await provider.browseCollectionsPage(
      MusicCatalogCollectionKind.playlist,
      offset: 2,
      limit: 1,
    );

    expect(
      provider.pagedCollectionKinds,
      MusicCatalogCollectionKind.values.toSet(),
    );
    expect(artists.collections.single.id, 'artist-page');
    expect(artists.nextOffset, 3);
    expect(artists.totalCount, 5);
    expect(artists.hasMore, isTrue);
    expect(albums.collections.single.id, 'album-page');
    expect(albums.nextOffset, 3);
    expect(albums.totalCount, 3);
    expect(albums.hasMore, isFalse);
    expect(playlists.collections.single.id, 'playlist-page');
    expect(playlists.totalCount, 10);
    expect(playlists.hasMore, isTrue);
    expect(
      requests.every(
        (request) =>
            request.queryParameters['StartIndex'] == '2' &&
            request.queryParameters['Limit'] == '1' &&
            request.queryParameters['EnableTotalRecordCount'] == 'true' &&
            request.queryParameters['api_key'] == 'api-secret',
      ),
      isTrue,
    );
    expect(requests.first.path, '/jellyfin/Artists');
    expect(requests[1].path, '/jellyfin/Users/user-1/Items');

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
    expect(requests, hasLength(3));
  });

  test('loads Jellyfin home discovery album shelves with bounded ordering',
      () async {
    final requests = <Uri>[];
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        requests.add(uri);
        return uri.path.endsWith('/Items/Latest')
            ? _jellyfinLatestAlbumsJson
            : _jellyfinAlbumsJson;
      },
    );

    final recentlyAdded = await provider.browseDiscoveryCollections(
      MusicCatalogDiscoveryKind.recentlyAdded,
      limit: 7,
    );
    final frequentlyPlayed = await provider.browseDiscoveryCollections(
      MusicCatalogDiscoveryKind.frequentlyPlayed,
      limit: 7,
    );
    final recentlyPlayed = await provider.browseDiscoveryCollections(
      MusicCatalogDiscoveryKind.recentlyPlayed,
      limit: 7,
    );
    final favorites = await provider.browseDiscoveryCollections(
      MusicCatalogDiscoveryKind.favorites,
      limit: 7,
    );
    final random = await provider.browseDiscoveryCollections(
      MusicCatalogDiscoveryKind.random,
      limit: 7,
    );

    expect(provider.discoveryKinds, <MusicCatalogDiscoveryKind>[
      MusicCatalogDiscoveryKind.recentlyAdded,
      MusicCatalogDiscoveryKind.frequentlyPlayed,
      MusicCatalogDiscoveryKind.recentlyPlayed,
      MusicCatalogDiscoveryKind.favorites,
      MusicCatalogDiscoveryKind.random,
    ]);
    expect(
      provider.capabilities,
      contains(MusicSourceCapability.recommendations),
    );
    expect(recentlyAdded.single.id, 'album-latest');
    expect(frequentlyPlayed.single.id, 'album-1');
    expect(recentlyPlayed.single.id, 'album-1');
    expect(favorites.single.id, 'album-1');
    expect(random.single.id, 'album-1');

    final latestRequest = requests[0];
    expect(latestRequest.path, '/jellyfin/Items/Latest');
    expect(latestRequest.queryParameters['userId'], 'user-1');
    expect(latestRequest.queryParameters['includeItemTypes'], 'MusicAlbum');
    expect(latestRequest.queryParameters['limit'], '7');
    expect(latestRequest.queryParameters['groupItems'], 'false');
    expect(latestRequest.queryParameters['api_key'], 'api-secret');

    final frequentRequest = requests[1];
    expect(frequentRequest.path, '/jellyfin/Users/user-1/Items');
    expect(frequentRequest.queryParameters['IncludeItemTypes'], 'MusicAlbum');
    expect(frequentRequest.queryParameters['SortBy'], 'PlayCount');
    expect(frequentRequest.queryParameters['SortOrder'], 'Descending');
    expect(frequentRequest.queryParameters['IsPlayed'], 'true');
    expect(frequentRequest.queryParameters['Limit'], '7');

    final recentRequest = requests[2];
    expect(recentRequest.queryParameters['SortBy'], 'DatePlayed');
    expect(recentRequest.queryParameters['SortOrder'], 'Descending');
    expect(recentRequest.queryParameters['IsPlayed'], 'true');

    final favoriteRequest = requests[3];
    expect(favoriteRequest.queryParameters['SortBy'], 'SortName');
    expect(favoriteRequest.queryParameters['SortOrder'], 'Descending');
    expect(favoriteRequest.queryParameters['IsFavorite'], 'true');
    expect(favoriteRequest.queryParameters['IsPlayed'], isNull);

    final randomRequest = requests[4];
    expect(randomRequest.queryParameters['SortBy'], 'Random');
    expect(randomRequest.queryParameters['SortOrder'], 'Descending');
    expect(randomRequest.queryParameters['IsPlayed'], isNull);
  });

  test('pages Jellyfin query-backed discovery shelves', () async {
    Uri? capturedUri;
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        capturedUri = uri;
        return '''
          {
            "StartIndex": 9,
            "TotalRecordCount": 12,
            "Items": [
              {
                "Id": "album-continued",
                "Name": "Late Rooms",
                "AlbumArtist": "Mira Sol",
                "ProductionYear": 2026,
                "ChildCount": 10
              }
            ]
          }
        ''';
      },
    );

    final page = await provider.browseDiscoveryCollectionsPage(
      MusicCatalogDiscoveryKind.recentlyPlayed,
      offset: 9,
      limit: 1,
    );

    expect(
      provider.pagedDiscoveryKinds,
      <MusicCatalogDiscoveryKind>{
        MusicCatalogDiscoveryKind.frequentlyPlayed,
        MusicCatalogDiscoveryKind.recentlyPlayed,
        MusicCatalogDiscoveryKind.favorites,
        MusicCatalogDiscoveryKind.random,
      },
    );
    expect(page.collections.single.id, 'album-continued');
    expect(page.nextOffset, 10);
    expect(page.totalCount, 12);
    expect(page.hasMore, isTrue);
    expect(capturedUri!.path, '/jellyfin/Users/user-1/Items');
    expect(capturedUri!.queryParameters['StartIndex'], '9');
    expect(capturedUri!.queryParameters['Limit'], '1');
    expect(capturedUri!.queryParameters['EnableTotalRecordCount'], 'true');
    expect(capturedUri!.queryParameters['SortBy'], 'DatePlayed');
    expect(capturedUri!.queryParameters['IsPlayed'], 'true');

    await expectLater(
      provider.browseDiscoveryCollectionsPage(
        MusicCatalogDiscoveryKind.recentlyAdded,
      ),
      throwsUnsupportedError,
    );
    await expectLater(
      provider.browseDiscoveryCollectionsPage(
        MusicCatalogDiscoveryKind.random,
        offset: -1,
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.browseDiscoveryCollectionsPage(
        MusicCatalogDiscoveryKind.random,
        limit: 0,
      ),
      throwsArgumentError,
    );
  });

  test('loads Jellyfin instant-mix radio for track artist and album seeds',
      () async {
    final requests = <Uri>[];
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        requests.add(uri);
        return _jellyfinItemsJson;
      },
    );

    final trackRadio = await provider.loadRadio(
      const MusicCatalogRadioSeed(
        kind: MusicCatalogRadioSeedKind.track,
        id: ' song-1 ',
      ),
      limit: 7,
    );
    final artistRadio = await provider.loadRadio(
      const MusicCatalogRadioSeed(
        kind: MusicCatalogRadioSeedKind.artist,
        id: 'artist-1',
      ),
      limit: 8,
    );
    final albumRadio = await provider.loadRadio(
      const MusicCatalogRadioSeed(
        kind: MusicCatalogRadioSeedKind.album,
        id: 'album-1',
      ),
      limit: 9,
    );

    expect(provider, isA<MusicCatalogRadioProvider>());
    expect(
      provider.radioSeedKinds,
      MusicCatalogRadioSeedKind.values.toSet(),
    );
    expect(trackRadio.single.title, 'Sea Glass');
    expect(artistRadio.single.sourceId, provider.id);
    expect(albumRadio.single.streamUrl, isNull);
    expect(
      requests.map((request) => request.path),
      <String>[
        '/jellyfin/Songs/song-1/InstantMix',
        '/jellyfin/Artists/artist-1/InstantMix',
        '/jellyfin/Albums/album-1/InstantMix',
      ],
    );
    expect(
      requests.map((request) => request.queryParameters['limit']),
      <String>['7', '8', '9'],
    );
    expect(
      requests.every(
        (request) =>
            request.queryParameters['userId'] == 'user-1' &&
            request.queryParameters['fields'] == 'Genres' &&
            request.queryParameters['enableImages'] == 'true' &&
            request.queryParameters['enableImageTypes'] == 'Primary' &&
            request.queryParameters['imageTypeLimit'] == '1' &&
            request.queryParameters['api_key'] == 'api-secret',
      ),
      isTrue,
    );

    await expectLater(
      provider.loadRadio(
        const MusicCatalogRadioSeed(
          kind: MusicCatalogRadioSeedKind.album,
          id: ' ',
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      provider.loadRadio(
        const MusicCatalogRadioSeed(
          kind: MusicCatalogRadioSeedKind.artist,
          id: 'artist-1',
        ),
        limit: 0,
      ),
      throwsArgumentError,
    );
    expect(requests, hasLength(3));
  });

  test('loads Jellyfin artist albums, album tracks, and playlist tracks',
      () async {
    final requests = <Uri>[];
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        requests.add(uri);
        if (uri.path.endsWith('/Playlists/playlist-1/Items')) {
          return _jellyfinItemsJson;
        }
        if (uri.queryParameters['ArtistIds'] == 'artist-1') {
          return _jellyfinAlbumsJson;
        }
        if (uri.queryParameters['ParentId'] == 'album-1') {
          return _jellyfinItemsJson;
        }
        throw StateError('Unexpected request: $uri');
      },
    );

    final artist = await provider.loadCollection(
      const MusicCatalogCollection(
        id: 'artist-1',
        title: 'Mira Sol',
        kind: MusicCatalogCollectionKind.artist,
      ),
    );
    final album = await provider.loadCollection(
      const MusicCatalogCollection(
        id: 'album-1',
        title: 'Blue Rooms',
        kind: MusicCatalogCollectionKind.album,
      ),
    );
    final playlist = await provider.loadCollection(
      const MusicCatalogCollection(
        id: 'playlist-1',
        title: 'Night Focus',
        kind: MusicCatalogCollectionKind.playlist,
      ),
    );

    expect(artist.collections.single.title, 'Blue Rooms');
    expect(artist.tracks, isEmpty);
    expect(album.tracks.single.title, 'Sea Glass');
    expect(album.tracks.single.streamUrl, isNull);
    expect(album.tracks.single.artworkUri, isNull);
    expect(album.tracks.single.providerArtworkId, 'song-1');
    expect(playlist.tracks.single.externalId, 'song-1');
    expect(requests[0].queryParameters['ArtistIds'], 'artist-1');
    expect(requests[0].queryParameters['IncludeItemTypes'], 'MusicAlbum');
    expect(requests[1].queryParameters['ParentId'], 'album-1');
    expect(requests[1].queryParameters['IncludeItemTypes'], 'Audio');
    expect(
      requests[2].path,
      '/jellyfin/Playlists/playlist-1/Items',
    );
    expect(requests[2].queryParameters['UserId'], 'user-1');
  });

  test('creates edits and deletes Jellyfin playlists through documented APIs',
      () async {
    final requests = <Uri>[];
    final methods = <String>[];
    final bodies = <Map<String, Object?>?>[];
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (_) async => '{"Items":[]}',
      mutationLoader: (uri, method, body) async {
        requests.add(uri);
        methods.add(method);
        bodies.add(body);
      },
    );

    expect(
      provider.capabilities,
      contains(MusicSourceCapability.playlistMutation),
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

    expect(methods, <String>['POST', 'POST', 'POST', 'POST', 'DELETE']);
    expect(requests.map((request) => request.path), <String>[
      '/jellyfin/Playlists',
      '/jellyfin/Playlists/playlist-1',
      '/jellyfin/Playlists/playlist-1/Items',
      '/jellyfin/Playlists/playlist-1',
      '/jellyfin/Items/playlist-1',
    ]);
    expect(bodies[0], <String, Object?>{
      'Name': 'Morning Focus',
      'Ids': <String>['song-1', 'song-2'],
      'UserId': 'user-1',
      'MediaType': 'Audio',
    });
    expect(bodies[1], <String, Object?>{'Name': 'Deep Focus'});
    expect(bodies[2], isNull);
    expect(requests[2].queryParameters['ids'], 'song-3,song-4');
    expect(requests[2].queryParameters['userId'], 'user-1');
    expect(bodies[3], <String, Object?>{
      'Ids': <String>['song-2', 'song-1', 'song-2'],
    });
    expect(bodies[4], isNull);
    expect(
      requests.every(
        (request) => request.queryParameters['api_key'] == 'api-secret',
      ),
      isTrue,
    );
    expect(
      () => provider.createPlaylist('   '),
      throwsArgumentError,
    );
    expect(
      () => provider.replacePlaylistTracks(
        'playlist-1',
        const <String>[''],
      ),
      throwsArgumentError,
    );
  });

  test('loads Jellyfin artwork with header auth and a credential-free URI',
      () async {
    Uri? capturedUri;
    Map<String, String>? capturedHeaders;
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test/jellyfin'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (_) async => '{"Items":[]}',
      artworkLoader: (uri, headers) async {
        capturedUri = uri;
        capturedHeaders = headers;
        return Uint8List.fromList(<int>[1, 2, 3]);
      },
    );

    final bytes = await provider.loadArtwork(
      'album-1',
      version: 'image-tag',
      maxWidth: 320,
    );

    expect(bytes, <int>[1, 2, 3]);
    expect(capturedUri!.path, '/jellyfin/Items/album-1/Images/Primary');
    expect(capturedUri!.queryParameters['maxWidth'], '320');
    expect(capturedUri!.queryParameters['quality'], '90');
    expect(capturedUri!.queryParameters['tag'], 'image-tag');
    expect(capturedUri!.queryParameters.containsKey('api_key'), isFalse);
    expect(capturedUri.toString(), isNot(contains('api-secret')));
    expect(capturedHeaders, <String, String>{
      'X-Emby-Token': 'api-secret',
    });
  });

  test('handles empty responses and offline policy for user-owned media', () {
    expect(parseJellyfinItemsResponse('{"Items":[]}'), isEmpty);
    expect(
      () => parseJellyfinItemsResponse('[]'),
      throwsA(isA<FormatException>()),
    );

    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (_) async => '{"Items":[]}',
    );
    final policy = OfflineMediaPolicy(<MusicSourceProvider>[provider]);
    final track = Track(
      id: 'jellyfin-track',
      title: 'Jellyfin Track',
      sourceId: provider.id,
      externalId: 'song-1',
    );

    expect(policy.canCache(track), isTrue);
    expect(policy.canDownload(track), isTrue);
  });

  test('tests credentials without requiring a search result', () async {
    Uri? capturedUri;
    final provider = JellyfinProvider(
      baseUri: Uri.parse('https://media.example.test'),
      userId: 'user-1',
      apiKey: 'api-secret',
      requestLoader: (uri) async {
        capturedUri = uri;
        return '{"Items":[]}';
      },
    );

    await provider.testConnection();

    expect(capturedUri!.path, '/Users/user-1/Items');
    expect(capturedUri!.queryParameters['api_key'], 'api-secret');
    expect(capturedUri!.queryParameters['Limit'], '1');
  });
}

const _jellyfinItemsJson = '''
{
  "Items": [
    {
      "Id": "song-1",
      "Name": "Sea Glass",
      "Artists": ["Mira Sol", "Yunus Bay"],
      "Album": "Blue Rooms",
      "Genres": ["Ambient", "Electronic"],
      "RunTimeTicks": 2450000000,
      "ImageTags": {
        "Primary": "image-tag"
      }
    }
  ],
  "TotalRecordCount": 1
}
''';

const _jellyfinSearchPageJson = '''
{
  "Items": [
    {
      "Id": "song-1",
      "Name": "Sea Glass",
      "Artists": ["Mira Sol", "Yunus Bay"],
      "Album": "Blue Rooms",
      "Genres": ["Ambient"],
      "RunTimeTicks": 2450000000
    }
  ],
  "StartIndex": 3,
  "TotalRecordCount": 5
}
''';

const _jellyfinSearchHintsJson = '''
{
  "SearchHints": [
    {"Name": "Mira Sol", "Type": "MusicArtist"},
    {"Name": "Blue Rooms", "Type": "MusicAlbum", "Artists": ["Mira Sol"]},
    {"Name": "Sea Glass", "Type": "Audio", "Artists": ["Mira Sol"], "Album": "Blue Rooms"},
    {"Name": "Sea Glass", "Type": "Audio"},
    {"Name": "", "Type": "Audio"}
  ]
}
''';

const _jellyfinArtistsJson = '''
{
  "Items": [
    {
      "Id": "artist-1",
      "Name": "Mira Sol",
      "RecursiveItemCount": 12,
      "ImageTags": {"Primary": "artist-image-tag"}
    }
  ]
}
''';

const _jellyfinAlbumsJson = '''
{
  "Items": [
    {
      "Id": "album-1",
      "Name": "Blue Rooms",
      "AlbumArtist": "Mira Sol",
      "ProductionYear": 2025,
      "ChildCount": 8,
      "ImageTags": {"Primary": "album-image-tag"}
    }
  ]
}
''';

const _jellyfinLatestAlbumsJson = '''
[
  {
    "Id": "album-latest",
    "Name": "Latest Rooms",
    "AlbumArtist": "Mira Sol",
    "ProductionYear": 2026,
    "ChildCount": 9,
    "ImageTags": {"Primary": "latest-image-tag"}
  }
]
''';

const _jellyfinPlaylistsJson = '''
{
  "Items": [
    {
      "Id": "playlist-1",
      "Name": "Night Focus",
      "ChildCount": 4,
      "ImageTags": {"Primary": "playlist-image-tag"}
    }
  ]
}
''';

const _jellyfinArtistPageJson = '''
{
  "Items": [
    {
      "Id": "artist-page",
      "Name": "Paged Artist",
      "RecursiveItemCount": 4
    }
  ],
  "StartIndex": 2,
  "TotalRecordCount": 5
}
''';

const _jellyfinAlbumPageJson = '''
{
  "Items": [
    {
      "Id": "album-page",
      "Name": "Paged Album",
      "AlbumArtist": "Paged Artist"
    }
  ],
  "StartIndex": 2,
  "TotalRecordCount": 3
}
''';

const _jellyfinPlaylistPageJson = '''
{
  "Items": [
    {
      "Id": "playlist-page",
      "Name": "Paged Playlist",
      "ChildCount": 3
    }
  ],
  "StartIndex": 2,
  "TotalRecordCount": 10
}
''';
