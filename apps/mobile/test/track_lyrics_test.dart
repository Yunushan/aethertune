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

  test('applies a portable timing correction to cue and karaoke timing', () {
    const document = '''
<tt><body><div><p begin="1s" end="3s"><span begin="0.2s" end="0.8s">Hello</span></p></div></body></tt>
''';
    final lyrics = TrackLyrics(
      trackId: 'track-1',
      plainText: document,
      timingOffset: const Duration(milliseconds: -1500),
    );

    final line = lyrics.syncedLines.single;
    expect(line.timestamp, Duration.zero);
    expect(line.endTimestamp, const Duration(milliseconds: 1500));
    expect(line.words.single.timestamp, Duration.zero);
    expect(line.words.single.endTimestamp, const Duration(milliseconds: 300));

    final delayed = lyrics.copyWith(
      timingOffset: const Duration(milliseconds: 250),
    );
    expect(
      delayed.syncedLines.single.timestamp,
      const Duration(seconds: 1, milliseconds: 250),
    );
    expect(
      delayed.syncedLines.single.words.single.timestamp,
      const Duration(milliseconds: 1450),
    );
  });

  test('finds the active synced lyric line for a playback position', () {
    final lines = parseSyncedLyricLines('''
[00:01.00]Intro
[00:05.00]Verse
[00:10.00]Chorus
''');

    expect(syncedLyricLineIndexAt(lines, Duration.zero), -1);
    expect(
      syncedLyricLineIndexAt(lines, const Duration(milliseconds: 1000)),
      0,
    );
    expect(syncedLyricLineIndexAt(lines, const Duration(seconds: 7)), 1);
    expect(syncedLyricLineIndexAt(lines, const Duration(seconds: 30)), 2);
    expect(syncedLyricLineIndexAt(<SyncedLyricLine>[], Duration.zero), -1);
  });

  test('parses TTML timed lines and word-level karaoke spans', () {
    const document = '''
<?xml version="1.0" encoding="UTF-8"?>
<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
  <p begin="00:00:01.000" end="00:00:03.000">
    <span begin="0.2s">Hello</span><span begin="0.6s" end="1.0s">world</span>
  </p>
  <p begin="00:00:04.500">Final line</p>
</div></body></tt>
''';
    expect(isTtmlLyricsDocument(document), isTrue);
    final lines = parseSyncedLyricLines(document);

    expect(lines, hasLength(2));
    expect(lines[0].text, 'Hello world');
    expect(lines[0].timestamp, const Duration(seconds: 1));
    expect(lines[0].endTimestamp, const Duration(seconds: 3));
    expect(lines[0].words.map((word) => word.text), <String>['Hello', 'world']);
    expect(
      lines[0].words.map((word) => word.timestamp),
      <Duration>[
        const Duration(milliseconds: 1200),
        const Duration(milliseconds: 1600),
      ],
    );
    expect(lines[0].words[0].endTimestamp, const Duration(milliseconds: 1600));
    expect(lines[0].words[1].endTimestamp, const Duration(seconds: 2));
    expect(syncedLyricWordIndexAt(lines[0].words, const Duration(milliseconds: 1300)), 0);
    expect(syncedLyricWordIndexAt(lines[0].words, const Duration(milliseconds: 1700)), 1);
    expect(syncedLyricWordIndexAt(lines[0].words, const Duration(seconds: 3)), -1);
    expect(lines[1].text, 'Final line');
    expect(lines[1].timestamp, const Duration(milliseconds: 4500));
  });

  test('parses SRT cue timing and clears the highlight after a cue ends', () {
    const document = '''
1
00:00:01,250 --> 00:00:03,500
First lyric

00:00:04.000 --> 00:00:06.125
Second
line
''';
    expect(isSrtLyricsDocument(document), isTrue);
    final lines = parseSyncedLyricLines(document);

    expect(lines, hasLength(2));
    expect(lines[0].timestamp, const Duration(milliseconds: 1250));
    expect(lines[0].endTimestamp, const Duration(milliseconds: 3500));
    expect(lines[0].text, 'First lyric');
    expect(lines[1].timestamp, const Duration(seconds: 4));
    expect(lines[1].endTimestamp, const Duration(milliseconds: 6125));
    expect(lines[1].text, 'Second\nline');
    expect(syncedLyricLineIndexAt(lines, const Duration(seconds: 2)), 0);
    expect(
      syncedLyricLineIndexAt(lines, const Duration(milliseconds: 3750)),
      -1,
    );
    expect(syncedLyricLineIndexAt(lines, const Duration(seconds: 5)), 1);
    expect(
      isSrtLyricsDocument('00:00:03,000 --> 00:00:01,000\nBackwards'),
      isFalse,
    );
  });

  test('parses WebVTT cues, cue settings, and inline markup', () {
    const document = '''
WEBVTT

opening
00:01.250 --> 00:03.500 align:start
<i>First</i> line

04:00:00.000 --> 04:00:02.000
Second line
''';

    final lines = parseSyncedLyricLines(document);

    expect(isWebVttLyricsDocument(document), isTrue);
    expect(lines, hasLength(2));
    expect(lines[0].timestamp, const Duration(milliseconds: 1250));
    expect(lines[0].endTimestamp, const Duration(milliseconds: 3500));
    expect(lines[0].text, 'First line');
    expect(lines[1].timestamp, const Duration(hours: 4));
  });

  test('plain lyrics are not treated as synced lyrics', () {
    final lyrics = TrackLyrics(
      trackId: 'track-1',
      plainText: 'first line\nsecond line',
    );

    expect(lyrics.hasSyncedLines, isFalse);
    expect(lyrics.syncedLines, isEmpty);
  });

  test('serializes provider attribution and reads legacy manual lyrics', () {
    final lyrics = TrackLyrics(
      trackId: 'track-1',
      plainText: '[00:01.00]First line',
      sourceId: 'lrclib',
      sourceName: 'LRCLIB',
      sourceExternalId: '42',
      sourceUri: Uri.parse('https://lrclib.net/api/get/42'),
      timingOffset: const Duration(seconds: 45),
      updatedAt: DateTime.utc(2026, 7, 10),
    );

    final restored = TrackLyrics.fromJson(lyrics.toJson());
    final legacy = TrackLyrics.fromJson(<String, Object?>{
      'trackId': 'legacy',
      'plainText': 'manual lyrics',
    });

    expect(restored.hasProviderAttribution, isTrue);
    expect(restored.attributionLabel, 'LRCLIB');
    expect(restored.sourceExternalId, '42');
    expect(restored.sourceUri, Uri.parse('https://lrclib.net/api/get/42'));
    expect(restored.timingOffset, TrackLyrics.maxTimingOffset);
    expect(legacy.sourceId, 'manual');
    expect(legacy.timingOffset, Duration.zero);
    expect(legacy.hasProviderAttribution, isFalse);
  });
}
