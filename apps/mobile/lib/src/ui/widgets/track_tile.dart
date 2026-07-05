import 'package:flutter/material.dart';

import '../../domain/track.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.track,
    required this.onPlay,
    required this.onFavorite,
    required this.onRemove,
    super.key,
  });

  final Track track;
  final VoidCallback onPlay;
  final VoidCallback onFavorite;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.music_note)),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${track.artist} · ${track.album}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onPlay,
      trailing: PopupMenuButton<_TrackAction>(
        onSelected: (action) {
          switch (action) {
            case _TrackAction.play:
              onPlay();
              break;
            case _TrackAction.favorite:
              onFavorite();
              break;
            case _TrackAction.remove:
              onRemove();
              break;
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<_TrackAction>>[
          const PopupMenuItem(
            value: _TrackAction.play,
            child: ListTile(
              leading: Icon(Icons.play_arrow),
              title: Text('Play'),
            ),
          ),
          PopupMenuItem(
            value: _TrackAction.favorite,
            child: ListTile(
              leading: Icon(
                track.isFavorite ? Icons.favorite : Icons.favorite_border,
              ),
              title: Text(track.isFavorite ? 'Unfavorite' : 'Favorite'),
            ),
          ),
          const PopupMenuItem(
            value: _TrackAction.remove,
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Remove from library'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TrackAction { play, favorite, remove }
