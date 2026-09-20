import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aethertune/main.dart' as app;
import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/local_diagnostic_log.dart';
import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/domain/playlist.dart';
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

const _secretKey = 'aethertune.native.acceptance.secret';
const _syntheticSecret = 'native-fixture-not-a-real-credential';
const _sentinelKey = 'aethertune.native.acceptance.unrelated';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final phase = Platform.environment['AETHERTUNE_ACCEPTANCE_PHASE'];

  testWidgets('native Linux acceptance: $phase', (tester) async {
    // Refuse to seed or mutate a real user's desktop preferences/keyring.
    final home = Platform.environment['AETHERTUNE_ACCEPTANCE_HOME'];
    expect(Platform.isLinux, isTrue);
    expect(home, isNotNull);
    expect(Platform.environment['HOME'], home);
    final root = Directory(home!);
    expect(await root.resolveSymbolicLinks(), root.path);
    expect(
      await File(p.join(home, '.aethertune-native-fixture')).readAsString(),
      'aethertune-native-acceptance-v1\n',
    );
    final support = await getApplicationSupportDirectory();
    expect(p.isWithin(home, support.path), isTrue);
    final documents = await getApplicationDocumentsDirectory();
    expect(documents.path, p.join(home, 'unavailable-documents'));
    expect(
      await FileSystemEntity.type(documents.path, followLinks: false),
      FileSystemEntityType.file,
    );
    final evidence = Directory(p.join(home, 'evidence'));
    await evidence.create(recursive: true);
    final checks = <String>[];
    final prefs = await SharedPreferences.getInstance();
    const vault = FlutterSecureStorage();

    if (phase == 'seed') {
      expect(prefs.getKeys(), isEmpty);
      expect(await createLibraryStorage().read(), isNull);
      final media = Directory(p.join(home, 'media'));
      await media.create();
      final original = File(p.join(media.path, 'Original.wav'));
      await original.writeAsBytes(_tone(440), flush: true);
      await File(
        p.join(media.path, 'Imported.wav'),
      ).writeAsBytes(_tone(660), flush: true);
      final track = Track(
        id: 'native-legacy-track',
        title: 'Native Legacy Track',
        artist: 'Acceptance Fixture',
        localPath: original.path,
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
        await prefs.setString(
          'aethertune.playlists.v1',
          jsonEncode([
            Playlist(
              id: 'native-legacy-playlist',
              name: 'Native Legacy Playlist',
              trackIds: [track.id],
            ).toJson(),
          ]),
        ),
        isTrue,
      );
      expect(
        await prefs.setBool('aethertune.onboarding_completed.v1', true),
        isTrue,
      );
      expect(await prefs.setString(_sentinelKey, 'preserve-me'), isTrue);
      expect(
        await prefs.setString(
          LocalDiagnosticLog.legacyStorageKey,
          jsonEncode([
            {'message': 'access_token=$_syntheticSecret'},
          ]),
        ),
        isTrue,
      );
      await vault.write(key: _secretKey, value: _syntheticSecret);
      expect(await vault.read(key: _secretKey), _syntheticSecret);
      await prefs.reload();
      expect(prefs.getString('aethertune.tracks.v1'), contains(track.id));
      checks.addAll([
        'real-preferences-seeded',
        'real-secret-service-round-trip',
      ]);
    } else {
      expect(['migrate', 'reopen'], contains(phase));
      expect(prefs.getString(_sentinelKey), 'preserve-me');
      expect(await vault.read(key: _secretKey), _syntheticSecret);
      checks.add('credential-survived-process-restart');
      // Keep the integration binding's assertion handler while running the
      // production entry point and all of its real plugin initialization.
      final errorHandler = FlutterError.onError;
      await app.main();
      FlutterError.onError = errorHandler;
      await _until(tester, () => find.byType(HomeScreen).evaluate().isNotEmpty);
      final context = tester.element(find.byType(HomeScreen));
      expect(Localizations.localeOf(context), const Locale('en'));
      expect(Directionality.of(context), TextDirection.ltr);
      final library = context.read<LibraryStore>();
      final player = context.read<PlayerController>();
      final diagnostics = context.read<LocalDiagnosticLog>();
      expect(library.loaded, isTrue);
      expect(library.loadError, isNull);
      final legacyTrack = library.tracks.singleWhere(
        (track) => track.id == 'native-legacy-track',
      );
      expect(library.playlists.first.id, 'native-legacy-playlist');
      expect(createLibraryStorage(), isA<FileLibraryStorage>());
      expect(await createLibraryStorage().read(), isNotNull);
      await prefs.reload();
      expect(prefs.containsKey(LocalDiagnosticLog.legacyStorageKey), isFalse);
      expect(diagnostics.exportJson(), isNot(contains(_syntheticSecret)));
      expect(prefs.getString(_sentinelKey), 'preserve-me');
      expect(await vault.read(key: _secretKey), _syntheticSecret);
      checks.addAll([
        'unsupported-system-locale-falls-back-to-english',
        'production-app-startup',
        'native-library-snapshot',
        'legacy-diagnostic-cleanup',
      ]);

      if (phase == 'migrate') {
        expect(library.tracks, hasLength(1));
        await _selectNavigation(tester, 5);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.scrollUntilVisible(
          find.text('Offline cache storage'),
          600,
          scrollable: find.byType(Scrollable).last,
          maxScrolls: 60,
        );
        await _until(
          tester,
          () => find.text('Could not read cache usage.').evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull);
        checks.add('unavailable-documents-directory-does-not-break-startup');
        await _selectNavigation(tester, 1);
        await tester.pump(const Duration(milliseconds: 300));
        final scanned = await scanLocalFilesInBackground([
          p.join(home, 'media', 'Imported.wav'),
        ]);
        expect(scanned.tracks, hasLength(1));
        await library.addTracks(scanned.tracks);
        await library.toggleFavorite('native-legacy-track');
        await library.setTrackRating('native-legacy-track', 4);
        await library.addTrackToPlaylist(
          library.playlists.first.id,
          scanned.tracks.single.id,
        );
        expect(library.saveError, isNull);
        checks.add('native-scan-and-library-mutations');

        final playbackQueue = [
          library.tracks.singleWhere((track) => track.id == legacyTrack.id),
          library.tracks.singleWhere(
            (track) => track.id == scanned.tracks.single.id,
          ),
        ];
        await player.setVolume(1);
        await player.playTrack(
          playbackQueue.first,
          queue: playbackQueue,
          queueIndex: 0,
        );
        await _until(
          tester,
          () => player.isPlaying && player.position.inMilliseconds >= 700,
        );
        expect(player.duration.inMilliseconds, inInclusiveRange(9500, 10500));
        checks.add('native-decode-and-position-progress');

        await _mpris('Pause');
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
        await _mpris('Play');
        await _until(
          tester,
          () => player.isPlaying && player.position.inMilliseconds > 3500,
        );
        await _mpris('Next');
        await _until(
          tester,
          () =>
              player.current?.id == scanned.tracks.single.id &&
              player.isPlaying,
        );
        await _until(tester, () => player.position.inMilliseconds > 500);
        checks.add('mpris-pause-play-next-and-seek');
        await player.setVolume(0.4);
        await player.stop();
        await tester.pump(const Duration(milliseconds: 500));
        await prefs.reload();
        expect(player.current?.id, scanned.tracks.single.id);
      } else {
        expect(library.tracks, hasLength(2));
        expect(legacyTrack.isFavorite, isTrue);
        expect(legacyTrack.rating, 4);
        expect(library.playlists.first.trackIds, hasLength(2));
        await _until(tester, () => player.queue.length == 2);
        expect(
          player.current?.localPath,
          p.join(home, 'media', 'Imported.wav'),
        );
        expect(player.isPlaying, isFalse);
        expect(player.volume, closeTo(0.4, 0.001));
        checks.add('library-queue-and-settings-survived-restart');
        await vault.delete(key: _secretKey);
        expect(await vault.read(key: _secretKey), isNull);
        checks.add('native-credential-deletion');
      }

      await _selectNavigation(tester, 1);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Native Legacy Track'), findsWidgets);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final snapshot = await boundary.toImage(pixelRatio: 1);
      final png = await snapshot.toByteData(format: ui.ImageByteFormat.png);
      await File(
        p.join(evidence.path, '$phase.png'),
      ).writeAsBytes(png!.buffer.asUint8List(), flush: true);
      snapshot.dispose();
      expect(tester.takeException(), isNull);
      await player.stop();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    }

    await File(p.join(evidence.path, '$phase.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'phase': phase,
        'status': 'passed',
        'os': Platform.operatingSystemVersion,
        'checks': checks,
        'scope':
            'Native Linux fixture. Virtual display/audio, not physical-device acceptance.',
      }),
      flush: true,
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = Stopwatch()..start();
  while (!ready()) {
    if (deadline.elapsed > const Duration(seconds: 25)) {
      fail('Native client condition did not become ready in 25 seconds.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _selectNavigation(WidgetTester tester, int index) async {
  await _until(
    tester,
    () =>
        find.byType(NavigationRail).evaluate().isNotEmpty ||
        find.byType(NavigationBar).evaluate().isNotEmpty,
  );
  final rail = find.byType(NavigationRail);
  if (rail.evaluate().isNotEmpty) {
    final navigation = tester.widget<NavigationRail>(rail);
    final label = (navigation.destinations[index].label as Text).data!;
    final target = find.descendant(of: rail, matching: find.text(label));
    final direction = index >= navigation.selectedIndex! ? 100.0 : -100.0;
    await tester.scrollUntilVisible(
      target,
      direction,
      scrollable: find
          .descendant(of: rail, matching: find.byType(Scrollable))
          .first,
    );
    await tester.tap(target);
  } else {
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    final label =
        (navigation.destinations[index] as NavigationDestination).label;
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _mpris(String method) async {
  final result = await Process.run('gdbus', [
    'call',
    '--session',
    '--dest',
    'org.mpris.MediaPlayer2.dev.aethertune.playback.instance$pid',
    '--object-path',
    '/org/mpris/MediaPlayer2',
    '--method',
    'org.mpris.MediaPlayer2.Player.$method',
  ]).timeout(const Duration(seconds: 10));
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

Uint8List _tone(double frequency) {
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
  for (var index = 0; index < frames; index++) {
    data.setInt16(
      44 + index * 2,
      (5000 * math.sin(2 * math.pi * frequency * index / rate)).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
