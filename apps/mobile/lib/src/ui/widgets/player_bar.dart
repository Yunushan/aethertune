import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../player/offline_playback_policy.dart';
import '../../player/player_controller.dart';

class PlayerBar extends StatelessWidget {
  const PlayerBar({
    required this.onOpenQueue,
    required this.onSaveQueue,
    required this.onOpenLyrics,
    super.key,
  });

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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  const CircleAvatar(child: Icon(Icons.music_note)),
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
                    onPressed: () => _runPlaybackAction(
                      context,
                      player.previous,
                    ),
                    icon: const Icon(Icons.skip_previous),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _runPlaybackAction(
                      context,
                      player.togglePlayPause,
                    ),
                    icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(player.isPlaying ? 'Pause' : 'Play'),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: () => _runPlaybackAction(
                      context,
                      player.next,
                    ),
                    icon: const Icon(Icons.skip_next),
                  ),
                ],
              ),
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
