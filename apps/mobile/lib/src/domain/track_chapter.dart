final class TrackChapter {
  TrackChapter({required Duration start, required String title})
    : start = _nonNegative(start),
      title = _nonEmptyTitle(title);

  final Duration start;
  final String title;

  Map<String, Object?> toJson() => <String, Object?>{
    'startMs': start.inMilliseconds,
    'title': title,
  };

  static TrackChapter? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final startMs = value['startMs'];
    final title = value['title'];
    if (startMs is! int || title is! String) {
      return null;
    }

    try {
      return TrackChapter(
        start: Duration(milliseconds: startMs),
        title: title,
      );
    } on ArgumentError {
      return null;
    }
  }

  static List<TrackChapter> normalize(
    Iterable<TrackChapter> chapters, {
    Duration maximum = Duration.zero,
  }) {
    final byStart = <int, TrackChapter>{};
    for (final chapter in chapters) {
      if (maximum > Duration.zero && chapter.start >= maximum) {
        continue;
      }
      byStart[chapter.start.inMilliseconds] = chapter;
    }

    final normalized = byStart.values.toList(growable: false)
      ..sort((left, right) => left.start.compareTo(right.start));
    return List<TrackChapter>.unmodifiable(normalized);
  }

  static Duration _nonNegative(Duration value) {
    if (value.isNegative) {
      throw ArgumentError.value(
        value,
        'start',
        'Chapter start cannot be negative.',
      );
    }
    return value;
  }

  static String _nonEmptyTitle(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        value,
        'title',
        'Chapter title cannot be empty.',
      );
    }
    return normalized;
  }
}

List<TrackChapter> parseTrackChapters(
  String source, {
  Duration maximum = Duration.zero,
}) {
  final chapters = <TrackChapter>[];
  final lines = source.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index].trim();
    if (line.isEmpty) {
      continue;
    }

    final match = RegExp(
      r'^(\d{1,3}):([0-5]\d)(?::([0-5]\d))?\s+(.+)$',
    ).firstMatch(line);
    if (match == null) {
      throw FormatException('Line ${index + 1} must start with a timestamp.');
    }

    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    final third = match.group(3);
    final start = third == null
        ? Duration(minutes: first, seconds: second)
        : Duration(hours: first, minutes: second, seconds: int.parse(third));
    if (maximum > Duration.zero && start >= maximum) {
      throw FormatException('Line ${index + 1} starts after the track ends.');
    }

    chapters.add(TrackChapter(start: start, title: match.group(4)!));
  }

  return TrackChapter.normalize(chapters, maximum: maximum);
}

String formatTrackChapters(Iterable<TrackChapter> chapters) {
  return TrackChapter.normalize(chapters)
      .map(
        (chapter) =>
            '${formatTrackChapterTimestamp(chapter.start)} ${chapter.title}',
      )
      .join('\n');
}

String formatTrackChapterTimestamp(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (safe.inHours > 0) {
    return '${safe.inHours}:$minutes:$seconds';
  }
  return '${safe.inMinutes}:$seconds';
}
