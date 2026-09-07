import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aethertune/main.dart' as app;
import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/local_diagnostic_log.dart';
import 'package:aethertune/src/data/offline_cache_background_scheduler.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/ios_acceptance_control.dart';
import 'support/native_sync_transport_contracts.dart';

const _secretKey = 'aethertune.ios.acceptance.secret';
const _secret = 'synthetic-ios-fixture-only';
const _seeded = 'aethertune.ios.acceptance.seeded';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const device = String.fromEnvironment('AETHERTUNE_ACCEPTANCE_UDID');
  const fixtureName = String.fromEnvironment('AETHERTUNE_ACCEPTANCE_NAME');
  const source = String.fromEnvironment('AETHERTUNE_ACCEPTANCE_SHA');

  testWidgets('native iOS acceptance', (tester) async {
    expect(Platform.isIOS, isTrue);
    final support = await getApplicationSupportDirectory();
    final fixture = Directory(p.join(support.path, 'aethertune-ios-fixture'));
    // Dart's iOS runtime exposes an empty Platform.environment. Read the
    // host-owned control file, bound to this binary and the actual guest path.
    final phase = iosAcceptancePhase(
      controlJson: await File(
        p.join(fixture.path, 'control.json'),
      ).readAsString(),
      supportPath: support.path,
      device: device,
      fixtureName: fixtureName,
      source: source,
    );
    expect(
      await File(p.join(fixture.path, 'marker')).readAsString(),
      'aethertune-ios-native-acceptance-v1\n',
    );
    final checks = <Map<String, Object?>>[];
    final report = <String, Object?>{
      'sourceCommit': source,
      'device': device,
      'phase': phase,
      'pid': pid,
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'os': Platform.operatingSystemVersion,
      'checks': checks,
      'scope':
          'Real iOS Simulator application, synthetic local library and guest-only CA. Not physical audio, signing, upgrades or deployed operations.',
    };
    void passed(String name) => checks.add({'name': name, 'passed': true});
    PlayerController? player;
    try {
      await OfflineCacheBackgroundScheduler().cancel();
      passed('native-background-cancellation');
      final prefs = await SharedPreferences.getInstance();
      const vault = FlutterSecureStorage();
      final media = File(p.join(support.path, 'ios-acceptance.wav'));
      if (phase == 'seed') {
        expect(prefs.getKeys(), isEmpty);
        expect(await createLibraryStorage().read(), isNull);
        expect(await vault.containsKey(key: _secretKey), isFalse);
        await media.writeAsBytes(_tone(), flush: true);
        final track = Track(
          id: 'ios-native-track',
          title: 'iOS Native Acceptance',
          artist: 'Synthetic Fixture',
          localPath: media.path,
          duration: const Duration(seconds: 10),
        );
        expect(
          await prefs.setString(
            'aethertune.tracks.v1',
            jsonEncode([track.toJson()]),
          ),
          isTrue,
        );
        expect(
          await prefs.setBool('aethertune.onboarding_completed.v1', true),
          isTrue,
        );
        expect(await prefs.setBool('aethertune.offline_mode.v1', true), isTrue);
        await vault.write(key: _secretKey, value: _secret);
      } else {
        expect(prefs.getBool(_seeded), isTrue);
        expect(await media.exists(), isTrue);
      }
      if (phase != 'sync') {
        expect(await vault.read(key: _secretKey), _secret);
        passed(
          phase == 'seed'
              ? 'native-keychain-round-trip'
              : 'keychain-survived-process-restart',
        );
      }
      final assertionHandler = FlutterError.onError;
      await app.main();
      FlutterError.onError = assertionHandler;
      await _until(tester, () => find.byType(HomeScreen).evaluate().isNotEmpty);
      final context = tester.element(find.byType(HomeScreen));
      final library = context.read<LibraryStore>();
      player = context.read<PlayerController>();
      expect(library.loaded, isTrue);
      expect(library.loadError, isNull);
      expect(library.tracks, hasLength(1));
      expect(library.tracks.single.id, 'ios-native-track');
      expect(createLibraryStorage(), isA<FileLibraryStorage>());
      expect(await createLibraryStorage().read(), isNotNull);
      passed('production-app-startup');
      if (phase != 'sync') passed('native-library-snapshot');

      if (phase == 'seed') {
        await library.toggleFavorite('ios-native-track');
        await library.setTrackRating('ios-native-track', 4);
        expect(library.saveError, isNull);
        final playback = player;
        await playback.playTrack(library.tracks.single);
        await _until(
          tester,
          () => playback.isPlaying && playback.position.inMilliseconds >= 700,
        );
        expect(playback.duration.inMilliseconds, inInclusiveRange(9500, 10500));
        await playback.togglePlayPause();
        await _until(tester, () => !playback.isPlaying);
        await tester.pump(const Duration(milliseconds: 300));
        final paused = playback.position;
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          (playback.position - paused).inMilliseconds.abs(),
          lessThan(200),
        );
        await playback.seek(const Duration(seconds: 3));
        await _until(
          tester,
          () => (playback.position.inMilliseconds - 3000).abs() < 500,
        );
        await playback.setVolume(0.4);
        await playback.stop();
        passed('native-decode-progress-pause-seek-stop');
        expect(await prefs.setBool(_seeded, true), isTrue);
        passed('persistent-fixture-checkpoint');
      } else if (phase == 'reopen') {
        expect(library.tracks.single.isFavorite, isTrue);
        expect(library.tracks.single.rating, 4);
        final playback = player;
        await _until(tester, () => playback.queue.isNotEmpty);
        expect(playback.current?.id, 'ios-native-track');
        expect(playback.isPlaying, isFalse);
        expect(playback.volume, closeTo(0.4, 0.001));
        passed('library-queue-settings-survived-process-restart');
        await vault.delete(key: _secretKey);
        expect(await vault.read(key: _secretKey), isNull);
        passed('native-keychain-deletion');
      } else {
        final transport = await runNativeSyncTransportContracts(
          certificateDirectory: fixture.path,
          evidenceDirectory: fixture.path,
        );
        expect(transport, hasLength(8));
        expect(transport.every((check) => check['passed'] == true), isTrue);
        checks.addAll(transport);
      }

      expect(context.read<LocalDiagnosticLog>().entries, isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final snapshot = await boundary.toImage(pixelRatio: 1);
      try {
        final png = await snapshot.toByteData(format: ui.ImageByteFormat.png);
        await File(
          p.join(support.path, 'ios-acceptance-$phase.png'),
        ).writeAsBytes(png!.buffer.asUint8List(), flush: true);
      } finally {
        snapshot.dispose();
      }
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
      await File(
        p.join(support.path, 'ios-acceptance-$phase.json'),
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
      binding.reportData = report;
      await player?.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready()) {
    if (watch.elapsed > const Duration(seconds: 25)) {
      fail('Native iOS condition timed out.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Uint8List _tone() {
  const rate = 22050;
  const frames = rate * 10;
  final data = ByteData(44 + frames * 2);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, data.lengthInBytes - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  for (var frame = 0; frame < frames; frame++) {
    data.setInt16(
      44 + frame * 2,
      (math.sin(2 * math.pi * 440 * frame / rate) * 4000).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
