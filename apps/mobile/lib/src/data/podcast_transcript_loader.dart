import 'dart:convert';
import 'dart:io';

import '../domain/track_lyrics.dart';

const maxPodcastTranscriptBytes = 256 * 1024;

typedef PodcastTranscriptLoader = Future<PodcastTranscriptDocument> Function(
  Uri transcriptUri,
);

/// A user-requested Podcasting 2.0 transcript kept only for the reader view.
final class PodcastTranscriptDocument {
  const PodcastTranscriptDocument({
    required this.text,
    this.contentType,
  });

  final String text;
  final String? contentType;

  List<SyncedLyricLine> get timedLines => parseSyncedLyricLines(text);

  String get displayText {
    final lines = timedLines;
    if (lines.isNotEmpty) {
      return lines.map((line) => line.text).join('\n\n');
    }
    return text;
  }
}

Future<PodcastTranscriptDocument> loadPodcastTranscript(
  Uri transcriptUri,
) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.getUrl(transcriptUri);
    request.headers.set(
      HttpHeaders.acceptHeader,
      'text/plain, text/vtt, application/x-subrip, application/ttml+xml;q=0.9, */*;q=0.1',
    );
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Transcript request failed with HTTP ${response.statusCode}.',
        uri: transcriptUri,
      );
    }

    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxPodcastTranscriptBytes) {
        throw const FormatException('Podcast transcript is too large to open.');
      }
      bytes.addAll(chunk);
    }
    return decodePodcastTranscript(
      bytes,
      contentType: response.headers.contentType?.mimeType,
    );
  } finally {
    client.close(force: true);
  }
}

PodcastTranscriptDocument decodePodcastTranscript(
  List<int> bytes, {
  String? contentType,
}) {
  if (bytes.isEmpty) {
    throw const FormatException('Podcast transcript is empty.');
  }
  if (bytes.length > maxPodcastTranscriptBytes) {
    throw const FormatException('Podcast transcript is too large to open.');
  }
  try {
    final text = utf8.decode(bytes, allowMalformed: false)
        .replaceFirst('\ufeff', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (text.isEmpty) {
      throw const FormatException('Podcast transcript is empty.');
    }
    return PodcastTranscriptDocument(text: text, contentType: contentType);
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException('Podcast transcript must be valid UTF-8 text.');
  }
}
