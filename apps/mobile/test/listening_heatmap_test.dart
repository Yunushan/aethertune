import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/widgets/listening_heatmap.dart';

void main() {
  testWidgets('renders bounded daily cells across calendar weeks', (
    tester,
  ) async {
    final days = <LibraryListeningHeatmapDay>[
      LibraryListeningHeatmapDay(
        day: DateTime(2026, 7, 5),
        playbackCount: 2,
        estimatedListeningDuration: const Duration(minutes: 10),
      ),
      LibraryListeningHeatmapDay(
        day: DateTime(2026, 7, 6),
        playbackCount: 0,
        estimatedListeningDuration: Duration.zero,
      ),
      LibraryListeningHeatmapDay(
        day: DateTime(2026, 7, 7),
        playbackCount: 1,
        estimatedListeningDuration: const Duration(minutes: 4),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListeningHeatmap(days: days)),
      ),
    );

    expect(find.byKey(const Key('listening-heatmap-scroll')), findsOneWidget);
    expect(
      find.byKey(const Key('listening-heatmap-2026-07-05')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('listening-heatmap-2026-07-06')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('listening-heatmap-2026-07-07')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('2026-07-05: 2 plays, 10m estimated listening'),
      findsOneWidget,
    );
  });

  testWidgets('hides the heatmap when no calendar days are provided', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ListeningHeatmap(days: <LibraryListeningHeatmapDay>[]),
        ),
      ),
    );

    expect(find.byKey(const Key('listening-heatmap-scroll')), findsNothing);
  });
}
