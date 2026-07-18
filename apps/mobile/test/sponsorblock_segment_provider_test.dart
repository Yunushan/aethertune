import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/sponsorblock_segment_provider.dart';

void main() {
  test('accepts bounded enabled skip categories and normalizes segments', () {
    final segments = parseSponsorBlockSegments(
      '''[
        {"segment":[30,45],"category":"sponsor","actionType":"skip"},
        {"segment":[5,10],"category":"intro","actionType":"skip"},
        {"segment":[50,55],"category":"sponsor","actionType":"mute"},
        {"segment":[60,70],"category":"outro","actionType":"skip"}
      ]''',
      maximum: const Duration(seconds: 60),
      categories: const <String>{'sponsor', 'intro'},
    );

    expect(segments, hasLength(2));
    expect(segments.first.start, const Duration(seconds: 5));
    expect(segments.last.label, 'SponsorBlock: sponsor');
  });

  test('rejects malformed response shapes', () {
    expect(
      () => parseSponsorBlockSegments('{}', maximum: const Duration(minutes: 1)),
      throwsA(isA<FormatException>()),
    );
  });
}
