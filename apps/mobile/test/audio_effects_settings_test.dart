import 'dart:async';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_effects.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';
import 'package:aethertune/src/ui/widgets/audio_effects_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('configures native equalizer, volume boost, and spatial controls', (
    tester,
  ) async {
    final engine = _WidgetAudioEffectsEngine();
    final player = PlayerController(audioEngine: engine);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: player,
            builder: (context, _) => AudioEffectsSettingsTile(player: player),
          ),
        ),
      ),
    );

    expect(find.text('Off'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey<String>('audio-effects-settings-tile')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.text('Volume boost'), findsOneWidget);
    expect(find.text('Spatial audio'), findsOneWidget);
    expect(find.text('60 Hz'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('equalizer-enabled-switch')),
    );
    await tester.pumpAndSettle();
    expect(engine.equalizerEnabledValue, isTrue);

    await tester.tap(
      find.byKey(const ValueKey<String>('equalizer-preset-dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bass boost').last);
    await tester.pumpAndSettle();
    expect(
      engine.equalizerProfileValue.preset,
      PlaybackEqualizerPreset.bassBoost,
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('loudness-enhancer-enabled-switch')),
    );
    await tester.pumpAndSettle();
    expect(engine.loudnessEnhancerEnabledValue, isTrue);

    final virtualizerSwitch = find.byKey(
      const ValueKey<String>('virtualizer-enabled-switch'),
    );
    await tester.ensureVisible(virtualizerSwitch);
    await tester.pumpAndSettle();
    await tester.tap(virtualizerSwitch);
    await tester.pumpAndSettle();
    expect(engine.virtualizerEnabledValue, isTrue);

    final spatialSliderFinder = find.byKey(
      const ValueKey<String>('virtualizer-strength-slider'),
    );
    await tester.ensureVisible(spatialSliderFinder);
    final spatialSlider = tester.widget<Slider>(spatialSliderFinder);
    spatialSlider.onChangeEnd!(650);
    await tester.pumpAndSettle();
    expect(engine.virtualizerStrengthValue, 650);

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bass boost'), findsOneWidget);
    expect(find.textContaining('Volume boost'), findsOneWidget);
    expect(find.textContaining('Spatial audio'), findsOneWidget);
  });
}

class _WidgetAudioEffectsEngine
    implements AudioEffectsPlaybackAudioEngine, VirtualizerPlaybackAudioEngine {
  bool equalizerEnabledValue = false;
  PlaybackEqualizerProfile equalizerProfileValue =
      const PlaybackEqualizerProfile(preset: PlaybackEqualizerPreset.flat);
  bool loudnessEnhancerEnabledValue = false;
  double loudnessEnhancerTargetGainValue = 0;
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
  ];

  @override
  Stream<Object?> get stateChanges => const Stream<Object?>.empty();

  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();

  @override
  Stream<ProcessingState> get processingStateStream =>
      const Stream<ProcessingState>.empty();

  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();

  @override
  bool get playing => false;

  @override
  bool get shuffleModeEnabled => false;

  @override
  LoopMode get loopMode => LoopMode.off;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get bufferedPosition => Duration.zero;

  @override
  double get speed => 1;

  @override
  double get volume => 1;

  @override
  bool get hasNext => false;

  @override
  bool get hasPrevious => false;

  @override
  bool get supportsEqualizer => true;

  @override
  bool get supportsLoudnessEnhancer => true;

  @override
  bool get supportsVirtualizer => true;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position, {int? index}) async {}

  @override
  Future<void> seekToNext() async {}

  @override
  Future<void> seekToPrevious() async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setSpeed(double speed) async {}

  @override
  Future<void> setVolume(double volume) async {}

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

  @override
  Future<void> dispose() async {}
}
