import 'dart:convert';

const supportedLyricsDocumentExtensions = <String>['txt', 'lrc'];

bool isSupportedLyricsDocumentName(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == fileName.length - 1) {
    return false;
  }

  final extension = fileName.substring(dotIndex + 1).toLowerCase();
  return supportedLyricsDocumentExtensions.contains(extension);
}

String decodeLyricsDocumentBytes(
  List<int> bytes, {
  String? fileName,
}) {
  try {
    final decoded = utf8.decode(bytes, allowMalformed: false);
    return _normalizeLyricsDocumentText(decoded);
  } on FormatException {
    final name = fileName?.trim();
    final suffix = name == null || name.isEmpty ? '' : ' for $name';
    throw FormatException('Lyrics document$suffix must be valid UTF-8 text.');
  }
}

String _normalizeLyricsDocumentText(String value) {
  final withoutBom = value.startsWith('\ufeff') ? value.substring(1) : value;
  return withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
}
