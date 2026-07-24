import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/jamendo_chart_cache.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores bounded metadata without a Jamendo stream URL', () async {
    final cache = SharedPreferencesJamendoChartCache(
      clock: () => DateTime.utc(2026, 7, 24, 12),
    );
    final sourceTracks = List<Track>.generate(
      7,
      (index) => Track(
        id: 'jamendo:${index + 1}',
        title: 'Public track ${index + 1}',
        artist: 'Open artist',
        duration: const Duration(minutes: 3),
        artworkUri: Uri.parse('https://images.example.test/${index + 1}.jpg'),
        streamUrl: 'https://stream.example.test/${index + 1}.mp3',
        sourceId: 'jamendo',
        externalId: '${index + 1}',
        addedAt: DateTime.utc(2026, 7, 24),
      ),
    );

    await cache.write('popular.all', sourceTracks);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('aethertune.jamendo.chart.v1.popular.all')!;
    expect(raw, isNot(contains('stream.example.test')));
    final cached = await cache.read('popular.all');
    expect(cached, isNotNull);
    expect(cached!.savedAt, DateTime.utc(2026, 7, 24, 12));
    expect(cached.tracks, hasLength(6));
    expect(cached.tracks.every((track) => track.streamUrl == null), isTrue);
    expect(cached.tracks.first.externalId, '1');
  });

  test('rejects unsafe or malformed persisted chart records', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'aethertune.jamendo.chart.v1.popular.all': jsonEncode(<String, Object?>{
        'savedAtMilliseconds': DateTime.utc(2026, 7, 24).millisecondsSinceEpoch,
        'tracks': <Object?>[
          <String, Object?>{
            'id': 'jamendo:7',
            'title': 'Unsafe cached stream',
            'durationMs': 180000,
            'sourceId': 'jamendo',
            'externalId': '7',
            'streamUrl': 'https://stream.example.test/7.mp3',
          },
        ],
      }),
    });

    final cache = SharedPreferencesJamendoChartCache();
    expect(await cache.read('popular.all'), isNull);
  });

  test('uses separate normalized keys and expires charts after one day', () {
    expect(
      jamendoChartCacheKey(genre: ' JAZZ ', lyricsLanguageCode: ' TR '),
      'jazz.tr',
    );
    expect(jamendoChartCacheKey(), 'popular.all');

    final cached = JamendoCachedChart(
      tracks: <Track>[],
      savedAt: DateTime.utc(2026, 7, 23, 12),
    );
    expect(cached.isExpired(DateTime.utc(2026, 7, 24, 12)), isFalse);
    expect(cached.isExpired(DateTime.utc(2026, 7, 24, 12, 0, 1)), isTrue);
  });

  test('clears every chart entry without touching unrelated preferences', () async {
    final cache = SharedPreferencesJamendoChartCache();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('aethertune.jamendo.chart.v1.popular.all', '{}');
    await prefs.setString('aethertune.jamendo.chart.v1.jazz.tr', '{}');
    await prefs.setString('aethertune.theme.v1', 'dark');

    await cache.clear();

    expect(prefs.getString('aethertune.jamendo.chart.v1.popular.all'), isNull);
    expect(prefs.getString('aethertune.jamendo.chart.v1.jazz.tr'), isNull);
    expect(prefs.getString('aethertune.theme.v1'), 'dark');
  });
}
