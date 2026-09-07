import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/player/player_state_store.dart';
import 'package:aethertune/src/ui/widgets/player_state_failure_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/player_storage_fixture.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('save failure is announced and reload enables a real retry', (
    tester,
  ) async {
    final storage = ControlledPlayerStorage();
    final player = PlayerController(
      audioEngine: _NoticeEngine(),
      stateStore: PlayerStateStore(storage: storage),
    );
    addTearDown(player.dispose);
    await player.loadPersistedQueue();
    storage.failWrites = true;
    expect(await player.createSavedQueue('Rejected'), isNull);
    await tester.pumpWidget(_app(player));
    expect(
      find.textContaining('Player changes could not be saved'),
      findsOneWidget,
    );
    final announcements = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .where((widget) => widget.properties.liveRegion == true);
    expect(announcements, isNotEmpty);
    storage.failWrites = false;
    await tester.tap(find.text('Reload saved player data'));
    await tester.pumpAndSettle();
    expect(player.persistenceError, isNull);
    expect(
      find.textContaining('Player changes could not be saved'),
      findsNothing,
    );
    expect(await player.createSavedQueue('Retry'), isNotNull);
    expect(
      storage.current!.values[PlayerStateStore.queuesKey],
      contains('Retry'),
    );
  });

  for (final size in [const Size(320, 480), const Size(480, 320)]) {
    for (final direction in TextDirection.values) {
      testWidgets(
        'previous recovery is confirmed and reachable at $size $direction 3x text',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.reset);
          final storage = ControlledPlayerStorage();
          final state = PlayerStateStore(storage: storage);
          expect(await state.load(), isTrue);
          expect(
            await state.write({PlayerStateStore.settingsKey: '{"volume":0.3}'}),
            isTrue,
          );
          expect(
            await state.write({PlayerStateStore.settingsKey: '{"volume":0.6}'}),
            isTrue,
          );
          state.reportLoadFailure();
          final player = PlayerController(
            audioEngine: _NoticeEngine(),
            stateStore: state,
          );
          addTearDown(player.dispose);
          await tester.pumpWidget(_app(player, scale: 3, direction: direction));
          await tester.ensureVisible(find.text('Restore previous player data'));
          await tester.tap(find.text('Restore previous player data'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Cancel'));
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(
            storage.current!.values[PlayerStateStore.settingsKey],
            '{"volume":0.6}',
          );
          await tester.ensureVisible(find.text('Restore previous player data'));
          await tester.tap(find.text('Restore previous player data'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Restore'));
          await tester.tap(find.text('Restore'));
          await tester.pumpAndSettle();
          expect(player.persistenceError, isNull);
          expect(player.volume, 0.3);
          expect(
            storage.current!.values[PlayerStateStore.settingsKey],
            '{"volume":0.3}',
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Library content'), findsOneWidget);
        },
      );
    }
  }
}

Widget _app(
  PlayerController player, {
  double scale = 1,
  TextDirection direction = TextDirection.ltr,
}) {
  final navigatorKey = GlobalKey<NavigatorState>();
  return MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: Directionality(
        textDirection: direction,
        child: PlayerStateFailureNotice(
          player: player,
          navigatorKey: navigatorKey,
          child: child!,
        ),
      ),
    ),
    home: const Scaffold(body: Text('Library content')),
  );
}

class _NoticeEngine implements PlaybackAudioEngine {
  @override
  Stream<Object?> get stateChanges => const Stream.empty();
  @override
  Stream<Duration?> get durationStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  bool get playing => false;
  @override
  bool get shuffleModeEnabled => false;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  double get volume => 1;
  @override
  dynamic noSuchMethod(Invocation invocation) => invocation.isMethod
      ? Future<void>.value()
      : super.noSuchMethod(invocation);
}
