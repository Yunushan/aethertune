import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/track.dart';
import '../../player/offline_playback_policy.dart';
import '../../player/player_controller.dart';
import 'track_artwork.dart';

class DesktopQueuePaneResizeHandle extends StatelessWidget {
  const DesktopQueuePaneResizeHandle({
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        key: const Key('desktop-queue-pane-resize'),
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDragUpdate(details.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        child: const SizedBox(
          width: 12,
          child: Center(child: VerticalDivider(width: 1)),
        ),
      ),
    );
  }
}

class DesktopQueuePane extends StatelessWidget {
  const DesktopQueuePane({
    required this.onOpenNowPlaying,
    required this.onOpenQueue,
    super.key,
  });

  final VoidCallback onOpenNowPlaying;
  final VoidCallback onOpenQueue;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final current = player.current;
    final queue = player.queue;

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.queue_music,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Queue',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Open queue editor',
                  onPressed: queue.isEmpty ? null : onOpenQueue,
                  icon: const Icon(Icons.open_in_full),
                ),
              ],
            ),
          ),
          if (current != null)
            _CurrentQueueTrack(
              track: current,
              isPlaying: player.isPlaying,
              onOpenNowPlaying: onOpenNowPlaying,
              onTogglePlayPause: () => _runPlaybackAction(
                context,
                player.togglePlayPause,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nothing is playing.'),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${queue.length} track${queue.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          Expanded(
            child: queue.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Queue tracks appear here.'),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    itemCount: queue.length,
                    onReorderItem: (oldIndex, newIndex) {
                      player.moveTrackInQueue(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final track = queue[index];
                      final isCurrent = current?.id == track.id;
                      return _QueueTrackTile(
                        key: ValueKey<String>(track.id),
                        track: track,
                        isCurrent: isCurrent,
                        index: index,
                        onPlay: () => _runPlaybackAction(
                          context,
                          () => player.playTrack(track),
                        ),
                        onRemove: isCurrent
                            ? null
                            : () => player.removeTrackFromQueue(track.id),
                      );
                    },
                  ),
          ),
        ],
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

class _CurrentQueueTrack extends StatelessWidget {
  const _CurrentQueueTrack({
    required this.track,
    required this.isPlaying,
    required this.onOpenNowPlaying,
    required this.onTogglePlayPause,
  });

  final Track track;
  final bool isPlaying;
  final VoidCallback onOpenNowPlaying;
  final Future<void> Function() onTogglePlayPause;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: TrackArtwork(
        artworkUri: track.artworkUri,
        providerId: track.sourceId,
        providerArtworkId: track.providerArtworkId,
        providerArtworkVersion: track.providerArtworkVersion,
        size: 48,
        borderRadius: 6,
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onOpenNowPlaying,
      trailing: IconButton.filledTonal(
        tooltip: isPlaying ? 'Pause' : 'Play',
        onPressed: onTogglePlayPause,
        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}

class _QueueTrackTile extends StatelessWidget {
  const _QueueTrackTile({
    required super.key,
    required this.track,
    required this.isCurrent,
    required this.index,
    required this.onPlay,
    required this.onRemove,
  });

  final Track track;
  final bool isCurrent;
  final int index;
  final VoidCallback onPlay;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      selected: isCurrent,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: TrackArtwork(
        artworkUri: track.artworkUri,
        providerId: track.sourceId,
        providerArtworkId: track.providerArtworkId,
        providerArtworkVersion: track.providerArtworkVersion,
        size: 40,
        borderRadius: 4,
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onPlay,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: 'Remove from queue',
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }
}
