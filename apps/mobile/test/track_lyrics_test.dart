import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track_lyrics.dart';

void main() {
  test('parses LRC timestamped lyric lines', () {
    final lines = parseSyncedLyricLines('''
[ti:Song title]
[offset:100][00:01.00]Offset tag is ignored
[00:10.50]Ten seconds
[00:05.000][00:15.2]Repeated chorus
[01:02.345]Minute mark
[00:99.00]Invalid timestamp
Plain lyric line
''');

    expect(
      lines.map((line) => line.text),
      <String>[
        'Offset tag is ignored',
        'Repeated chorus',
        'Ten seconds',
        'Repeated chorus',
        'Minute mark',
      ],
    );
    expect(
      lines.map((line) => line.timestamp.inMilliseconds),
      <int>[1000, 5000, 10500, 15200, 62345],
    );
  });

  test('exposes parsed synced lines from track lyrics', () {
    final lyrics = TrackLyrics(
      trackId: 'track-1',
      plainText: '[00:02.00]Second line\nplain text',
    );

    expect(lyrics.hasSyncedLines, isTrue);
    expect(lyrics.syncedLines.single.text, 'Second line');
    expect(
      formatSyncedLyricTimestamp(lyrics.syncedLines.single.timestamp),
      '0:02',
    );
  });

  test('plain lyrics are not treated as synced lyrics', () {
    final lyrics = TrackLyrics(
      trackId: 'track-1',
      plainText: 'first line\nsecond line',
    );

    expect(lyrics.hasSyncedLines, isFalse);
    expect(lyrics.syncedLines, isEmpty);
  });
}
