import 'dart:math' as math;

const minReplayGainDb = -24.0;
const maxReplayGainDb = 24.0;
const maxReplayGainPeak = 8.0;

enum ReplayGainMode { track, album }

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

/// Parses an EBU R128 gain tag such as `-720` (representing -7.20 dB).
///
/// Opus and Vorbis store R128 values as signed integer hundredths of a dB.
double? parseEbuR128GainDb(String? value) {
  final match = RegExp(r'^[+-]?\d+$').firstMatch(value?.trim() ?? '');
  if (match == null) {
    return null;
  }
  final hundredths = int.tryParse(match.group(0) ?? '');
  if (hundredths == null) {
    return null;
  }
  return sanitizeReplayGainDb(hundredths / 100);
}

/// Returns a valid linear ReplayGain peak amplitude.
double? sanitizeReplayGainPeak(double? value) {
  if (value == null || !value.isFinite || value <= 0 || value > maxReplayGainPeak) {
    return null;
  }
  return value;
}

/// Parses a native ReplayGain peak value such as `0.978642`.
double? parseReplayGainPeak(String? value) {
  final match = RegExp(r'^[+]?(?:\d+(?:\.\d+)?|\.\d+)$')
      .firstMatch(value?.trim() ?? '');
  return sanitizeReplayGainPeak(double.tryParse(match?.group(0) ?? ''));
}

double replayGainMultiplier(double? gainDb) {
  final normalizedGain = sanitizeReplayGainDb(gainDb);
  if (normalizedGain == null) {
    return 1;
  }
  return math.pow(10, normalizedGain / 20).toDouble();
}

double? replayGainForMode({
  required ReplayGainMode mode,
  double? trackGainDb,
  double? albumGainDb,
}) {
  return switch (mode) {
    ReplayGainMode.track =>
      sanitizeReplayGainDb(trackGainDb) ?? sanitizeReplayGainDb(albumGainDb),
    ReplayGainMode.album =>
      sanitizeReplayGainDb(albumGainDb) ?? sanitizeReplayGainDb(trackGainDb),
  };
}

/// Selects a peak value that corresponds to the gain selected for [mode].
double? replayGainPeakForMode({
  required ReplayGainMode mode,
  double? trackGainDb,
  double? albumGainDb,
  double? trackPeak,
  double? albumPeak,
}) {
  final hasTrackGain = sanitizeReplayGainDb(trackGainDb) != null;
  final hasAlbumGain = sanitizeReplayGainDb(albumGainDb) != null;
  final useTrack = switch (mode) {
    ReplayGainMode.track => hasTrackGain || !hasAlbumGain,
    ReplayGainMode.album => !hasAlbumGain && hasTrackGain,
  };
  return sanitizeReplayGainPeak(useTrack ? trackPeak : albumPeak);
}

double replayGainAdjustedVolume({
  required double baseVolume,
  required bool enabled,
  double? gainDb,
  double? peak,
}) {
  final clampedBaseVolume = baseVolume.clamp(0, 1).toDouble();
  if (!enabled) {
    return clampedBaseVolume;
  }
  final normalizedVolume = (clampedBaseVolume * replayGainMultiplier(gainDb))
      .clamp(0, 1)
      .toDouble();
  final normalizedPeak = sanitizeReplayGainPeak(peak);
  if (normalizedPeak == null) {
    return normalizedVolume;
  }
  return math.min(normalizedVolume, 1 / normalizedPeak).toDouble();
}
