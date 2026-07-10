import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/library_store.dart';

const double listeningRecapCardWidth = 360;
const double listeningRecapCardHeight = 450;

class ListeningRecapCard extends StatelessWidget {
  const ListeningRecapCard({
    super.key,
    required this.recap,
  });

  final LibraryListeningRecap recap;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF111315);
    const surface = Color(0xFF202427);
    const primary = Color(0xFF56D8C5);
    const secondary = Color(0xFFF1BC59);
    const tertiary = Color(0xFFE9748F);
    const foreground = Color(0xFFF5F7F7);
    const muted = Color(0xFFB8C0C0);
    final stats = recap.stats;
    final topTrack = stats.topTracks.isEmpty ? null : stats.topTracks.first;
    final topArtist = stats.topArtists.isEmpty ? null : stats.topArtists.first;
    final topAlbum = stats.topAlbums.isEmpty ? null : stats.topAlbums.first;
    final topGenre = stats.topGenres.isEmpty ? null : stats.topGenres.first;

    return SizedBox(
      width: listeningRecapCardWidth,
      height: listeningRecapCardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF353B3D)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DefaultTextStyle(
            style: const TextStyle(color: foreground),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.graphic_eq,
                          color: background,
                          size: 24,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'AetherTune',
                            style: TextStyle(
                              color: foreground,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Listening recap',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  listeningRecapLabel(recap),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: secondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  formatListeningRecapDuration(
                    stats.estimatedListeningDuration,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: foreground,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'listening time',
                  style: TextStyle(color: muted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _RecapMetric(
                          value: '${stats.playbackCount}',
                          label: 'plays',
                          color: primary,
                        ),
                      ),
                      const SizedBox(
                        height: 34,
                        child: VerticalDivider(
                          width: 1,
                          color: Color(0xFF465052),
                        ),
                      ),
                      Expanded(
                        child: _RecapMetric(
                          value: '${stats.uniquePlayedTrackCount}',
                          label: 'tracks',
                          color: tertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'MOST PLAYED',
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.music_note, color: primary, size: 22),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            topTrack?.track.title ?? 'No top track yet',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: foreground,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            topTrack == null
                                ? 'Keep listening to build your recap'
                                : '${topTrack.track.artist} - ${topTrack.playCount} play(s)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                _RecapFactRow(
                  icon: Icons.person_outline,
                  label: 'Top artist',
                  value: topArtist?.label ?? 'Not enough data',
                  color: secondary,
                ),
                const SizedBox(height: 8),
                _RecapFactRow(
                  icon: Icons.album_outlined,
                  label: topAlbum == null ? 'Top genre' : 'Top album',
                  value: topAlbum?.label ?? topGenre?.label ?? 'Not enough data',
                  color: tertiary,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Private, local listening history',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecapMetric extends StatelessWidget {
  const _RecapMetric({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 21,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Color(0xFFB8C0C0), fontSize: 11),
        ),
      ],
    );
  }
}

class _RecapFactRow extends StatelessWidget {
  const _RecapFactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(color: Color(0xFFB8C0C0), fontSize: 12),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFF5F7F7),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

String listeningRecapLabel(LibraryListeningRecap recap) {
  switch (recap.period) {
    case LibraryRecapPeriod.month:
      return '${_monthName(recap.start.month)} ${recap.start.year}';
    case LibraryRecapPeriod.year:
      return recap.start.year.toString();
  }
}

String listeningRecapPngFileName(LibraryListeningRecap recap) {
  switch (recap.period) {
    case LibraryRecapPeriod.month:
      return 'aethertune-recap-${recap.start.year}-'
          '${recap.start.month.toString().padLeft(2, '0')}.png';
    case LibraryRecapPeriod.year:
      return 'aethertune-recap-${recap.start.year}.png';
  }
}

String formatListeningRecapDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return minutes == 0 ? '$hours hr' : '$hours hr $minutes min';
  }
  return '${duration.inMinutes} min';
}

Future<Uint8List> captureListeningRecapPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 3,
}) async {
  if (pixelRatio <= 0) {
    throw ArgumentError.value(pixelRatio, 'pixelRatio', 'Must be positive.');
  }

  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is RenderRepaintBoundary && renderObject.debugNeedsPaint) {
    throw StateError('The listening recap card has not been painted yet.');
  }
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('The listening recap card is not ready to capture.');
  }

  final image = await renderObject.toImage(pixelRatio: pixelRatio);
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Flutter could not encode the listening recap PNG.');
    }
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}

String _monthName(int month) {
  const names = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}
