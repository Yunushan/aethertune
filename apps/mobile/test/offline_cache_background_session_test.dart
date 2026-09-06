import 'dart:async';

import 'package:aethertune/src/data/offline_cache_background_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('aethertune/test-background-session');
const _codec = StandardMethodCodec();

Future<Object?> _nativeCall(String method) {
  final result = Completer<Object?>();
  ServicesBinding.instance.channelBuffers.push(
    _channel.name,
    _codec.encodeMethodCall(MethodCall(method)),
    (data) {
      try {
        result.complete(data == null ? null : _codec.decodeEnvelope(data));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    },
  );
  return result.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    messenger.setMockMethodCallHandler(_channel, (_) async => true);
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    _channel.setMethodCallHandler(null);
  });

  test('stop waits for the work and its persistence cleanup', () async {
    final session = OfflineCacheBackgroundSession(channel: _channel);
    final started = Completer<void>();
    final work = Completer<void>();
    final cleanup = Completer<void>();
    final events = <String>[];
    final run = session.run((signal) async {
      signal.cancelCurrentWith(() => events.add('cancel'));
      started.complete();
      try {
        await work.future;
      } finally {
        events.add('cleanup-start');
        await cleanup.future;
        events.add('cleanup-end');
      }
    });
    await started.future;
    final stop = _nativeCall('stop').then((reply) {
      events.add('ack');
      return reply;
    });
    await Future<void>.delayed(Duration.zero);
    expect(session.shouldContinue, isFalse);
    expect(events, ['cancel']);
    work.complete();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['cancel', 'cleanup-start']);
    cleanup.complete();
    await run;
    expect(await stop, isTrue);
    expect(events, ['cancel', 'cleanup-start', 'cleanup-end', 'ack']);
    expect(await _nativeCall('stop'), isTrue);
  });

  test('stop before ready prevents all work', () async {
    final ready = Completer<bool>();
    final requested = Completer<void>();
    messenger.setMockMethodCallHandler(_channel, (_) {
      requested.complete();
      return ready.future;
    });
    final session = OfflineCacheBackgroundSession(channel: _channel);
    var calls = 0;
    final run = session.run((_) async {
      calls++;
    });
    await requested.future;
    final stop = _nativeCall('stop');
    await Future<void>.delayed(Duration.zero);
    ready.complete(true);
    await run;
    expect(await stop, isTrue);
    expect(calls, 0);
  });

  for (final reply in <Object?>[false, null]) {
    test('denied ready reply $reply prevents work', () async {
      messenger.setMockMethodCallHandler(_channel, (_) async => reply);
      final session = OfflineCacheBackgroundSession(channel: _channel);
      await session.run((_) async => fail('Denied engine must not run.'));
      expect(session.shouldContinue, isFalse);
      expect(await _nativeCall('stop'), isTrue);
    });
  }

  test('work failure still drains before acknowledging stop', () async {
    final session = OfflineCacheBackgroundSession(channel: _channel);
    final started = Completer<void>();
    final work = Completer<void>();
    final run = session.run((_) async {
      started.complete();
      await work.future;
    });
    final failure = expectLater(run, throwsStateError);
    await started.future;
    final firstStop = _nativeCall('stop');
    final secondStop = _nativeCall('stop');
    work.completeError(StateError('Fixture write failed'));
    await failure;
    expect(await firstStop, isTrue);
    expect(await secondStop, isTrue);
  });

  test(
    'late cancellation hook is notified once and session cannot rerun',
    () async {
      final session = OfflineCacheBackgroundSession(channel: _channel);
      final started = Completer<void>();
      final release = Completer<void>();
      var cancellations = 0;
      final run = session.run((signal) async {
        started.complete();
        await release.future;
        signal.cancelCurrentWith(() {
          cancellations++;
        });
      });
      await started.future;
      final stop = _nativeCall('stop');
      await Future<void>.delayed(Duration.zero);
      release.complete();
      await run;
      expect(await stop, isTrue);
      expect(cancellations, 1);
      await expectLater(session.run((_) async {}), throwsStateError);
    },
  );

  test(
    'missing ready method fails closed and unknown messages are rejected',
    () async {
      messenger.setMockMethodCallHandler(_channel, null);
      final session = OfflineCacheBackgroundSession(channel: _channel);
      await expectLater(
        session.run((_) async => fail('No ready handshake.')),
        throwsA(isA<MissingPluginException>()),
      );
      expect(await _nativeCall('stop'), isTrue);
      expect(await _nativeCall('unknown'), isNull);
    },
  );
}
