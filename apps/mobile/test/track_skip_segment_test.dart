import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_skip_segment.dart';

void main() {
  test('parses, sorts, and formats timestamped skip segments', () {
    final segments = parseTrackSkipSegments(
      '2:30-2:45 Outro\n0:30-0:45 Intro',
      maximum: const Duration(minutes: 3),
    );

    expect(segments.map((segment) => segment.label), <String>[
      'Intro',
      'Outro',
    ]);
    expect(segments.first.start, const Duration(seconds: 30));
    expect(
      formatTrackSkipSegments(segments),
      '0:30-0:45 Intro\n2:30-2:45 Outro',
    );
  });

  test('rejects malformed, overlapping, and out-of-range manual segments', () {
    expect(
      () => parseTrackSkipSegments('Introduction'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseTrackSkipSegments('0:30-0:45 Intro\n0:40-0:50 Overlap'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => parseTrackSkipSegments(
        '2:50-3:10 Ending',
        maximum: const Duration(minutes: 3),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('track skip segments round trip and discard invalid provider data', () {
    final track = Track(
      id: 'skippable',
      title: 'Long form',
      duration: const Duration(minutes: 5),
      skipSegments: <TrackSkipSegment>[
        TrackSkipSegment(
          start: const Duration(minutes: 4),
          end: const Duration(minutes: 4, seconds: 30),
          label: 'Credits',
        ),
      ],
    );

    final restored = Track.fromJson(track.toJson());

    expect(restored.skipSegments.single.label, 'Credits');
    expect(
      Track.fromJson(<String, Object?>{
        'id': 'legacy',
        'title': 'Legacy',
        'skipSegments': <Object?>[
          <String, Object?>{'startMs': -1, 'endMs': 1000},
          <String, Object?>{'startMs': 1000, 'endMs': 2000, 'label': 'Good'},
        ],
      }).skipSegments.single.label,
      'Good',
    );
  });
}
