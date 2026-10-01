import 'dart:async';

import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/system_media_playback_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final state in [ProcessingState.completed, ProcessingState.idle]) {
    test('Play rewinds the last track after $state at its end', () async {
      final player = _PlaybackPlayer(
        processingStateValue: state,
        positionValue: const Duration(seconds: 20),
        durationValue: const Duration(seconds: 20),
      );
      final engine = SystemMediaPlaybackEngine(
        JustAudioPlaybackEngine(player: player),
      );
      addTearDown(engine.dispose);

      await engine.play();

      expect(player.commands, ['seek:0', 'play']);
      expect(player.position, Duration.zero);
      expect(player.playing, isTrue);
      expect(player.currentIndex, 2);
    });
  }

  test('Play resumes a paused track at its current position', () async {
    final player = _PlaybackPlayer(
      processingStateValue: ProcessingState.ready,
      positionValue: const Duration(seconds: 12),
      durationValue: const Duration(seconds: 20),
    );
    final engine = JustAudioPlaybackEngine(player: player);
    addTearDown(engine.dispose);

    await engine.play();

    expect(player.commands, ['play']);
    expect(player.position, const Duration(seconds: 12));
    await engine.pause();
    await engine.seek(const Duration(seconds: 7));
    await engine.play();
    expect(player.position, const Duration(seconds: 7));
    expect(player.commands, ['play', 'pause', 'seek:7000', 'play']);
  });

  test('Completed playback without a duration still rewinds', () async {
    final player = _PlaybackPlayer(
      processingStateValue: ProcessingState.completed,
      positionValue: const Duration(seconds: 20),
    );
    final engine = JustAudioPlaybackEngine(player: player);
    addTearDown(engine.dispose);

    await engine.play();

    expect(player.commands, ['seek:0', 'play']);
  });

  for (final duration in [null, Duration.zero]) {
    test(
      'Unknown or zero duration does not imply completion: $duration',
      () async {
        final player = _PlaybackPlayer(
          processingStateValue: ProcessingState.ready,
          positionValue: const Duration(seconds: 20),
          durationValue: duration,
        );
        final engine = JustAudioPlaybackEngine(player: player);
        addTearDown(engine.dispose);

        await engine.play();

        expect(player.commands, ['play']);
        expect(player.position, const Duration(seconds: 20));
        expect(player.currentIndex, 2);
      },
    );
  }

  test('A failed rewind does not start playback or hide the error', () async {
    final player = _PlaybackPlayer(
      processingStateValue: ProcessingState.completed,
      positionValue: const Duration(seconds: 20),
      seekError: StateError('Synthetic rewind failure'),
    );
    final engine = JustAudioPlaybackEngine(player: player);
    addTearDown(engine.dispose);

    await expectLater(engine.play(), throwsStateError);

    expect(player.commands, ['seek:0']);
    expect(player.playing, isFalse);
  });

  test('Play waits for rewind but returns before playback ends', () async {
    final seekGate = Completer<void>();
    final playbackEnd = Completer<void>();
    final player = _PlaybackPlayer(
      processingStateValue: ProcessingState.completed,
      positionValue: const Duration(seconds: 20),
      seekGate: seekGate,
      playbackEnd: playbackEnd,
    );
    final engine = JustAudioPlaybackEngine(player: player);
    addTearDown(() async {
      if (!seekGate.isCompleted) seekGate.complete();
      if (!playbackEnd.isCompleted) playbackEnd.complete();
      await engine.dispose();
    });

    final playRequest = engine.play();
    await Future<void>.delayed(Duration.zero);
    expect(player.commands, ['seek:0']);
    expect(player.playing, isFalse);

    seekGate.complete();
    await playRequest.timeout(const Duration(seconds: 2));
    expect(player.commands, ['seek:0', 'play']);
    expect(playbackEnd.isCompleted, isFalse);
  });
}

class _PlaybackPlayer extends AudioPlayer {
  _PlaybackPlayer({
    required this.processingStateValue,
    required this.positionValue,
    this.durationValue,
    this.seekError,
    this.seekGate,
    this.playbackEnd,
  });

  ProcessingState processingStateValue;
  Duration positionValue;
  final Duration? durationValue;
  final Object? seekError;
  final Completer<void>? seekGate;
  final Completer<void>? playbackEnd;
  final commands = <String>[];
  bool playingValue = false;
  int currentIndexValue = 2;

  @override
  ProcessingState get processingState => processingStateValue;

  @override
  Duration get position => positionValue;

  @override
  Duration? get duration => durationValue;

  @override
  bool get playing => playingValue;

  @override
  int? get currentIndex => currentIndexValue;

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    commands.add('seek:${position?.inMilliseconds}');
    if (seekError != null) throw seekError!;
    await seekGate?.future;
    positionValue = position ?? Duration.zero;
    if (index != null) currentIndexValue = index;
    processingStateValue = ProcessingState.ready;
  }

  @override
  Future<void> play() {
    commands.add('play');
    playingValue = true;
    return playbackEnd?.future ?? Future<void>.value();
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    playingValue = false;
  }
}
