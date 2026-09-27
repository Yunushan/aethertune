import 'package:flutter/material.dart';

import '../data/library_store.dart';
import 'widgets/listening_stats_bar_chart.dart';

enum LibraryStatsChartMetric { plays, listeningTime }

class LibraryStatsCharts extends StatefulWidget {
  const LibraryStatsCharts({super.key, required this.stats});

  final LibraryStatsSummary stats;

  @override
  State<LibraryStatsCharts> createState() => _LibraryStatsChartsState();
}

class _LibraryStatsChartsState extends State<LibraryStatsCharts> {
  var _metric = LibraryStatsChartMetric.plays;

  @override
  Widget build(BuildContext context) {
    final stats = widget.stats;
    final trackData = stats.topTracks
        .map(
          (trackStats) => ListeningStatsBarDatum(
            label: trackStats.track.title,
            value: _valueFor(
              playCount: trackStats.playCount,
              listeningDuration: trackStats.estimatedListeningDuration,
            ),
            valueLabel: _labelFor(
              playCount: trackStats.playCount,
              listeningDuration: trackStats.estimatedListeningDuration,
            ),
          ),
        )
        .toList(growable: false);
    final artistData = stats.topArtists
        .map(
          (artistStats) => ListeningStatsBarDatum(
            label: artistStats.label,
            value: _valueFor(
              playCount: artistStats.playCount,
              listeningDuration: artistStats.estimatedListeningDuration,
            ),
            valueLabel: _labelFor(
              playCount: artistStats.playCount,
              listeningDuration: artistStats.estimatedListeningDuration,
            ),
          ),
        )
        .toList(growable: false);
    final albumData = stats.topAlbums
        .map(
          (albumStats) => ListeningStatsBarDatum(
            label: albumStats.label,
            value: _valueFor(
              playCount: albumStats.playCount,
              listeningDuration: albumStats.estimatedListeningDuration,
            ),
            valueLabel: _labelFor(
              playCount: albumStats.playCount,
              listeningDuration: albumStats.estimatedListeningDuration,
            ),
          ),
        )
        .toList(growable: false);
    final genreData = stats.topGenres
        .map(
          (genreStats) => ListeningStatsBarDatum(
            label: genreStats.label,
            value: _valueFor(
              playCount: genreStats.playCount,
              listeningDuration: genreStats.estimatedListeningDuration,
            ),
            valueLabel: _labelFor(
              playCount: genreStats.playCount,
              listeningDuration: genreStats.estimatedListeningDuration,
            ),
          ),
        )
        .toList(growable: false);
    final sourceData = stats.topSources
        .map(
          (sourceStats) => ListeningStatsBarDatum(
            label: sourceStats.label,
            value: _valueFor(
              playCount: sourceStats.playCount,
              listeningDuration: sourceStats.estimatedListeningDuration,
            ),
            valueLabel: _labelFor(
              playCount: sourceStats.playCount,
              listeningDuration: sourceStats.estimatedListeningDuration,
            ),
          ),
        )
        .toList(growable: false);
    final folderData = stats.topFolders
        .map(
          (folderStats) => ListeningStatsBarDatum(
            label: folderStats.label,
            value: _valueFor(
              playCount: folderStats.playCount,
              listeningDuration: folderStats.estimatedListeningDuration,
            ),
            valueLabel: _labelFor(
              playCount: folderStats.playCount,
              listeningDuration: folderStats.estimatedListeningDuration,
            ),
          ),
        )
        .toList(growable: false);
    if (trackData.isEmpty &&
        artistData.isEmpty &&
        albumData.isEmpty &&
        genreData.isEmpty &&
        sourceData.isEmpty &&
        folderData.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final charts = <Widget>[
      if (trackData.isNotEmpty)
        ListeningStatsBarChart(
          title: 'Top tracks chart',
          icon: Icons.music_note_outlined,
          color: colorScheme.primary,
          data: trackData,
        ),
      if (artistData.isNotEmpty)
        ListeningStatsBarChart(
          title: 'Top artists chart',
          icon: Icons.person_outline,
          color: colorScheme.tertiary,
          data: artistData,
        ),
      if (albumData.isNotEmpty)
        ListeningStatsBarChart(
          title: 'Top albums chart',
          icon: Icons.album_outlined,
          color: colorScheme.secondary,
          data: albumData,
        ),
      if (genreData.isNotEmpty)
        ListeningStatsBarChart(
          title: 'Top genres chart',
          icon: Icons.category_outlined,
          color: colorScheme.error,
          data: genreData,
        ),
      if (sourceData.isNotEmpty)
        ListeningStatsBarChart(
          title: 'Top sources chart',
          icon: Icons.source_outlined,
          color: colorScheme.primaryContainer,
          data: sourceData,
        ),
      if (folderData.isNotEmpty)
        ListeningStatsBarChart(
          title: 'Top folders chart',
          icon: Icons.folder_outlined,
          color: colorScheme.secondaryContainer,
          data: folderData,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SegmentedButton<LibraryStatsChartMetric>(
          key: const Key('listening-stats-chart-metric'),
          segments: const <ButtonSegment<LibraryStatsChartMetric>>[
            ButtonSegment<LibraryStatsChartMetric>(
              value: LibraryStatsChartMetric.plays,
              icon: Icon(Icons.play_arrow_outlined),
              tooltip: 'Play count',
            ),
            ButtonSegment<LibraryStatsChartMetric>(
              value: LibraryStatsChartMetric.listeningTime,
              icon: Icon(Icons.schedule_outlined),
              tooltip: 'Listening time',
            ),
          ],
          selected: <LibraryStatsChartMetric>{_metric},
          onSelectionChanged: (selection) {
            setState(() => _metric = selection.first);
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (charts.length == 1) {
              return charts.single;
            }
            if (constraints.maxWidth >= 720) {
              final chartWidth = (constraints.maxWidth - 28) / 2;
              return Wrap(
                spacing: 28,
                runSpacing: 20,
                children: <Widget>[
                  for (final chart in charts)
                    SizedBox(width: chartWidth, child: chart),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (
                  var index = 0;
                  index < charts.length;
                  index += 1
                ) ...<Widget>[
                  charts[index],
                  if (index != charts.length - 1) const SizedBox(height: 20),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  int _valueFor({
    required int playCount,
    required Duration listeningDuration,
  }) => switch (_metric) {
    LibraryStatsChartMetric.plays => playCount,
    LibraryStatsChartMetric.listeningTime => listeningDuration.inSeconds,
  };

  String _labelFor({
    required int playCount,
    required Duration listeningDuration,
  }) => switch (_metric) {
    LibraryStatsChartMetric.plays => '$playCount play(s)',
    LibraryStatsChartMetric.listeningTime => formatLibraryStatsDuration(
      listeningDuration,
    ),
  };
}

String formatLibraryStatsDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '0m';
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0 && minutes > 0) {
    return '${hours}h ${minutes}m';
  }
  if (hours > 0) {
    return '${hours}h';
  }

  return '${duration.inMinutes}m';
}
