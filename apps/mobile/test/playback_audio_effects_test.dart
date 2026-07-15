import 'package:aethertune/src/player/playback_audio_effects.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flat preset keeps every device frequency unchanged', () {
    const profile = PlaybackEqualizerProfile(
      preset: PlaybackEqualizerPreset.flat,
    );

    expect(equalizerGainForFrequency(profile, 60), 0);
    expect(equalizerGainForFrequency(profile, 1000), 0);
    expect(equalizerGainForFrequency(profile, 16000), 0);
  });

  test('bass preset boosts low bands and leaves midrange flat', () {
    const profile = PlaybackEqualizerProfile(
      preset: PlaybackEqualizerPreset.bassBoost,
    );

    expect(equalizerGainForFrequency(profile, 80), 6);
    expect(equalizerGainForFrequency(profile, 250), 3);
    expect(equalizerGainForFrequency(profile, 1000), 0);
  });

  test('custom profiles interpolate on a logarithmic frequency scale', () {
    const profile = PlaybackEqualizerProfile(
      preset: PlaybackEqualizerPreset.custom,
      customPoints: <PlaybackEqualizerPoint>[
        PlaybackEqualizerPoint(frequencyHz: 100, gainDb: 0),
        PlaybackEqualizerPoint(frequencyHz: 10000, gainDb: 10),
      ],
    );

    expect(equalizerGainForFrequency(profile, 1000), closeTo(5, 0.0001));
    expect(equalizerGainForFrequency(profile, 20), 0);
    expect(equalizerGainForFrequency(profile, 20000), 10);
  });

  test('empty custom profiles and invalid frequencies resolve to flat', () {
    const profile = PlaybackEqualizerProfile(
      preset: PlaybackEqualizerPreset.custom,
    );

    expect(equalizerGainForFrequency(profile, 1000), 0);
    expect(equalizerGainForFrequency(profile, double.nan), 0);
    expect(equalizerGainForFrequency(profile, 0), 0);
  });

  test('custom profiles ignore invalid points and collapse duplicates', () {
    const profile = PlaybackEqualizerProfile(
      preset: PlaybackEqualizerPreset.custom,
      customPoints: <PlaybackEqualizerPoint>[
        PlaybackEqualizerPoint(frequencyHz: -1, gainDb: 12),
        PlaybackEqualizerPoint(frequencyHz: 1000, gainDb: 2),
        PlaybackEqualizerPoint(frequencyHz: 1000, gainDb: 4),
        PlaybackEqualizerPoint(frequencyHz: 2000, gainDb: double.nan),
      ],
    );

    expect(equalizerGainForFrequency(profile, 1000), 4);
  });
}
