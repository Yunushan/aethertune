const supportedPlaybackSpeedValues = <double>[
  0.5,
  0.75,
  1,
  1.25,
  1.5,
  2,
  2.5,
  3,
];

bool isSupportedPlaybackSpeed(double speed) {
  return supportedPlaybackSpeedValues.contains(speed);
}
