import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/lrclib_lyrics_provider.dart';
import 'package:aethertune/src/domain/lyrics_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('returns persisted cached results without issuing a network request',
      () async {
    final cache = _MemorySearchCache();
    var requests = 0;
    final provider = LrcLibLyricsProvider(
      searchCache: cache,
      responseLoader: (uri, headers) async {
        requests += 1;
        return '[{"id":7,"trackName":"Cached Song","artistName":"Artist","plainLyrics":"Cached text"}]';
      },
    );
    const query = LyricsSearchQuery(
      keywords: 'cached song',
      trackName: 'Cached Song',
      artistName: 'Artist',
    );

    await provider.search(query);
    final cached = await provider.searchOffline(query);

    expect(requests, 1);
    expect(cached.single.trackName, 'Cached Song');
  });

  test('expires cached results after the configured lifetime', () async {
    final cache = _MemorySearchCache();
    final savedAt = DateTime.utc(2026, 7, 14, 10);
    var now = savedAt;
    final provider = LrcLibLyricsProvider(
      searchCache: cache,
      clock: () => now,
      cacheLifetime: const Duration(days: 30),
      responseLoader: (uri, headers) async => _searchResponse,
    );
    const query = LyricsSearchQuery(keywords: 'signal');

    await provider.search(query);
    now = savedAt.add(const Duration(days: 31));

    await expectLater(
      provider.searchOffline(query),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('expired'),
        ),
      ),
    );
  });

  test('clears every cached lyrics search on request', () async {
    final cache = _MemorySearchCache();
    final provider = LrcLibLyricsProvider(
      searchCache: cache,
      responseLoader: (uri, headers) async => _searchResponse,
    );

    await provider.search(const LyricsSearchQuery(keywords: 'signal'));
    await provider.search(const LyricsSearchQuery(keywords: 'other'));
    await provider.clearCachedSearchResults();

    expect(cache.values, isEmpty);
  });

  test('clears persisted cached searches without affecting a new search',
      () async {
    final provider = LrcLibLyricsProvider(
      responseLoader: (uri, headers) async => _searchResponse,
    );
    const firstQuery = LyricsSearchQuery(keywords: 'signal');
    const secondQuery = LyricsSearchQuery(keywords: 'other');

    await provider.search(firstQuery);
    await provider.clearCachedSearchResults();

    await expectLater(provider.searchOffline(firstQuery), throwsStateError);
    await provider.search(secondQuery);
    expect((await provider.searchOffline(secondQuery)).first.externalId, '42');
  });

  test('does not persist malformed provider responses', () async {
    final cache = _MemorySearchCache();
    final provider = LrcLibLyricsProvider(
      searchCache: cache,
      responseLoader: (uri, headers) async => '{}',
    );
    const query = LyricsSearchQuery(keywords: 'broken');

    await expectLater(provider.search(query), throwsA(isA<FormatException>()));
    expect(cache.values, isEmpty);
  });
  test('search uses the documented endpoint, disclosure, and user agent', () async {
    Uri? capturedUri;
    Map<String, String>? capturedHeaders;
    final provider = LrcLibLyricsProvider(
      baseUri: Uri.parse('https://lyrics.example.test/base'),
      responseLoader: (uri, headers) async {
        capturedUri = uri;
        capturedHeaders = headers;
        return _searchResponse;
      },
    );

    final results = await provider.search(
      const LyricsSearchQuery(
        keywords: 'Signal Mira',
        trackName: 'Signal',
        artistName: 'Mira',
        albumName: 'Dawn',
        duration: Duration(seconds: 180),
      ),
    );

    expect(capturedUri!.path, '/base/api/search');
    expect(capturedUri!.queryParameters, <String, String>{
      'q': 'Signal Mira',
    });
    expect(capturedHeaders![HttpHeaders.acceptHeader], 'application/json');
    expect(
      capturedHeaders![HttpHeaders.userAgentHeader],
      LrcLibLyricsProvider.userAgent,
    );
    expect(provider.disclosure.networkDomains, <String>['lyrics.example.test']);
    expect(provider.disclosure.cachesMetadata, isTrue);
    expect(provider.disclosure.requiresUserCredentials, isFalse);
    expect(provider.disclosure.dataSent.single, contains('track title'));

    expect(results.map((result) => result.externalId), <String>['42', '7']);
    expect(results.first.trackName, 'Signal');
    expect(results.first.hasSyncedLyrics, isTrue);
    expect(results.first.preferredLyrics, startsWith('[00:01.00]'));
    expect(results.first.duration, const Duration(milliseconds: 180400));
    expect(
      results.first.sourceUri,
      Uri.parse('https://lyrics.example.test/base/api/get/42'),
    );
  });

  test('field search omits unknown metadata and parser deduplicates IDs', () async {
    Uri? capturedUri;
    final provider = LrcLibLyricsProvider(
      responseLoader: (uri, headers) async {
        capturedUri = uri;
        return _searchResponse;
      },
    );

    final results = await provider.search(
      const LyricsSearchQuery(
        trackName: 'Signal',
        artistName: 'Unknown Artist',
        albumName: 'Unknown Album',
      ),
    );

    expect(capturedUri!.queryParameters, <String, String>{
      'track_name': 'Signal',
    });
    expect(results, hasLength(2));
    expect(results.last.instrumental, isTrue);
    expect(results.last.isSelectable, isFalse);
  });

  test('rejects empty searches and malformed response shapes', () async {
    final provider = LrcLibLyricsProvider(
      responseLoader: (uri, headers) async => '{}',
    );

    expect(
      provider.search(const LyricsSearchQuery()),
      throwsArgumentError,
    );
    expect(
      provider.search(const LyricsSearchQuery(keywords: 'signal')),
      throwsA(isA<FormatException>()),
    );
  });
}

class _MemorySearchCache implements LrcLibSearchCache {
  final Map<String, LrcLibCachedSearch> values =
      <String, LrcLibCachedSearch>{};

  @override
  Future<LrcLibCachedSearch?> read(String key) async => values[key];

  @override
  Future<void> write(String key, LrcLibCachedSearch entry) async {
    values[key] = entry;
  }

  @override
  Future<void> clear() async => values.clear();
}

const _searchResponse = '''
[
  {
    "id": 7,
    "trackName": "Other Signal",
    "artistName": "Someone Else",
    "albumName": "Elsewhere",
    "duration": 205,
    "instrumental": true,
    "plainLyrics": null,
    "syncedLyrics": null
  },
  {
    "id": 42,
    "trackName": "Signal",
    "artistName": "Mira",
    "albumName": "Dawn",
    "duration": 180.4,
    "instrumental": false,
    "plainLyrics": "First line\\nSecond line",
    "syncedLyrics": "[00:01.00]First line\\n[00:04.20]Second line"
  },
  {
    "id": 42,
    "trackName": "Duplicate",
    "artistName": "Mira",
    "albumName": "Dawn",
    "duration": 180,
    "instrumental": false,
    "plainLyrics": "duplicate",
    "syncedLyrics": null
  }
]
''';
