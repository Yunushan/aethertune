import 'dart:math' as math;

const minReplayGainDb = -24.0;
const maxReplayGainDb = 24.0;

/// Returns a bounded ReplayGain value suitable for a player volume multiplier.
double? sanitizeReplayGainDb(double? value) {
  if (value == null ||
      !value.isFinite ||
      value < minReplayGainDb ||
      value > maxReplayGainDb) {
    return null;
  }
  return value;
}

/// Parses a native ReplayGain comment such as `-7.20 dB`.
double? parseReplayGainDb(String? value) {
  final match = RegExp(
    r'^([+-]?(?:\d+(?:\.\d+)?|\.\d+))\s*(?:db)?$',
    caseSensitive: false,
  ).firstMatch(value?.trim() ?? '');
  return sanitizeReplayGainDb(double.tryParse(match?.group(1) ?? ''));
}

double replayGainMultiplier(double? gainDb) {
  final normalizedGain = sanitizeReplayGainDb(gainDb);
  if (normalizedGain == null) {
    return 1;
  }
  return math.pow(10, normalizedGain / 20).toDouble();
}

double replayGainAdjustedVolume({
  required double baseVolume,
  required bool enabled,
  double? gainDb,
}) {
  final clampedBaseVolume = baseVolume.clamp(0, 1).toDouble();
  if (!enabled) {
    return clampedBaseVolume;
  }
  return (clampedBaseVolume * replayGainMultiplier(gainDb))
      .clamp(0, 1)
      .toDouble();
}
