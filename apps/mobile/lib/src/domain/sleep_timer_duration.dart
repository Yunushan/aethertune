const int minCustomSleepTimerMinutes = 1;
const int maxCustomSleepTimerMinutes = 24 * 60;
const Duration defaultSleepTimerFadeDuration = Duration(seconds: 30);
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
