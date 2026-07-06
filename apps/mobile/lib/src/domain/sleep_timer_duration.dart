const int minCustomSleepTimerMinutes = 1;
const int maxCustomSleepTimerMinutes = 24 * 60;

Duration? parseCustomSleepTimerDuration(String input) {
  final minutes = int.tryParse(input.trim());
  if (minutes == null ||
      minutes < minCustomSleepTimerMinutes ||
      minutes > maxCustomSleepTimerMinutes) {
    return null;
  }

  return Duration(minutes: minutes);
}
