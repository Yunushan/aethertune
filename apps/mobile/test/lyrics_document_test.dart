import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/lyrics_document.dart';

void main() {
  test('recognizes supported lyrics document file names', () {
    expect(isSupportedLyricsDocumentName('lyrics.txt'), isTrue);
    expect(isSupportedLyricsDocumentName('song.LRC'), isTrue);
    expect(isSupportedLyricsDocumentName('notes.md'), isFalse);
    expect(isSupportedLyricsDocumentName('lyrics'), isFalse);
  });

  test('decodes utf8 lyrics documents with normalized newlines', () {
    final bytes = utf8.encode('\ufeff[00:01.00]First\r\nSecond\rThird\n');

    expect(
      decodeLyricsDocumentBytes(bytes, fileName: 'song.lrc'),
      '[00:01.00]First\nSecond\nThird',
    );
  });

  test('rejects non-utf8 lyrics documents', () {
    expect(
      () => decodeLyricsDocumentBytes(<int>[0xff, 0xfe], fileName: 'bad.lrc'),
      throwsA(isA<FormatException>()),
    );
  });
}
