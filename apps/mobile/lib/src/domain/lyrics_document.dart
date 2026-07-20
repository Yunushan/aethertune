import 'dart:convert';

import 'track_lyrics.dart';

const supportedLyricsDocumentExtensions = <String>[
  'txt',
  'lrc',
  'srt',
  'vtt',
  'ttml',
];

class LyricsDocumentExport {
  const LyricsDocumentExport({
    required this.fileName,
    required this.text,
  });

  final String fileName;
  final String text;

  List<int> get bytes => utf8.encode(text);

  String get extension => lyricsDocumentExtensionForText(text);
}

bool isSupportedLyricsDocumentName(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) {
    return false;
  }

  final extension = fileName.substring(dotIndex + 1).toLowerCase();
  return supportedLyricsDocumentExtensions.contains(extension);
}

LyricsDocumentExport? buildLyricsDocumentExport({
  required String title,
  required String artist,
  required String plainText,
}) {
  final text = _normalizeLyricsDocumentText(plainText);
  if (text.isEmpty) {
    return null;
  }

  return LyricsDocumentExport(
    fileName: lyricsDocumentFileName(
      title: title,
      artist: artist,
      plainText: text,
    ),
    text: text,
  );
}

String lyricsDocumentFileName({
  required String title,
  required String artist,
  required String plainText,
}) {
  final titlePart = _safeLyricsFileNamePart(title, fallback: 'lyrics');
  final artistPart = _safeLyricsFileNamePart(
    artist,
    fallback: 'Unknown Artist',
  );
  final extension = lyricsDocumentExtensionForText(plainText);

  if (artistPart == 'Unknown Artist') {
    return '$titlePart.$extension';
  }

  return '$artistPart - $titlePart.$extension';
}

String lyricsDocumentExtensionForText(String plainText) {
  if (isTtmlLyricsDocument(plainText)) {
    return 'ttml';
  }
  if (isWebVttLyricsDocument(plainText)) {
    return 'vtt';
  }
  if (isSrtLyricsDocument(plainText)) {
    return 'srt';
  }
  return parseSyncedLyricLines(plainText).isEmpty ? 'txt' : 'lrc';
}

String decodeLyricsDocumentBytes(
  List<int> bytes, {
  String? fileName,
}) {
  try {
    final decoded = utf8.decode(bytes, allowMalformed: false);
    final normalized = _normalizeLyricsDocumentText(decoded);
    if (_lyricsDocumentHasExtension(fileName, 'ttml') &&
        (!isTtmlLyricsDocument(normalized) ||
            parseSyncedLyricLines(normalized).isEmpty)) {
      throw const FormatException('TTML lyrics must contain valid lyric lines.');
    }
    if (_lyricsDocumentHasExtension(fileName, 'srt') &&
        !isSrtLyricsDocument(normalized)) {
      throw const FormatException('SRT lyrics must contain valid cue blocks.');
    }
    if (_lyricsDocumentHasExtension(fileName, 'vtt') &&
        (!isWebVttLyricsDocument(normalized) ||
            parseSyncedLyricLines(normalized).isEmpty)) {
      throw const FormatException(
        'WebVTT lyrics must contain a WEBVTT header and valid cue blocks.',
      );
    }
    return normalized;
  } on FormatException {
    final name = fileName?.trim();
    final suffix = name == null || name.isEmpty ? '' : ' for $name';
    throw FormatException('Lyrics document$suffix must be valid UTF-8 text.');
  }
}

bool _lyricsDocumentHasExtension(String? fileName, String extension) {
  if (fileName == null) {
    return false;
  }
  return fileName.trim().toLowerCase().endsWith('.$extension');
}

String _normalizeLyricsDocumentText(String value) {
  final withoutBom = value.startsWith('\ufeff') ? value.substring(1) : value;
  return withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
}

String _safeLyricsFileNamePart(String value, {required String fallback}) {
  final withoutInvalidCharacters =
      value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ');
  final withoutRepeatedWhitespace = withoutInvalidCharacters
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^\.+|\.+$'), '')
      .trim();

  if (withoutRepeatedWhitespace.isEmpty) {
    return fallback;
  }

  if (withoutRepeatedWhitespace.length <= 80) {
    return withoutRepeatedWhitespace;
  }

  return withoutRepeatedWhitespace.substring(0, 80).trimRight();
}
