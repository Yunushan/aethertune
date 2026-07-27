import 'package:aethertune/src/data/itunes_metadata_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends a bounded explicit song-only metadata query', () async {
    Uri? requestUri;
    Map<String, String>? requestHeaders;
    final provider = ItunesMetadataProvider(
      country: 'TR',
      limiter: _instantLimiter(),
      loader: (uri, headers) async {
        requestUri = uri;
        requestHeaders = headers;
        return _response;
      },
    );

    final page = await provider.searchPage('aether song', limit: 99);

    expect(requestUri, isNotNull);
    expect(requestUri!.scheme, 'https');
    expect(requestUri!.host, 'itunes.apple.com');
    expect(requestUri!.path, '/search');
    expect(
      requestUri!.queryParameters,
      <String, String>{
        'term': 'aether song',
        'country': 'tr',
        'media': 'music',
        'entity': 'song',
        'explicit': 'No',
        'limit': '50',
      },
    );
    expect(requestHeaders!['accept'], 'application/json');
    expect(requestHeaders!['user-agent'], ItunesMetadataProvider.userAgent);
    expect(page.nextCursor, isNull);
    expect(page.totalCount, 1);
    expect(page.tracks.single.id, 'itunes:123456789');
    expect(page.tracks.single.externalId, '123456789');
    expect(page.tracks.single.sourceId, 'itunes-metadata');
    expect(page.tracks.single.isPlayable, isFalse);
    expect(page.tracks.single.artworkUri, isNull);
    expect(page.tracks.single.duration, const Duration(milliseconds: 215000));
    expect(page.tracks.single.year, 2024);
    expect(page.tracks.single.trackNumber, 2);
  });

  test('filters malformed, non-song, and duplicate catalog rows', () {
    final tracks = parseItunesSongSearchResponse(
      '''
{
  "results": [
    {"kind":"song","trackId":"bad","trackName":"Invalid"},
    {"kind":"music-video","trackId":1,"trackName":"Video"},
    {"kind":"song","trackId":123456789,"trackName":"Aether Song","artistName":"Mira Sol","collectionName":"Night Signal","primaryGenreName":"Ambient","trackTimeMillis":215000,"releaseDate":"2024-01-01T00:00:00Z","trackNumber":2},
    {"kind":"song","trackId":123456789,"trackName":"Duplicate"},
    {"kind":"song","trackId":987654321,"trackName":"Unknown fields"}
  ]
}
''',
      limit: 10,
    );

    expect(tracks, hasLength(2));
    expect(tracks.first.artist, 'Mira Sol');
    expect(tracks.first.album, 'Night Signal');
    expect(tracks.first.genre, 'Ambient');
    expect(tracks.last.artist, 'Unknown Artist');
    expect(tracks.last.album, 'Unknown Album');
    expect(tracks.last.genre, 'Unknown Genre');
    expect(tracks.last.duration, Duration.zero);
  });

  test('maps type-ahead and validates storefronts', () async {
    final provider = ItunesMetadataProvider(
      limiter: _instantLimiter(),
      loader: (_, _) async => _response,
    );

    final suggestions = await provider.suggest('aether', limit: 1);

    expect(suggestions.single.value, 'Aether Song');
    expect(suggestions.single.subtitle, 'Mira Sol - Night Signal');
    expect(
      () => ItunesMetadataProvider(country: 'tur'),
      throwsArgumentError,
    );
    expect(
      () => ItunesMetadataProvider(country: '1!'),
      throwsArgumentError,
    );
  });

  test('serial limiter spaces explicit requests by three seconds', () async {
    var now = DateTime.utc(2026, 7, 27, 10);
    final delays = <Duration>[];
    final limiter = ItunesRequestLimiter(
      clock: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );
    final provider = ItunesMetadataProvider(
      limiter: limiter,
      loader: (_, _) async => _response,
    );

    await provider.searchPage('first');
    await provider.searchPage('second');

    expect(delays, <Duration>[ItunesRequestLimiter.minimumInterval]);
  });
}

ItunesRequestLimiter _instantLimiter() {
  return ItunesRequestLimiter(
    delay: (_) async {},
  );
}

const _response = '''
{
  "resultCount": 1,
  "results": [
    {
      "kind": "song",
      "trackId": 123456789,
      "trackName": "Aether Song",
      "artistName": "Mira Sol",
      "collectionName": "Night Signal",
      "primaryGenreName": "Ambient",
      "trackTimeMillis": 215000,
      "releaseDate": "2024-01-01T00:00:00Z",
      "trackNumber": 2,
      "previewUrl": "https://audio.example.test/preview.m4a",
      "artworkUrl100": "https://images.example.test/cover.jpg"
    }
  ]
}
''';
