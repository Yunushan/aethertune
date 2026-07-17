import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/track.dart';
import '../../player/offline_playback_policy.dart';
import '../../player/player_controller.dart';
import 'track_artwork.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({
    required this.track,
    required this.onPlay,
    this.detailText,
    this.onStartRadio,
    this.onSimilarTracks,
    this.onShare,
    required this.onFavorite,
    required this.onAddToPlaylist,
    required this.onLyrics,
    required this.onEditMetadata,
    this.onEditArtwork,
    required this.onRemove,
    super.key,
  });

  final Track track;
  final VoidCallback onPlay;
  final String? detailText;
  final VoidCallback? onStartRadio;
  final VoidCallback? onSimilarTracks;
  final VoidCallback? onShare;
  final VoidCallback onFavorite;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onLyrics;
  final VoidCallback onEditMetadata;
  final VoidCallback? onEditArtwork;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final baseSubtitle = '${track.artist} · ${track.album} · ${track.genre}';
    final detail = detailText?.trim();
    final subtitle = detail == null || detail.isEmpty
        ? baseSubtitle
        : '$baseSubtitle\n$detail';

    return ListTile(
      leading: TrackArtwork(
        artworkUri: track.artworkUri,
        providerId: track.sourceId,
        providerArtworkId: track.providerArtworkId,
        providerArtworkVersion: track.providerArtworkVersion,
        borderRadius: 22,
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        maxLines: detail == null || detail.isEmpty ? 1 : 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onPlay,
      trailing: PopupMenuButton<_TrackAction>(
        onSelected: (action) {
          switch (action) {
            case _TrackAction.play:
              onPlay();
              break;
            case _TrackAction.startRadio:
              onStartRadio?.call();
              break;
            case _TrackAction.similarTracks:
              onSimilarTracks?.call();
              break;
            case _TrackAction.share:
              onShare?.call();
              break;
            case _TrackAction.playNext:
              unawaited(_enqueue(context, playNext: true));
              break;
            case _TrackAction.addToQueue:
              unawaited(_enqueue(context));
              break;
            case _TrackAction.favorite:
              onFavorite();
              break;
            case _TrackAction.addToPlaylist:
              onAddToPlaylist();
              break;
            case _TrackAction.lyrics:
              onLyrics();
              break;
            case _TrackAction.editMetadata:
              onEditMetadata();
              break;
            case _TrackAction.editArtwork:
              onEditArtwork?.call();
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
          if (onStartRadio != null)
            const PopupMenuItem(
              value: _TrackAction.startRadio,
              child: ListTile(
                leading: Icon(Icons.radio_outlined),
                title: Text('Start radio'),
              ),
            ),
          if (onSimilarTracks != null)
            const PopupMenuItem(
              value: _TrackAction.similarTracks,
              child: ListTile(
                leading: Icon(Icons.hub_outlined),
                title: Text('Similar tracks'),
              ),
            ),
          if (onShare != null)
            const PopupMenuItem(
              value: _TrackAction.share,
              child: ListTile(
                leading: Icon(Icons.ios_share),
                title: Text('Copy share text'),
              ),
            ),
          const PopupMenuItem(
            value: _TrackAction.playNext,
            child: ListTile(
              leading: Icon(Icons.queue_play_next),
              title: Text('Play next'),
            ),
          ),
          const PopupMenuItem(
            value: _TrackAction.addToQueue,
            child: ListTile(
              leading: Icon(Icons.playlist_add),
              title: Text('Add to queue'),
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
            value: _TrackAction.addToPlaylist,
            child: ListTile(
              leading: Icon(Icons.playlist_add),
              title: Text('Add to playlist'),
            ),
          ),
          const PopupMenuItem(
            value: _TrackAction.lyrics,
            child: ListTile(
              leading: Icon(Icons.lyrics_outlined),
              title: Text('Lyrics'),
            ),
          ),
          const PopupMenuItem(
            value: _TrackAction.editMetadata,
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit metadata'),
            ),
          ),
          if (onEditArtwork != null)
            const PopupMenuItem(
              value: _TrackAction.editArtwork,
              child: ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Artwork'),
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

  Future<void> _enqueue(
    BuildContext context, {
    bool playNext = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PlayerController>().enqueueTrack(
        track,
        playNext: playNext,
      );
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            playNext
                ? '${track.title} will play next.'
                : 'Added ${track.title} to the queue.',
          ),
        ),
      );
    } on OfflinePlaybackBlockedException catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(offlinePlaybackBlockedMessage(error.track))),
        );
      }
    } on Object {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not update the queue.')),
        );
      }
    }
  }
}

enum _TrackAction {
  play,
  startRadio,
  similarTracks,
  share,
  playNext,
  addToQueue,
  favorite,
  addToPlaylist,
  lyrics,
  editMetadata,
  editArtwork,
  remove,
}
