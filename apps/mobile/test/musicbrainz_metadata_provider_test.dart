import 'package:aethertune/src/data/musicbrainz_metadata_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search sends bounded explicit metadata query with identification', () async {
    Uri? requestUri;
    Map<String, String>? requestHeaders;
    final provider = MusicBrainzMetadataProvider(
      loader: (uri, headers) async {
        requestUri = uri;
        requestHeaders = headers;
        return _recordingResponse;
      },
      limiter: MusicBrainzRequestLimiter(),
    );

    final results = await provider.search(
      title: 'Aether Song',
      artist: 'Mira Sol',
      album: 'Night Signal',
      limit: 99,
    );

    expect(requestUri, isNotNull);
    expect(requestUri!.scheme, 'https');
    expect(requestUri!.host, 'musicbrainz.org');
    expect(requestUri!.path, '/ws/2/recording');
    expect(
      requestUri!.queryParameters['query'],
      'recording:"Aether Song" AND artist:"Mira Sol" AND release:"Night Signal"',
    );
    expect(requestUri!.queryParameters['fmt'], 'json');
    expect(requestUri!.queryParameters['limit'], '25');
    expect(requestHeaders!['accept'], 'application/json');
    expect(requestHeaders!['user-agent'], MusicBrainzMetadataProvider.userAgent);
    expect(results.single.title, 'Aether Song');
  });

  test('parser filters malformed and duplicate recordings', () {
    final results = parseMusicBrainzRecordingSearchResponse(
      '''
{
  "recordings": [
    {"id": "not-an-mbid", "title": "Invalid"},
    {"id": "11111111-1111-1111-1111-111111111111", "title": "", "artist-credit": []},
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "title": "Aether Song",
      "artist-credit": [{"name": "Mira Sol"}],
      "releases": [{"title": "Night Signal"}],
      "genres": [{"name": "Ambient"}],
      "length": 215000,
      "score": 99
    },
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "title": "Duplicate"
    },
    {
      "id": "22222222-2222-2222-2222-222222222222",
      "title": "Unknown fields"
    }
  ]
}
''',
      limit: 10,
    );

    expect(results, hasLength(2));
    expect(results.first.artist, 'Mira Sol');
    expect(results.first.album, 'Night Signal');
    expect(results.first.genre, 'Ambient');
    expect(results.first.duration, const Duration(milliseconds: 215000));
    expect(results.last.artist, 'Unknown Artist');
    expect(results.last.album, 'Unknown Album');
  });

  test('serial limiter spaces explicit requests by one second', () async {
    var now = DateTime.utc(2026, 7, 17, 10);
    final delays = <Duration>[];
    final limiter = MusicBrainzRequestLimiter(
      clock: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );
    final provider = MusicBrainzMetadataProvider(
      limiter: limiter,
      loader: (_, _) async => _recordingResponse,
    );

    await provider.search(title: 'First', artist: '', album: '');
    await provider.search(title: 'Second', artist: '', album: '');

    expect(delays, <Duration>[const Duration(seconds: 1)]);
  });
}

const _recordingResponse = '''
{
  "recordings": [
    {
      "id": "11111111-1111-1111-1111-111111111111",
      "title": "Aether Song",
      "artist-credit": [{"name": "Mira Sol"}],
      "releases": [{"title": "Night Signal"}],
      "genres": [{"name": "Ambient"}],
      "length": 215000,
      "score": 99
    }
  ]
}
''';
