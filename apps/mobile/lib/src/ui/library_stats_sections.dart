import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../domain/playback_history_entry.dart';
import '../domain/track.dart';
import 'library_stats_charts.dart';
import 'widgets/listening_recap_card.dart';

class LibraryStatsOverview extends StatelessWidget {
  const LibraryStatsOverview({super.key, required this.stats});

  final LibraryStatsSummary stats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _StatsMetricTile(
          icon: Icons.library_music_outlined,
          label: 'Tracks',
          value: stats.trackCount.toString(),
        ),
        _StatsMetricTile(
          icon: Icons.favorite_border,
          label: 'Favorites',
          value: stats.favoriteTrackCount.toString(),
        ),
        _StatsMetricTile(
          icon: Icons.play_circle_outline,
          label: 'Plays',
          value: stats.playbackCount.toString(),
        ),
        _StatsMetricTile(
          icon: Icons.schedule,
          label: 'Listening',
          value: formatLibraryStatsDuration(stats.estimatedListeningDuration),
        ),
      ],
    );
  }
}

class _StatsMetricTile extends StatelessWidget {
  const _StatsMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(value, style: Theme.of(context).textTheme.titleMedium),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LibraryStatsTrackSection extends StatelessWidget {
  const LibraryStatsTrackSection({super.key, required this.stats});

  final LibraryStatsSummary stats;

  @override
  Widget build(BuildContext context) {
    return LibraryStatsSection(
      title: 'Top tracks',
      children: <Widget>[
        for (final trackStats in stats.topTracks)
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(trackStats.track.title),
            subtitle: Text(
              '${trackStats.track.artist} · '
              '${trackStats.playCount} play(s) · '
              '${formatLibraryStatsDuration(trackStats.estimatedListeningDuration)}',
            ),
            trailing: Text(formatLibraryHistoryTime(trackStats.lastPlayedAt)),
          ),
      ],
    );
  }
}

class LibraryStatsGroupSection extends StatelessWidget {
  const LibraryStatsGroupSection({
    super.key,
    required this.title,
    required this.icon,
    required this.groups,
  });

  final String title;
  final IconData icon;
  final List<LibraryStatsGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return LibraryStatsSection(
      title: title,
      children: <Widget>[
        for (final group in groups)
          ListTile(
            leading: Icon(icon),
            title: Text(group.label),
            subtitle: Text(
              '${group.playCount} play(s) · '
              '${group.trackCount} track(s) · '
              '${formatLibraryStatsDuration(group.estimatedListeningDuration)}',
            ),
            trailing: Text(formatLibraryHistoryTime(group.lastPlayedAt)),
          ),
      ],
    );
  }
}

class ListeningRecapSection extends StatelessWidget {
  const ListeningRecapSection({
    super.key,
    required this.title,
    required this.icon,
    required this.recaps,
    required this.onShare,
  });

  final String title;
  final IconData icon;
  final List<LibraryListeningRecap> recaps;
  final ValueChanged<LibraryListeningRecap> onShare;

  @override
  Widget build(BuildContext context) {
    if (recaps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final recap in recaps)
              SizedBox(
                width: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(icon),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                listeningRecapLabel(recap),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              key: ValueKey<String>(
                                'listening-recap-preview-'
                                '${recap.period.name}-'
                                '${recap.start.year}-'
                                '${recap.start.month}',
                              ),
                              tooltip: 'Save recap image',
                              onPressed: () => onShare(recap),
                              icon: const Icon(Icons.image_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _listeningRecapSummary(recap.stats),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${recap.stats.uniquePlayedTrackCount} track(s)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _listeningRecapSummary(LibraryStatsSummary stats) {
  final parts = <String>[
    '${stats.playbackCount} play(s)',
    formatLibraryStatsDuration(stats.estimatedListeningDuration),
  ];
  if (stats.topTracks.isNotEmpty) {
    parts.add('Top track: ${stats.topTracks.first.track.title}');
  } else if (stats.topArtists.isNotEmpty) {
    parts.add('Top artist: ${stats.topArtists.first.label}');
  }

  return parts.join(' · ');
}

class LibraryStatsSection extends StatelessWidget {
  const LibraryStatsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Card(child: Column(children: children)),
      ],
    );
  }
}

class PlaybackHistoryEntrySection extends StatelessWidget {
  const PlaybackHistoryEntrySection({
    super.key,
    required this.entries,
    required this.tracksById,
    required this.onPlay,
    required this.onRemove,
  });

  final List<PlaybackHistoryEntry> entries;
  final Map<String, Track> tracksById;
  final ValueChanged<Track> onPlay;
  final ValueChanged<PlaybackHistoryEntry> onRemove;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (final entry in entries) {
      final track = tracksById[entry.trackId];
      if (track == null) {
        continue;
      }

      tiles.add(
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(track.title),
          subtitle: Text(
            '${track.artist} · ${formatLibraryHistoryTime(entry.playedAt)}',
          ),
          trailing: IconButton(
            tooltip: 'Remove this play',
            onPressed: () => onRemove(entry),
            icon: const Icon(Icons.close),
          ),
          onTap: () => onPlay(track),
        ),
      );
    }

    return LibraryStatsSection(title: 'Play history entries', children: tiles);
  }
}

String formatLibraryHistoryTime(DateTime? value) {
  if (value == null) {
    return '';
  }

  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
