const int minCustomSleepTimerMinutes = 1;
const int maxCustomSleepTimerMinutes = 24 * 60;
const Duration defaultSleepTimerFadeDuration = Duration(seconds: 30);
const List<Duration> sleepTimerFadeDurationOptions = <Duration>[
  Duration(seconds: 10),
  defaultSleepTimerFadeDuration,
  Duration(minutes: 1),
  Duration(minutes: 2),
];
const int sleepTimerFadeSteps = 10;

Duration? parseCustomSleepTimerDuration(String input) {
  final minutes = int.tryParse(input.trim());
  if (minutes == null ||
      minutes < minCustomSleepTimerMinutes ||
      minutes > maxCustomSleepTimerMinutes) {
    return null;
  }

  return Duration(minutes: minutes);
}

String sleepTimerFadeDurationLabel(Duration duration) {
  if (duration.inSeconds < 60) {
    return '${duration.inSeconds} seconds';
  }

  final minutes = duration.inMinutes;
  return minutes == 1 ? '1 minute' : '$minutes minutes';
}

String formatSleepTimerRemaining(Duration duration) {
  if (duration <= Duration.zero || duration.inSeconds < 60) {
    return 'Less than 1 minute';
  }

  final totalMinutes = duration.inMinutes;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours == 0) {
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }
  if (minutes == 0) {
    return hours == 1 ? '1 hour' : '$hours hours';
  }
  final hourLabel = hours == 1 ? '1 hour' : '$hours hours';
  final minuteLabel = minutes == 1 ? '1 minute' : '$minutes minutes';
  return '$hourLabel $minuteLabel';
}

Duration sleepTimerFadeStartDelay(
  Duration timerDuration, {
  Duration fadeDuration = defaultSleepTimerFadeDuration,
}) {
  if (timerDuration <= fadeDuration) {
    return Duration.zero;
  }

  return timerDuration - fadeDuration;
}

Duration sleepTimerFadeStepInterval(
  Duration fadeDuration, {
  int steps = sleepTimerFadeSteps,
}) {
  if (steps <= 0 || fadeDuration <= Duration.zero) {
    return Duration.zero;
  }

  return Duration(
    microseconds: fadeDuration.inMicroseconds ~/ steps,
  );
}

double sleepTimerFadeVolume({
  required double startVolume,
  required int step,
  int steps = sleepTimerFadeSteps,
}) {
  if (steps <= 0) {
    return 0;
  }

  final clampedStep = step.clamp(0, steps).toInt();
  final volume = startVolume * (1 - clampedStep / steps);
  return volume.clamp(0, 1).toDouble();
}
