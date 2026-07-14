import 'package:flutter/material.dart';

import '../../domain/playlist.dart';
import '../../domain/track.dart';
import 'track_artwork.dart';

class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    required this.playlist,
    this.tracks = const <Track>[],
    this.size = 40,
    super.key,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final double size;

  @override
  Widget build(BuildContext context) {
    final artworkUri = playlist.artworkUri;
    if (artworkUri != null) {
      return TrackArtwork(
        artworkUri: artworkUri,
        artworkCrop: playlist.artworkCrop,
        size: size,
        borderRadius: 10,
        fallbackIcon: Icons.queue_music,
      );
    }

    if (tracks.isNotEmpty) {
      return _GeneratedPlaylistArtwork(
        playlist: playlist,
        tracks: tracks,
        size: size,
      );
    }

    return _PlaylistArtworkFallback(size: size);
  }
}

class _GeneratedPlaylistArtwork extends StatelessWidget {
  const _GeneratedPlaylistArtwork({
    required this.playlist,
    required this.tracks,
    required this.size,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final double size;

  @override
  Widget build(BuildContext context) {
    final selectedTracks = tracks.take(4).toList(growable: false);
    if (selectedTracks.length == 1) {
      return Semantics(
        label: 'Generated artwork for ${playlist.name}',
        image: true,
        child: TrackArtwork(
          key: Key('playlist-artwork-collage-${playlist.id}'),
          artworkUri: selectedTracks.single.artworkUri,
          providerId: selectedTracks.single.sourceId,
          providerArtworkId: selectedTracks.single.providerArtworkId,
          providerArtworkVersion: selectedTracks.single.providerArtworkVersion,
          size: size,
          borderRadius: 10,
          fallbackIcon: Icons.queue_music,
        ),
      );
    }

    final tileSize = size / 2;
    return Semantics(
      label: 'Generated artwork collage for ${playlist.name}',
      image: true,
      child: SizedBox.square(
        key: Key('playlist-artwork-collage-${playlist.id}'),
        dimension: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
            ),
            itemCount: 4,
            itemBuilder: (context, index) {
              if (index >= selectedTracks.length) {
                return _PlaylistArtworkFallback(size: tileSize);
              }
              final track = selectedTracks[index];
              return TrackArtwork(
                artworkUri: track.artworkUri,
                providerId: track.sourceId,
                providerArtworkId: track.providerArtworkId,
                providerArtworkVersion: track.providerArtworkVersion,
                size: tileSize,
                borderRadius: 0,
                fallbackIcon: Icons.queue_music,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PlaylistArtworkFallback extends StatelessWidget {
  const _PlaylistArtworkFallback({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.queue_music,
        color: colorScheme.onSecondaryContainer,
        size: size * 0.55,
      ),
    );
  }
}
