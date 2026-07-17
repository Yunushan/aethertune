import 'dart:async';

import 'package:aethertune/src/domain/replay_gain.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_effects.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('routes system-media library selections through queue playback', () async {
    final engine = _FakeMediaLibraryBrowseEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[
      Track(id: 'one', title: 'One', localPath: '/music/one.mp3'),
      Track(id: 'two', title: 'Two', localPath: '/music/two.mp3'),
    ];

    controller.setMediaLibraryBrowseTracks(tracks);

    expect(
      engine.browseTracks.map((track) => track.id),
      <String>['one', 'two'],
    );
    await engine.selectBrowseTrack(tracks.last);

    expect(controller.current?.id, 'two');
    expect(
      controller.queue.map((track) => track.id),
      <String>['one', 'two'],
    );
    expect(engine.queue.map((track) => track.id), <String>['one', 'two']);
    expect(engine.initialIndex, 1);
    expect(engine.playingValue, isTrue);
  });

  test('loops from B back to A and clears markers on a track change',
      () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final first = _track('first');
    final second = _track('second');

    await controller.playTrack(first, queue: <Track>[first, second]);
    engine.emitDuration(const Duration(minutes: 3));
    controller.setABRepeatStart(const Duration(seconds: 12));
    expect(controller.hasABRepeatStart, isTrue);
    expect(
      controller.setABRepeatEnd(const Duration(seconds: 12, milliseconds: 499)),
      isFalse,
    );
    expect(controller.isABRepeatActive, isFalse);
    expect(controller.setABRepeatEnd(const Duration(seconds: 22)), isTrue);
    expect(controller.isABRepeatActive, isTrue);

    engine.emitPosition(const Duration(seconds: 22));
    await Future<void>.delayed(Duration.zero);
    expect(engine.seekPositions.last, const Duration(seconds: 12));

    engine.emitAutomaticIndex(1);
    expect(controller.current?.id, 'second');
    expect(controller.hasABRepeatStart, isFalse);
    expect(controller.isABRepeatActive, isFalse);

    controller.setABRepeatStart(const Duration(seconds: 2));
    expect(controller.setABRepeatEnd(const Duration(seconds: 4)), isTrue);
    await controller.playTrack(first, queue: <Track>[first, second]);
    expect(controller.current?.id, 'first');
    expect(controller.hasABRepeatStart, isFalse);
  });

  test('clamps A-B markers to a known track duration and clears them',
      () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    await controller.playTrack(_track('one'));
    engine.emitDuration(const Duration(seconds: 30));

    controller.setABRepeatStart(const Duration(seconds: 45));
    expect(controller.aBRepeatStart, const Duration(seconds: 30));
    expect(controller.setABRepeatEnd(const Duration(seconds: 31)), isFalse);
    controller.clearABRepeat();

    expect(controller.aBRepeatStart, isNull);
    expect(controller.aBRepeatEnd, isNull);
  });

  test('persists supported playback speed and rejects unsupported values',
      () async {
    final firstEngine = _FakePlaybackAudioEngine();
    final firstController = PlayerController(audioEngine: firstEngine);
    await firstController.setPlaybackSpeed(1.5);
    await firstController.setTemporaryPlaybackSpeed(2);
    expect(firstEngine.speedValue, 2);
    expect(firstController.playbackSpeed, 2);
    expect(firstController.defaultPlaybackSpeed, 1.5);
    firstController.dispose();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.playbackSpeed, 1.5);
    expect(restoredController.defaultPlaybackSpeed, 1.5);
    await expectLater(
      restoredController.setPlaybackSpeed(1.1),
      throwsArgumentError,
    );
  });

  test('persists volume and rejects values outside the supported range',
      () async {
    final firstEngine = _FakePlaybackAudioEngine();
    final firstController = PlayerController(audioEngine: firstEngine);
    await firstController.setVolume(0.35);

    expect(firstController.volume, 0.35);
    expect(firstEngine.volumeValue, 0.35);
    firstController.dispose();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.volume, 0.35);
    expect(restoredEngine.volumeValue, 0.35);
    await expectLater(restoredController.setVolume(-0.1), throwsArgumentError);
    await expectLater(restoredController.setVolume(1.1), throwsArgumentError);
  });

  test('persists supported crossfade durations for capable engines', () async {
    final firstEngine = _FakePlaybackAudioEngine();
    final firstController = PlayerController(audioEngine: firstEngine);

    await firstController.setCrossfadeDuration(const Duration(seconds: 3));

    expect(firstController.supportsCrossfade, isTrue);
    expect(firstController.crossfadeDuration, const Duration(seconds: 3));
    await expectLater(
      firstController.setCrossfadeDuration(const Duration(seconds: 4)),
      throwsArgumentError,
    );
    firstController.dispose();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.crossfadeDuration, const Duration(seconds: 3));
  });

  test('rejects crossfade when the audio backend does not support it',
      () async {
    final controller = PlayerController(audioEngine: _NoCrossfadeAudioEngine());
    addTearDown(controller.dispose);

    expect(controller.supportsCrossfade, isFalse);
    await expectLater(
      controller.setCrossfadeDuration(const Duration(seconds: 3)),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('persists supported playback pitch and hides it from unsupported engines',
      () async {
    final firstEngine = _FakePlaybackAudioEngine()
      ..supportsPitchValue = true;
    final firstController = PlayerController(audioEngine: firstEngine);
    await firstController.setPlaybackPitch(1.25);
    expect(firstEngine.pitchValue, 1.25);
    expect(firstController.defaultPlaybackPitch, 1.25);
    firstController.dispose();

    final restoredEngine = _FakePlaybackAudioEngine()
      ..supportsPitchValue = true;
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();
    expect(restoredController.defaultPlaybackPitch, 1.25);
    expect(restoredEngine.pitchValue, 1.25);
    await expectLater(
      restoredController.setPlaybackPitch(1.1),
      throwsArgumentError,
    );

    final unsupportedController = PlayerController(
      audioEngine: _FakePlaybackAudioEngine(),
    );
    addTearDown(unsupportedController.dispose);
    expect(unsupportedController.supportsPitch, isFalse);
    await expectLater(
      unsupportedController.setPlaybackPitch(1.25),
      throwsUnsupportedError,
    );
  });

  test('persists per-track pitch overrides without changing the default',
      () async {
    final firstEngine = _FakePlaybackAudioEngine()..supportsPitchValue = true;
    final firstController = PlayerController(audioEngine: firstEngine);
    await firstController.setPlaybackPitch(1.25);
    await firstController.setTrackPlaybackPitch('track-1', 0.75);
    expect(firstController.defaultPlaybackPitch, 1.25);
    expect(firstController.playbackPitchForTrack('track-1'), 0.75);
    firstController.dispose();

    final restoredEngine = _FakePlaybackAudioEngine()..supportsPitchValue = true;
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();
    expect(restoredController.defaultPlaybackPitch, 1.25);
    expect(restoredController.playbackPitchForTrack('track-1'), 0.75);

    await restoredController.playTrack(_track('track-1'));
    expect(restoredEngine.pitchValue, 0.75);
    await restoredController.clearTrackPlaybackPitch('track-1');
    expect(restoredController.playbackPitchForTrack('track-1'), isNull);
    expect(restoredEngine.pitchValue, 1.25);
    await expectLater(
      restoredController.setTrackPlaybackPitch('', 1.25),
      throwsArgumentError,
    );
  });

  test('persists and restores Android audio effect settings', () async {
    final firstEngine = _FakeAudioEffectsEngine();
    final firstController = PlayerController(audioEngine: firstEngine);

    await firstController.setEqualizerEnabled(true);
    await firstController.setEqualizerPreset(
      PlaybackEqualizerPreset.bassBoost,
    );
    await firstController.setLoudnessEnhancerEnabled(true);
    await firstController.setLoudnessEnhancerTargetGain(5.5);
    await firstController.setVirtualizerEnabled(true);
    await firstController.setVirtualizerStrength(650);

    expect(firstEngine.equalizerEnabledValue, isTrue);
    expect(
      firstEngine.equalizerProfileValue.preset,
      PlaybackEqualizerPreset.bassBoost,
    );
    expect(firstEngine.loudnessEnhancerEnabledValue, isTrue);
    expect(firstEngine.loudnessEnhancerTargetGainValue, 5.5);
    expect(firstEngine.virtualizerEnabledValue, isTrue);
    expect(firstEngine.virtualizerStrengthValue, 650);
    firstController.dispose();

    final restoredEngine = _FakeAudioEffectsEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.equalizerEnabled, isTrue);
    expect(
      restoredController.equalizerPreset,
      PlaybackEqualizerPreset.bassBoost,
    );
    expect(restoredController.loudnessEnhancerEnabled, isTrue);
    expect(restoredController.loudnessEnhancerTargetGainDb, 5.5);
    expect(restoredController.virtualizerEnabled, isTrue);
    expect(restoredController.virtualizerStrength, 650);
    expect(restoredEngine.equalizerEnabledValue, isTrue);
    expect(restoredEngine.loudnessEnhancerEnhancerSetCalls, 1);
    expect(restoredEngine.virtualizerEnabledValue, isTrue);
    expect(restoredEngine.virtualizerStrengthValue, 650);
  });

  test('syncs only library-backed queue references without starting playback',
      () async {
    final updatedAt = DateTime.utc(2026, 7, 16, 12);
    final source = PlayerController(
      audioEngine: _FakePlaybackAudioEngine(),
      clock: () => updatedAt,
    );
    addTearDown(source.dispose);
    final libraryOne = _track('library-one');
    final sourceOnly = _track('source-only');
    final libraryTwo = _track('library-two');
    await source.playTrack(
      libraryTwo,
      queue: <Track>[libraryOne, sourceOnly, libraryTwo],
    );

    final snapshot = source.exportQueueSyncSnapshot(<Track>[
      libraryOne,
      libraryTwo,
    ]);
    expect(snapshot.trackIds, <String>['library-one', 'library-two']);
    expect(snapshot.currentTrackId, 'library-two');
    expect(snapshot.updatedAt, updatedAt);

    final destinationEngine = _FakePlaybackAudioEngine();
    final destination = PlayerController(audioEngine: destinationEngine);
    addTearDown(destination.dispose);
    await destination.playTrack(_track('previous'));
    final restored = await destination.restoreQueueSyncSnapshot(snapshot, <Track>[
      _track('library-one', localPath: '/device-a/one.mp3'),
      _track('library-two', localPath: '/device-a/two.mp3'),
    ]);

    expect(restored, 2);
    expect(destination.queue.map((track) => track.id), <String>[
      'library-one',
      'library-two',
    ]);
    expect(destination.current?.id, 'library-two');
    expect(destinationEngine.stopCalls, 1);
    expect(destinationEngine.playingValue, isFalse);
    expect(destinationEngine.setQueueCalls, 1);
  });

  test('persists skip silence only through a supported playback engine',
      () async {
    final firstEngine = _FakeSkipSilenceEngine();
    final firstController = PlayerController(audioEngine: firstEngine);

    expect(firstController.supportsSkipSilence, isTrue);
    await firstController.setSkipSilenceEnabled(true);
    expect(firstEngine.skipSilenceEnabledValue, isTrue);
    firstController.dispose();

    final restoredEngine = _FakeSkipSilenceEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.skipSilenceEnabled, isTrue);
    expect(restoredEngine.skipSilenceEnabledValue, isTrue);
  });

  test('persists the failed-track recovery preference', () async {
    final firstController = PlayerController(
      audioEngine: _FakePlaybackAudioEngine(),
    );
    await firstController.setSkipFailedTracksEnabled(false);
    firstController.dispose();

    final restoredController = PlayerController(
      audioEngine: _FakePlaybackAudioEngine(),
    );
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.skipFailedTracksEnabled, isFalse);
  });

  test('loads device bands and persists a custom equalizer curve', () async {
    final firstEngine = _FakeAudioEffectsEngine();
    final firstController = PlayerController(audioEngine: firstEngine);
    await firstController.playTrack(_track('one'));

    expect(firstController.equalizerBands, hasLength(3));
    await firstController.setEqualizerEnabled(true);
    await firstController.previewEqualizerBandGain(0, 4.5);
    await firstController.persistEqualizerBandGains();

    expect(
      firstController.equalizerPreset,
      PlaybackEqualizerPreset.custom,
    );
    expect(firstController.equalizerBands.first.gainDb, 4.5);
    expect(firstController.hasCustomEqualizerProfile, isTrue);
    expect(
      firstEngine.equalizerProfileValue.customPoints.first.gainDb,
      4.5,
    );
    firstController.dispose();

    final restoredEngine = _FakeAudioEffectsEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(
      restoredEngine.equalizerProfileValue.preset,
      PlaybackEqualizerPreset.custom,
    );
    expect(
      restoredEngine.equalizerProfileValue.customPoints.first.frequencyHz,
      60,
    );
    expect(
      restoredEngine.equalizerProfileValue.customPoints.first.gainDb,
      4.5,
    );
  });

  test('rejects audio effects on unsupported engines and invalid gain',
      () async {
    final unsupported = PlayerController(
      audioEngine: _NoCrossfadeAudioEngine(),
    );
    addTearDown(unsupported.dispose);

    expect(unsupported.supportsEqualizer, isFalse);
    await expectLater(
      unsupported.setEqualizerEnabled(true),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      unsupported.setSkipSilenceEnabled(true),
      throwsA(isA<UnsupportedError>()),
    );

    final supported = PlayerController(audioEngine: _FakeAudioEffectsEngine());
    addTearDown(supported.dispose);
    await expectLater(
      supported.setLoudnessEnhancerTargetGain(12.5),
      throwsArgumentError,
    );
    await expectLater(
      supported.setVirtualizerStrength(1001),
      throwsArgumentError,
    );
  });

  test('applies persisted ReplayGain normalization for queue transitions',
      () async {
    final firstEngine = _FakePlaybackAudioEngine();
    final firstController = PlayerController(audioEngine: firstEngine);
    final tracks = <Track>[
      _track('quiet', replayGainTrackDb: -6),
      _track('loud', replayGainTrackDb: 6, replayGainAlbumDb: -3),
    ];

    await firstController.setVolume(0.5);
    await firstController.playTrack(tracks.first, queue: tracks);
    await firstController.setLoudnessNormalizationEnabled(true);

    expect(firstEngine.volumeValue, closeTo(0.25059, 0.0001));
    firstEngine.emitAutomaticIndex(1);
    await _flushAsyncWork();
    expect(firstEngine.volumeValue, closeTo(0.99763, 0.0001));
    await firstController.setReplayGainMode(ReplayGainMode.album);
    expect(firstEngine.volumeValue, closeTo(0.35397, 0.0001));
    firstController.dispose();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.loudnessNormalizationEnabled, isTrue);
    expect(restoredController.replayGainMode, ReplayGainMode.album);
  });

  test('uses each track ReplayGain envelope during crossfade', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[
      _track('quiet', replayGainTrackDb: -6),
      _track('loud', replayGainTrackDb: 6),
    ];

    await controller.setVolume(0.5);
    await controller.setLoudnessNormalizationEnabled(true);
    await controller.playTrack(tracks.first, queue: tracks);

    expect(engine.crossfadeVolumeFor(tracks.first), closeTo(0.25059, 0.0001));
    expect(engine.crossfadeVolumeFor(tracks.last), closeTo(0.99763, 0.0001));
  });

  test('persists skip intervals and clamps skip seeks to track bounds',
      () async {
    final firstEngine = _FakePlaybackAudioEngine();
    final firstController = PlayerController(audioEngine: firstEngine);
    await firstController.setSkipBackwardInterval(const Duration(seconds: 15));
    await firstController.setSkipForwardInterval(const Duration(seconds: 45));
    firstEngine
      ..positionValue = const Duration(seconds: 10)
      ..emitDuration(const Duration(seconds: 40));

    await firstController.skipBackward();
    expect(firstEngine.positionValue, Duration.zero);
    firstEngine.positionValue = const Duration(seconds: 20);
    await firstController.skipForward();
    expect(firstEngine.positionValue, const Duration(seconds: 40));
    await expectLater(
      firstController.setSkipForwardInterval(const Duration(seconds: 12)),
      throwsArgumentError,
    );
    firstController.dispose();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedPlaybackSettings();

    expect(restoredController.skipBackwardInterval, const Duration(seconds: 15));
    expect(restoredController.skipForwardInterval, const Duration(seconds: 45));
  });

  test('loads one native queue and follows gapless index transitions',
      () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];

    await controller.playTrack(tracks.first, queue: tracks);

    expect(engine.setQueueCalls, 1);
    expect(engine.queue.map((track) => track.id), <String>['1', '2', '3']);
    expect(engine.initialIndex, 0);
    expect(controller.current?.id, '1');
    expect(controller.playbackStartSerial, 1);

    engine.emitAutomaticIndex(1);

    expect(controller.current?.id, '2');
    expect(controller.playbackStartSerial, 2);
    expect(engine.setQueueCalls, 1);
  });

  test('uses native next and previous without reloading the queue', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];
    await controller.playTrack(tracks.first, queue: tracks);

    await controller.next();
    expect(controller.current?.id, '2');
    expect(engine.seekToNextCalls, 1);
    expect(engine.setQueueCalls, 1);

    await controller.previous();
    expect(controller.current?.id, '1');
    expect(engine.seekToPreviousCalls, 1);
    expect(engine.setQueueCalls, 1);
  });

  test('skips failed tracks and stops after all looped queue items fail',
      () async {
    final engine = _FakePlaybackAudioEngine()..loopModeValue = LoopMode.all;
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];
    await controller.playTrack(tracks.first, queue: tracks);

    engine.emitError(StateError('first failed'));
    await _flushAsyncWork();
    expect(controller.current?.id, '2');

    engine.emitError(StateError('second failed'));
    await _flushAsyncWork();
    expect(controller.current?.id, '3');

    engine.emitError(StateError('third failed'));
    await _flushAsyncWork();
    expect(engine.stopCalls, 1);
    expect(engine.currentIndex, 2);
  });

  test('leaves playback unchanged when failed-track recovery is disabled',
      () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2')];
    await controller.playTrack(tracks.first, queue: tracks);
    await controller.setSkipFailedTracksEnabled(false);

    engine.emitError(StateError('failed'));
    await _flushAsyncWork();

    expect(controller.current?.id, '1');
    expect(engine.stopCalls, 0);
    expect(engine.currentIndex, 0);
  });

  test('filters network queue entries while offline', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[
      _track('local-1'),
      _track(
        'remote',
        localPath: '',
        streamUrl: 'https://media.example.test/remote.mp3',
      ),
      _track('local-2'),
    ];
    controller.setOfflineModeEnabled(true);

    await controller.playTrack(tracks.first, queue: tracks);

    expect(
      engine.queue.map((track) => track.id),
      <String>['local-1', 'local-2'],
    );
    engine.emitAutomaticIndex(1);
    expect(controller.current?.id, 'local-2');
  });

  test('rebuilds edited queues at the current track and position', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];
    await controller.playTrack(tracks[1], queue: tracks);
    engine.positionValue = const Duration(seconds: 37);

    controller.moveTrackInQueue(2, 0);
    await _flushAsyncWork();

    expect(engine.setQueueCalls, 2);
    expect(engine.queue.map((track) => track.id), <String>['3', '1', '2']);
    expect(engine.initialIndex, 2);
    expect(engine.initialPosition, const Duration(seconds: 37));

    controller.removeTrackFromQueue('1');
    await _flushAsyncWork();
    expect(engine.queue.map((track) => track.id), <String>['3', '2']);
    expect(engine.initialIndex, 1);
  });

  test('restores a persisted queue into the native gapless engine', () async {
    final firstEngine = _FakePlaybackAudioEngine();
    final firstController = PlayerController(audioEngine: firstEngine);
    final tracks = <Track>[_track('1'), _track('2'), _track('3')];
    await firstController.playTrack(tracks[1], queue: tracks);
    firstController.dispose();
    await _flushAsyncWork();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restoredController = PlayerController(audioEngine: restoredEngine);
    addTearDown(restoredController.dispose);
    await restoredController.loadPersistedQueue();

    expect(restoredController.queue.map((track) => track.id), <String>[
      '1',
      '2',
      '3',
    ]);
    expect(restoredController.current?.id, '2');

    await restoredController.togglePlayPause();
    expect(restoredEngine.setQueueCalls, 1);
    expect(restoredEngine.initialIndex, 1);
    expect(restoredEngine.playing, isTrue);
  });

  test('persists independently switchable named queues', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    final firstQueue = <Track>[_track('1'), _track('2')];
    final focusQueue = <Track>[_track('3'), _track('4')];
    await controller.playTrack(firstQueue[1], queue: firstQueue);

    final focus = await controller.createSavedQueue('Focus');
    expect(focus, isNotNull);
    expect(await controller.switchSavedQueue(focus!.id), isTrue);
    expect(controller.queue, isEmpty);
    expect(controller.current, isNull);
    await controller.playTrack(focusQueue.first, queue: focusQueue);

    expect(await controller.switchSavedQueue('default'), isTrue);
    expect(controller.activeQueueName, 'Queue 1');
    expect(controller.queue.map((track) => track.id), <String>['1', '2']);
    expect(controller.current?.id, '2');
    expect(
      controller.savedQueues.map((queue) => queue.name),
      <String>['Queue 1', 'Focus'],
    );

    controller.dispose();
    await _flushAsyncWork();

    final restoredEngine = _FakePlaybackAudioEngine();
    final restored = PlayerController(audioEngine: restoredEngine);
    addTearDown(restored.dispose);
    await restored.loadPersistedQueue();

    expect(restored.activeQueueId, 'default');
    expect(restored.queue.map((track) => track.id), <String>['1', '2']);
    final restoredFocus = restored.savedQueues.singleWhere(
      (queue) => queue.name == 'Focus',
    );
    expect(await restored.switchSavedQueue(restoredFocus.id), isTrue);
    expect(restored.queue.map((track) => track.id), <String>['3', '4']);
    expect(restored.current?.id, '3');
  });

  test(
    'resolves credentialed queues after restart without persisting secrets',
    () async {
      const secret = 'private-api-key';
      final metadataQueue = <Track>[
        Track(
          id: 'private-1',
          title: 'Private 1',
          sourceId: 'self-hosted',
          externalId: 'song-1',
        ),
        Track(
          id: 'private-2',
          title: 'Private 2',
          sourceId: 'self-hosted',
          externalId: 'song-2',
        ),
      ];
      Future<Track> resolve(Track track) async {
        return track.copyWith(
          streamUrl:
              'https://music.example.test/${track.externalId}?api_key=$secret',
          streamUrlIsEphemeral: true,
        );
      }

      final firstEngine = _FakePlaybackAudioEngine();
      final firstController = PlayerController(
        audioEngine: firstEngine,
        trackResolver: resolve,
      );
      await firstController.playTrack(
        metadataQueue.first,
        queue: metadataQueue,
      );

      expect(firstEngine.queue, hasLength(2));
      expect(
        firstEngine.queue.every((track) => track.streamUrl!.contains(secret)),
        isTrue,
      );
      final prefs = await SharedPreferences.getInstance();
      final firstSnapshot = prefs.getString('aethertune.player_queue.v1')!;
      expect(firstSnapshot, isNot(contains(secret)));
      expect(firstSnapshot, isNot(contains('api_key')));
      firstController.dispose();
      await _flushAsyncWork();

      final restoredEngine = _FakePlaybackAudioEngine();
      final restoredController = PlayerController(
        audioEngine: restoredEngine,
        trackResolver: resolve,
      );
      addTearDown(restoredController.dispose);
      await restoredController.loadPersistedQueue();

      expect(restoredController.queue.every((track) => !track.isPlayable), isTrue);
      await restoredController.togglePlayPause();

      expect(restoredEngine.queue, hasLength(2));
      expect(
        restoredEngine.queue.every(
          (track) => track.streamUrl!.contains(secret),
        ),
        isTrue,
      );
      final restoredSnapshot = prefs.getString('aethertune.player_queue.v1')!;
      expect(restoredSnapshot, isNot(contains(secret)));
      expect(restoredSnapshot, isNot(contains('api_key')));
    },
  );

  test('removes every queued track for a deleted provider account', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final privateTrack = Track(
      id: 'private',
      title: 'Private',
      streamUrl: 'https://music.example.test/private',
      sourceId: 'self-hosted',
    );
    final localTrack = _track('local');
    await controller.playTrack(privateTrack, queue: <Track>[
      privateTrack,
      localTrack,
    ]);

    await controller.removeTracksFromSource('self-hosted');

    expect(controller.current, isNull);
    expect(controller.queue.map((track) => track.id), <String>['local']);
    expect(engine.stopCalls, 1);
    final prefs = await SharedPreferences.getInstance();
    final snapshot = prefs.getString('aethertune.player_queue.v1')!;
    expect(snapshot, isNot(contains('music.example.test')));
    expect(snapshot, contains('local'));
  });

  test('removes deleted provider tracks from inactive saved queues', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final localTrack = _track('local');
    final privateTrack = Track(
      id: 'private',
      title: 'Private',
      streamUrl: 'https://music.example.test/private',
      sourceId: 'self-hosted',
    );
    await controller.playTrack(localTrack, queue: <Track>[localTrack]);
    final privateQueue = await controller.createSavedQueue('Private');
    await controller.switchSavedQueue(privateQueue!.id);
    await controller.playTrack(privateTrack, queue: <Track>[privateTrack]);
    await controller.switchSavedQueue('default');

    await controller.removeTracksFromSource('self-hosted');
    await controller.switchSavedQueue(privateQueue.id);

    expect(controller.queue, isEmpty);
    expect(controller.current, isNull);
  });

  test(
    'refreshes an active credentialed queue without retaining old URLs',
    () async {
      const oldSecret = 'old-private-api-key';
      const newSecret = 'new-private-api-key';
      final resolverInputs = <Track>[];
      final engine = _FakePlaybackAudioEngine();
      final controller = PlayerController(
        audioEngine: engine,
        trackResolver: (track) async {
          resolverInputs.add(track);
          return track.copyWith(
            artworkUri: Uri.file('/private/cache/$newSecret.png'),
            artworkUriIsEphemeral: true,
            streamUrl:
                'https://music.example.test/${track.externalId}?key=$newSecret',
            streamUrlIsEphemeral: true,
          );
        },
      );
      addTearDown(controller.dispose);
      final privateTracks = <Track>[
        Track(
          id: 'private-1',
          title: 'Private 1',
          artworkUri: Uri.file('/private/cache/$oldSecret-1.png'),
          artworkUriIsEphemeral: true,
          providerArtworkId: 'cover-1',
          streamUrl:
              'https://music.example.test/song-1?key=$oldSecret',
          streamUrlIsEphemeral: true,
          sourceId: 'self-hosted',
          externalId: 'song-1',
        ),
        Track(
          id: 'private-2',
          title: 'Private 2',
          artworkUri: Uri.file('/private/cache/$oldSecret-2.png'),
          artworkUriIsEphemeral: true,
          providerArtworkId: 'cover-2',
          streamUrl:
              'https://music.example.test/song-2?key=$oldSecret',
          streamUrlIsEphemeral: true,
          sourceId: 'self-hosted',
          externalId: 'song-2',
        ),
      ];
      await controller.playTrack(
        privateTracks.first,
        queue: privateTracks,
      );
      await _flushAsyncWork();
      engine.positionValue = const Duration(seconds: 43);

      await controller.refreshTracksFromSource('self-hosted');
      await _flushAsyncWork();

      expect(engine.stopCalls, 1);
      expect(engine.setQueueCalls, 2);
      expect(engine.initialIndex, 0);
      expect(engine.initialPosition, const Duration(seconds: 43));
      expect(engine.playing, isTrue);
      expect(
        engine.queue.every(
          (track) => track.streamUrl!.contains(newSecret),
        ),
        isTrue,
      );
      expect(
        engine.queue.any(
          (track) =>
              track.streamUrl!.contains(oldSecret) ||
              track.artworkUri.toString().contains(oldSecret),
        ),
        isFalse,
      );
      expect(resolverInputs, hasLength(2));
      expect(
        resolverInputs.every(
          (track) =>
              track.streamUrl == null &&
              track.artworkUri == null &&
              track.providerArtworkId != null,
        ),
        isTrue,
      );
      expect(controller.current?.id, 'private-1');
      expect(controller.position, const Duration(seconds: 43));

      final prefs = await SharedPreferences.getInstance();
      final snapshot = prefs.getString('aethertune.player_queue.v1')!;
      expect(snapshot, isNot(contains(oldSecret)));
      expect(snapshot, isNot(contains(newSecret)));
      expect(snapshot, isNot(contains('music.example.test')));
      expect(snapshot, contains('cover-1'));
    },
  );

  test('stops a rotated source when its current track cannot be resolved',
      () async {
    const oldSecret = 'retired-api-key';
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(
      audioEngine: engine,
      trackResolver: (track) async => throw StateError('Provider unavailable'),
    );
    addTearDown(controller.dispose);
    final privateTrack = Track(
      id: 'private',
      title: 'Private',
      streamUrl: 'https://music.example.test/private?key=$oldSecret',
      streamUrlIsEphemeral: true,
      sourceId: 'self-hosted',
      externalId: 'song-1',
    );
    await controller.playTrack(privateTrack, queue: <Track>[privateTrack]);
    await _flushAsyncWork();

    await controller.refreshTracksFromSource('self-hosted');

    expect(engine.stopCalls, 1);
    expect(engine.setQueueCalls, 1);
    expect(engine.playing, isFalse);
    expect(controller.current?.streamUrl, isNull);
    expect(controller.current?.isPlayable, isFalse);
    final prefs = await SharedPreferences.getInstance();
    final snapshot = prefs.getString('aethertune.player_queue.v1')!;
    expect(snapshot, isNot(contains(oldSecret)));
    expect(snapshot, isNot(contains('music.example.test')));
  });

  test('isolates the current source for stop-at-end behavior', () async {
    final engine = _FakePlaybackAudioEngine();
    final controller = PlayerController(audioEngine: engine);
    addTearDown(controller.dispose);
    final tracks = <Track>[_track('1'), _track('2')];
    await controller.playTrack(tracks.first, queue: tracks);
    engine.positionValue = const Duration(minutes: 1);

    controller.stopAtEndOfTrack();
    await _flushAsyncWork();

    expect(engine.queue.map((track) => track.id), <String>['1']);
    expect(engine.initialPosition, const Duration(minutes: 1));

    engine.emitCompleted();
    await _flushAsyncWork();
    expect(engine.stopCalls, 1);
    expect(controller.stopAtEndOfTrackEnabled, isFalse);
  });
}

Future<void> _flushAsyncWork() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Track _track(
  String id, {
  String? localPath,
  String? streamUrl,
  double? replayGainTrackDb,
  double? replayGainAlbumDb,
}) {
  return Track(
    id: id,
    title: 'Track $id',
    localPath: localPath ?? '/music/$id.mp3',
    streamUrl: streamUrl,
    replayGainTrackDb: replayGainTrackDb,
    replayGainAlbumDb: replayGainAlbumDb,
  );
}

class _FakePlaybackAudioEngine
    implements
        CrossfadePlaybackAudioEngine,
        PitchPlaybackAudioEngine,
        PlaybackErrorAudioEngine {
  final _stateController = StreamController<Object?>.broadcast(sync: true);
  final _durationController =
      StreamController<Duration?>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _processingController =
      StreamController<ProcessingState>.broadcast(sync: true);
  final _indexController = StreamController<int?>.broadcast(sync: true);
  final _errorController = StreamController<Object>.broadcast(sync: true);

  List<Track> queue = <Track>[];
  int initialIndex = 0;
  Duration initialPosition = Duration.zero;
  Duration positionValue = Duration.zero;
  bool playingValue = false;
  bool shuffleValue = false;
  LoopMode loopModeValue = LoopMode.off;
  double volumeValue = 1;
  double speedValue = 1;
  double pitchValue = 1;
  bool supportsPitchValue = false;
  Duration crossfadeDurationValue = Duration.zero;
  CrossfadeTrackVolumeResolver? crossfadeTrackVolumeResolver;
  int currentIndex = 0;
  int setQueueCalls = 0;
  int seekToNextCalls = 0;
  int seekToPreviousCalls = 0;
  int stopCalls = 0;
  final List<Duration> seekPositions = <Duration>[];

  @override
  Stream<Object?> get stateChanges => _stateController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _processingController.stream;

  @override
  Stream<int?> get currentIndexStream => _indexController.stream;

  @override
  Stream<Object> get errorStream => _errorController.stream;

  @override
  bool get playing => playingValue;

  @override
  bool get shuffleModeEnabled => shuffleValue;

  @override
  LoopMode get loopMode => loopModeValue;

  @override
  Duration get position => positionValue;

  @override
  Duration get bufferedPosition => positionValue;

  @override
  double get speed => speedValue;

  @override
  bool get supportsPitch => supportsPitchValue;

  @override
  double get pitch => pitchValue;

  @override
  double get volume => volumeValue;

  @override
  bool get hasNext => currentIndex + 1 < queue.length;

  @override
  bool get hasPrevious => currentIndex > 0;

  @override
  bool get supportsCrossfade => true;

  @override
  Duration get crossfadeDuration => crossfadeDurationValue;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    setQueueCalls += 1;
    queue = List<Track>.from(tracks);
    this.initialIndex = initialIndex;
    this.initialPosition = initialPosition;
    currentIndex = initialIndex;
    positionValue = initialPosition;
    _indexController.add(initialIndex);
  }

  void emitAutomaticIndex(int index) {
    currentIndex = index;
    positionValue = Duration.zero;
    _positionController.add(positionValue);
    _indexController.add(index);
  }

  void emitPosition(Duration position) {
    positionValue = position;
    _positionController.add(positionValue);
  }

  void emitCompleted() {
    _processingController.add(ProcessingState.completed);
  }

  void emitError(Object error) => _errorController.add(error);

  @override
  Future<void> play() async {
    playingValue = true;
    _stateController.add(null);
  }

  @override
  Future<void> pause() async {
    playingValue = false;
    _stateController.add(null);
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playingValue = false;
    _stateController.add(null);
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    seekPositions.add(position);
    positionValue = position;
    _positionController.add(positionValue);
    if (index != null) {
      currentIndex = index;
      _indexController.add(index);
    }
  }

  @override
  Future<void> seekToNext() async {
    seekToNextCalls += 1;
    emitAutomaticIndex(currentIndex + 1);
  }

  @override
  Future<void> seekToPrevious() async {
    seekToPreviousCalls += 1;
    emitAutomaticIndex(currentIndex - 1);
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    shuffleValue = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopModeValue = mode;
  }

  void emitDuration(Duration duration) {
    _durationController.add(duration);
  }

  @override
  Future<void> setSpeed(double speed) async {
    speedValue = speed;
  }

  @override
  Future<void> setPitch(double pitch) async {
    if (!supportsPitchValue) {
      throw UnsupportedError('Pitch control is unavailable for this backend.');
    }
    pitchValue = pitch;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeValue = volume;
  }

  @override
  void setCrossfadeTrackVolumeResolver(
    CrossfadeTrackVolumeResolver? resolver,
  ) {
    crossfadeTrackVolumeResolver = resolver;
  }

  double crossfadeVolumeFor(Track track) =>
      crossfadeTrackVolumeResolver?.call(track) ?? volumeValue;

  @override
  Future<void> setCrossfadeDuration(Duration duration) async {
    crossfadeDurationValue = duration;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _durationController.close();
    await _positionController.close();
    await _processingController.close();
    await _indexController.close();
    await _errorController.close();
  }
}

class _NoCrossfadeAudioEngine extends _FakePlaybackAudioEngine {
  @override
  bool get supportsCrossfade => false;
}

class _FakeAudioEffectsEngine extends _FakePlaybackAudioEngine
    implements AudioEffectsPlaybackAudioEngine, VirtualizerPlaybackAudioEngine {
  bool equalizerEnabledValue = false;
  PlaybackEqualizerProfile equalizerProfileValue =
      const PlaybackEqualizerProfile(
        preset: PlaybackEqualizerPreset.flat,
      );
  bool loudnessEnhancerEnabledValue = false;
  double loudnessEnhancerTargetGainValue = 0;
  int loudnessEnhancerEnhancerSetCalls = 0;
  bool virtualizerEnabledValue = false;
  int virtualizerStrengthValue = 500;
  List<PlaybackEqualizerBand> bands = const <PlaybackEqualizerBand>[
    PlaybackEqualizerBand(
      index: 0,
      centerFrequencyHz: 60,
      gainDb: 0,
      minGainDb: -12,
      maxGainDb: 12,
    ),
    PlaybackEqualizerBand(
      index: 1,
      centerFrequencyHz: 1000,
      gainDb: 0,
      minGainDb: -12,
      maxGainDb: 12,
    ),
    PlaybackEqualizerBand(
      index: 2,
      centerFrequencyHz: 12000,
      gainDb: 0,
      minGainDb: -12,
      maxGainDb: 12,
    ),
  ];

  @override
  bool get supportsEqualizer => true;

  @override
  bool get supportsLoudnessEnhancer => true;

  @override
  bool get supportsVirtualizer => true;

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    equalizerEnabledValue = enabled;
  }

  @override
  Future<void> setEqualizerProfile(PlaybackEqualizerProfile profile) async {
    equalizerProfileValue = profile;
    bands = <PlaybackEqualizerBand>[
      for (final band in bands)
        band.copyWith(
          gainDb: equalizerGainForFrequency(
            profile,
            band.centerFrequencyHz,
          ).clamp(band.minGainDb, band.maxGainDb).toDouble(),
        ),
    ];
  }

  @override
  Future<List<PlaybackEqualizerBand>> loadEqualizerBands() async {
    return List<PlaybackEqualizerBand>.from(bands);
  }

  @override
  Future<void> setLoudnessEnhancerEnabled(bool enabled) async {
    loudnessEnhancerEnabledValue = enabled;
    loudnessEnhancerEnhancerSetCalls += 1;
  }

  @override
  Future<void> setLoudnessEnhancerTargetGain(double gainDb) async {
    loudnessEnhancerTargetGainValue = gainDb;
  }

  @override
  Future<void> setVirtualizerEnabled(bool enabled) async {
    virtualizerEnabledValue = enabled;
  }

  @override
  Future<void> setVirtualizerStrength(int strength) async {
    virtualizerStrengthValue = strength;
  }
}

class _FakeSkipSilenceEngine extends _FakePlaybackAudioEngine
    implements SkipSilencePlaybackAudioEngine {
  bool skipSilenceEnabledValue = false;

  @override
  bool get supportsSkipSilence => true;

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) async {
    skipSilenceEnabledValue = enabled;
  }
}

class _FakeMediaLibraryBrowseEngine extends _FakePlaybackAudioEngine
    implements MediaLibraryBrowsePlaybackAudioEngine {
  List<Track> browseTracks = <Track>[];
  MediaLibraryTrackSelectionHandler? _onTrackSelected;

  @override
  void setMediaLibraryBrowseTracks(
    Iterable<Track> tracks, {
    required MediaLibraryTrackSelectionHandler onTrackSelected,
  }) {
    browseTracks = List<Track>.from(tracks);
    _onTrackSelected = onTrackSelected;
  }

  Future<void> selectBrowseTrack(Track track) async {
    await _onTrackSelected!(track);
  }
}
