import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune/src/data/local_diagnostic_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

const _secret = 'AUDIT_SYNTHETIC_SECRET';
const _source = 'package:aethertune/src/player/player_controller.dart';
const _stack =
    '#0 PlayerController.play ($_source:120:7)\n'
    '#1 _Future._propagateToListeners (dart:async/future_impl.dart:720:3)';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'persists useful structured diagnostics without calling error.toString',
    () async {
      final now = DateTime.utc(2026, 9, 5, 18);
      final log = LocalDiagnosticLog(clock: () => now);
      addTearDown(log.dispose);
      await log.record(
        _DangerousError(),
        stackTrace: StackTrace.fromString(_stack),
        origin: 'flutter',
      );
      expect(log.persistenceError, isFalse);
      final entry = log.entries.single;
      expect(entry.recordedAt, now);
      expect(entry.origin, 'flutter');
      expect(entry.category, LocalDiagnosticCategory.exception);
      expect(entry.message, 'Operation failed');
      expect(entry.frames.map((frame) => frame.uri), [
        _source,
        'dart:async/future_impl.dart',
      ]);
      expect(entry.frames.first.line, 120);
      expect(entry.frames.first.column, 7);
      final exported = jsonDecode(log.exportJson()) as Map;
      expect(exported['version'], 2);
      expect(exported['privacy'], contains('explicit user action'));
      final restored = LocalDiagnosticLog();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.entries.single.toJson(), entry.toJson());
    },
  );

  final sensitiveFormats = [
    'token=$_secret',
    'access_token=$_secret',
    'refresh_token=$_secret',
    '{"token":"$_secret"}',
    '{"nested":{"password":"$_secret"}}',
    'Authorization: Bearer $_secret',
    'Cookie: session=$_secret',
    'https://example.invalid/song?access_token=$_secret',
    'https://example.invalid/song?p=$_secret&t=$_secret',
    'https://example.invalid/song?%61ccess_token=$_secret',
    'https://example.invalid/$_secret/song',
    'https://$_secret:$_secret@example.invalid/song',
    'file:///private/$_secret/song.mp3',
    r'C:\Users\AUDIT_SYNTHETIC_SECRET\Music\song.mp3',
    'Bearer $_secret',
    _secret,
  ];
  for (var index = 0; index < sensitiveFormats.length; index++) {
    test(
      'omits sensitive payload format $index from all capture fields',
      () async {
        final value = sensitiveFormats[index];
        final log = LocalDiagnosticLog();
        addTearDown(log.dispose);
        await log.record(
          HttpException(
            value,
            uri: Uri.parse('https://example.invalid/$_secret'),
          ),
          origin: value,
          stackTrace: StackTrace.fromString(
            '$value\n#0 $_secret ($_source:1:2)',
          ),
        );
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString(LocalDiagnosticLog.storageKey),
          isNot(contains(_secret)),
        );
        expect(log.exportJson(), isNot(contains(_secret)));
        expect(log.entries.single.origin, 'unknown');
        expect(log.entries.single.category, LocalDiagnosticCategory.http);
      },
    );
  }

  final categories = <Object, LocalDiagnosticCategory>{
    FlutterError(_secret): LocalDiagnosticCategory.framework,
    PlatformException(
      code: _secret,
      message: _secret,
      details: {'password': _secret},
    ): LocalDiagnosticCategory.platform,
    MissingPluginException(_secret): LocalDiagnosticCategory.missingPlugin,
    const SocketException(_secret): LocalDiagnosticCategory.network,
    const HttpException(_secret): LocalDiagnosticCategory.http,
    TimeoutException(_secret): LocalDiagnosticCategory.timeout,
    const FileSystemException(_secret, _secret):
        LocalDiagnosticCategory.filesystem,
    const FormatException(_secret, _secret): LocalDiagnosticCategory.format,
    ArgumentError.value(_secret): LocalDiagnosticCategory.argument,
    StateError(_secret): LocalDiagnosticCategory.state,
    TypeError(): LocalDiagnosticCategory.type,
    UnsupportedError(_secret): LocalDiagnosticCategory.unsupported,
    AssertionError(_secret): LocalDiagnosticCategory.assertion,
    Exception(_secret): LocalDiagnosticCategory.exception,
    _secret: LocalDiagnosticCategory.unknown,
  };
  for (final item in categories.entries) {
    test('retains category ${item.value.name} without raw details', () async {
      final log = LocalDiagnosticLog();
      addTearDown(log.dispose);
      await log.record(item.key, origin: 'platform-dispatcher');
      expect(log.entries.single.category, item.value);
      expect(log.exportJson(), isNot(contains(_secret)));
    });
  }

  test('keeps bounded numeric OS and platform codes only', () async {
    final log = LocalDiagnosticLog();
    addTearDown(log.dispose);
    for (final error in [
      const FileSystemException(_secret, _secret, OSError(_secret, 28)),
      const SocketException(_secret, osError: OSError(_secret, 61)),
      PlatformException(code: '404', message: _secret),
      PlatformException(code: _secret),
      PlatformException(code: '2147483648'),
      PlatformException(code: '9' * 10000),
    ]) {
      await log.record(error, origin: 'flutter');
    }
    expect(log.entries.map((entry) => entry.code).whereType<int>().toSet(), {
      28,
      61,
      404,
    });
    expect(log.exportJson(), isNot(contains(_secret)));
  });

  test('retains runtime Dart frames from a real parsing failure', () async {
    final log = LocalDiagnosticLog();
    addTearDown(log.dispose);
    try {
      jsonDecode('{');
      fail('Expected a parse error');
    } catch (error, stack) {
      await log.record(error, stackTrace: stack, origin: 'flutter');
    }
    expect(log.entries.single.category, LocalDiagnosticCategory.format);
    expect(log.entries.single.frames, isNotEmpty);
    expect(
      log.entries.single.frames.any(
        (frame) => frame.uri.startsWith('dart:convert/'),
      ),
      isTrue,
    );
  });

  for (final uri in [
    'https://example.invalid/$_secret.dart',
    'file:///home/$_secret.dart',
    r'C:\private\AUDIT_SYNTHETIC_SECRET.dart',
    'package:aethertune/file.dart?token=$_secret',
    'package:aethertune/file.dart#$_secret',
    'package://$_secret@aethertune/file.dart',
    'package:aethertune/%41UDIT_SYNTHETIC_SECRET.dart',
    _secret,
  ]) {
    test('rejects an unsafe stored source location $uri', () {
      expect(
        LocalDiagnosticFrame.fromJson({'uri': uri, 'line': 1, 'column': 2}),
        isNull,
      );
    });
  }

  test('bounds frames and handles invalid or throwing stack traces', () async {
    final log = LocalDiagnosticLog();
    addTearDown(log.dispose);
    await log.record(
      Exception(),
      origin: 'flutter',
      stackTrace: StackTrace.fromString(List.filled(30, _stack).join('\n')),
    );
    expect(log.entries.single.frames, hasLength(12));
    await log.record(
      Exception(),
      origin: 'flutter',
      stackTrace: _BrokenStack(),
    );
    expect(log.entries.first.frames, isEmpty);
    await log.record(
      Exception(),
      origin: 'flutter',
      stackTrace: StackTrace.fromString('#bad $_secret\n${'x' * 20000}'),
    );
    expect(log.entries.first.frames, isEmpty);
    expect(log.exportJson(), isNot(contains(_secret)));
  });

  test(
    'removes legacy reports while preserving unrelated preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalDiagnosticLog.legacyStorageKey: '{"access_token":"$_secret"}',
        'aethertune.tracks.v1': 'keep-library',
        'provider-secret': 'keep-credential',
      });
      final log = LocalDiagnosticLog();
      addTearDown(log.dispose);
      await log.load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.containsKey(LocalDiagnosticLog.legacyStorageKey), isFalse);
      expect(prefs.getString('aethertune.tracks.v1'), 'keep-library');
      expect(prefs.getString('provider-secret'), 'keep-credential');
      expect(log.entries, isEmpty);
      expect(log.persistenceError, isFalse);
    },
  );

  test(
    'rewrites untrusted v2 fields instead of trusting its version marker',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalDiagnosticLog.storageKey: jsonEncode({
          'version': 2,
          'entries': [
            {'recordedAt': 123},
            {'recordedAt': 'not-a-date'},
            {
              'recordedAt': '2026-09-05T15:00:00Z',
              'category': _secret,
              'origin': _secret,
              'message': _secret,
              'stackTrace': _secret,
              'code': _secret,
              'frames': [
                {
                  'uri': 'https://example.invalid/$_secret',
                  'line': 1,
                  'column': 1,
                },
                {'uri': _source, 'line': 10, 'column': 3, 'payload': _secret},
              ],
            },
          ],
          'extra': _secret,
        }),
      });
      final log = LocalDiagnosticLog();
      addTearDown(log.dispose);
      await log.load();
      expect(log.entries, hasLength(1));
      expect(log.entries.single.category, LocalDiagnosticCategory.unknown);
      expect(log.entries.single.frames, hasLength(1));
      expect(log.exportJson(), isNot(contains(_secret)));
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalDiagnosticLog.storageKey,
        ),
        isNot(contains(_secret)),
      );
    },
  );

  for (final raw in <Object>[
    '{bad',
    '{"version":99}',
    10,
    'x' * (LocalDiagnosticLog.maximumStoredCharacters + 1),
  ]) {
    test(
      'repairs malformed or oversized diagnostics ${raw.runtimeType}',
      () async {
        SharedPreferences.setMockInitialValues({
          LocalDiagnosticLog.storageKey: raw,
        });
        final log = LocalDiagnosticLog();
        addTearDown(log.dispose);
        await log.load();
        expect(log.loaded, isTrue);
        expect(log.persistenceError, isFalse);
        expect(log.entries, isEmpty);
        expect(
          (await SharedPreferences.getInstance())
              .getString(LocalDiagnosticLog.storageKey)!
              .length,
          lessThan(LocalDiagnosticLog.maximumStoredCharacters),
        );
      },
    );
  }

  test(
    'serializes load record and clear without resurrecting cleared reports',
    () async {
      var now = DateTime.utc(2026, 9, 5);
      final log = LocalDiagnosticLog(
        clock: () => now = now.add(const Duration(seconds: 1)),
      );
      addTearDown(log.dispose);
      final before = log.record(
        const FileSystemException('', '', OSError('', 1)),
        origin: 'flutter',
      );
      final cleared = log.clear();
      final after = log.record(
        const FileSystemException('', '', OSError('', 2)),
        origin: 'flutter',
      );
      await Future.wait([before, cleared, after]);
      expect(await cleared, isTrue);
      expect(log.entries.single.code, 2);
      final restored = LocalDiagnosticLog();
      addTearDown(restored.dispose);
      await restored.load();
      expect(restored.entries.single.code, 2);
    },
  );

  test(
    'record before load preserves existing history and retention is bounded',
    () async {
      var now = DateTime.utc(2026, 9, 5);
      LocalDiagnosticLog create() => LocalDiagnosticLog(
        clock: () => now = now.add(const Duration(seconds: 1)),
      );
      final first = create();
      await first.record(
        const FileSystemException('', '', OSError('', 0)),
        origin: 'flutter',
      );
      first.dispose();
      final log = create();
      addTearDown(log.dispose);
      await log.record(
        const FileSystemException('', '', OSError('', 1)),
        origin: 'flutter',
      );
      expect(log.entries, hasLength(2));
      for (var index = 2; index <= 45; index++) {
        await log.record(
          FileSystemException('', '', OSError('', index)),
          origin: 'flutter',
        );
      }
      expect(log.entries, hasLength(LocalDiagnosticLog.maximumEntries));
      expect(log.entries.first.code, 45);
      expect(log.entries.last.code, 6);
      expect(
        log.exportJson().length,
        lessThan(LocalDiagnosticLog.maximumStoredCharacters),
      );
    },
  );

  test(
    'failed writes stay in memory without recursively throwing and retry',
    () async {
      final store = await _installStore();
      store.rejectWrites = true;
      final log = LocalDiagnosticLog();
      addTearDown(log.dispose);
      await log.record(Exception(_secret), origin: 'flutter');
      expect(log.persistenceError, isTrue);
      expect(log.entries, hasLength(1));
      store.rejectWrites = false;
      await log.record(Exception(_secret), origin: 'flutter');
      expect(log.persistenceError, isFalse);
      expect(log.entries, hasLength(2));
    },
  );

  test(
    'failed legacy cleanup is visible and clearing retries even with no entries',
    () async {
      final store = await _installStore({
        LocalDiagnosticLog.legacyStorageKey: _secret,
        'unrelated': 'preserve',
      });
      store.rejectRemovals = true;
      final log = LocalDiagnosticLog();
      addTearDown(log.dispose);
      await log.load();
      expect(log.persistenceError, isTrue);
      expect(log.entries, isEmpty);
      expect(log.exportJson(), isNot(contains(_secret)));
      expect(await log.clear(), isFalse);
      store.rejectRemovals = false;
      expect(await log.clear(), isTrue);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect(prefs.containsKey(LocalDiagnosticLog.legacyStorageKey), isFalse);
      expect(prefs.containsKey(LocalDiagnosticLog.storageKey), isFalse);
      expect(prefs.getString('unrelated'), 'preserve');
    },
  );

  test(
    'platform read exceptions never escape startup or error capture',
    () async {
      final store = await _installStore();
      store.throwReads = true;
      final log = LocalDiagnosticLog();
      addTearDown(log.dispose);
      await log.load();
      await log.record(Exception(_secret), origin: 'flutter');
      expect(log.loaded, isTrue);
      expect(log.persistenceError, isTrue);
      expect(await log.clear(), isFalse);
      store.throwReads = false;
      expect(await log.clear(), isTrue);
      expect(log.exportJson(), isNot(contains(_secret)));
    },
  );

  test(
    'bounds pending error storms and persists discarded report counts',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalDiagnosticLog.storageKey: jsonEncode({
          'version': 2,
          'discardedReports': 7,
          'entries': [],
        }),
      });
      final log = LocalDiagnosticLog();
      addTearDown(log.dispose);
      await Future.wait([
        for (var index = 0; index < 100; index++)
          log.record(Exception(_secret), origin: 'flutter'),
      ]);
      expect(log.entries, hasLength(LocalDiagnosticLog.maximumPendingRecords));
      expect((jsonDecode(log.exportJson()) as Map)['discardedReports'], 67);
      final restarted = LocalDiagnosticLog();
      addTearDown(restarted.dispose);
      await restarted.load();
      expect(
        (jsonDecode(restarted.exportJson()) as Map)['discardedReports'],
        67,
      );
      expect(await restarted.clear(), isTrue);
      expect(
        (jsonDecode(restarted.exportJson()) as Map)['discardedReports'],
        0,
      );
    },
  );

  test('new reports after disposal do not restart storage work', () async {
    final log = LocalDiagnosticLog();
    log.dispose();
    await log.record(Exception(_secret), origin: 'flutter');
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        LocalDiagnosticLog.storageKey,
      ),
      isFalse,
    );
  });

  test('pending capture finishes safely after notifier disposal', () async {
    final log = LocalDiagnosticLog();
    final pending = log.record(Exception(_secret), origin: 'flutter');
    log.dispose();
    await pending;
  });
}

class _DangerousError implements Exception {
  @override
  String toString() =>
      throw StateError('Error payload must never be evaluated');
}

class _BrokenStack implements StackTrace {
  @override
  String toString() => throw StateError('Stack unavailable');
}

Future<_DiagnosticStore> _installStore([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  final previous = SharedPreferencesStorePlatform.instance;
  final store = _DiagnosticStore(await previous.getAll());
  SharedPreferencesStorePlatform.instance = store;
  addTearDown(() {
    SharedPreferencesStorePlatform.instance = previous;
    SharedPreferences.setMockInitialValues({});
  });
  return store;
}

class _DiagnosticStore extends InMemorySharedPreferencesStore {
  _DiagnosticStore(super.data) : super.withData();
  bool rejectWrites = false;
  bool rejectRemovals = false;
  bool throwReads = false;

  @override
  Future<Map<String, Object>> getAll() async {
    if (throwReads) throw StateError(_secret);
    return super.getAll();
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (rejectWrites) return false;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (rejectRemovals) return false;
    return super.remove(key);
  }
}
