import 'dart:convert';
import 'dart:io';

import 'package:aethertune/main.dart' as app;
import 'package:aethertune/src/ui/home_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'support/native_sync_transport_contracts.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Linux application sync transport', (tester) async {
    final home = Platform.environment['AETHERTUNE_ACCEPTANCE_HOME'];
    expect(Platform.isLinux, isTrue);
    expect(home, isNotNull);
    expect(Platform.environment['HOME'], home);
    expect(await Directory(home!).resolveSymbolicLinks(), home);
    expect(
      await File(p.join(home, '.aethertune-native-fixture')).readAsString(),
      'aethertune-native-acceptance-v1\n',
    );
    final certificates = p.join(home, 'certificates');
    expect(
      Platform.environment['SSL_CERT_FILE'],
      p.join(certificates, 'trusted-bundle.pem'),
    );
    final evidence = Directory(p.join(home, 'evidence'));
    await evidence.create(recursive: true);
    final report = <String, Object?>{
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'pid': pid,
      'scope': 'Actual Linux application startup and shared sync executor',
      'trustFixture': 'Process-local platform roots plus a synthetic test CA',
    };
    try {
      final assertionHandler = FlutterError.onError;
      await app.main();
      FlutterError.onError = assertionHandler;
      final watch = Stopwatch()..start();
      while (find.byType(HomeScreen).evaluate().isEmpty) {
        if (watch.elapsed > const Duration(seconds: 25)) {
          fail('The real application did not reach its home screen.');
        }
        await tester.pump(const Duration(milliseconds: 50));
      }
      final checks = await tester.runAsync(
        () => runNativeSyncTransportContracts(
          certificateDirectory: certificates,
          evidenceDirectory: evidence.path,
        ),
      );
      expect(checks, isNotNull);
      expect(checks, hasLength(8));
      expect(checks!.every((check) => check['passed'] == true), isTrue);
      report['checks'] = [
        {'name': 'actual-application-home-screen', 'passed': true},
        ...checks,
      ];
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      report['status'] = 'passed';
    } on Object catch (error, stack) {
      report.addAll({
        'status': 'failed',
        'error': error.toString(),
        'stack': stack.toString(),
      });
      rethrow;
    } finally {
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
      await File(p.join(evidence.path, 'sync.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    }
  });
}
