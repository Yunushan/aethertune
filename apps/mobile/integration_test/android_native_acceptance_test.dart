import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aethertune/main.dart' as app;
import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_transport.dart';
import 'package:aethertune/src/data/local_diagnostic_log.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _vaultKey = 'aethertune.android.acceptance.secret';
const _secret = 'synthetic-android-acceptance-only';
const _marker = 'aethertune.android.acceptance.seeded';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment('AETHERTUNE_ANDROID_PHASE');
  const avd = String.fromEnvironment('AETHERTUNE_ANDROID_AVD');

  testWidgets(
    'native Android acceptance: $phase',
    (tester) async {
      // A test binary must never seed a physical device or a personal AVD profile.
      expect(Platform.isAndroid, isTrue);
      expect(avd.startsWith('AetherTune_Acceptance_'), isTrue);
      expect(await _property('ro.kernel.qemu'), '1');
      expect(await _property('ro.boot.qemu.avd_name'), avd);
      expect(['seed', 'reopen'], contains(phase));
      final prefs = await SharedPreferences.getInstance();
      final support = await getApplicationSupportDirectory();
      final media = File(p.join(support.path, 'android-acceptance.wav'));
      const vault = FlutterSecureStorage();
      final checks = <String>[];

      if (phase == 'seed') {
        expect(prefs.getKeys(), isEmpty);
        expect(await createLibraryStorage().read(), isNull);
        expect(await vault.containsKey(key: _vaultKey), isFalse);
        await media.writeAsBytes(_tone(), flush: true);
        final track = Track(
          id: 'android-native-track',
          title: 'Android Native Acceptance',
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
        await vault.write(key: _vaultKey, value: _secret);
      } else {
        expect(prefs.getBool(_marker), isTrue);
        expect(await media.exists(), isTrue);
      }
      expect(await vault.read(key: _vaultKey), _secret);
      checks.add(
        phase == 'seed'
            ? 'native-keystore-round-trip'
            : 'keystore-survived-process-restart',
      );

      final assertionHandler = FlutterError.onError;
      await app.main();
      FlutterError.onError = assertionHandler;
      await _until(tester, () => find.byType(HomeScreen).evaluate().isNotEmpty);
      final context = tester.element(find.byType(HomeScreen));
      final library = context.read<LibraryStore>();
      final player = context.read<PlayerController>();
      final diagnostics = context.read<LocalDiagnosticLog>();
      expect(library.loaded, isTrue);
      expect(library.loadError, isNull);
      expect(library.tracks, hasLength(1));
      expect(library.tracks.single.id, 'android-native-track');
      expect(createLibraryStorage(), isA<FileLibraryStorage>());
      expect(await createLibraryStorage().read(), isNotNull);
      checks.addAll(['production-app-startup', 'native-library-snapshot']);

      if (phase == 'seed') {
        await library.toggleFavorite('android-native-track');
        await library.setTrackRating('android-native-track', 4);
        expect(library.saveError, isNull);
        await player.playTrack(library.tracks.single);
        await _until(
          tester,
          () => player.isPlaying && player.position.inMilliseconds >= 700,
        );
        expect(player.duration.inMilliseconds, inInclusiveRange(9500, 10500));
        await player.togglePlayPause();
        await _until(tester, () => !player.isPlaying);
        await tester.pump(const Duration(milliseconds: 300));
        final paused = player.position;
        await tester.pump(const Duration(milliseconds: 400));
        expect((player.position - paused).inMilliseconds.abs(), lessThan(200));
        await player.seek(const Duration(seconds: 3));
        await _until(
          tester,
          () => (player.position.inMilliseconds - 3000).abs() < 500,
        );
        await player.setVolume(0.4);
        await player.stop();
        checks.add('native-decode-progress-pause-seek-stop');
        await _nativeHttp();
        checks.add('native-HTTP-UTF8-authorization-no-redirect');
        expect(await prefs.setBool(_marker, true), isTrue);
      } else {
        expect(library.tracks.single.isFavorite, isTrue);
        expect(library.tracks.single.rating, 4);
        await _until(tester, () => player.queue.isNotEmpty);
        expect(player.current?.id, 'android-native-track');
        expect(player.isPlaying, isFalse);
        expect(player.volume, closeTo(0.4, 0.001));
        checks.add('library-queue-settings-survived-process-restart');
        await vault.delete(key: _vaultKey);
        expect(await vault.read(key: _vaultKey), isNull);
        checks.add('native-keystore-deletion');
      }

      expect(tester.takeException(), isNull);
      expect(diagnostics.entries, isEmpty);
      final result = <String, Object?>{
        'status': 'passed',
        'phase': phase,
        'os': Platform.operatingSystemVersion,
        'abi': await _property('ro.product.cpu.abi'),
        'checks': checks,
        'scope':
            'Android emulator, synthetic local data. Not physical audio, TLS trust, signing, or upgrade acceptance.',
      };
      await File(
        p.join(support.path, 'android-acceptance-$phase.json'),
      ).writeAsString(
        const JsonEncoder.withIndent('  ').convert(result),
        flush: true,
      );
      binding.reportData = result;
      await player.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<String> _property(String name) async {
  final result = await Process.run('/system/bin/getprop', [
    name,
  ]).timeout(const Duration(seconds: 5));
  expect(result.exitCode, 0);
  return (result.stdout as String).trim();
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final timer = Stopwatch()..start();
  while (!ready()) {
    if (timer.elapsed > const Duration(seconds: 25)) {
      fail('Android native condition timed out.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _nativeHttp() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  var validRequest = false;
  final subscription = server.listen((request) async {
    requests++;
    validRequest =
        request.method == 'PUT' &&
        request.headers.value('authorization') == 'Bearer $_secret' &&
        await utf8.decoder.bind(request).join() ==
            '{"title":"\u00e7\u0131\u011f"}';
    request.response
      ..statusCode = 302
      ..headers.set('location', '/must-not-follow')
      ..write('{"native":"ok"}');
    await request.response.close();
  });
  try {
    final response = await executeLibrarySyncHttpRequest(
      'PUT',
      Uri.parse('http://127.0.0.1:${server.port}/'),
      headers: {'authorization': 'Bearer $_secret'},
      body: '{"title":"\u00e7\u0131\u011f"}',
      transferTimeout: const Duration(seconds: 5),
    );
    expect(response.statusCode, 302);
    expect(response.body, '{"native":"ok"}');
    expect(requests, 1);
    expect(validRequest, isTrue);
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}

Uint8List _tone() {
  const rate = 22050;
  const frames = rate * 10;
  final data = ByteData(44 + frames * 2);
  void ascii(int offset, String text) {
    for (var index = 0; index < text.length; index++) {
      data.setUint8(offset + index, text.codeUnitAt(index));
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
