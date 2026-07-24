import 'package:aethertune/src/data/jamendo_provider.dart';
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
}

String _response(List<String> ids) {
  final rows = ids
      .map(
        (id) => '{"id":"$id","name":"Track $id","artist_name":"Artist","album_name":"Album","duration":180,"audio":"https://stream.example.test/$id.mp3"}',
      )
      .join(',');
  return '{"headers":{"status":"success","code":0},"results":[$rows]}';
}
