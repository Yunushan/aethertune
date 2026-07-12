import 'package:flutter/material.dart';

import '../../data/library_store.dart';

class ListeningHeatmap extends StatelessWidget {
  const ListeningHeatmap({required this.days, super.key});

  final List<LibraryListeningHeatmapDay> days;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) {
      return const SizedBox.shrink();
    }

    final entries = <DateTime, LibraryListeningHeatmapDay>{
      for (final day in days) _calendarDay(day.day): day,
    };
    final firstDay = _calendarDay(days.first.day);
    final lastDay = _calendarDay(days.last.day);
    final maximumPlays = days.fold<int>(
      0,
      (maximum, day) =>
          day.playbackCount > maximum ? day.playbackCount : maximum,
    );
    final weeks = _heatmapWeeks(firstDay, lastDay, entries);

    return Semantics(
      label: 'Listening calendar with ${days.length} days',
      child: SingleChildScrollView(
        key: const Key('listening-heatmap-scroll'),
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final week in weeks)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 2),
                child: Column(
                  children: <Widget>[
                    for (final day in week)
                      _ListeningHeatmapCell(
                        day: day,
                        maximumPlays: maximumPlays,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ListeningHeatmapCell extends StatelessWidget {
  const _ListeningHeatmapCell({required this.day, required this.maximumPlays});

  final LibraryListeningHeatmapDay? day;
  final int maximumPlays;

  @override
  Widget build(BuildContext context) {
    const cellSize = 14.0;
    final value = day;
    if (value == null) {
      return const SizedBox(width: cellSize, height: cellSize + 2);
    }

    final intensity = maximumPlays <= 0
        ? 0.0
        : value.playbackCount / maximumPlays;
    final colorScheme = Theme.of(context).colorScheme;
    final color = Color.lerp(
      colorScheme.surfaceContainerHighest,
      colorScheme.primary,
      intensity,
    )!;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 2),
      child: Semantics(
        label: _heatmapDayLabel(value),
        child: Container(
          key: Key('listening-heatmap-${_dayKey(value.day)}'),
          width: cellSize,
          height: cellSize,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

List<List<LibraryListeningHeatmapDay?>> _heatmapWeeks(
  DateTime firstDay,
  DateTime lastDay,
  Map<DateTime, LibraryListeningHeatmapDay> entries,
) {
  final firstWeekStart = DateTime(
    firstDay.year,
    firstDay.month,
    firstDay.day - firstDay.weekday + DateTime.monday,
  );
  final weeks = <List<LibraryListeningHeatmapDay?>>[];
  for (
    var weekStart = firstWeekStart;
    !weekStart.isAfter(lastDay);
    weekStart = DateTime(weekStart.year, weekStart.month, weekStart.day + 7)
  ) {
    weeks.add(<LibraryListeningHeatmapDay?>[
      for (var offset = 0; offset < 7; offset += 1)
        entries[DateTime(
          weekStart.year,
          weekStart.month,
          weekStart.day + offset,
        )],
    ]);
  }
  return weeks;
}

DateTime _calendarDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _heatmapDayLabel(LibraryListeningHeatmapDay day) {
  final date = _dayKey(day.day);
  final playLabel = day.playbackCount == 1 ? 'play' : 'plays';
  return '$date: ${day.playbackCount} $playLabel, '
      '${_formatDuration(day.estimatedListeningDuration)} estimated listening';
}

String _dayKey(DateTime day) {
  final month = day.month.toString().padLeft(2, '0');
  final date = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$date';
}

String _formatDuration(Duration duration) {
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }
  return '${duration.inMinutes}m';
}
