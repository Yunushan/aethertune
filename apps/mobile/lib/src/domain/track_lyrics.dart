class SyncedLyricLine {
  const SyncedLyricLine({
    required this.timestamp,
    required this.text,
  });

  final Duration timestamp;
  final String text;
}

/// User-managed plain-text or LRC lyrics attached to one library track.
class TrackLyrics {
  TrackLyrics({
    required this.trackId,
    required this.plainText,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String trackId;
  final String plainText;
  final DateTime updatedAt;

  bool get isEmpty => plainText.trim().isEmpty;
  List<SyncedLyricLine> get syncedLines => parseSyncedLyricLines(plainText);
  bool get hasSyncedLines => syncedLines.isNotEmpty;

  TrackLyrics copyWith({
    String? trackId,
    String? plainText,
    DateTime? updatedAt,
  }) {
    return TrackLyrics(
      trackId: trackId ?? this.trackId,
      plainText: plainText ?? this.plainText,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'trackId': trackId,
      'plainText': plainText,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TrackLyrics.fromJson(Map<String, Object?> json) {
    return TrackLyrics(
      trackId: json['trackId'] as String,
      plainText: json['plainText'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

List<SyncedLyricLine> parseSyncedLyricLines(String input) {
  final indexedLines = <_IndexedSyncedLyricLine>[];
  var order = 0;

  for (final rawLine in input.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }

    final timestamps = <Duration>[];
    var textStart = 0;
    for (final match in _lrcTagPattern.allMatches(line)) {
      if (match.start != textStart) {
        break;
      }

      final tagValue = match.group(1);
      if (tagValue != null) {
        final timestamp = _parseLrcTimestamp(tagValue);
        if (timestamp != null) {
          timestamps.add(timestamp);
        }
      }
      textStart = match.end;
    }

    if (timestamps.isEmpty) {
      continue;
    }

    final text = line.substring(textStart).trim();
    if (text.isEmpty) {
      continue;
    }

    for (final timestamp in timestamps) {
      indexedLines.add(
        _IndexedSyncedLyricLine(
          line: SyncedLyricLine(timestamp: timestamp, text: text),
          order: order,
        ),
      );
      order += 1;
    }
  }

  indexedLines.sort((a, b) {
    final byTimestamp = a.line.timestamp.compareTo(b.line.timestamp);
    return byTimestamp == 0 ? a.order.compareTo(b.order) : byTimestamp;
  });

  return indexedLines.map((entry) => entry.line).toList(growable: false);
}

String formatSyncedLyricTimestamp(Duration timestamp) {
  final totalSeconds = timestamp.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds.remainder(60);
  final secondsLabel = seconds.toString().padLeft(2, '0');

  return '$minutes:$secondsLabel';
}

int syncedLyricLineIndexAt(
  List<SyncedLyricLine> lines,
  Duration position,
) {
  var activeIndex = -1;
  for (var index = 0; index < lines.length; index += 1) {
    if (lines[index].timestamp > position) {
      break;
    }

    activeIndex = index;
  }

  return activeIndex;
}

final _lrcTagPattern = RegExp(r'\[([^\]]+)\]');
final _lrcTimestampPattern = RegExp(r'^(\d+):([0-5]?\d)(?:[\.:](\d{1,3}))?$');

Duration? _parseLrcTimestamp(String value) {
  final match = _lrcTimestampPattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }

  final minutes = int.tryParse(match.group(1) ?? '');
  final seconds = int.tryParse(match.group(2) ?? '');
  if (minutes == null || seconds == null || seconds > 59) {
    return null;
  }

  final milliseconds = _lrcFractionToMilliseconds(match.group(3));
  return Duration(
    minutes: minutes,
    seconds: seconds,
    milliseconds: milliseconds,
  );
}

int _lrcFractionToMilliseconds(String? rawFraction) {
  if (rawFraction == null || rawFraction.isEmpty) {
    return 0;
  }

  final normalized = rawFraction.length >= 3
      ? rawFraction.substring(0, 3)
      : rawFraction.padRight(3, '0');

  return int.parse(normalized);
}

class _IndexedSyncedLyricLine {
  const _IndexedSyncedLyricLine({
    required this.line,
    required this.order,
  });

  final SyncedLyricLine line;
  final int order;
}
