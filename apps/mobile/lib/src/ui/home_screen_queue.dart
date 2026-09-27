part of 'home_screen.dart';

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    final current = player.current;
    final savedQueues = player.savedQueues;
    final currentIndex = current == null
        ? -1
        : queue.indexWhere((track) => track.id == current.id);
    final hasUpcomingTracks =
        currentIndex >= 0 && currentIndex < queue.length - 1;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Queues'),
            subtitle: Text(
              '${savedQueues.length} saved · ${player.activeQueueName} active',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'Create queue',
                  onPressed: () => unawaited(_createQueue(context, player)),
                  icon: const Icon(Icons.playlist_add_outlined),
                ),
                PopupMenuButton<_SavedQueueAction>(
                  tooltip: 'Manage active queue',
                  onSelected: (action) =>
                      unawaited(_manageQueue(context, player, action)),
                  itemBuilder: (_) => <PopupMenuEntry<_SavedQueueAction>>[
                    const PopupMenuItem(
                      value: _SavedQueueAction.rename,
                      child: ListTile(
                        leading: Icon(Icons.drive_file_rename_outline),
                        title: Text('Rename queue'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _SavedQueueAction.delete,
                      enabled: savedQueues.length > 1,
                      child: const ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete queue'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _SavedQueueAction.clearUpcoming,
                      enabled: hasUpcomingTracks,
                      child: const ListTile(
                        leading: Icon(Icons.playlist_remove),
                        title: Text('Clear upcoming tracks'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _SavedQueueAction.clear,
                      enabled: queue.isNotEmpty,
                      child: const ListTile(
                        leading: Icon(Icons.delete_sweep_outlined),
                        title: Text('Clear queue'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          for (final savedQueue in savedQueues)
            ListTile(
              selected: savedQueue.id == player.activeQueueId,
              leading: Icon(
                savedQueue.id == player.activeQueueId
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(savedQueue.name),
              subtitle: Text('${savedQueue.snapshot.tracks.length} track(s)'),
              onTap: savedQueue.id == player.activeQueueId
                  ? null
                  : () => unawaited(player.switchSavedQueue(savedQueue.id)),
            ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: Text(player.activeQueueName),
            subtitle: Text('${queue.length} track(s)'),
          ),
          if (queue.isEmpty)
            const ListTile(
              leading: Icon(Icons.queue_music_outlined),
              title: Text('Queue is empty'),
              subtitle: Text(
                'Play tracks from Library, Playlists, or History.',
              ),
            )
          else
            for (final entry in queue.asMap().entries)
              _QueueTrackTile(
                index: entry.key,
                track: entry.value,
                queueLength: queue.length,
                isCurrent: current?.id == entry.value.id,
              ),
        ],
      ),
    );
  }

  Future<void> _createQueue(
    BuildContext context,
    PlayerController player,
  ) async {
    final name = await _promptForQueueName(context, title: 'Create queue');
    if (!context.mounted || name == null) {
      return;
    }
    final created = await player.createSavedQueue(name);
    if (!context.mounted) {
      return;
    }
    if (created == null) {
      if (player.persistenceError != null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use a unique queue name (up to 80 characters).'),
        ),
      );
      return;
    }
    await player.switchSavedQueue(created.id);
  }

  Future<void> _manageQueue(
    BuildContext context,
    PlayerController player,
    _SavedQueueAction action,
  ) async {
    switch (action) {
      case _SavedQueueAction.rename:
        final name = await _promptForQueueName(
          context,
          title: 'Rename queue',
          initialValue: player.activeQueueName,
        );
        if (!context.mounted || name == null) {
          return;
        }
        final renamed = await player.renameSavedQueue(
          player.activeQueueId,
          name,
        );
        if (context.mounted && !renamed && player.persistenceError == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Use a unique queue name (up to 80 characters).'),
            ),
          );
        }
        return;
      case _SavedQueueAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete queue?'),
            content: Text(
              'Delete ${player.activeQueueName} and its saved tracks?',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await player.deleteSavedQueue(player.activeQueueId);
        }
        return;
      case _SavedQueueAction.clearUpcoming:
      case _SavedQueueAction.clear:
        final upcomingOnly = action == _SavedQueueAction.clearUpcoming;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              upcomingOnly ? 'Clear upcoming tracks?' : 'Clear queue?',
            ),
            content: Text(
              upcomingOnly
                  ? 'The current track will keep playing.'
                  : 'This stops playback and removes every track from ${player.activeQueueName}.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) {
          return;
        }
        if (upcomingOnly) {
          await player.clearUpcomingTracks();
        } else {
          await player.clearActiveQueue();
        }
        return;
    }
  }

  Future<String?> _promptForQueueName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            autofocus: true,
            controller: controller,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Queue name'),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }
}

class _QueueTrackTile extends StatelessWidget {
  const _QueueTrackTile({
    required this.index,
    required this.track,
    required this.queueLength,
    required this.isCurrent,
  });

  final int index;
  final Track track;
  final int queueLength;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerController>();

    return ListTile(
      leading: Icon(isCurrent ? Icons.graphic_eq : Icons.music_note_outlined),
      title: Text(track.title),
      subtitle: Text(
        isCurrent
            ? '${track.artist} · Now playing'
            : '${track.artist} · ${track.album}',
      ),
      trailing: PopupMenuButton<_QueueTrackAction>(
        onSelected: (action) {
          switch (action) {
            case _QueueTrackAction.moveUp:
              player.moveTrackInQueue(index, index - 1);
              break;
            case _QueueTrackAction.moveDown:
              player.moveTrackInQueue(index, index + 1);
              break;
            case _QueueTrackAction.remove:
              player.removeTrackFromQueue(track.id);
              break;
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<_QueueTrackAction>>[
          PopupMenuItem(
            value: _QueueTrackAction.moveUp,
            enabled: index > 0,
            child: const ListTile(
              leading: Icon(Icons.arrow_upward),
              title: Text('Move up'),
            ),
          ),
          PopupMenuItem(
            value: _QueueTrackAction.moveDown,
            enabled: index < queueLength - 1,
            child: const ListTile(
              leading: Icon(Icons.arrow_downward),
              title: Text('Move down'),
            ),
          ),
          PopupMenuItem(
            value: _QueueTrackAction.remove,
            enabled: !isCurrent,
            child: const ListTile(
              leading: Icon(Icons.playlist_remove),
              title: Text('Remove from queue'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _QueueTrackAction { moveUp, moveDown, remove }

enum _SavedQueueAction { rename, delete, clearUpcoming, clear }
