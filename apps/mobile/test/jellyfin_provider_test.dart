import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/jellyfin_provider.dart';
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
