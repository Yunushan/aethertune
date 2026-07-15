import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/library_store.dart';

const double listeningRecapCardWidth = 360;
const double listeningRecapCardHeight = 450;

class ListeningRecapThemePicker extends StatelessWidget {
  const ListeningRecapThemePicker({
    super.key,
    required this.selectedTheme,
    required this.onChanged,
  });

  final ListeningRecapVisualTheme selectedTheme;
  final ValueChanged<ListeningRecapVisualTheme> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final theme in ListeningRecapVisualTheme.values)
          ChoiceChip(
            key: ValueKey<String>('listening-recap-theme-${theme.name}'),
            selected: selectedTheme == theme,
            onSelected: (selected) {
              if (selected) {
                onChanged(theme);
              }
            },
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (final color in listeningRecapThemeSwatch(theme))
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 3),
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                const SizedBox(width: 3),
                Text(theme.label),
              ],
            ),
          ),
      ],
    );
  }
}

class ListeningRecapCard extends StatelessWidget {
  const ListeningRecapCard({
    super.key,
    required this.recap,
    this.visualTheme = ListeningRecapVisualTheme.midnight,
  });

  final LibraryListeningRecap recap;
  final ListeningRecapVisualTheme visualTheme;

  @override
  Widget build(BuildContext context) {
    final palette = _listeningRecapPalette(visualTheme);
    final stats = recap.stats;
    final topTrack = stats.topTracks.isEmpty ? null : stats.topTracks.first;
    final topArtist = stats.topArtists.isEmpty ? null : stats.topArtists.first;
    final topAlbum = stats.topAlbums.isEmpty ? null : stats.topAlbums.first;
    final topGenre = stats.topGenres.isEmpty ? null : stats.topGenres.first;

    return SizedBox(
      width: listeningRecapCardWidth,
      height: listeningRecapCardHeight,
      child: DecoratedBox(
        key: ValueKey<String>('listening-recap-card-${visualTheme.name}'),
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DefaultTextStyle(
            style: TextStyle(color: palette.foreground),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.primary,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(6),
                        ),
                      ),
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Icon(
                          Icons.graphic_eq,
                          color: palette.background,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'AetherTune',
                            style: TextStyle(
                              color: palette.foreground,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Listening recap',
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                            ),
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
                  style: TextStyle(
                    color: palette.secondary,
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
                  style: TextStyle(
                    color: palette.foreground,
                    fontSize: 38,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'listening time',
                  style: TextStyle(color: palette.muted, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: palette.surface,
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: _RecapMetric(
                          value: '${stats.playbackCount}',
                          label: 'plays',
                          color: palette.primary,
                          labelColor: palette.muted,
                        ),
                      ),
                      SizedBox(
                        height: 34,
                        child: VerticalDivider(
                          width: 1,
                          color: palette.divider,
                        ),
                      ),
                      Expanded(
                        child: _RecapMetric(
                          value: '${stats.uniquePlayedTrackCount}',
                          label: 'tracks',
                          color: palette.tertiary,
                          labelColor: palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'MOST PLAYED',
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.music_note,
                      color: palette.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            topTrack?.track.title ?? 'No top track yet',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: palette.foreground,
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
                            style: TextStyle(
                              color: palette.muted,
                              fontSize: 12,
                            ),
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
                  color: palette.secondary,
                  labelColor: palette.muted,
                  valueColor: palette.foreground,
                ),
                const SizedBox(height: 8),
                _RecapFactRow(
                  icon: Icons.album_outlined,
                  label: topAlbum == null ? 'Top genre' : 'Top album',
                  value: topAlbum?.label ?? topGenre?.label ?? 'Not enough data',
                  color: palette.tertiary,
                  labelColor: palette.muted,
                  valueColor: palette.foreground,
                ),
                const SizedBox(height: 18),
                Text(
                  'Private, local listening history',
                  style: TextStyle(color: palette.muted, fontSize: 11),
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
    required this.labelColor,
  });

  final String value;
  final String label;
  final Color color;
  final Color labelColor;

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
          style: TextStyle(color: labelColor, fontSize: 11),
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
    required this.labelColor,
    required this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color labelColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(color: labelColor, fontSize: 12),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

List<Color> listeningRecapThemeSwatch(ListeningRecapVisualTheme theme) {
  final palette = _listeningRecapPalette(theme);
  return <Color>[palette.primary, palette.secondary, palette.tertiary];
}

_ListeningRecapPalette _listeningRecapPalette(
  ListeningRecapVisualTheme theme,
) {
  switch (theme) {
    case ListeningRecapVisualTheme.midnight:
      return const _ListeningRecapPalette(
        background: Color(0xFF111315),
        surface: Color(0xFF202427),
        primary: Color(0xFF56D8C5),
        secondary: Color(0xFFF1BC59),
        tertiary: Color(0xFFE9748F),
        foreground: Color(0xFFF5F7F7),
        muted: Color(0xFFB8C0C0),
        divider: Color(0xFF465052),
        border: Color(0xFF353B3D),
      );
    case ListeningRecapVisualTheme.daylight:
      return const _ListeningRecapPalette(
        background: Color(0xFFF4F7FA),
        surface: Color(0xFFFFFFFF),
        primary: Color(0xFF006B5F),
        secondary: Color(0xFF8B1E3F),
        tertiary: Color(0xFF1D4ED8),
        foreground: Color(0xFF172126),
        muted: Color(0xFF4B5A61),
        divider: Color(0xFFC3CDD2),
        border: Color(0xFFAEBBC2),
      );
    case ListeningRecapVisualTheme.signal:
      return const _ListeningRecapPalette(
        background: Color(0xFF101214),
        surface: Color(0xFF24282B),
        primary: Color(0xFFFFD600),
        secondary: Color(0xFF62A8FF),
        tertiary: Color(0xFFFF7A85),
        foreground: Color(0xFFF8FAFB),
        muted: Color(0xFFC1C7CA),
        divider: Color(0xFF51595E),
        border: Color(0xFF3B4246),
      );
    case ListeningRecapVisualTheme.monochrome:
      return const _ListeningRecapPalette(
        background: Color(0xFFF7F8F9),
        surface: Color(0xFFE2E5E7),
        primary: Color(0xFF111315),
        secondary: Color(0xFF34393D),
        tertiary: Color(0xFF656C70),
        foreground: Color(0xFF111315),
        muted: Color(0xFF4D555A),
        divider: Color(0xFFA8AFB3),
        border: Color(0xFF24282C),
      );
  }
}

class _ListeningRecapPalette {
  const _ListeningRecapPalette({
    required this.background,
    required this.surface,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.foreground,
    required this.muted,
    required this.divider,
    required this.border,
  });

  final Color background;
  final Color surface;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color foreground;
  final Color muted;
  final Color divider;
  final Color border;
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
