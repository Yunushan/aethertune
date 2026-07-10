import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../player/offline_playback_policy.dart';
import '../../player/player_controller.dart';
import 'track_artwork.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({
    required this.onOpenNowPlaying,
    required this.onOpenQueue,
    required this.onSaveQueue,
    required this.onOpenLyrics,
    super.key,
  });

  final VoidCallback onOpenNowPlaying;
  final VoidCallback onOpenQueue;
  final VoidCallback onSaveQueue;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final current = player.current;

    if (current == null) {
      return Material(
        elevation: 3,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                const Icon(Icons.music_note_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No track playing. Import local audio to start.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            StreamBuilder<Duration>(
              stream: player.positionStream,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = player.duration;
                final max = duration.inMilliseconds <= 0
                    ? 1.0
                    : duration.inMilliseconds.toDouble();
                final value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();

                return Slider(
                  value: value,
                  max: max,
                  onChanged: (value) {
                    player.seek(Duration(milliseconds: value.round()));
                  },
                );
              },
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Tooltip(
                          message: 'Open now playing',
                          child: Semantics(
                            button: true,
                            label: 'Open now playing for ${current.title}',
                            child: InkWell(
                              key: const Key('open-now-playing'),
                              borderRadius: BorderRadius.circular(4),
                              onTap: onOpenNowPlaying,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: <Widget>[
                                    TrackArtwork(
                                      artworkUri: current.artworkUri,
                                      size: 40,
                                      borderRadius: 8,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Text(
                                            current.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                          Text(
                                            current.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!compact) ...<Widget>[
                        IconButton(
                          tooltip: 'Lyrics',
                          onPressed: onOpenLyrics,
                          icon: const Icon(Icons.subtitles_outlined),
                        ),
                        IconButton(
                          tooltip: 'Edit queue',
                          onPressed: player.queue.isEmpty ? null : onOpenQueue,
                          icon: const Icon(Icons.queue_music),
                        ),
                        IconButton(
                          tooltip: 'Save queue as playlist',
                          onPressed: player.queue.isEmpty ? null : onSaveQueue,
                          icon: const Icon(Icons.playlist_add),
                        ),
                        IconButton(
                          tooltip: 'Previous',
                          onPressed: () => _runPlaybackAction(context, player.previous),
                          icon: const Icon(Icons.skip_previous),
                        ),
                      ],
                      IconButton.filledTonal(
                        tooltip: player.isPlaying ? 'Pause' : 'Play',
                        onPressed: () => _runPlaybackAction(
                          context,
                          player.togglePlayPause,
                        ),
                        icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow),
                      ),
                      IconButton(
                        tooltip: 'Next',
                        onPressed: () => _runPlaybackAction(context, player.next),
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runPlaybackAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on OfflinePlaybackBlockedException catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(offlinePlaybackBlockedMessage(error.track))),
      );
    }
  }
}
