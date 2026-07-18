import 'package:xml/xml.dart';

class SyncedLyricWord {
  const SyncedLyricWord({
    required this.timestamp,
    required this.text,
    this.endTimestamp,
  });

  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
}

class SyncedLyricLine {
  const SyncedLyricLine({
    required this.timestamp,
    required this.text,
    this.endTimestamp,
    this.words = const <SyncedLyricWord>[],
  });

  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
  final List<SyncedLyricWord> words;

  bool get hasWordTiming => words.isNotEmpty;
}

/// User-managed plain-text or LRC lyrics attached to one library track.
class TrackLyrics {
  TrackLyrics({
    required this.trackId,
    required this.plainText,
    this.sourceId = 'manual',
    this.sourceName = '',
    this.sourceExternalId = '',
    this.sourceUri,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String trackId;
  final String plainText;
  final String sourceId;
  final String sourceName;
  final String sourceExternalId;
  final Uri? sourceUri;
  final DateTime updatedAt;

  bool get isEmpty => plainText.trim().isEmpty;
  bool get isTtmlDocument => isTtmlLyricsDocument(plainText);
  bool get isSrtDocument => isSrtLyricsDocument(plainText);
  List<SyncedLyricLine> get syncedLines => parseSyncedLyricLines(plainText);
  bool get hasSyncedLines => syncedLines.isNotEmpty;
  bool get hasProviderAttribution =>
      sourceId.trim().isNotEmpty &&
      sourceId != 'manual' &&
      sourceName.trim().isNotEmpty;
  String? get attributionLabel =>
      hasProviderAttribution ? sourceName.trim() : null;

  TrackLyrics copyWith({
    String? trackId,
    String? plainText,
    String? sourceId,
    String? sourceName,
    String? sourceExternalId,
    Uri? sourceUri,
    DateTime? updatedAt,
  }) {
    return TrackLyrics(
      trackId: trackId ?? this.trackId,
      plainText: plainText ?? this.plainText,
      sourceId: sourceId ?? this.sourceId,
      sourceName: sourceName ?? this.sourceName,
      sourceExternalId: sourceExternalId ?? this.sourceExternalId,
      sourceUri: sourceUri ?? this.sourceUri,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'trackId': trackId,
      'plainText': plainText,
      'sourceId': sourceId,
      'sourceName': sourceName,
      'sourceExternalId': sourceExternalId,
      'sourceUri': sourceUri?.toString(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TrackLyrics.fromJson(Map<String, Object?> json) {
    return TrackLyrics(
      trackId: json['trackId'] as String,
      plainText: json['plainText'] as String? ?? '',
      sourceId: json['sourceId'] as String? ?? 'manual',
      sourceName: json['sourceName'] as String? ?? '',
      sourceExternalId: json['sourceExternalId'] as String? ?? '',
      sourceUri: _parseLyricsSourceUri(json['sourceUri'] as String?),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

Uri? _parseLyricsSourceUri(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return Uri.tryParse(value);
}

List<SyncedLyricLine> parseSyncedLyricLines(String input) {
  if (isTtmlLyricsDocument(input)) {
    return _parseTtmlSyncedLyricLines(input);
  }
  final webVttLines = _parseWebVttSyncedLyricLines(input);
  if (webVttLines.isNotEmpty) {
    return webVttLines;
  }
  final srtLines = _parseSrtSyncedLyricLines(input);
  if (srtLines.isNotEmpty) {
    return srtLines;
  }

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
    final line = lines[index];
    if (line.timestamp > position) {
      break;
    }
    if (line.endTimestamp == null || position < line.endTimestamp!) {
      activeIndex = index;
    }
  }

  return activeIndex;
}

int syncedLyricWordIndexAt(
  List<SyncedLyricWord> words,
  Duration position,
) {
  for (var index = 0; index < words.length; index += 1) {
    final word = words[index];
    final end = word.endTimestamp;
    if (position >= word.timestamp && (end == null || position < end)) {
      return index;
    }
  }

  return -1;
}

bool isTtmlLyricsDocument(String input) {
  var root = input.trimLeft();
  if (root.startsWith('<?xml')) {
    final declarationEnd = root.indexOf('?>');
    if (declarationEnd == -1) {
      return false;
    }
    root = root.substring(declarationEnd + 2).trimLeft();
  }
  return RegExp(r'^<(?:[\w.-]+:)?tt(?:\s|>)', caseSensitive: false)
      .hasMatch(root);
}

bool isSrtLyricsDocument(String input) =>
    _parseSrtSyncedLyricLines(input).isNotEmpty;

bool isWebVttLyricsDocument(String input) =>
    input.trimLeft().startsWith('WEBVTT');

List<SyncedLyricLine> _parseWebVttSyncedLyricLines(String input) {
  if (!isWebVttLyricsDocument(input)) {
    return const <SyncedLyricLine>[];
  }

  final indexedLines = <_IndexedSyncedLyricLine>[];
  var order = 0;
  for (final rawBlock in input.split(RegExp(r'\n\s*\n'))) {
    final blockLines = rawBlock
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .toList(growable: false);
    if (blockLines.isEmpty ||
        blockLines.first.startsWith('WEBVTT') ||
        blockLines.first.startsWith('NOTE') ||
        blockLines.first.startsWith('STYLE') ||
        blockLines.first.startsWith('REGION')) {
      continue;
    }

    final timingLineIndex = blockLines.indexWhere(
      (line) => line.contains('-->'),
    );
    if (timingLineIndex < 0) {
      continue;
    }
    final timing = _parseWebVttTiming(blockLines[timingLineIndex]);
    if (timing == null || timing.end < timing.start) {
      continue;
    }
    final text = blockLines
        .skip(timingLineIndex + 1)
        .where((line) => line.isNotEmpty)
        .map((line) => line.replaceAll(RegExp(r'<[^>]*>'), ''))
        .join('\n')
        .trim();
    if (text.isEmpty) {
      continue;
    }
    indexedLines.add(
      _IndexedSyncedLyricLine(
        line: SyncedLyricLine(
          timestamp: timing.start,
          endTimestamp: timing.end,
          text: text,
        ),
        order: order,
      ),
    );
    order += 1;
  }
  indexedLines.sort((a, b) {
    final byTimestamp = a.line.timestamp.compareTo(b.line.timestamp);
    return byTimestamp == 0 ? a.order.compareTo(b.order) : byTimestamp;
  });
  return indexedLines.map((entry) => entry.line).toList(growable: false);
}

_SrtTiming? _parseWebVttTiming(String value) {
  final match = RegExp(
    r'^((?:\d+:)?[0-5]\d:[0-5]\d[.,]\d{1,3})\s+-->\s+((?:\d+:)?[0-5]\d:[0-5]\d[.,]\d{1,3})(?:\s+.*)?$',
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final start = _parseWebVttTimestamp(match.group(1)!);
  final end = _parseWebVttTimestamp(match.group(2)!);
  if (start == null || end == null) {
    return null;
  }
  return _SrtTiming(start: start, end: end);
}

Duration? _parseWebVttTimestamp(String value) {
  final parts = value.replaceAll(',', '.').split(':');
  if (parts.length != 2 && parts.length != 3) {
    return null;
  }
  final secondsParts = parts.last.split('.');
  if (secondsParts.length != 2) {
    return null;
  }
  final hours = parts.length == 3 ? int.tryParse(parts[0]) : 0;
  final minutes = int.tryParse(parts[parts.length - 2]);
  final seconds = int.tryParse(secondsParts[0]);
  if (hours == null || minutes == null || seconds == null) {
    return null;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: _lrcFractionToMilliseconds(secondsParts[1]),
  );
}

List<SyncedLyricLine> _parseSrtSyncedLyricLines(String input) {
  final indexedLines = <_IndexedSyncedLyricLine>[];
  var order = 0;
  for (final rawBlock in input.split(RegExp(r'\n\s*\n'))) {
    final blockLines = rawBlock
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .toList(growable: false);
    if (blockLines.isEmpty) {
      continue;
    }
    var timingLineIndex = 0;
    if (RegExp(r'^\d+$').hasMatch(blockLines.first)) {
      timingLineIndex = 1;
    }
    if (timingLineIndex >= blockLines.length) {
      continue;
    }
    final timing = _parseSrtTiming(blockLines[timingLineIndex]);
    if (timing == null || timing.end < timing.start) {
      continue;
    }
    final text = blockLines
        .skip(timingLineIndex + 1)
        .where((line) => line.isNotEmpty)
        .join('\n');
    if (text.isEmpty) {
      continue;
    }
    indexedLines.add(
      _IndexedSyncedLyricLine(
        line: SyncedLyricLine(
          timestamp: timing.start,
          endTimestamp: timing.end,
          text: text,
        ),
        order: order,
      ),
    );
    order += 1;
  }
  indexedLines.sort((a, b) {
    final byTimestamp = a.line.timestamp.compareTo(b.line.timestamp);
    return byTimestamp == 0 ? a.order.compareTo(b.order) : byTimestamp;
  });
  return indexedLines.map((entry) => entry.line).toList(growable: false);
}

_SrtTiming? _parseSrtTiming(String value) {
  final match = RegExp(
    r'^(\d+):([0-5]\d):([0-5]\d)[,.](\d{1,3})\s+-->\s+(\d+):([0-5]\d):([0-5]\d)[,.](\d{1,3})$',
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  Duration timestamp(int offset) => Duration(
        hours: int.parse(match.group(offset)!),
        minutes: int.parse(match.group(offset + 1)!),
        seconds: int.parse(match.group(offset + 2)!),
        milliseconds: _lrcFractionToMilliseconds(match.group(offset + 3)),
      );
  return _SrtTiming(start: timestamp(1), end: timestamp(5));
}

class _SrtTiming {
  const _SrtTiming({required this.start, required this.end});

  final Duration start;
  final Duration end;
}

List<SyncedLyricLine> _parseTtmlSyncedLyricLines(String input) {
  final document = _tryParseTtml(input);
  if (document == null) {
    return const <SyncedLyricLine>[];
  }

  final indexedLines = <_IndexedSyncedLyricLine>[];
  var order = 0;
  for (final paragraph in document.descendants.whereType<XmlElement>()) {
    if (paragraph.name.local.toLowerCase() != 'p') {
      continue;
    }

    final timestamp = _resolveTtmlTimestamp(
          _ttmlAttribute(paragraph, 'begin'),
          Duration.zero,
        ) ??
        Duration.zero;
    final endTimestamp = _resolveTtmlEndTimestamp(
      paragraph,
      start: timestamp,
      parentStart: Duration.zero,
    );
    final text = _ttmlText(paragraph);
    if (text.isEmpty) {
      continue;
    }

    final words = _ttmlWordsForParagraph(
      paragraph,
      lineTimestamp: timestamp,
      lineEndTimestamp: endTimestamp,
    );
    indexedLines.add(
      _IndexedSyncedLyricLine(
        line: SyncedLyricLine(
          timestamp: timestamp,
          endTimestamp: endTimestamp,
          text: text,
          words: words,
        ),
        order: order,
      ),
    );
    order += 1;
  }

  indexedLines.sort((a, b) {
    final byTimestamp = a.line.timestamp.compareTo(b.line.timestamp);
    return byTimestamp == 0 ? a.order.compareTo(b.order) : byTimestamp;
  });
  return indexedLines.map((entry) => entry.line).toList(growable: false);
}

XmlDocument? _tryParseTtml(String input) {
  try {
    return XmlDocument.parse(input.trimLeft());
  } on XmlParserException {
    return null;
  }
}

String? _ttmlAttribute(XmlElement element, String localName) {
  for (final attribute in element.attributes) {
    if (attribute.name.local.toLowerCase() == localName.toLowerCase()) {
      return attribute.value;
    }
  }
  return null;
}

Duration? _resolveTtmlEndTimestamp(
  XmlElement element, {
  required Duration start,
  required Duration parentStart,
}) {
  final explicitEnd = _resolveTtmlTimestamp(
    _ttmlAttribute(element, 'end'),
    parentStart,
  );
  if (explicitEnd != null) {
    return explicitEnd;
  }
  final duration = _parseTtmlOffset(_ttmlAttribute(element, 'dur'));
  return duration == null ? null : start + duration;
}

Duration? _resolveTtmlTimestamp(String? value, Duration parentStart) {
  if (value == null) {
    return null;
  }
  final offset = _parseTtmlOffset(value);
  if (offset != null) {
    return parentStart + offset;
  }
  return _parseTtmlClock(value);
}

Duration? _parseTtmlOffset(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)(h|m|s|ms)$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final amount = double.tryParse(match.group(1) ?? '');
  if (amount == null || amount.isNegative) {
    return null;
  }
  final unit = (match.group(2) ?? '').toLowerCase();
  final milliseconds = switch (unit) {
    'h' => amount * Duration.millisecondsPerHour,
    'm' => amount * Duration.millisecondsPerMinute,
    's' => amount * Duration.millisecondsPerSecond,
    'ms' => amount,
    _ => 0.0,
  };
  return Duration(milliseconds: milliseconds.round());
}

Duration? _parseTtmlClock(String value) {
  final match = RegExp(
    r'^(?:(\d+):)?([0-5]?\d):([0-5]?\d)(?:\.(\d{1,3}))?$',
  ).firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final hours = int.tryParse(match.group(1) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(2) ?? '');
  final seconds = int.tryParse(match.group(3) ?? '');
  if (minutes == null || seconds == null) {
    return null;
  }
  return Duration(
    hours: hours,
    minutes: minutes,
    seconds: seconds,
    milliseconds: _lrcFractionToMilliseconds(match.group(4)),
  );
}

String _ttmlText(XmlElement element) {
  final buffer = StringBuffer();
  void visit(XmlNode node) {
    if (node is XmlText) {
      buffer.write(node.value);
      return;
    }
    if (node is XmlElement && node.name.local.toLowerCase() == 'br') {
      buffer.write(' ');
      return;
    }
    if (node is XmlElement &&
        node.name.local.toLowerCase() == 'span' &&
        buffer.isNotEmpty &&
        !RegExp(r'\s$').hasMatch(buffer.toString())) {
      buffer.write(' ');
    }
    for (final child in node.children) {
      visit(child);
    }
  }

  visit(element);
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<SyncedLyricWord> _ttmlWordsForParagraph(
  XmlElement paragraph, {
  required Duration lineTimestamp,
  required Duration? lineEndTimestamp,
}) {
  final candidates = <_TtmlWordCandidate>[];

  void visit(XmlElement element, Duration parentStart, Duration? parentEnd) {
    for (final child in element.children.whereType<XmlElement>()) {
      final start = _resolveTtmlTimestamp(
            _ttmlAttribute(child, 'begin'),
            parentStart,
          ) ??
          parentStart;
      final explicitEnd = _resolveTtmlEndTimestamp(
        child,
        start: start,
        parentStart: parentStart,
      );
      final end = explicitEnd ?? parentEnd;
      final hasTimedDescendant = child.descendants
          .whereType<XmlElement>()
          .any((nested) => _ttmlAttribute(nested, 'begin') != null);
      final text = _ttmlText(child);
      if (child.name.local.toLowerCase() == 'span' &&
          _ttmlAttribute(child, 'begin') != null &&
          !hasTimedDescendant &&
          text.isNotEmpty) {
        candidates.add(
          _TtmlWordCandidate(
            timestamp: start,
            endTimestamp: explicitEnd,
            text: text,
          ),
        );
      } else {
        visit(child, start, end);
      }
    }
  }

  visit(paragraph, lineTimestamp, lineEndTimestamp);
  candidates.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return List<SyncedLyricWord>.generate(candidates.length, (index) {
    final candidate = candidates[index];
    final nextTimestamp = index + 1 < candidates.length
        ? candidates[index + 1].timestamp
        : lineEndTimestamp;
    return SyncedLyricWord(
      timestamp: candidate.timestamp,
      endTimestamp: candidate.endTimestamp ?? nextTimestamp,
      text: candidate.text,
    );
  }, growable: false);
}

class _TtmlWordCandidate {
  const _TtmlWordCandidate({
    required this.timestamp,
    required this.endTimestamp,
    required this.text,
  });

  final Duration timestamp;
  final Duration? endTimestamp;
  final String text;
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
