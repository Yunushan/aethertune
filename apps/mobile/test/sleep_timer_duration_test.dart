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
}
