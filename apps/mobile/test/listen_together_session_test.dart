import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/listen_together_session.dart';

void main() {
  test('keeps legacy unique-ID sessions readable', () {
    final session = ListenTogetherSession.fromJson(<String, Object?>{
      'version': 1,
      'trackIds': <String>['first', 'second'],
      'currentTrackId': 'second',
      'positionMilliseconds': 12000,
      'playing': true,
    });

    expect(session.currentIndex, isNull);
    expect(session.toJson()['version'], 1);
  });

  test('round-trips repeated entries with their selected occurrence', () {
    final session = ListenTogetherSession.fromJson(<String, Object?>{
      'version': 2,
      'trackIds': <String>['first', 'second', 'first'],
      'currentTrackId': 'first',
      'currentIndex': 2,
      'positionMilliseconds': 12000,
      'playing': true,
    });

    expect(session.trackIds, <String>['first', 'second', 'first']);
    expect(session.currentIndex, 2);
    expect(session.toJson()['version'], 2);
    expect(session.toJson()['currentIndex'], 2);
  });

  test('rejects a v2 selection that does not match its queue item', () {
    expect(
      () => ListenTogetherSession.fromJson(<String, Object?>{
        'version': 2,
        'trackIds': <String>['first', 'second'],
        'currentTrackId': 'first',
        'currentIndex': 1,
        'positionMilliseconds': 0,
        'playing': false,
      }),
      throwsFormatException,
    );
  });
}
