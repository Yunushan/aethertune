import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/podcast_transcript_loader.dart';

void main() {
  test('decodes bounded UTF-8 WebVTT transcript text for reading', () {
    final transcript = decodePodcastTranscript(
      utf8.encode('''
WEBVTT

00:00:01.000 --> 00:00:03.000
Opening words

00:00:04.000 --> 00:00:06.000
Closing words
'''),
      contentType: 'text/vtt',
    );

    expect(transcript.contentType, 'text/vtt');
    expect(transcript.displayText, 'Opening words\n\nClosing words');
  });

  test('rejects empty, oversized, and malformed transcript documents', () {
    expect(
      () => decodePodcastTranscript(const <int>[]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodePodcastTranscript(
        List<int>.filled(maxPodcastTranscriptBytes + 1, 0x61),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodePodcastTranscript(const <int>[0xff]),
      throwsA(isA<FormatException>()),
    );
  });
}
