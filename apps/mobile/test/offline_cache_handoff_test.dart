import 'dart:async';
import 'dart:io';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/offline_cache_background_scheduler.dart';
import 'package:aethertune/src/data/offline_cache_queue_worker.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/ui/widgets/offline_cache_foreground_worker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('paused initial mount never starts foreground work', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await fixture.mount();
    tester.binding.scheduleForcedFrame();
    await tester.pumpAndSettle();

    expect(fixture.createdWorkers, 0);
    expect(fixture.calls, contains('schedule'));
  });

  testWidgets('pause cancels and drains before persisting the handoff', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await fixture.mount();
    await tester.pumpAndSettle();
    expect(fixture.worker.started, isTrue);
    fixture.calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(fixture.worker.stopCalls, 1);
    expect(fixture.calls, isEmpty);
    expect(
      fixture.library.offlineCacheEntryById(fixture.entry.id)!.status,
      OfflineCacheEntryStatus.processing,
    );

    fixture.worker.finish.complete();
    await tester.pumpAndSettle();
    expect(fixture.calls, ['schedule']);
    expect(
      fixture.library.offlineCacheEntryById(fixture.entry.id)!.status,
      OfflineCacheEntryStatus.queued,
    );
    expect(fixture.createdWorkers, 1);
    await tester.pump(const Duration(minutes: 2));
    expect(fixture.createdWorkers, 1);
    expect(fixture.calls, ['schedule']);
  });

  testWidgets('resume waits for cancellation then reloads background changes', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await fixture.mount();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fixture.worker.finish.complete();
    await tester.pumpAndSettle();

    final background = LibraryStore();
    await background.load();
    await background.markOfflineCacheEntryCached(
      fixture.entry.id,
      fixture.entry.track,
      reason: 'Completed by background engine',
    );
    background.dispose();
    expect(
      fixture.library.offlineCacheQueue.single.status,
      OfflineCacheEntryStatus.queued,
    );
    final cancellation = Completer<void>();
    fixture.onCall = (call) async {
      if (call.method == 'cancel') await cancellation.future;
      return true;
    };
    fixture.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.calls, ['cancel']);
    expect(fixture.createdWorkers, 1);
    expect(
      fixture.library.offlineCacheQueue.single.status,
      OfflineCacheEntryStatus.queued,
    );

    cancellation.complete();
    await tester.pumpAndSettle();
    expect(
      fixture.library.offlineCacheQueue.single.status,
      OfflineCacheEntryStatus.cached,
    );
    expect(fixture.library.saveError, isNull);
    expect(fixture.createdWorkers, 1);
    await fixture.library.setOfflineModeEnabled(true);
    expect(fixture.library.saveError, isNull);
  });

  testWidgets('rapid resume cancels a pending schedule before any new worker', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await fixture.mount();
    await tester.pumpAndSettle();
    fixture.calls.clear();
    final schedule = Completer<void>();
    fixture.onCall = (call) async {
      if (call.method == 'schedule') await schedule.future;
      return true;
    };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fixture.worker.finish.complete();
    await tester.pumpAndSettle();
    expect(fixture.calls, ['schedule']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(fixture.createdWorkers, 1);
    expect(fixture.calls, ['schedule']);

    schedule.complete();
    await tester.pumpAndSettle();
    expect(fixture.calls, ['schedule', 'cancel']);
    expect(fixture.createdWorkers, 2);
    expect(fixture.library.saveError, isNull);
  });

  testWidgets('pause during worker creation cannot start the late worker', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    final creation = Completer<OfflineCacheQueueWorker>();
    fixture.workerCreation = () => creation.future;
    await fixture.mount();
    await tester.pumpAndSettle();
    expect(fixture.createdWorkers, 1);
    fixture.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(fixture.calls, isEmpty);
    creation.complete(fixture.worker);
    await tester.pumpAndSettle();
    expect(fixture.worker.started, isFalse);
    expect(fixture.worker.stopCalls, 1);
    expect(fixture.calls, ['schedule']);
  });

  testWidgets('scheduler failure stops automatic retries and is reported', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    fixture.onCall = (_) async =>
        throw PlatformException(code: 'cancel-failed');
    await fixture.mount();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<PlatformException>());
    expect(fixture.createdWorkers, 0);
    expect(fixture.calls, ['cancel']);
    await tester.pump(const Duration(minutes: 2));
    expect(fixture.calls, ['cancel']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('worker platform failure is reported without a retry loop', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    fixture.workerCreation = () async =>
        throw StateError('Documents unavailable');
    await fixture.mount();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(fixture.createdWorkers, 1);
    await fixture.library.setOfflineCacheLimitMegabytes(128);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 2));
    expect(fixture.createdWorkers, 1);
    expect(tester.takeException(), isNull);
  });

  for (final missing in [false, true]) {
    testWidgets('unacknowledged native stop blocks resume: missing=$missing', (
      tester,
    ) async {
      final fixture = await _Fixture.create(tester);
      fixture.onCall = (_) async {
        if (missing) throw MissingPluginException('No stop handshake');
        return false;
      };
      await fixture.mount();
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        missing ? isA<MissingPluginException>() : isA<StateError>(),
      );
      expect(fixture.createdWorkers, 0);
      await tester.pump(const Duration(minutes: 2));
      expect(fixture.createdWorkers, 0);
      fixture.onCall = (_) async => true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(fixture.createdWorkers, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a rejected native schedule is reported instead of accepted', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await fixture.mount();
    await tester.pumpAndSettle();
    fixture.calls.clear();
    fixture.onCall = (_) async => false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fixture.worker.finish.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<StateError>());
    expect(fixture.calls, ['schedule']);
    expect(
      fixture.library.offlineCacheQueue.single.status,
      OfflineCacheEntryStatus.queued,
    );
    await tester.pump(const Duration(minutes: 2));
    expect(fixture.calls, ['schedule']);
    expect(fixture.createdWorkers, 1);
  });

  testWidgets('desktop tray pause keeps the same worker active', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await fixture.mount(platform: TargetPlatform.linux);
    await tester.pumpAndSettle();
    fixture.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(fixture.worker.stopCalls, 0);
    expect(fixture.calls, isEmpty);
    expect(fixture.createdWorkers, 1);
  });

  testWidgets('dispose stops the active pass without scheduling work', (
    tester,
  ) async {
    final fixture = await _Fixture.create(tester);
    await fixture.mount();
    await tester.pumpAndSettle();
    fixture.calls.clear();
    await tester.pumpWidget(const SizedBox());
    expect(fixture.worker.stopCalls, 1);
    fixture.worker.finish.complete();
    await tester.pumpAndSettle();
    expect(fixture.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  _Fixture(this.tester, this.library, this.entry, this.worker);

  final WidgetTester tester;
  final LibraryStore library;
  final OfflineCacheEntry entry;
  final _DrainingWorker worker;
  final calls = <String>[];
  int createdWorkers = 0;
  Future<Object?> Function(MethodCall)? onCall;
  Future<OfflineCacheQueueWorker> Function()? workerCreation;
  static const channel = MethodChannel('aethertune/test-cache-handoff');

  static Future<_Fixture> create(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final library = LibraryStore();
    await library.load();
    await library.setAutomaticOfflineQueueEnabled(true);
    final track = Track(
      id: 'handoff',
      title: 'Handoff',
      localPath: '/fixture.wav',
    );
    final entry = await library.queueOfflineCache(
      track,
      OfflineMediaAction.cache,
      const OfflineMediaPolicy(
        <MusicSourceProvider>[],
      ).evaluate(track, OfflineMediaAction.cache),
    );
    final worker = _DrainingWorker(entry.id);
    final fixture = _Fixture(tester, library, entry, worker);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      fixture.calls.add(call.method);
      if (fixture.onCall != null) return fixture.onCall!(call);
      return true;
    });
    addTearDown(() async {
      if (!worker.finish.isCompleted) worker.finish.complete();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      library.dispose();
    });
    return fixture;
  }

  Future<void> mount({TargetPlatform platform = TargetPlatform.android}) =>
      tester.pumpWidget(
        ChangeNotifierProvider<LibraryStore>.value(
          value: library,
          child: OfflineCacheForegroundWorker(
            platform: platform,
            backgroundScheduler: OfflineCacheBackgroundScheduler(
              channel: channel,
              isSupported: true,
            ),
            createWorker: () async {
              createdWorkers++;
              return workerCreation == null ? worker : await workerCreation!();
            },
            child: const SizedBox(),
          ),
        ),
      );
}

class _DrainingWorker extends OfflineCacheQueueWorker {
  _DrainingWorker(this.entryId)
    : super(
        cacheRoot: Directory.systemTemp,
        resolveTrack: (track) async => track,
      );

  final String entryId;
  final finish = Completer<void>();
  bool started = false;
  int stopCalls = 0;

  @override
  void stop() => stopCalls++;

  @override
  Future<List<OfflineCacheEntry>> processPending(
    LibraryStore library, {
    int maxEntries = OfflineCacheQueueWorker.defaultMaximumEntriesPerPass,
  }) async {
    started = true;
    await library.markOfflineCacheEntryProcessing(entryId);
    await finish.future;
    return [];
  }
}
