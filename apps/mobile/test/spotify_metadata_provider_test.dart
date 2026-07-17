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
}
