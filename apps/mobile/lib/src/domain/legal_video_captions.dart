import 'dart:io';

import 'package:path/path.dart' as p;

import 'lyrics_document.dart';

const maxLegalVideoCaptionBytes = 256 * 1024;

class LegalVideoCaptionDocument {
  const LegalVideoCaptionDocument({
    required this.title,
    required this.text,
  });

  final String title;
  final String text;
}

/// Decodes a bounded external caption file that MediaKit can render directly.
LegalVideoCaptionDocument decodeLegalVideoCaptionDocument(
  List<int> bytes, {
  required String fileName,
}) {
  final normalizedName = fileName.trim();
  final extension = _captionExtension(normalizedName);
  if (extension != 'srt' && extension != 'vtt') {
    throw const FormatException('Choose an SRT or WebVTT caption file.');
  }
  if (bytes.length > maxLegalVideoCaptionBytes) {
    throw const FormatException('Caption files must not exceed 256 KiB.');
  }

  final text = decodeLyricsDocumentBytes(bytes, fileName: normalizedName);
  return LegalVideoCaptionDocument(
    title: normalizedName.substring(0, normalizedName.length - extension.length - 1),
    text: text,
  );
}

/// Returns the first valid, same-name WebVTT or SRT sidecar for a local video.
Future<LegalVideoCaptionDocument?> loadLocalVideoCaptionSidecar(
  Uri source,
) async {
  if (source.scheme != 'file') {
    return null;
  }

  try {
    final videoPath = source.toFilePath();
    final basePath = p.join(
      p.dirname(videoPath),
      p.basenameWithoutExtension(videoPath),
    );
    for (final extension in <String>['vtt', 'srt']) {
      final file = File('$basePath.$extension');
      if (!await file.exists()) {
        continue;
      }
      if (await file.length() > maxLegalVideoCaptionBytes) {
        continue;
      }
      final bytes = await file.readAsBytes();
      try {
        return decodeLegalVideoCaptionDocument(
          bytes,
          fileName: p.basename(file.path),
        );
      } on FormatException {
        // A malformed sidecar must not prevent the video from opening.
      }
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

String _captionExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1).toLowerCase();
}
