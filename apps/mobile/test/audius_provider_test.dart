import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/audius_provider.dart';

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
