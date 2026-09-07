import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:aethertune/main.dart' as app;
import 'package:aethertune/src/data/library_sync_transport.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/native_sync_transport_contracts.dart';

const _input = r'C:\Input';
const _evidence = r'C:\Evidence';
const _fixture = 'aethertune-windows-sync-acceptance-v1\n';

// The native runner registers a URL scheme before this guard executes. This
// test entrypoint must only be launched by the isolated Sandbox guest driver.
Future<void> main() async {
  if (!Platform.isWindows ||
      Platform.environment['USERNAME'] != 'WDAGUtilityAccount' ||
      Platform.environment['USERPROFILE'] != r'C:\Users\WDAGUtilityAccount' ||
      await File('$_input/sync-fixture-v1').readAsString() != _fixture) {
    exit(2);
  }
  final phase = Platform.environment['AETHERTUNE_SYNC_PHASE'];
  final checks = <Map<String, Object?>>[];
  final errors = <String>[];
  final report = <String, Object?>{
    'phase': phase,
    'pid': pid,
    'startedAt': DateTime.now().toUtc().toIso8601String(),
    'checks': checks,
    'frameworkErrors': errors,
    'scope': 'Actual application startup and sync executor in Windows Sandbox',
  };
  var code = 1;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    _require(
      await prefs.setBool('aethertune.onboarding_completed.v1', true) &&
          await prefs.setBool('aethertune.offline_mode.v1', true),
      'Guest preferences could not be seeded',
    );
    await app.main();
    final previousFrameworkError = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details.exception.runtimeType.toString());
      previousFrameworkError?.call(details);
    };
    final previousPlatformError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      errors.add(error.runtimeType.toString());
      return previousPlatformError?.call(error, stack) ?? false;
    };
    await WidgetsBinding.instance.endOfFrame.timeout(
      const Duration(seconds: 10),
    );
    checks.add({'name': 'actual-application-first-frame', 'passed': true});
    if (phase == 'contracts') {
      checks.addAll(
        await runNativeSyncTransportContracts(
          certificateDirectory: '$_input/certificates',
          evidenceDirectory: _evidence,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      _require(errors.isEmpty, 'Unexpected asynchronous application error');
      report['status'] = 'passed';
      code = 0;
    } else if (phase == 'tls' || phase == 'headers' || phase == 'body') {
      final port = int.parse(Platform.environment['AETHERTUNE_SYNC_PORT']!);
      _require(port > 0 && port <= 65535, 'Invalid guest peer port');
      await _save('ready-$phase.json', {...report, 'status': 'ready'});
      // Production deadlines remain unchanged. The external guest peer proves
      // that native window close, not a timeout or forced process kill, ends it.
      await executeLibrarySyncHttpRequest(
        'GET',
        Uri.parse('${phase == 'tls' ? 'https' : 'http'}://127.0.0.1:$port/'),
        headers: nativeSyncAcceptanceHeaders,
      );
      throw StateError(
        'Unfinished request returned before native window close',
      );
    } else {
      throw StateError('Unknown acceptance phase');
    }
  } on Object catch (error, stack) {
    report.addAll({
      'status': 'failed',
      'error': error.toString(),
      'stack': stack.toString(),
    });
  }
  report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
  await _save('$phase.json', report);
  exit(code);
}

Future<void> _save(String name, Map<String, Object?> report) =>
    File('$_evidence/$name').writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}
