import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/subsonic_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';

void main() {
  test('searches Subsonic servers and returns metadata-only tracks', () async {
    Uri? capturedUri;
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test/navidrome'),
      username: 'yunus',
      password: 'secret',
      requestLoader: (uri) async {
        capturedUri = uri;
        return _searchResponseJson;
      },
      limit: 3,
    );

    expect(provider.id, startsWith('subsonic-'));
    expect(provider.name, 'Navidrome / Subsonic');
    expect(
      provider.capabilities,
      containsAll(const <MusicSourceCapability>[
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.streamResolution,
        MusicSourceCapability.libraryBrowse,
        MusicSourceCapability.offlineCache,
        MusicSourceCapability.downloads,
        MusicSourceCapability.authentication,
      ]),
    );
    expect(provider.disclosure.networkDomains, <String>[
      'music.example.test',
    ]);
    expect(provider.disclosure.requiresUserCredentials, isTrue);
    expect(provider.disclosure.cachesMedia, isTrue);
    expect(provider.disclosure.supportsDownloads, isTrue);

    final tracks = await provider.search('aether');

    expect(capturedUri, isNotNull);
    expect(capturedUri!.path, '/navidrome/rest/search3.view');
    expect(capturedUri!.queryParameters['u'], 'yunus');
    expect(capturedUri!.queryParameters['p'], 'enc:736563726574');
    expect(capturedUri!.queryParameters['v'], '1.16.1');
    expect(capturedUri!.queryParameters['c'], 'AetherTune');
    expect(capturedUri!.queryParameters['f'], 'json');
    expect(capturedUri!.queryParameters['query'], 'aether');
    expect(capturedUri!.queryParameters['artistCount'], '0');
    expect(capturedUri!.queryParameters['albumCount'], '0');
    expect(capturedUri!.queryParameters['songCount'], '3');
    expect(tracks, hasLength(2));
    expect(tracks.first.title, 'Aether Session');
    expect(tracks.first.artist, 'Open Artist');
    expect(tracks.first.album, 'Self Hosted Album');
    expect(tracks.first.genre, 'Ambient');
    expect(tracks.first.duration, const Duration(seconds: 245));
    expect(tracks.first.sourceId, provider.id);
    expect(tracks.first.externalId, 'song-1');
    expect(tracks.first.streamUrl, isNull);
    expect(tracks.first.artworkUri, isNull);
    expect(
      await provider.resolveStream(tracks.first),
      Uri(
        scheme: 'https',
        host: 'music.example.test',
        path: '/navidrome/rest/stream.view',
        queryParameters: const <String, String>{
          'u': 'yunus',
          'p': 'enc:736563726574',
          'v': '1.16.1',
          'c': 'AetherTune',
          'f': 'json',
          'id': 'song-1',
        },
      ),
    );
  });

  test('redacts reversible password encoding from provider errors', () async {
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test'),
      username: 'demo',
      password: 'pw',
      requestLoader: (uri) async => throw StateError('Request failed: $uri'),
    );

    await expectLater(
      provider.search('aether'),
      throwsA(
        predicate<Object>((error) {
          final message = error.toString();
          return message.contains('Navidrome / Subsonic request failed') &&
              message.contains('[redacted]') &&
              !message.contains('7077') &&
              !message.contains('p=enc%3A7077');
        }),
      ),
    );
  });

  test('handles failed responses and offline policy for user-owned media', () {
    expect(
      () => parseSubsonicSearchResponse(_failedResponseJson),
      throwsA(isA<FormatException>()),
    );

    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test'),
      username: 'demo',
      password: 'pw',
      requestLoader: (_) async => _searchResponseJson,
    );
    final decision = OfflineMediaPolicy(<MusicSourceProvider>[
      provider,
    ]).evaluate(
      const SubsonicSong(
        id: 'song-1',
        title: 'Aether Session',
        artist: 'Open Artist',
        album: 'Self Hosted Album',
        genre: 'Ambient',
        duration: Duration(seconds: 245),
        coverArt: 'cover-1',
        suffix: 'mp3',
      ).toTrack(sourceId: provider.id),
      OfflineMediaAction.cache,
    );

    expect(decision.isAllowed, isTrue);
    expect(decision.providerId, provider.id);
  });

  test('tests credentials through the Subsonic ping endpoint', () async {
    Uri? capturedUri;
    final provider = SubsonicProvider(
      baseUri: Uri.parse('https://music.example.test'),
      username: 'yunus',
      password: 'secret',
      requestLoader: (uri) async {
        capturedUri = uri;
        return '{"subsonic-response":{"status":"ok"}}';
      },
    );

    await provider.testConnection();

    expect(capturedUri!.path, '/rest/ping.view');
    expect(capturedUri!.queryParameters['u'], 'yunus');
    expect(capturedUri!.queryParameters['p'], 'enc:736563726574');
  });
}

const _searchResponseJson = '''
{
  "subsonic-response": {
    "status": "ok",
    "version": "1.16.1",
    "searchResult3": {
      "song": [
        {
          "id": "song-1",
          "title": "Aether Session",
          "artist": "Open Artist",
          "album": "Self Hosted Album",
          "genre": "Ambient",
          "duration": 245,
          "coverArt": "cover-1",
          "suffix": "mp3"
        },
        {
          "id": "song-2",
          "title": "Local Cloud",
          "artist": "Server Artist",
          "album": "Self Hosted Album",
          "duration": 125
        }
      ]
    }
  }
}
''';

const _failedResponseJson = '''
{
  "subsonic-response": {
    "status": "failed",
    "error": {
      "code": 40,
      "message": "Wrong username or password."
    }
  }
}
''';
