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

String _captionExtension(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == fileName.length - 1) {
    return '';
  }
  return fileName.substring(dotIndex + 1).toLowerCase();
}
