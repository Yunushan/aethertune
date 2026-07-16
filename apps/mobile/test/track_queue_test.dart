import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_queue.dart';

void main() {
  test('serializes queue snapshots with the current track', () {
    final snapshot = TrackQueueSnapshot(
      currentTrackId: '2',
      tracks: <Track>[_track('1'), _track('2')],
    );

    final restored = TrackQueueSnapshot.fromJson(snapshot.toJson());

    expect(restored.currentTrackId, '2');
    expect(restored.currentTrack?.id, '2');
    expect(restored.tracks.map((track) => track.id), <String>['1', '2']);
  });

  test('falls back to the first queue track when current track is missing', () {
    final snapshot = TrackQueueSnapshot(
      currentTrackId: 'missing',
      tracks: <Track>[_track('1'), _track('2')],
    );

    expect(snapshot.currentTrack?.id, '1');
  });

  test('bounds and validates privacy-safe queue sync references', () {
    final snapshot = TrackQueueReferenceSnapshot.fromJson(<String, Object?>{
      'version': TrackQueueReferenceSnapshot.syncVersion,
      'trackIds': <Object?>[' first ', 4, '', 'second'],
      'currentTrackId': ' second ',
      'updatedAt': '2026-07-16T12:00:00Z',
    });

    expect(snapshot.trackIds, <String>['first', 'second']);
    expect(snapshot.currentTrackId, 'second');
    expect(snapshot.updatedAt, DateTime.utc(2026, 7, 16, 12));
    expect(snapshot.toJson()['trackIds'], <String>['first', 'second']);
    expect(
      () => TrackQueueReferenceSnapshot.fromJson(<String, Object?>{
        'version': 2,
        'trackIds': <Object?>[],
        'updatedAt': '2026-07-16T12:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test('moves queue items without mutating the original queue', () {
    final queue = <Track>[
      _track('1'),
      _track('2'),
      _track('3'),
    ];

    final reordered = moveQueueItem(queue, 2, 0);

    expect(reordered.map((track) => track.id), <String>['3', '1', '2']);
    expect(queue.map((track) => track.id), <String>['1', '2', '3']);
  });

  test('ignores invalid queue move indexes', () {
    final queue = <Track>[_track('1'), _track('2')];

    expect(
      moveQueueItem(queue, -1, 1).map((track) => track.id),
      <String>['1', '2'],
    );
    expect(
      moveQueueItem(queue, 0, 9).map((track) => track.id),
      <String>['1', '2'],
    );
    expect(
      moveQueueItem(queue, 1, 1).map((track) => track.id),
      <String>['1', '2'],
    );
  });

  test('removes matching tracks from queue order', () {
    final queue = <Track>[
      _track('1'),
      _track('2'),
      _track('1'),
      _track('3'),
    ];

    final remaining = removeTrackFromQueueItems(queue, '1');

    expect(remaining.map((track) => track.id), <String>['2', '3']);
    expect(queue.map((track) => track.id), <String>['1', '2', '1', '3']);
  });
}

Track _track(String id) {
  return Track(
    id: id,
    title: 'Track $id',
    localPath: '/music/$id.mp3',
  );
}
