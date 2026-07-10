import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/jellyfin_provider.dart';
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
    expect(capturedUri!.queryParameters['Limit'], '3');

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
