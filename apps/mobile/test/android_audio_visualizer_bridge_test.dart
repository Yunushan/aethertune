import 'package:aethertune/src/player/android_audio_visualizer_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes malformed visualizer values into bounded bands', () {
    final bands = normalizeAudioVisualizerBands(<Object?>[
      -2,
      0.25,
      3,
      double.nan,
      'not-a-band',
      double.infinity,
    ]);

    expect(bands, <double>[0, 0.25, 1, 0, 0, 0]);
  });

  test('limits visualizer output to the renderer band count', () {
    final bands = normalizeAudioVisualizerBands(
      List<num>.generate(24, (index) => index / 20),
    );

    expect(bands, hasLength(16));
    expect(bands.first, 0);
    expect(bands.last, 0.75);
  });
}
