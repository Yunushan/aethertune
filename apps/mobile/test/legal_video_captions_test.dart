import 'dart:convert';

import 'package:aethertune/src/domain/legal_video_captions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes bounded valid WebVTT files for video subtitles', () {
    final document = decodeLegalVideoCaptionDocument(
      utf8.encode('WEBVTT\n\n00:00.000 --> 00:01.000\nHello'),
      fileName: 'English.vtt',
    );

    expect(document.title, 'English');
    expect(document.text, contains('Hello'));
  });

  test('rejects unsupported, malformed, and oversized caption files', () {
    expect(
      () => decodeLegalVideoCaptionDocument(
        utf8.encode('lyrics'),
        fileName: 'lyrics.lrc',
      ),
      throwsFormatException,
    );
    expect(
      () => decodeLegalVideoCaptionDocument(
        utf8.encode('1\n00:00:03,000 --> 00:00:01,000\nBackwards'),
        fileName: 'broken.srt',
      ),
      throwsFormatException,
    );
    expect(
      () => decodeLegalVideoCaptionDocument(
        List<int>.filled(maxLegalVideoCaptionBytes + 1, 0),
        fileName: 'large.vtt',
      ),
      throwsFormatException,
    );
  });
}
