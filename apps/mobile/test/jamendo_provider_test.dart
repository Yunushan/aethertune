import 'dart:typed_data';

import 'package:aethertune/src/data/jamendo_provider.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('searches the documented Jamendo endpoint with bounded paging', () async {
    Uri? requested;
    final provider = JamendoProvider(
      clientId: 'client-id',
      loader: (uri) async {
        requested = uri;
        return _response(<String>['1', '2']);
      },
    );

    final page = await provider.searchPage('chill', limit: 2);

    expect(requested?.host, 'api.jamendo.com');
    expect(requested?.queryParameters['client_id'], 'client-id');
    expect(requested?.queryParameters['search'], 'chill');
    expect(requested?.queryParameters['offset'], '0');
    expect(requested?.queryParameters['limit'], '2');
    expect(requested?.queryParameters['type'], 'single albumtrack');
    expect(page.tracks.map((track) => track.id), <String>['jamendo:1', 'jamendo:2']);
    expect(page.nextCursor, '2');
    expect(page.tracks.first.streamUrl, 'https://stream.example.test/1.mp3');
  });

  test('loads a bounded artist-grouped public popularity chart', () async {
    Uri? requested;
    final provider = JamendoProvider(
      clientId: 'client-id',
      loader: (uri) async {
        requested = uri;
        return _response(<String>['1', '2']);
      },
    );

    final tracks = await provider.fetchPopular(limit: 2);

    expect(tracks.map((track) => track.id), <String>['jamendo:1', 'jamendo:2']);
    expect(requested?.path, '/v3.0/tracks/');
    expect(requested?.queryParameters['client_id'], 'client-id');
    expect(requested?.queryParameters['limit'], '2');
    expect(requested?.queryParameters['order'], 'popularity_total');
    expect(requested?.queryParameters['groupby'], 'artist_id');
    expect(requested?.queryParameters['type'], 'single albumtrack');
    expect(requested?.queryParameters['audioformat'], 'mp32');
    expect(requested?.queryParameters['search'], isNull);
    await expectLater(provider.fetchPopular(limit: 0), throwsArgumentError);
  });

  test('loads a documented featured-genre chart with a popularity boost',
      () async {
    Uri? requested;
    final provider = JamendoProvider(
      clientId: 'client-id',
      loader: (uri) async {
        requested = uri;
        return _response(<String>['1']);
      },
    );

    await provider.fetchPopular(
      featuredGenre: JamendoFeaturedGenre.jazz,
      lyricsLanguageCode: ' TR ',
    );

    expect(requested?.queryParameters['featured'], '1');
    expect(requested?.queryParameters['tags'], 'jazz');
    expect(requested?.queryParameters['boost'], 'popularity_total');
    expect(requested?.queryParameters['groupby'], 'artist_id');
    expect(requested?.queryParameters['order'], isNull);
    expect(requested?.queryParameters['lang'], 'tr');
    await expectLater(
      provider.fetchPopular(lyricsLanguageCode: 'tur'),
      throwsArgumentError,
    );
  });

  test('validates Jamendo payloads and rejects unsafe media URLs', () {
    final tracks = parseJamendoTracksResponse('''
      {"headers":{"status":"success","code":0},"results":[
        {"id":"1","name":"Safe","artist_name":"Artist","album_name":"Album","duration":"120","audio":"https://stream.example.test/1.mp3","image":"https://art.example.test/1.jpg"},
        {"id":"2","name":"Unsafe","audio":"http://stream.example.test/2.mp3","image":"https://user:password@art.example.test/2.jpg"},
        {"id":"invalid","name":"Ignored"}
      ]}
    ''');

    expect(tracks, hasLength(2));
    expect(tracks.first.duration, const Duration(seconds: 120));
    expect(tracks.first.artworkUri, Uri.parse('https://art.example.test/1.jpg'));
    expect(tracks[1].streamUrl, isNull);
    expect(tracks[1].artworkUri, isNull);
    expect(
      () => parseJamendoTracksResponse(
        '{"headers":{"status":"failed","code":5,"error_message":"Nope"},"results":[]}',
      ),
      throwsFormatException,
    );
  });

  test('uses a safe official stream redirect only for Jamendo tracks', () async {
    final provider = JamendoProvider(clientId: 'client-id');
    final metadataTrack = parseJamendoTracksResponse(
      '{"headers":{"status":"success","code":0},"results":[{"id":"7","name":"Track"}]}',
    ).single;

    final stream = await provider.resolveStream(metadataTrack);

    expect(stream?.host, 'api.jamendo.com');
    expect(stream?.path, '/v3.0/tracks/file/');
    expect(stream?.queryParameters['client_id'], 'client-id');
    expect(stream?.queryParameters['id'], '7');
    expect(stream?.queryParameters['action'], 'stream');
  });

  test('does not resolve a different provider track', () async {
    final provider = JamendoProvider(clientId: 'client-id');
    final track = parseJamendoTracksResponse(
      '{"headers":{"status":"success","code":0},"results":[{"id":"7","name":"Track"}]}',
    ).single.copyWith(sourceId: 'local');

    expect(await provider.resolveStream(track), isNull);
  });

  test('browses and explicitly searches bounded Jamendo catalog collections',
      () async {
    final requests = <Uri>[];
    final provider = JamendoProvider(
      clientId: 'client-id',
      loader: (uri) async {
        requests.add(uri);
        if (uri.path.endsWith('/artists/')) {
          return _artistCatalogResponse;
        }
        if (uri.path.endsWith('/albums/')) {
          return _albumCatalogResponse;
        }
        return _playlistCatalogResponse;
      },
    );

    final artists = await provider.browseCollectionsPage(
      MusicCatalogCollectionKind.artist,
      offset: 2,
      limit: 2,
    );
    final albums = await provider.searchCollectionsPage(
      MusicCatalogCollectionKind.album,
      '  aurora  ',
      offset: 1,
      limit: 1,
    );
    final playlists = await provider.searchCollectionsPage(
      MusicCatalogCollectionKind.playlist,
      '  night  ',
      offset: 3,
      limit: 1,
    );

    expect(provider, isA<MusicCatalogCollectionSearchProvider>());
    expect(provider.pagedCollectionKinds, <MusicCatalogCollectionKind>{
      MusicCatalogCollectionKind.artist,
      MusicCatalogCollectionKind.album,
      MusicCatalogCollectionKind.playlist,
    });
    expect(artists.collections.single.title, 'Mira Sol');
    expect(artists.nextOffset, 3);
    expect(artists.totalCount, 4);
    expect(artists.hasMore, isTrue);
    expect(albums.collections.single.title, 'Aurora Rooms');
    expect(albums.collections.single.subtitle, 'Mira Sol · 2026-01-01');
    expect(albums.nextOffset, 2);
    expect(albums.totalCount, 2);
    expect(albums.hasMore, isFalse);
    expect(playlists.collections.single.title, 'Night Drive');
    expect(playlists.collections.single.subtitle, 'Mira Sol · 2026-02-01');
    expect(playlists.nextOffset, 4);

    final artistRequest = requests.first;
    expect(artistRequest.path, '/v3.0/artists/');
    expect(artistRequest.queryParameters['client_id'], 'client-id');
    expect(artistRequest.queryParameters['offset'], '2');
    expect(artistRequest.queryParameters['limit'], '2');
    expect(artistRequest.queryParameters['fullcount'], 'true');
    expect(artistRequest.queryParameters['order'], 'popularity_total');
    expect(artistRequest.queryParameters['hasimage'], 'true');
    expect(artistRequest.queryParameters['namesearch'], isNull);

    final albumRequest = requests[1];
    expect(albumRequest.path, '/v3.0/albums/');
    expect(albumRequest.queryParameters['offset'], '1');
    expect(albumRequest.queryParameters['limit'], '1');
    expect(albumRequest.queryParameters['namesearch'], 'aurora');
    expect(albumRequest.queryParameters['type'], 'album single');

    final playlistRequest = requests[2];
    expect(playlistRequest.path, '/v3.0/playlists/');
    expect(playlistRequest.queryParameters['offset'], '3');
    expect(playlistRequest.queryParameters['limit'], '1');
    expect(playlistRequest.queryParameters['namesearch'], 'night');
    expect(playlistRequest.queryParameters['order'], 'creationdate_desc');
    expect(playlistRequest.queryParameters['imagesize'], isNull);

    final empty = await provider.searchCollectionsPage(
      MusicCatalogCollectionKind.artist,
      '  ',
    );
    expect(empty.collections, isEmpty);
    expect(requests, hasLength(3));
    await expectLater(
      provider.browseCollectionsPage(MusicCatalogCollectionKind.playlist,
          offset: -1),
      throwsArgumentError,
    );
    await expectLater(
      provider.browseCollectionsPage(MusicCatalogCollectionKind.artist,
          offset: -1),
      throwsArgumentError,
    );
  });

  test('loads nested Jamendo artist albums and album tracks with safe artwork',
      () async {
    final requests = <Uri>[];
    final artworkRequests = <Uri>[];
    final provider = JamendoProvider(
      clientId: 'client-id',
      loader: (uri) async {
        requests.add(uri);
        if (uri.path.endsWith('/artists/albums/')) {
          return _artistAlbumsResponse;
        }
        if (uri.path.endsWith('/playlists/tracks/')) {
          return _playlistTracksResponse;
        }
        return _albumTracksResponse;
      },
      artworkLoader: (uri, headers) async {
        artworkRequests.add(uri);
        expect(headers, isEmpty);
        return Uint8List.fromList(<int>[1, 2, 3]);
      },
    );

    final artist = await provider.loadCollection(
      const MusicCatalogCollection(
        id: '41',
        title: 'Mira Sol',
        kind: MusicCatalogCollectionKind.artist,
      ),
    );
    final album = await provider.loadCollection(
      const MusicCatalogCollection(
        id: '42',
        title: 'Aurora Rooms',
        kind: MusicCatalogCollectionKind.album,
      ),
    );
    final playlist = await provider.loadCollection(
      const MusicCatalogCollection(
        id: '43',
        title: 'Night Drive',
        kind: MusicCatalogCollectionKind.playlist,
      ),
    );
    final bytes = await provider.loadArtwork(
      'https://art.example.test/mira.jpg',
    );

    expect(artist.collections.single.title, 'Aurora Rooms');
    expect(artist.collections.single.subtitle, 'Mira Sol · 2026-01-01');
    expect(artist.tracks, isEmpty);
    expect(album.tracks.single.title, 'Window Signal');
    expect(album.tracks.single.artist, 'Mira Sol');
    expect(album.tracks.single.album, 'Aurora Rooms');
    expect(album.tracks.single.streamUrl, 'https://stream.example.test/72.mp3');
    expect(playlist.tracks.single.title, 'Road Signal');
    expect(playlist.tracks.single.album, 'Night Drive');
    expect(bytes, orderedEquals(<int>[1, 2, 3]));
    expect(artworkRequests.single.host, 'art.example.test');

    final artistRequest = requests.first;
    expect(artistRequest.path, '/v3.0/artists/albums/');
    expect(artistRequest.queryParameters['id'], '41');
    expect(artistRequest.queryParameters['limit'], '100');
    expect(artistRequest.queryParameters['imagesize'], '300');
    expect(artistRequest.queryParameters['audioformat'], isNull);
    final albumRequest = requests[1];
    expect(albumRequest.path, '/v3.0/albums/tracks/');
    expect(albumRequest.queryParameters['id'], '42');
    expect(albumRequest.queryParameters['track_type'], isNull);
    final playlistRequest = requests[2];
    expect(playlistRequest.path, '/v3.0/playlists/tracks/');
    expect(playlistRequest.queryParameters['id'], '43');
    expect(playlistRequest.queryParameters['track_type'], 'single albumtrack');
    expect(await provider.loadArtwork('http://art.example.test/unsafe.jpg'), isNull);
  });
}

String _response(List<String> ids) {
  final rows = ids
      .map(
        (id) => '{"id":"$id","name":"Track $id","artist_name":"Artist","album_name":"Album","duration":180,"audio":"https://stream.example.test/$id.mp3"}',
      )
      .join(',');
  return '{"headers":{"status":"success","code":0},"results":[$rows]}';
}

const _artistCatalogResponse = '''
{
  "headers":{"status":"success","code":0,"results_fullcount":"4"},
  "results":[
    {"id":"41","name":"Mira Sol","joindate":"2020-01-01","image":"https://art.example.test/mira.jpg"}
  ]
}
''';

const _albumCatalogResponse = '''
{
  "headers":{"status":"success","code":0,"results_fullcount":2},
  "results":[
    {"id":"42","name":"Aurora Rooms","artist_name":"Mira Sol","releasedate":"2026-01-01","image":"https://art.example.test/aurora.jpg"}
  ]
}
''';

const _playlistCatalogResponse = '''
{
  "headers":{"status":"success","code":0,"results_fullcount":4},
  "results":[
    {"id":"43","name":"Night Drive","user_name":"Mira Sol","creationdate":"2026-02-01"}
  ]
}
''';

const _artistAlbumsResponse = '''
{
  "headers":{"status":"success","code":0},
  "results":[
    {
      "id":"41","name":"Mira Sol","image":"https://art.example.test/mira.jpg",
      "albums":[
        {"id":"42","name":"Aurora Rooms","releasedate":"2026-01-01","image":"https://art.example.test/aurora.jpg"}
      ]
    }
  ]
}
''';

const _albumTracksResponse = '''
{
  "headers":{"status":"success","code":0},
  "results":[
    {
      "id":"42","name":"Aurora Rooms","artist_name":"Mira Sol","image":"https://art.example.test/aurora.jpg",
      "tracks":[
        {"id":"72","name":"Window Signal","duration":200,"audio":"https://stream.example.test/72.mp3"}
      ]
    }
  ]
}
''';

const _playlistTracksResponse = '''
{
  "headers":{"status":"success","code":0},
  "results":[
    {
      "id":"43","name":"Night Drive","user_name":"Mira Sol",
      "tracks":[
        {"id":"73","name":"Road Signal","artist_name":"Mira Sol","duration":190,"audio":"https://stream.example.test/73.mp3"}
      ]
    }
  ]
}
''';
