import 'dart:convert';
import 'dart:io';

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

  test('loads the first valid local WebVTT or SRT sidecar', () async {
    final directory = await Directory.systemTemp.createTemp('aethertune-video');
    addTearDown(() => directory.delete(recursive: true));
    final video = File('${directory.path}${Platform.pathSeparator}show.mp4');
    await video.writeAsBytes(<int>[0]);
    await File('${directory.path}${Platform.pathSeparator}show.vtt').writeAsString(
      'WEBVTT\n\n00:00.000 --> 00:01.000\nHello',
    );
    await File('${directory.path}${Platform.pathSeparator}show.srt').writeAsString(
      '1\n00:00:00,000 --> 00:00:01,000\nFallback',
    );

    final document = await loadLocalVideoCaptionSidecar(video.uri);

    expect(document?.title, 'show');
    expect(document?.text, contains('Hello'));
  });

  test('skips malformed sidecars and falls back to the next valid file', () async {
    final directory = await Directory.systemTemp.createTemp('aethertune-video');
    addTearDown(() => directory.delete(recursive: true));
    final video = File('${directory.path}${Platform.pathSeparator}show.mp4');
    await video.writeAsBytes(<int>[0]);
    await File('${directory.path}${Platform.pathSeparator}show.vtt').writeAsString(
      'WEBVTT\n\nNo timestamped cue',
    );
    await File('${directory.path}${Platform.pathSeparator}show.srt').writeAsString(
      '1\n00:00:00,000 --> 00:00:01,000\nFallback',
    );

    final document = await loadLocalVideoCaptionSidecar(video.uri);

    expect(document?.text, contains('Fallback'));
  });
}
