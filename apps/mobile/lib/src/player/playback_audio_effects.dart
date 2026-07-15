import 'dart:math' as math;

enum PlaybackEqualizerPreset { flat, bassBoost, vocal, treble, custom }

final class PlaybackEqualizerPoint {
  const PlaybackEqualizerPoint({
    required this.frequencyHz,
    required this.gainDb,
  });

  final double frequencyHz;
  final double gainDb;

  Map<String, Object> toJson() => <String, Object>{
    'frequencyHz': frequencyHz,
    'gainDb': gainDb,
  };
}

final class PlaybackEqualizerProfile {
  const PlaybackEqualizerProfile({
    required this.preset,
    this.customPoints = const <PlaybackEqualizerPoint>[],
  });

  final PlaybackEqualizerPreset preset;
  final List<PlaybackEqualizerPoint> customPoints;
}

final class PlaybackEqualizerBand {
  const PlaybackEqualizerBand({
    required this.index,
    required this.centerFrequencyHz,
    required this.gainDb,
    required this.minGainDb,
    required this.maxGainDb,
  });

  final int index;
  final double centerFrequencyHz;
  final double gainDb;
  final double minGainDb;
  final double maxGainDb;

  PlaybackEqualizerBand copyWith({double? gainDb}) {
    return PlaybackEqualizerBand(
      index: index,
      centerFrequencyHz: centerFrequencyHz,
      gainDb: gainDb ?? this.gainDb,
      minGainDb: minGainDb,
      maxGainDb: maxGainDb,
    );
  }
}

const _flatEqualizerPoints = <PlaybackEqualizerPoint>[
  PlaybackEqualizerPoint(frequencyHz: 20, gainDb: 0),
  PlaybackEqualizerPoint(frequencyHz: 20000, gainDb: 0),
];

const _bassBoostEqualizerPoints = <PlaybackEqualizerPoint>[
  PlaybackEqualizerPoint(frequencyHz: 20, gainDb: 6),
  PlaybackEqualizerPoint(frequencyHz: 80, gainDb: 6),
  PlaybackEqualizerPoint(frequencyHz: 250, gainDb: 3),
  PlaybackEqualizerPoint(frequencyHz: 1000, gainDb: 0),
  PlaybackEqualizerPoint(frequencyHz: 20000, gainDb: 0),
];

const _vocalEqualizerPoints = <PlaybackEqualizerPoint>[
  PlaybackEqualizerPoint(frequencyHz: 20, gainDb: -2),
  PlaybackEqualizerPoint(frequencyHz: 250, gainDb: 0),
  PlaybackEqualizerPoint(frequencyHz: 1000, gainDb: 2),
  PlaybackEqualizerPoint(frequencyHz: 3000, gainDb: 4),
  PlaybackEqualizerPoint(frequencyHz: 8000, gainDb: 1),
  PlaybackEqualizerPoint(frequencyHz: 20000, gainDb: 0),
];

const _trebleEqualizerPoints = <PlaybackEqualizerPoint>[
  PlaybackEqualizerPoint(frequencyHz: 20, gainDb: 0),
  PlaybackEqualizerPoint(frequencyHz: 1000, gainDb: 0),
  PlaybackEqualizerPoint(frequencyHz: 3000, gainDb: 2),
  PlaybackEqualizerPoint(frequencyHz: 8000, gainDb: 5),
  PlaybackEqualizerPoint(frequencyHz: 20000, gainDb: 6),
];

double equalizerGainForFrequency(
  PlaybackEqualizerProfile profile,
  double frequencyHz,
) {
  final points = switch (profile.preset) {
    PlaybackEqualizerPreset.flat => _flatEqualizerPoints,
    PlaybackEqualizerPreset.bassBoost => _bassBoostEqualizerPoints,
    PlaybackEqualizerPreset.vocal => _vocalEqualizerPoints,
    PlaybackEqualizerPreset.treble => _trebleEqualizerPoints,
    PlaybackEqualizerPreset.custom => profile.customPoints,
  };
  if (points.isEmpty || !frequencyHz.isFinite || frequencyHz <= 0) {
    return 0;
  }

  final sorted =
      points
          .where(
            (point) =>
                point.frequencyHz.isFinite &&
                point.frequencyHz > 0 &&
                point.gainDb.isFinite,
          )
          .toList()
        ..sort((left, right) => left.frequencyHz.compareTo(right.frequencyHz));
  final ordered = <PlaybackEqualizerPoint>[];
  for (final point in sorted) {
    if (ordered.isNotEmpty && ordered.last.frequencyHz == point.frequencyHz) {
      ordered[ordered.length - 1] = point;
    } else {
      ordered.add(point);
    }
  }
  if (ordered.isEmpty) {
    return 0;
  }
  if (frequencyHz <= ordered.first.frequencyHz) {
    return ordered.first.gainDb;
  }
  if (frequencyHz >= ordered.last.frequencyHz) {
    return ordered.last.gainDb;
  }

  for (var index = 1; index < ordered.length; index += 1) {
    final upper = ordered[index];
    if (frequencyHz > upper.frequencyHz) {
      continue;
    }
    final lower = ordered[index - 1];
    final lowerLog = math.log(lower.frequencyHz);
    final upperLog = math.log(upper.frequencyHz);
    final ratio = (math.log(frequencyHz) - lowerLog) / (upperLog - lowerLog);
    return lower.gainDb + ((upper.gainDb - lower.gainDb) * ratio);
  }

  return ordered.last.gainDb;
}
