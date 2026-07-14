import 'package:aethertune/src/domain/replay_gain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses bounded ReplayGain comments', () {
    expect(parseReplayGainDb('-7.20 dB'), -7.2);
    expect(parseReplayGainDb('+3DB'), 3);
    expect(parseReplayGainDb('NaN'), isNull);
    expect(parseReplayGainDb('-25 dB'), isNull);
  });

  test('applies normalization without exceeding the player range', () {
    expect(
      replayGainAdjustedVolume(
        baseVolume: 0.8,
        enabled: true,
        gainDb: -6,
      ),
      closeTo(0.40095, 0.0001),
    );
    expect(
      replayGainAdjustedVolume(baseVolume: 0.8, enabled: true, gainDb: 6),
      1,
    );
    expect(
      replayGainAdjustedVolume(baseVolume: 0.8, enabled: false, gainDb: -6),
      0.8,
    );
  });
}
