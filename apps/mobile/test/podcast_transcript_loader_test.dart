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
    expect(transcript.timedLines, hasLength(2));
    expect(transcript.timedLines.first.timestamp, const Duration(seconds: 1));
  });

  test('renders SRT and TTML transcript cues as readable text', () {
    final srt = decodePodcastTranscript(
      utf8.encode('''
1
00:00:01,000 --> 00:00:02,000
SRT opening
'''),
    );
    final ttml = decodePodcastTranscript(
      utf8.encode('''
<tt><body><div><p begin="1s" end="2s">TTML opening</p></div></body></tt>
'''),
    );

    expect(srt.displayText, 'SRT opening');
    expect(ttml.displayText, 'TTML opening');
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
