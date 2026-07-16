import 'dart:convert';

import 'package:aethertune/src/data/local_diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists bounded, redacted local-only diagnostics', () async {
    var now = DateTime.utc(2026, 7, 16, 12);
    final log = LocalDiagnosticLog(clock: () => now);
    await log.load();

    await log.record(
      Exception(
        'token=never-export-this authorization: Bearer also-never-export\n'
        'file:///private/music/song.mp3 https://name:password@example.com',
      ),
      stackTrace: StackTrace.fromString('password=private-value'),
      origin: 'flutter',
    );

    expect(log.entries, hasLength(1));
    final entry = log.entries.single;
    expect(entry.message, contains('token=[redacted]'));
    expect(entry.message, contains('authorization=[redacted]'));
    expect(entry.message, contains('file://[redacted]'));
    expect(entry.message, contains('https://[redacted]@example.com'));
    expect(entry.message, isNot(contains('never-export-this')));
    expect(entry.message, isNot(contains('also-never-export')));
    expect(entry.stackTrace, contains('password=[redacted]'));
    expect(entry.stackTrace, isNot(contains('private-value')));

    final exported = jsonDecode(log.exportJson()) as Map<String, Object?>;
    expect(exported['format'], 'aethertune-local-diagnostics');
    expect(exported['privacy'], contains('explicit user action'));
    expect(exported['entries'], hasLength(1));

    final restored = LocalDiagnosticLog();
    await restored.load();
    expect(restored.entries.single.message, entry.message);
    expect(restored.entries.single.recordedAt, now);
    log.dispose();
    restored.dispose();
  });

  test('drops the oldest entries after the retention limit', () async {
    var now = DateTime.utc(2026, 7, 16, 12);
    final log = LocalDiagnosticLog(clock: () => now);
    await log.load();

    for (var index = 0; index <= LocalDiagnosticLog.maximumEntries; index++) {
      now = now.add(const Duration(seconds: 1));
      await log.record(Exception('failure-$index'), origin: 'test');
    }

    expect(log.entries, hasLength(LocalDiagnosticLog.maximumEntries));
    expect(log.entries.first.message, contains('failure-40'));
    expect(log.entries.last.message, contains('failure-1'));
    log.dispose();
  });
}
