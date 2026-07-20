import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders all compact chart dimensions and listening-time mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final stats = LibraryStatsSummary(
      trackCount: 4,
      libraryDuration: const Duration(minutes: 16),
      favoriteTrackCount: 1,
      playbackCount: 12,
      uniquePlayedTrackCount: 3,
      estimatedListeningDuration: const Duration(minutes: 48),
      topTracks: <LibraryStatsTrack>[
        LibraryStatsTrack(
          track: Track(id: 'signal', title: 'Signal', artist: 'Mira'),
          playCount: 8,
          estimatedListeningDuration: const Duration(minutes: 32),
        ),
      ],
      topArtists: const <LibraryStatsGroup>[
        LibraryStatsGroup(
          label: 'Mira',
          playCount: 8,
          trackCount: 2,
          estimatedListeningDuration: Duration(minutes: 32),
        ),
      ],
      topAlbums: const <LibraryStatsGroup>[
        LibraryStatsGroup(
          label: 'Dawn',
          playCount: 7,
          trackCount: 2,
          estimatedListeningDuration: Duration(minutes: 28),
        ),
      ],
      topGenres: const <LibraryStatsGroup>[
        LibraryStatsGroup(
          label: 'Ambient',
          playCount: 6,
          trackCount: 3,
          estimatedListeningDuration: Duration(minutes: 24),
        ),
      ],
      topSources: const <LibraryStatsGroup>[
        LibraryStatsGroup(
          label: 'Jellyfin',
          playCount: 5,
          trackCount: 2,
          estimatedListeningDuration: Duration(minutes: 20),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LibraryStatsCharts(stats: stats),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Top tracks chart'), findsOneWidget);
    expect(find.text('Top artists chart'), findsOneWidget);
    expect(find.text('Top albums chart'), findsOneWidget);
    expect(find.text('Top genres chart'), findsOneWidget);
    expect(find.text('Top sources chart'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.schedule_outlined));
    await tester.pumpAndSettle();
    expect(find.text('28m'), findsOneWidget);
    expect(find.text('20m'), findsOneWidget);
    expect(
      tester.widget<SegmentedButton<LibraryStatsChartMetric>>(
        find.byKey(const Key('listening-stats-chart-metric')),
      ).selected,
      <LibraryStatsChartMetric>{LibraryStatsChartMetric.listeningTime},
    );
    expect(tester.takeException(), isNull);
  });
}
