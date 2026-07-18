import 'track_chapter.dart';

final class TrackSkipSegment {
  static const minDuration = Duration(milliseconds: 500);
  static const maxSegments = 20;
  static const maxLabelLength = 80;

  TrackSkipSegment({
    required Duration start,
    required Duration end,
    String label = '',
  }) : start = _nonNegative(start, 'start'),
       end = _nonNegative(end, 'end'),
       label = _normalizeLabel(label) {
    if (this.end - this.start < minDuration) {
      throw ArgumentError.value(
        end,
        'end',
        'Skip segment must be at least 0.5 seconds.',
      );
    }
  }

  final Duration start;
  final Duration end;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{
    'startMs': start.inMilliseconds,
    'endMs': end.inMilliseconds,
    'label': label,
  };

  static TrackSkipSegment? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final startMs = value['startMs'];
    final endMs = value['endMs'];
    if (startMs is! int || endMs is! int) {
      return null;
    }
    try {
      return TrackSkipSegment(
        start: Duration(milliseconds: startMs),
        end: Duration(milliseconds: endMs),
        label: value['label'] is String ? value['label'] as String : '',
      );
    } on ArgumentError {
      return null;
    }
  }

  static List<TrackSkipSegment> normalize(
    Iterable<TrackSkipSegment> segments, {
    Duration maximum = Duration.zero,
  }) {
    final candidates = <TrackSkipSegment>[];
    for (final segment in segments) {
      if (maximum > Duration.zero && segment.start >= maximum) {
        continue;
      }
      final end = maximum > Duration.zero && segment.end > maximum
          ? maximum
          : segment.end;
      if (end - segment.start < minDuration) {
        continue;
      }
      candidates.add(
        TrackSkipSegment(start: segment.start, end: end, label: segment.label),
      );
    }
    candidates.sort((left, right) => left.start.compareTo(right.start));
    final normalized = <TrackSkipSegment>[];
    for (final segment in candidates) {
      if (normalized.isNotEmpty && segment.start < normalized.last.end) {
        continue;
      }
      normalized.add(segment);
      if (normalized.length == maxSegments) {
        break;
      }
    }
    return List<TrackSkipSegment>.unmodifiable(normalized);
  }

  static Duration _nonNegative(Duration value, String name) {
    if (value.isNegative) {
      throw ArgumentError.value(
        value,
        name,
        'Skip segment position cannot be negative.',
      );
    }
    return value;
  }

  static String _normalizeLabel(String value) {
    final normalized = value.trim();
    if (normalized.length <= maxLabelLength) {
      return normalized;
    }
    return normalized.substring(0, maxLabelLength);
  }
}

List<TrackSkipSegment> parseTrackSkipSegments(
  String source, {
  Duration maximum = Duration.zero,
}) {
  final segments = <TrackSkipSegment>[];
  final lines = source.split(RegExp(r'\r?\n'));
  final range = RegExp(
    r'^(\d{1,3}:[0-5]\d(?::[0-5]\d)?)\s*-\s*(\d{1,3}:[0-5]\d(?::[0-5]\d)?)(?:\s+(.+))?$',
  );
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index].trim();
    if (line.isEmpty) {
      continue;
    }
    final match = range.firstMatch(line);
    if (match == null) {
      throw FormatException('Line ${index + 1} must use start-end timestamps.');
    }
    final start = _parseSkipTimestamp(match.group(1)!);
    final end = _parseSkipTimestamp(match.group(2)!);
    if (maximum > Duration.zero && end > maximum) {
      throw FormatException('Line ${index + 1} ends after the track ends.');
    }
    try {
      segments.add(
        TrackSkipSegment(start: start, end: end, label: match.group(3) ?? ''),
      );
    } on ArgumentError catch (error) {
      throw FormatException('Line ${index + 1}: ${error.message}');
    }
  }
  final normalized = TrackSkipSegment.normalize(segments, maximum: maximum);
  if (normalized.length != segments.length) {
    throw const FormatException(
      'Skip segments cannot overlap or share a start time.',
    );
  }
  return normalized;
}

String formatTrackSkipSegments(Iterable<TrackSkipSegment> segments) {
  return TrackSkipSegment.normalize(segments)
      .map(
        (segment) =>
            '${formatTrackChapterTimestamp(segment.start)}-${formatTrackChapterTimestamp(segment.end)}${segment.label.isEmpty ? '' : ' ${segment.label}'}',
      )
      .join('\n');
}

Duration _parseSkipTimestamp(String value) {
  final parts = value.split(':').map(int.parse).toList(growable: false);
  return parts.length == 2
      ? Duration(minutes: parts[0], seconds: parts[1])
      : Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
}
