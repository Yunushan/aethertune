import 'package:aethertune/src/domain/replay_gain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses bounded ReplayGain comments', () {
    expect(parseReplayGainDb('-7.20 dB'), -7.2);
    expect(parseReplayGainDb('+3DB'), 3);
    expect(parseReplayGainDb('NaN'), isNull);
    expect(parseReplayGainDb('-25 dB'), isNull);
  });

  test('parses bounded EBU R128 gains in hundredths of a dB', () {
    expect(parseEbuR128GainDb('-720'), -7.2);
    expect(parseEbuR128GainDb('+325'), 3.25);
    expect(parseEbuR128GainDb('2500'), isNull);
    expect(parseEbuR128GainDb('-3.25'), isNull);
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

  test('selects an album gain with a safe track fallback', () {
    expect(
      replayGainForMode(
        mode: ReplayGainMode.album,
        trackGainDb: -6,
        albumGainDb: -3,
      ),
      -3,
    );
    expect(
      replayGainForMode(
        mode: ReplayGainMode.album,
        trackGainDb: -6,
      ),
      -6,
    );
  });
}
