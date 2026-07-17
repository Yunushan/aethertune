import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/itunes_podcast_directory.dart';

void main() {
  test('requests and parses bounded public podcast directory results', () async {
    Uri? capturedUri;
    final directory = ItunesPodcastDirectory(
      loader: (uri) async {
        capturedUri = uri;
        return _directoryResponse;
      },
    );

    final results = await directory.search('  science  ', limit: 2);

    expect(capturedUri, isNotNull);
    expect(capturedUri!.scheme, 'https');
    expect(capturedUri!.host, 'itunes.apple.com');
    expect(capturedUri!.path, '/search');
    expect(capturedUri!.queryParameters, <String, String>{
      'term': 'science',
      'media': 'podcast',
      'entity': 'podcast',
      'limit': '2',
      'explicit': 'No',
    });
    expect(results, hasLength(2));
    expect(results.first.title, 'Aether Science');
    expect(results.first.author, 'Open Lab');
    expect(results.first.genre, 'Science');
    expect(results.first.feedUri.toString(), 'https://feeds.example.test/aether');
    expect(results.last.title, 'Signal Room');

    expect(await directory.search('   '), isEmpty);
    await expectLater(directory.search('science', limit: 0), throwsArgumentError);
  });

  test('rejects missing, unsafe, duplicate, and untitled directory feeds', () {
    final results = parseItunesPodcastDirectoryResponse(
      _unsafeDirectoryResponse,
      limit: 20,
    );

    expect(results.map((result) => result.title), <String>['Safe show']);
    expect(
      () => parseItunesPodcastDirectoryResponse('[]', limit: 1),
      throwsFormatException,
    );
  });
}

const _directoryResponse = '''
{
  "resultCount": 4,
  "results": [
    {
      "collectionName": "Aether Science",
      "artistName": "Open Lab",
      "primaryGenreName": "Science",
      "feedUrl": "https://feeds.example.test/aether"
    },
    {
      "collectionName": "Duplicate feed",
      "artistName": "Ignored",
      "feedUrl": "https://feeds.example.test/aether"
    },
    {
      "collectionName": "Signal Room",
      "artistName": "Night Studio",
      "primaryGenreName": "Technology",
      "feedUrl": "https://feeds.example.test/signal"
    }
  ]
}
''';

const _unsafeDirectoryResponse = '''
{
  "results": [
    {"collectionName": "Missing feed"},
    {"collectionName": "File feed", "feedUrl": "file:///private/feed.xml"},
    {"collectionName": "   ", "feedUrl": "https://feeds.example.test/no-title"},
    {"collectionName": "Safe show", "feedUrl": "https://feeds.example.test/safe"},
    {"collectionName": "Duplicate", "feedUrl": "https://feeds.example.test/safe"}
  ]
}
''';
