import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/domain/track_queue.dart';

void main() {
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
