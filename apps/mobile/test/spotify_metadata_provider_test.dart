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

  test('returns bounded official Spotify track suggestions', () async {
    Uri? requestUri;
    String? requestToken;
    final provider = SpotifyMetadataProvider(
      accessTokenReader: () async => 'access-token',
      searchLoader: (uri, token) async {
        requestUri = uri;
        requestToken = token;
        return '''
          {"tracks": {"offset": 0, "total": 3, "items": [
            {"id":"one","name":"Aether","artists":[{"name":"Mira"}],"album":{"name":"Signals"}},
            {"id":"two","name":"Aether","artists":[{"name":"Orbit"}],"album":{"name":"Other"}},
            {"id":"three","name":"Beyond","artists":[],"album":{}}
          ]}}
        ''';
      },
    );

    final suggestions = await provider.suggest('  aether  ', limit: 1);

    expect(requestToken, 'access-token');
    expect(requestUri!.queryParameters['q'], 'aether');
    expect(requestUri!.queryParameters['type'], 'track');
    expect(requestUri!.queryParameters['limit'], '1');
    expect(requestUri!.queryParameters['offset'], '0');
    expect(
      provider.capabilities,
      contains(MusicSourceCapability.searchSuggestions),
    );
    expect(suggestions, hasLength(1));
    expect(suggestions.single.value, 'Aether');
    expect(suggestions.single.kind, MusicSourceSearchSuggestionKind.track);
    expect(suggestions.single.subtitle, 'Mira - Signals');
    expect(await provider.suggest('   '), isEmpty);
    await expectLater(provider.suggest('aether', limit: 0), throwsArgumentError);
  });
}
