import 'package:aethertune/src/data/lyrics_batch_matcher.dart';
import 'package:aethertune/src/domain/lyrics_provider.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selects exactly one compatible title, artist, and duration match', () async {
    final matcher = LyricsBatchMatcher(
      _FakeLyricsProvider(<String, List<LyricsSearchResult>>{
        'Signal': <LyricsSearchResult>[_result('signal')],
      }),
    );

    final report = await matcher.match(<Track>[_track('signal')]);

    expect(report.matches.single.result?.externalId, 'signal');
    expect(report.unmatchedCount, 0);
    expect(report.failedCount, 0);
  });

  test('rejects ambiguous, duration-mismatched, and unknown-artist matches',
      () async {
    final provider = _FakeLyricsProvider(<String, List<LyricsSearchResult>>{
      'Signal': <LyricsSearchResult>[_result('first'), _result('second')],
      'Short Signal': <LyricsSearchResult>[
        _result('short', duration: const Duration(minutes: 2)),
      ],
    });
    final matcher = LyricsBatchMatcher(provider);

    final report = await matcher.match(<Track>[
      _track('ambiguous'),
      _track('duration', title: 'Short Signal'),
      _track('unknown', artist: 'Unknown Artist'),
    ]);

    expect(report.matches, isEmpty);
    expect(report.unmatchedCount, 3);
    expect(provider.queries, hasLength(2));
  });

  test('caps consented batch queries and reports provider failures', () async {
    final provider = _FakeLyricsProvider(
      <String, List<LyricsSearchResult>>{},
      failingTitles: <String>{'Broken'},
    );
    final matcher = LyricsBatchMatcher(provider);
    final tracks = <Track>[
      _track('broken', title: 'Broken'),
      for (var index = 0; index < LyricsBatchMatcher.maxTracksPerBatch + 4; index++)
        _track('track-$index', title: 'Track $index'),
    ];

    final report = await matcher.match(tracks);

    expect(report.wasLimited, isTrue);
    expect(provider.queries, hasLength(LyricsBatchMatcher.maxTracksPerBatch));
    expect(report.failedCount, 1);
  });
}

Track _track(
  String id, {
  String title = 'Signal',
  String artist = 'Mira',
}) => Track(
  id: id,
  title: title,
  artist: artist,
  album: 'Dawn',
  duration: const Duration(minutes: 3),
);

LyricsSearchResult _result(
  String id, {
  Duration duration = const Duration(minutes: 3),
}) => LyricsSearchResult(
  providerId: 'test',
  providerName: 'Test lyrics',
  externalId: id,
  trackName: id == 'short' ? 'Short Signal' : 'Signal',
  artistName: 'Mira',
  albumName: 'Dawn',
  duration: duration,
  instrumental: false,
  plainLyrics: 'Line one',
  syncedLyrics: '',
  sourceUri: Uri.parse('https://lyrics.example.test/$id'),
);

final class _FakeLyricsProvider implements LyricsProvider {
  _FakeLyricsProvider(this.resultsByTitle, {Set<String>? failingTitles})
    : _failingTitles = failingTitles ?? <String>{};

  final Map<String, List<LyricsSearchResult>> resultsByTitle;
  final Set<String> _failingTitles;
  final List<LyricsSearchQuery> queries = <LyricsSearchQuery>[];

  @override
  String get id => 'test';

  @override
  String get name => 'Test lyrics';

  @override
  String get description => 'Test provider.';

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure();

  @override
  Future<List<LyricsSearchResult>> search(LyricsSearchQuery query) async {
    queries.add(query);
    if (_failingTitles.contains(query.trackName)) {
      throw StateError('provider unavailable');
    }
    return resultsByTitle[query.trackName] ?? const <LyricsSearchResult>[];
  }
}
