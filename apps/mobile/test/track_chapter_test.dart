import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_chapter.dart';

void main() {
  test('parses, sorts, and formats timestamped chapter text', () {
    final chapters = parseTrackChapters(
      '2:30 Detail\n0:00 Introduction\n1:05 Overview',
      maximum: const Duration(minutes: 3),
    );

    expect(chapters.map((chapter) => chapter.title), <String>[
      'Introduction',
      'Overview',
      'Detail',
    ]);
    expect(chapters[1].start, const Duration(minutes: 1, seconds: 5));
    expect(
      formatTrackChapters(chapters),
      '0:00 Introduction\n1:05 Overview\n2:30 Detail',
    );
  });

  test('rejects malformed or out-of-range manual chapter text', () {
    expect(
      () => parseTrackChapters('Introduction'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseTrackChapters(
        '3:00 Ending',
        maximum: const Duration(minutes: 3),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('track chapters round trip and normalize provider data', () {
    final track = Track(
      id: 'chaptered',
      title: 'Long form',
      duration: const Duration(minutes: 5),
      chapters: <TrackChapter>[
        TrackChapter(start: const Duration(minutes: 4), title: 'Wrap up'),
        TrackChapter(start: Duration.zero, title: 'Start'),
        TrackChapter(start: const Duration(minutes: 5), title: 'Too late'),
      ],
    );

    final restored = Track.fromJson(track.toJson());

    expect(restored.chapters.map((chapter) => chapter.title), <String>[
      'Start',
      'Wrap up',
    ]);
    expect(
      Track.fromJson(<String, Object?>{
        'id': 'legacy',
        'title': 'Legacy',
        'chapters': <Object?>[
          <String, Object?>{'startMs': -1, 'title': 'Bad'},
          <String, Object?>{'startMs': 1000, 'title': 'Good'},
        ],
      }).chapters.single.title,
      'Good',
    );
  });
}
