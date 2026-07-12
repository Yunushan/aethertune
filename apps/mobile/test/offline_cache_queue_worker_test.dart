import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/offline_cache_queue_worker.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('does not resolve media without an eligible foreground queue entry',
      () async {
    final root = await Directory.systemTemp.createTemp('aethertune-worker-');
    addTearDown(() => root.delete(recursive: true));
    final library = LibraryStore();
    await library.load();
    final worker = OfflineCacheQueueWorker(
      cacheRoot: root,
      resolveTrack: (_) => throw StateError('Resolver must not run.'),
    );

    expect(await worker.processNext(library), isNull);
    await library.setOfflineModeEnabled(true);
    expect(await worker.processNext(library), isNull);
  });
}
