import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/audius_provider.dart';
import 'package:aethertune/src/domain/music_catalog_provider.dart';

void main() {
  test('searches Audius with bounded offset paging', () async {
    Uri? requested;
    final provider = AudiusProvider(
      loader: (uri) async {
        requested = uri;
        return _response(<String>['track_1', 'track_2']);
      },
    );

    final page = await provider.searchPage('electronic', limit: 2);

    expect(requested?.host, 'api.audius.co');
    expect(requested?.path, '/v1/tracks/search');
    expect(requested?.queryParameters['query'], 'electronic');
    expect(requested?.queryParameters['offset'], '0');
    expect(requested?.queryParameters['limit'], '2');
    expect(
      page.tracks.map((track) => track.id),
      <String>['audius:track_1', 'audius:track_2'],
    );
    expect(page.nextCursor, '2');
  });

  test('loads a bounded server-ordered trending list', () async {
    Uri? requested;
    final provider = AudiusProvider(
      loader: (uri) async {
        requested = uri;
        return _response(<String>['trending']);
      },
    );

    final tracks = await provider.fetchTrending(limit: 6);

    expect(requested?.path, '/v1/tracks/trending');
    expect(requested?.queryParameters['limit'], '6');
    expect(tracks.single.id, 'audius:trending');
  });

  test('browses bounded public trending albums and playlists', () async {
    final requests = <Uri>[];
    final provider = AudiusProvider(
      loader: (uri) async {
        requests.add(uri);
        return '''
          {"data":[
            {"id":"album_1","playlist_name":"Open Album","is_album":true,"playlist_contents":[{}],"user":{"name":"Album Artist"},"artwork":{"480x480":"https://art.example.test/album.jpg"}},
            {"id":"playlist_1","playlist_name":"Open Playlist","is_album":false,"playlist_contents":[{},{}],"user":{"handle":"curator"}},
            {"id":"private_1","playlist_name":"Private","is_album":false,"is_private":true},
            {"id":"unlisted_1","playlist_name":"Unlisted","is_album":true,"is_unlisted":true}
          ]}
        ''';
      },
    );

    final albums = await provider.browseCollectionsPage(
      MusicCatalogCollectionKind.album,
      offset: 2,
      limit: 4,
    );
    final playlists = await provider.browseCollectionsPage(
      MusicCatalogCollectionKind.playlist,
      limit: 4,
    );

    expect(requests.first.path, '/v1/playlists/trending');
    expect(requests.first.queryParameters['offset'], '2');
    expect(requests.first.queryParameters['limit'], '4');
    expect(albums.collections.single.title, 'Open Album');
    expect(albums.collections.single.itemCount, 1);
    expect(albums.collections.single.artworkId, 'https://art.example.test/album.jpg');
    expect(albums.hasMore, isTrue);
    expect(albums.nextOffset, 6);
    expect(playlists.collections.single.title, 'Open Playlist');
    expect(playlists.collections.single.subtitle, 'curator');
    expect(playlists.collections.single.itemCount, 2);
  });

  test('loads a bounded public collection detail and filters unavailable tracks',
      () async {
    Uri? requested;
    final provider = AudiusProvider(
      loader: (uri) async {
        requested = uri;
        return '''
          {"data":[
            {"id":"public","title":"Public track"},
            {"id":"gated","title":"Gated track","is_stream_gated":true}
          ]}
        ''';
      },
    );

    final detail = await provider.loadCollection(
      const MusicCatalogCollection(
        id: 'playlist_1',
        title: 'Open Playlist',
        kind: MusicCatalogCollectionKind.playlist,
      ),
    );

    expect(requested?.path, '/v1/playlists/playlist_1/tracks');
    expect(requested?.queryParameters['limit'], '100');
    expect(detail.tracks, hasLength(1));
    expect(detail.tracks.single.album, 'Open Playlist');
  });

  test('loads only validated https Audius collection artwork', () async {
    Uri? requested;
    final provider = AudiusProvider(
      artworkLoader: (uri, headers) async {
        requested = uri;
        expect(headers, isEmpty);
        return Uint8List.fromList(<int>[1, 2, 3]);
      },
    );

    expect(
      await provider.loadArtwork('http://art.example.test/cover.jpg'),
      isNull,
    );
    final artwork = await provider.loadArtwork(
      'https://art.example.test/cover.jpg',
    );

    expect(requested, Uri.parse('https://art.example.test/cover.jpg'));
    expect(artwork, Uint8List.fromList(<int>[1, 2, 3]));
  });

  test('rejects gated, unlisted, malformed, and unsafe artwork records', () {
    final tracks = parseAudiusTracksResponse('''
      {"data":[
        {"id":"public","title":"Public","duration":120,"user":{"name":"Artist"},"artwork":{"480x480":"https://art.example.test/cover.jpg"}},
        {"id":"gated","title":"Gated","is_stream_gated":true},
        {"id":"unlisted","title":"Unlisted","is_unlisted":true},
        {"id":"unsafe","title":"Unsafe","artwork":{"480x480":"http://art.example.test/cover.jpg"}},
        {"id":"bad/id","title":"Ignored"}
      ]}
    ''');

    expect(tracks, hasLength(2));
    expect(tracks.first.artist, 'Artist');
    expect(tracks.first.duration, const Duration(seconds: 120));
    expect(tracks.first.artworkUri, Uri.parse('https://art.example.test/cover.jpg'));
    expect(tracks[1].artworkUri, isNull);
    expect(
      () => parseAudiusTracksResponse('{"data":{}}'),
      throwsFormatException,
    );
  });

  test('advances a full raw page even when policy filters a track', () async {
    final provider = AudiusProvider(
      loader: (_) async => '''
        {"data":[
          {"id":"public","title":"Public"},
          {"id":"gated","title":"Gated","is_stream_gated":true}
        ]}
      ''',
    );

    final page = await provider.searchPage('test', limit: 2);

    expect(page.tracks.map((track) => track.id), <String>['audius:public']);
    expect(page.nextCursor, '2');
  });

  test('resolves only valid Audius track IDs through the documented stream path',
      () async {
    final provider = AudiusProvider();
    final track = parseAudiusTracksResponse(
      '{"data":[{"id":"D7KyD","title":"Track"}]}',
    ).single;

    final stream = await provider.resolveStream(track);

    expect(stream, Uri.parse('https://api.audius.co/v1/tracks/D7KyD/stream'));
    expect(
      await provider.resolveStream(track.copyWith(sourceId: 'local')),
      isNull,
    );
    expect(
      await provider.resolveStream(track.copyWith(externalId: 'bad/id')),
      isNull,
    );
  });
}

String _response(List<String> ids) {
  final rows = ids
      .map(
        (id) =>
            '{"id":"$id","title":"Track $id","duration":180,"user":{"name":"Artist"}}',
      )
      .join(',');
  return '{"data":[$rows]}';
}
