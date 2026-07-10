import 'dart:ui' as ui;

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/listening_recap_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders and captures a monthly listening recap PNG', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundaryKey = GlobalKey();
    final recap = _recap(LibraryRecapPeriod.month);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: ListeningRecapCard(recap: recap),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('AetherTune'), findsOneWidget);
    expect(find.text('March 2026'), findsOneWidget);
    expect(find.text('3 hr 25 min'), findsOneWidget);
    expect(find.text('Night Spark'), findsOneWidget);
    expect(find.text('Orion - 7 play(s)'), findsOneWidget);

    final capture = await tester.runAsync<List<int>>(() async {
      final bytes = await captureListeningRecapPng(
        boundaryKey,
        pixelRatio: 1,
      );
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final result = <int>[
        frame.image.width,
        frame.image.height,
        ...bytes.take(8),
      ];
      frame.image.dispose();
      codec.dispose();
      return result;
    });
    expect(capture, isNotNull);
    final captured = capture!;
    expect(
      captured.skip(2),
      orderedEquals(<int>[137, 80, 78, 71, 13, 10, 26, 10]),
    );
    expect(captured.take(2), <int>[
      listeningRecapCardWidth.toInt(),
      listeningRecapCardHeight.toInt(),
    ]);
  });

  test('builds stable recap labels, durations, and PNG names', () {
    final monthly = _recap(LibraryRecapPeriod.month);
    final yearly = LibraryListeningRecap(
      period: LibraryRecapPeriod.year,
      start: DateTime.utc(2026),
      end: DateTime.utc(2027),
      stats: monthly.stats,
    );

    expect(listeningRecapLabel(monthly), 'March 2026');
    expect(listeningRecapPngFileName(monthly), 'aethertune-recap-2026-03.png');
    expect(listeningRecapLabel(yearly), '2026');
    expect(listeningRecapPngFileName(yearly), 'aethertune-recap-2026.png');
    expect(formatListeningRecapDuration(const Duration(minutes: 42)), '42 min');
    expect(formatListeningRecapDuration(const Duration(hours: 2)), '2 hr');
  });

  test('rejects invalid recap capture pixel ratios', () async {
    await expectLater(
      captureListeningRecapPng(GlobalKey(), pixelRatio: 0),
      throwsArgumentError,
    );
  });
}

LibraryListeningRecap _recap(LibraryRecapPeriod period) {
  final track = Track(
    id: 'night-spark',
    title: 'Night Spark',
    artist: 'Orion',
    album: 'Voltage',
    genre: 'Rock',
    duration: const Duration(minutes: 4),
    localPath: '/music/night-spark.mp3',
  );
  final stats = LibraryStatsSummary(
    from: DateTime.utc(2026, 3),
    to: DateTime.utc(2026, 4),
    trackCount: 24,
    libraryDuration: const Duration(hours: 2),
    favoriteTrackCount: 8,
    playbackCount: 42,
    uniquePlayedTrackCount: 18,
    estimatedListeningDuration: const Duration(hours: 3, minutes: 25),
    topTracks: <LibraryStatsTrack>[
      LibraryStatsTrack(
        track: track,
        playCount: 7,
        estimatedListeningDuration: const Duration(minutes: 28),
      ),
    ],
    topArtists: const <LibraryStatsGroup>[
      LibraryStatsGroup(
        label: 'Orion',
        playCount: 12,
        trackCount: 3,
        estimatedListeningDuration: Duration(minutes: 48),
      ),
    ],
    topAlbums: const <LibraryStatsGroup>[
      LibraryStatsGroup(
        label: 'Voltage',
        playCount: 9,
        trackCount: 4,
        estimatedListeningDuration: Duration(minutes: 36),
      ),
    ],
    topGenres: const <LibraryStatsGroup>[
      LibraryStatsGroup(
        label: 'Rock',
        playCount: 16,
        trackCount: 6,
        estimatedListeningDuration: Duration(minutes: 64),
      ),
    ],
  );

  return LibraryListeningRecap(
    period: period,
    start: DateTime.utc(2026, 3),
    end: DateTime.utc(2026, 4),
    stats: stats,
  );
}
