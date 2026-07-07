import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/domain/sleep_timer_duration.dart';

void main() {
  test('parses valid custom sleep timer minute input', () {
    expect(parseCustomSleepTimerDuration('1'), const Duration(minutes: 1));
    expect(parseCustomSleepTimerDuration(' 45 '), const Duration(minutes: 45));
    expect(
      parseCustomSleepTimerDuration('$maxCustomSleepTimerMinutes'),
      const Duration(hours: 24),
    );
  });

  test('rejects invalid custom sleep timer minute input', () {
    expect(parseCustomSleepTimerDuration(''), isNull);
    expect(parseCustomSleepTimerDuration('0'), isNull);
    expect(parseCustomSleepTimerDuration('-5'), isNull);
    expect(parseCustomSleepTimerDuration('2.5'), isNull);
    expect(parseCustomSleepTimerDuration('soon'), isNull);
    expect(
      parseCustomSleepTimerDuration('${maxCustomSleepTimerMinutes + 1}'),
      isNull,
    );
  });

  test('calculates sleep timer fade timing', () {
    expect(
      sleepTimerFadeStartDelay(const Duration(minutes: 5)),
      const Duration(minutes: 4, seconds: 30),
    );
    expect(
      sleepTimerFadeStartDelay(const Duration(seconds: 15)),
      Duration.zero,
    );
    expect(
      sleepTimerFadeStepInterval(defaultSleepTimerFadeDuration),
      const Duration(seconds: 3),
    );
  });

  test('calculates clamped sleep timer fade volumes', () {
    expect(sleepTimerFadeVolume(startVolume: 1, step: 0), 1);
    expect(sleepTimerFadeVolume(startVolume: 1, step: 5), 0.5);
    expect(sleepTimerFadeVolume(startVolume: 1, step: sleepTimerFadeSteps), 0);
    expect(sleepTimerFadeVolume(startVolume: 1, step: 99), 0);
    expect(
      sleepTimerFadeVolume(startVolume: 0.8, step: 5),
      closeTo(0.4, 0.001),
    );
  });
}
