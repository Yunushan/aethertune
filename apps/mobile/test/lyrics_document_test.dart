import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/lyrics_document.dart';

void main() {
  test('recognizes supported lyrics document file names', () {
    expect(isSupportedLyricsDocumentName('lyrics.txt'), isTrue);
    expect(isSupportedLyricsDocumentName('song.LRC'), isTrue);
    expect(isSupportedLyricsDocumentName('subtitles.srt'), isTrue);
    expect(isSupportedLyricsDocumentName('karaoke.ttml'), isTrue);
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

  test('rejects malformed TTML documents', () {
    expect(
      () => decodeLyricsDocumentBytes(
        utf8.encode('<tt><body><div><p begin="1s">Broken'),
        fileName: 'broken.ttml',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects malformed SRT documents', () {
    expect(
      () => decodeLyricsDocumentBytes(
        utf8.encode('1\n00:00:03,000 --> 00:00:01,000\nBackwards'),
        fileName: 'broken.srt',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects non-utf8 lyrics documents', () {
    expect(
      () => decodeLyricsDocumentBytes(<int>[0xff, 0xfe], fileName: 'bad.lrc'),
      throwsA(isA<FormatException>()),
    );
  });

  test('builds txt, lrc, srt, and ttml lyrics export documents', () {
    final plainExport = buildLyricsDocumentExport(
      title: 'Plain / Song',
      artist: '',
      plainText: '\ufeffFirst line\r\nSecond line\n',
    )!;
    final syncedExport = buildLyricsDocumentExport(
      title: 'Dawn:Signal',
      artist: 'Mira*Vale',
      plainText: '[00:01.00]First synced\r\n[00:04.20]Second synced',
    )!;
    final ttmlExport = buildLyricsDocumentExport(
      title: 'Karaoke',
      artist: 'Mira',
      plainText: '<tt><body><div><p begin="1s">Line</p></div></body></tt>',
    )!;
    final srtExport = buildLyricsDocumentExport(
      title: 'Subtitled',
      artist: 'Mira',
      plainText: '1\n00:00:01,000 --> 00:00:02,000\nFirst line',
    )!;

    expect(plainExport.fileName, 'Plain Song.txt');
    expect(plainExport.extension, 'txt');
    expect(plainExport.text, 'First line\nSecond line');
    expect(utf8.decode(plainExport.bytes), plainExport.text);

    expect(syncedExport.fileName, 'Mira Vale - Dawn Signal.lrc');
    expect(syncedExport.extension, 'lrc');
    expect(syncedExport.text, contains('[00:01.00]First synced'));
    expect(utf8.decode(syncedExport.bytes), syncedExport.text);

    expect(ttmlExport.fileName, 'Mira - Karaoke.ttml');
    expect(ttmlExport.extension, 'ttml');
    expect(srtExport.fileName, 'Mira - Subtitled.srt');
    expect(srtExport.extension, 'srt');
  });

  test('does not build empty lyrics export documents', () {
    expect(
      buildLyricsDocumentExport(
        title: 'Empty',
        artist: 'Mira',
        plainText: '   ',
      ),
      isNull,
    );
  });
}
