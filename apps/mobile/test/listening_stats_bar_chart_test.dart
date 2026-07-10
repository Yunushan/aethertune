import 'package:aethertune/src/ui/widgets/listening_stats_bar_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('normalizes listening bars and fits a compact viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child: ListeningStatsBarChart(
              title: 'Top tracks chart',
              icon: Icons.music_note_outlined,
              color: Colors.teal,
              data: <ListeningStatsBarDatum>[
                ListeningStatsBarDatum(
                  label: 'Night Spark',
                  value: 10,
                  valueLabel: '10 play(s)',
                ),
                ListeningStatsBarDatum(
                  label: 'A very long track title that must stay contained',
                  value: 5,
                  valueLabel: '5 play(s)',
                ),
                ListeningStatsBarDatum(
                  label: 'Quiet Signal',
                  value: 2,
                  valueLabel: '2 play(s)',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Top tracks chart'), findsOneWidget);
    expect(find.text('Night Spark'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((indicator) => indicator.value),
      <double>[1, 0.5, 0.2],
    );
  });

  testWidgets('hides a listening chart with no positive data', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ListeningStatsBarChart(
          title: 'Empty chart',
          icon: Icons.bar_chart,
          color: Colors.amber,
          data: <ListeningStatsBarDatum>[
            ListeningStatsBarDatum(
              label: 'Unplayed',
              value: 0,
              valueLabel: '0 play(s)',
            ),
          ],
        ),
      ),
    );

    expect(find.text('Empty chart'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
