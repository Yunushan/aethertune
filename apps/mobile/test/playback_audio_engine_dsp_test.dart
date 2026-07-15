import 'package:aethertune/src/player/playback_audio_effects.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Android pipeline accepts audio effect settings before a source loads',
    () async {
      final engine = JustAudioPlaybackEngine(enableAndroidAudioEffects: true);
      addTearDown(engine.dispose);

      expect(engine.supportsEqualizer, isTrue);
      expect(engine.supportsLoudnessEnhancer, isTrue);
      await engine.setEqualizerProfile(
        const PlaybackEqualizerProfile(
          preset: PlaybackEqualizerPreset.bassBoost,
        ),
      );
      await engine.setEqualizerEnabled(true);
      await engine.setLoudnessEnhancerTargetGain(4);
      await engine.setLoudnessEnhancerEnabled(true);
      expect(await engine.loadEqualizerBands(), isEmpty);
    },
  );

  test(
    'default pipeline reports platform audio effects as unavailable',
    () async {
      final engine = JustAudioPlaybackEngine();
      addTearDown(engine.dispose);

      expect(engine.supportsEqualizer, isFalse);
      expect(engine.supportsLoudnessEnhancer, isFalse);
    },
  );
}
