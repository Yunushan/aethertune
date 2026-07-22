import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/offline_cache_background_scheduler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('schedules, cancels, and completes Android background queue work',
      () async {
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(offlineCacheBackgroundChannel, (
      call,
    ) async {
      calls.add(call);
      return call.method == 'schedule';
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        offlineCacheBackgroundChannel,
        null,
      ),
    );
    final scheduler = OfflineCacheBackgroundScheduler(isSupported: true);

    expect(
      await scheduler.schedule(minimumLatency: const Duration(hours: 12)),
      isTrue,
    );
    await scheduler.cancel();
    await scheduler.complete(hasPendingWork: true);
    await scheduler.complete(
      hasPendingWork: false,
      nextRunDelay: const Duration(hours: 1),
    );

    expect(calls.map((call) => call.method), <String>[
      'schedule',
      'cancel',
      'complete',
      'complete',
    ]);
    expect(
      calls.first.arguments,
      <String, Object>{'minimumLatencyMilliseconds': 43200000},
    );
    expect(calls[2].arguments, <String, Object>{'hasPendingWork': true});
    expect(calls.last.arguments, <String, Object>{
      'hasPendingWork': false,
      'nextRunDelayMilliseconds': 3600000,
    });
  });

  test('leaves unsupported platforms untouched', () async {
    final scheduler = OfflineCacheBackgroundScheduler(isSupported: false);

    expect(await scheduler.schedule(), isFalse);
    await scheduler.cancel();
    await scheduler.complete(hasPendingWork: false);
  });
}
