import 'dart:convert';
import 'dart:io';

import 'package:aethertune/main.dart' as app;
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/ui/home_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'support/native_sync_transport_contracts.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const avd = String.fromEnvironment('AETHERTUNE_ANDROID_AVD');

  testWidgets(
    'native Android platform TLS acceptance',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      expect(avd.startsWith('AetherTune_Acceptance_'), isTrue);
      for (final property in {
        'ro.kernel.qemu': '1',
        'ro.boot.qemu.avd_name': avd,
      }.entries) {
        final result = await Process.run('/system/bin/getprop', [
          property.key,
        ]).timeout(const Duration(seconds: 5));
        expect(result.exitCode, 0);
        expect((result.stdout as String).trim(), property.value);
      }
      final support = await getApplicationSupportDirectory();
      final fixture = Directory(p.join(support.path, 'android-sync-fixture'));
      expect(
        await File(p.join(fixture.path, 'marker')).readAsString(),
        'aethertune-android-sync-acceptance-v1\n',
      );
      final report = <String, Object?>{
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'pid': pid,
        'os': Platform.operatingSystemVersion,
        'scope':
            'Real Android app and executor; synthetic CA in disposable guest AndroidCAStore. Not physical-device or deployed HTTPS acceptance.',
      };
      try {
        final setupLibrary = LibraryStore();
        try {
          await setupLibrary.load();
          expect(setupLibrary.loadError, isNull);
          await setupLibrary.setOnboardingCompleted(true);
          await setupLibrary.setOfflineModeEnabled(true);
          expect(setupLibrary.saveError, isNull);
        } finally {
          setupLibrary.dispose();
        }
        final assertionHandler = FlutterError.onError;
        await app.main();
        FlutterError.onError = assertionHandler;
        final watch = Stopwatch()..start();
        while (find.byType(HomeScreen).evaluate().isEmpty) {
          if (watch.elapsed > const Duration(seconds: 25)) {
            fail('The real Android application did not reach its home screen.');
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        final checks = await runNativeSyncTransportContracts(
          certificateDirectory: fixture.path,
          evidenceDirectory: fixture.path,
        );
        expect(checks, hasLength(8));
        expect(checks.every((check) => check['passed'] == true), isTrue);
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        report['checks'] = [
          {'name': 'actual-application-home-screen', 'passed': true},
          ...checks,
        ];
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
        await File(p.join(support.path, 'android-sync.json')).writeAsString(
          const JsonEncoder.withIndent('  ').convert(report),
          flush: true,
        );
        binding.reportData = report;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
