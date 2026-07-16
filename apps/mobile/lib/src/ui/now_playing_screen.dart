import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../domain/track.dart';
import '../domain/track_chapter.dart';
import '../player/offline_playback_policy.dart';
import '../player/player_controller.dart';
import 'widgets/artwork_palette_backdrop.dart';
import 'widgets/track_artwork.dart';
import 'widgets/track_share_card.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({
    required this.onOpenQueue,
    required this.onOpenLyrics,
    super.key,
  });

  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  static const _swipeThreshold = 48.0;
  double _horizontalDragDistance = 0;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final library = context.watch<LibraryStore>();
    final current = player.current;
    final savedCurrent = current == null
        ? null
        : _findTrack(library.tracks, current.id);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now playing'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Save track share card',
            onPressed: current == null ? null : () => _showTrackShareCard(current),
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: 'Lyrics',
            onPressed: current == null ? null : widget.onOpenLyrics,
            icon: const Icon(Icons.subtitles_outlined),
          ),
          IconButton(
            tooltip: 'Queue',
            onPressed: player.queue.isEmpty ? null : widget.onOpenQueue,
            icon: const Icon(Icons.queue_music),
          ),
          if (savedCurrent != null)
            IconButton(
              key: const Key('now-playing-chapters-editor'),
              tooltip: 'Edit chapters',
              onPressed: () => _showTrackChaptersEditor(savedCurrent),
              icon: const Icon(Icons.format_list_numbered),
            ),
          if (current != null)
            _TrackPlaybackSpeedMenu(
              player: player,
              library: library,
              track: current,
            ),
          _PlaybackSpeedMenu(
            player: player,
            trackPlaybackSpeedOverride: current == null
                ? null
                : library.playbackSpeedForTrack(current.id),
          ),
          if (player.supportsPitch) _PlaybackPitchMenu(player: player),
        ],
      ),
      body: current == null
          ? const Center(child: Text('No track is currently selected.'))
          : ArtworkPaletteBackdrop(
              artworkUri: current.artworkUri,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final savedTrack = _findTrack(library.tracks, current.id);
                  final currentQueueIndex = player.queue.indexWhere(
                    (track) => track.id == current.id,
                  );
                  final content = _NowPlayingContent(
                    track: current,
                    isFavorite: savedTrack?.isFavorite ?? false,
                    canFavorite: savedTrack != null,
                    player: player,
                    chapters: savedTrack?.chapters ?? current.chapters,
                    onToggleFavorite: savedTrack == null
                        ? null
                        : () => library.toggleFavorite(current.id),
                    onOpenQueue: widget.onOpenQueue,
                    onOpenLyrics: widget.onOpenLyrics,
                    onHorizontalDragStart: () => _horizontalDragDistance = 0,
                    onHorizontalDragUpdate: (delta) {
                      _horizontalDragDistance += delta;
                    },
                    onHorizontalDragEnd: () => _finishArtworkSwipe(player),
                    onArtworkPrevious: currentQueueIndex > 0
                        ? () => _runPlaybackAction(player.previous)
                        : null,
                    onArtworkNext: currentQueueIndex >= 0 &&
                            currentQueueIndex < player.queue.length - 1
                        ? () => _runPlaybackAction(player.next)
                        : null,
                  );

                  if (constraints.maxWidth >= 900) {
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Expanded(child: content.artwork),
                              const SizedBox(width: 56),
                              Expanded(child: content.controls),
                            ],
                          ),
                        ),
                      ),
                    );
                  }

                  return SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                      child: Column(
                        children: <Widget>[
                          content.artwork,
                          const SizedBox(height: 28),
                          content.controls,
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  void _finishArtworkSwipe(PlayerController player) {
    final distance = _horizontalDragDistance;
    _horizontalDragDistance = 0;
    if (distance <= -_swipeThreshold) {
      _runPlaybackAction(player.next);
    } else if (distance >= _swipeThreshold) {
      _runPlaybackAction(player.previous);
    }
  }

  Future<void> _runPlaybackAction(Future<void> Function() action) async {
    try {
      await action();
    } on OfflinePlaybackBlockedException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(offlinePlaybackBlockedMessage(error.track))),
      );
    }
  }

  Future<void> _showTrackShareCard(Track track) async {
    final boundaryKey = GlobalKey();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Track share card'),
        content: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: RepaintBoundary(
            key: boundaryKey,
            child: TrackShareCard(track: track),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () => _saveTrackShareCard(dialogContext, boundaryKey, track),
            icon: const Icon(Icons.image_outlined),
            label: const Text('Save PNG'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveTrackShareCard(BuildContext context, GlobalKey boundaryKey, Track track) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await captureTrackShareCardPng(boundaryKey);
      final fileName = 'aethertune-track-${track.id}.png';
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save track share card',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['png'],
        bytes: bytes,
      );
      if (outputPath == null || outputPath.isEmpty) return;
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
      }
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('Saved $fileName.')));
    } on Object catch (error) {
      if (context.mounted) messenger.showSnackBar(SnackBar(content: Text('Could not save track share card: $error')));
    }
  }

  Future<void> _showTrackChaptersEditor(Track track) async {
    final chapters = await _promptForTrackChapters(context, track);
    if (!mounted || chapters == null) {
      return;
    }

    final updated = await context.read<LibraryStore>().updateTrackChapters(
      track.id,
      chapters,
    );
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated == null
              ? 'Track is no longer in the library.'
              : 'Saved ${updated.chapters.length} chapter(s).',
        ),
      ),
    );
  }
}

class _NowPlayingContent {
  _NowPlayingContent({
    required Track track,
    required bool isFavorite,
    required bool canFavorite,
    required PlayerController player,
    required List<TrackChapter> chapters,
    required Future<void> Function()? onToggleFavorite,
    required VoidCallback onOpenQueue,
    required VoidCallback onOpenLyrics,
    required VoidCallback onHorizontalDragStart,
    required ValueChanged<double> onHorizontalDragUpdate,
    required VoidCallback onHorizontalDragEnd,
    required VoidCallback? onArtworkPrevious,
    required VoidCallback? onArtworkNext,
  })  : artwork = _NowPlayingArtwork(
          track: track,
          onHorizontalDragStart: onHorizontalDragStart,
          onHorizontalDragUpdate: onHorizontalDragUpdate,
          onHorizontalDragEnd: onHorizontalDragEnd,
          onPrevious: onArtworkPrevious,
          onNext: onArtworkNext,
        ),
        controls = _NowPlayingControls(
          track: track,
          isFavorite: isFavorite,
          canFavorite: canFavorite,
          player: player,
          chapters: chapters,
          onToggleFavorite: onToggleFavorite,
          onOpenQueue: onOpenQueue,
          onOpenLyrics: onOpenLyrics,
        );

  final Widget artwork;
  final Widget controls;
}

class _NowPlayingArtwork extends StatelessWidget {
  const _NowPlayingArtwork({
    required this.track,
    required this.onHorizontalDragStart,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
    required this.onPrevious,
    required this.onNext,
  });

  final Track track;
  final VoidCallback onHorizontalDragStart;
  final ValueChanged<double> onHorizontalDragUpdate;
  final VoidCallback onHorizontalDragEnd;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 48;
        final size = available.clamp(220.0, 480.0).toDouble();

        return Center(
          child: Semantics(
            key: const Key('now-playing-artwork-semantics'),
            image: true,
            label: 'Artwork for ${track.title}',
            hint: 'Use increase for next track or decrease for previous track.',
            value: 'Current track ${track.title}',
            increasedValue: onNext == null ? null : 'Next track',
            decreasedValue: onPrevious == null ? null : 'Previous track',
            onIncrease: onNext,
            onDecrease: onPrevious,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => onHorizontalDragStart(),
              onHorizontalDragUpdate: (details) {
                onHorizontalDragUpdate(details.primaryDelta ?? 0);
              },
              onHorizontalDragEnd: (_) => onHorizontalDragEnd(),
              child: TrackArtwork(
                key: const Key('now-playing-artwork'),
                artworkUri: track.artworkUri,
                providerId: track.sourceId,
                providerArtworkId: track.providerArtworkId,
                providerArtworkVersion: track.providerArtworkVersion,
                size: size,
                borderRadius: 8,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NowPlayingControls extends StatelessWidget {
  const _NowPlayingControls({
    required this.track,
    required this.isFavorite,
    required this.canFavorite,
    required this.player,
    required this.chapters,
    required this.onToggleFavorite,
    required this.onOpenQueue,
    required this.onOpenLyrics,
  });

  final Track track;
  final bool isFavorite;
  final bool canFavorite;
  final PlayerController player;
  final List<TrackChapter> chapters;
  final Future<void> Function()? onToggleFavorite;
  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;

  @override
  Widget build(BuildContext context) {
    final queueIndex = player.queue.indexWhere((item) => item.id == track.id);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      track.title,
                      key: const Key('now-playing-title'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (track.album.trim().isNotEmpty &&
                        track.album != 'Unknown Album')
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: canFavorite
                    ? (isFavorite ? 'Remove from favorites' : 'Add to favorites')
                    : 'Save this track to the library to favorite it',
                onPressed: onToggleFavorite,
                icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
              ),
            ],
          ),
          if (queueIndex >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Track ${queueIndex + 1} of ${player.queue.length}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          const SizedBox(height: 18),
          _PlaybackProgress(
            player: player,
            fallbackDuration: track.duration,
            chapters: chapters,
          ),
          if (chapters.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            _ChapterMarkers(player: player, chapters: chapters),
          ],
          const SizedBox(height: 4),
          _PlaybackVolumeControl(player: player),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              IconButton(
                key: const Key('now-playing-shuffle'),
                tooltip: player.shuffleEnabled ? 'Disable shuffle' : 'Enable shuffle',
                isSelected: player.shuffleEnabled,
                onPressed: () => player.setShuffleEnabled(!player.shuffleEnabled),
                icon: const Icon(Icons.shuffle),
              ),
              IconButton(
                tooltip: 'Previous',
                iconSize: 36,
                onPressed: player.queue.isEmpty
                    ? null
                    : () => _runPlaybackAction(context, player.previous),
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                key: const Key('now-playing-skip-backward'),
                tooltip: 'Skip back ${player.skipBackwardInterval.inSeconds} seconds',
                onPressed: player.duration > Duration.zero
                    ? player.skipBackward
                    : null,
                icon: const Icon(Icons.fast_rewind),
              ),
              IconButton.filled(
                key: const Key('now-playing-play-pause'),
                tooltip: player.isPlaying ? 'Pause' : 'Play',
                iconSize: 40,
                padding: const EdgeInsets.all(18),
                onPressed: () => _runPlaybackAction(
                  context,
                  player.togglePlayPause,
                ),
                icon: Icon(player.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(
                key: const Key('now-playing-skip-forward'),
                tooltip: 'Skip forward ${player.skipForwardInterval.inSeconds} seconds',
                onPressed: player.duration > Duration.zero
                    ? player.skipForward
                    : null,
                icon: const Icon(Icons.fast_forward),
              ),
              IconButton(
                tooltip: 'Next',
                iconSize: 36,
                onPressed: player.queue.isEmpty
                    ? null
                    : () => _runPlaybackAction(context, player.next),
                icon: const Icon(Icons.skip_next),
              ),
              IconButton(
                key: const Key('now-playing-repeat'),
                tooltip: _repeatTooltip(player.loopMode),
                isSelected: player.loopMode != LoopMode.off,
                onPressed: () => player.setLoopMode(_nextLoopMode(player.loopMode)),
                icon: Icon(
                  player.loopMode == LoopMode.one ? Icons.repeat_one : Icons.repeat,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TextButton.icon(
                onPressed: onOpenLyrics,
                icon: const Icon(Icons.subtitles_outlined),
                label: const Text('Lyrics'),
              ),
              TextButton.icon(
                onPressed: player.queue.isEmpty ? null : onOpenQueue,
                icon: const Icon(Icons.queue_music),
                label: const Text('Queue'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaybackSpeedMenu extends StatelessWidget {
  const _PlaybackSpeedMenu({
    required this.player,
    required this.trackPlaybackSpeedOverride,
  });

  final PlayerController player;
  final double? trackPlaybackSpeedOverride;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      key: const Key('now-playing-speed'),
      tooltip:
          'Default speed: ${_formatPlaybackSpeed(player.defaultPlaybackSpeed)}',
      icon: const Icon(Icons.speed),
      onSelected: (speed) async {
        await player.setPlaybackSpeed(speed);
        final override = trackPlaybackSpeedOverride;
        if (override != null) {
          await player.setTemporaryPlaybackSpeed(override);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<double>>[
        for (final speed in PlayerController.supportedPlaybackSpeeds)
          CheckedPopupMenuItem<double>(
            value: speed,
            checked: speed == player.defaultPlaybackSpeed,
            child: Text(_formatPlaybackSpeed(speed)),
          ),
      ],
    );
  }
}

class _PlaybackPitchMenu extends StatelessWidget {
  const _PlaybackPitchMenu({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      key: const Key('now-playing-pitch'),
      tooltip: 'Pitch: ${_formatPlaybackSpeed(player.defaultPlaybackPitch)}',
      icon: const Icon(Icons.music_note_outlined),
      onSelected: player.setPlaybackPitch,
      itemBuilder: (context) => <PopupMenuEntry<double>>[
        for (final pitch in PlayerController.supportedPlaybackPitches)
          CheckedPopupMenuItem<double>(
            value: pitch,
            checked: pitch == player.defaultPlaybackPitch,
            child: Text(_formatPlaybackSpeed(pitch)),
          ),
      ],
    );
  }
}

class _TrackPlaybackSpeedMenu extends StatelessWidget {
  const _TrackPlaybackSpeedMenu({
    required this.player,
    required this.library,
    required this.track,
  });

  final PlayerController player;
  final LibraryStore library;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final override = library.playbackSpeedForTrack(track.id);
    final activeSpeed = override ?? player.defaultPlaybackSpeed;
    return PopupMenuButton<_TrackPlaybackSpeedSelection>(
      key: const Key('now-playing-track-speed'),
      tooltip: override == null
          ? 'Track speed: Default (${_formatPlaybackSpeed(activeSpeed)})'
          : 'Track speed: ${_formatPlaybackSpeed(activeSpeed)}',
      icon: const Icon(Icons.tune),
      onSelected: (selection) async {
        final speed = selection.speed;
        if (speed == null) {
          await library.clearTrackPlaybackSpeed(track.id);
          await player.setTemporaryPlaybackSpeed(player.defaultPlaybackSpeed);
          return;
        }
        await library.setTrackPlaybackSpeed(track.id, speed);
        await player.setTemporaryPlaybackSpeed(speed);
      },
      itemBuilder: (context) => <PopupMenuEntry<_TrackPlaybackSpeedSelection>>[
          CheckedPopupMenuItem<_TrackPlaybackSpeedSelection>(
            key: const Key('now-playing-track-speed-default'),
            value: const _TrackPlaybackSpeedSelection(),
          checked: override == null,
          child: Text('Use default (${_formatPlaybackSpeed(player.defaultPlaybackSpeed)})'),
        ),
        const PopupMenuDivider(),
        for (final speed in PlayerController.supportedPlaybackSpeeds)
          CheckedPopupMenuItem<_TrackPlaybackSpeedSelection>(
            key: Key('now-playing-track-speed-$speed'),
            value: _TrackPlaybackSpeedSelection(speed),
            checked: override == speed,
            child: Text(_formatPlaybackSpeed(speed)),
          ),
      ],
    );
  }
}

class _TrackPlaybackSpeedSelection {
  const _TrackPlaybackSpeedSelection([this.speed]);

  final double? speed;
}

class _PlaybackVolumeControl extends StatelessWidget {
  const _PlaybackVolumeControl({required this.player});

  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    final disabled = player.isSleepFadeActive;
    return Row(
      children: <Widget>[
        Icon(
          player.volume == 0
              ? Icons.volume_off_outlined
              : Icons.volume_up_outlined,
          semanticLabel: 'Playback volume',
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            key: const Key('now-playing-volume'),
            value: player.volume,
            semanticFormatterCallback: (value) =>
                'Playback volume ${PlayerController.formatVolume(value)}',
            onChanged: disabled
                ? null
                : (value) => unawaited(player.previewVolume(value)),
            onChangeEnd: disabled
                ? null
                : (value) => unawaited(player.setVolume(value)),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            PlayerController.formatVolume(player.volume),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _ChapterMarkers extends StatelessWidget {
  const _ChapterMarkers({required this.player, required this.chapters});

  final PlayerController player;
  final List<TrackChapter> chapters;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final active = _activeChapter(chapters, snapshot.data ?? Duration.zero);
        return ExpansionTile(
          key: const Key('now-playing-chapters'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          title: const Text('Chapters'),
          subtitle: Text(
            active == null
                ? '${chapters.length} markers'
                : '${formatTrackChapterTimestamp(active.start)} ${active.title}',
          ),
          children: <Widget>[
            for (final chapter in chapters)
              ListTile(
                key: Key('now-playing-chapter-${chapter.start.inMilliseconds}'),
                dense: true,
                selected: chapter == active,
                leading: Text(formatTrackChapterTimestamp(chapter.start)),
                title: Text(chapter.title),
                onTap: () => player.seek(chapter.start),
              ),
          ],
        );
      },
    );
  }
}

TrackChapter? _activeChapter(
  List<TrackChapter> chapters,
  Duration position,
) {
  TrackChapter? active;
  for (final chapter in chapters) {
    if (chapter.start > position) {
      break;
    }
    active = chapter;
  }
  return active;
}

class _PlaybackProgress extends StatelessWidget {
  const _PlaybackProgress({
    required this.player,
    required this.fallbackDuration,
    required this.chapters,
  });

  final PlayerController player;
  final Duration fallbackDuration;
  final List<TrackChapter> chapters;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player.duration > Duration.zero
            ? player.duration
            : fallbackDuration;
        final maxMilliseconds = duration.inMilliseconds <= 0
            ? 1
            : duration.inMilliseconds;
        final value = position.inMilliseconds.clamp(0, maxMilliseconds).toDouble();

        return Column(
          children: <Widget>[
            Slider(
              key: const Key('now-playing-seek'),
              value: value,
              max: maxMilliseconds.toDouble(),
              semanticFormatterCallback: (value) =>
                  '${_formatPlaybackTime(Duration(milliseconds: value.round()))} of ${_formatPlaybackTime(duration)}',
              onChanged: duration > Duration.zero
                  ? (value) => player.seek(
                        Duration(milliseconds: value.round()),
                      )
                  : null,
            ),
            if (duration > Duration.zero && chapters.isNotEmpty)
              _ChapterTimelineMarkers(
                chapters: chapters,
                duration: duration,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(_formatPlaybackTime(position)),
                  Text('-${_formatPlaybackTime(_remaining(duration, position))}'),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChapterTimelineMarkers extends StatelessWidget {
  const _ChapterTimelineMarkers({
    required this.chapters,
    required this.duration,
  });

  final List<TrackChapter> chapters;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 6,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final durationMilliseconds = duration.inMilliseconds;
          if (durationMilliseconds <= 0) {
            return const SizedBox.shrink();
          }

          return Stack(
            children: <Widget>[
              for (final chapter in chapters)
                if (chapter.start < duration)
                  Positioned(
                    left: _chapterMarkerOffset(
                      chapter.start,
                      duration,
                      constraints.maxWidth,
                    ),
                    child: Semantics(
                      label: '${chapter.title} at '
                          '${formatTrackChapterTimestamp(chapter.start)}',
                      child: Container(
                        key: Key(
                          'now-playing-chapter-marker-'
                          '${chapter.start.inMilliseconds}',
                        ),
                        width: 3,
                        height: 6,
                        color: color,
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

double _chapterMarkerOffset(
  Duration start,
  Duration duration,
  double availableWidth,
) {
  if (duration <= Duration.zero || availableWidth <= 3) {
    return 0;
  }

  final fraction = (start.inMilliseconds / duration.inMilliseconds).clamp(0, 1);
  return (availableWidth * fraction).clamp(0, availableWidth - 3).toDouble();
}

Track? _findTrack(List<Track> tracks, String id) {
  for (final track in tracks) {
    if (track.id == id) {
      return track;
    }
  }
  return null;
}

Future<List<TrackChapter>?> _promptForTrackChapters(
  BuildContext context,
  Track track,
) {
  return showDialog<List<TrackChapter>>(
    context: context,
    builder: (_) => _TrackChaptersDialog(track: track),
  );
}

class _TrackChaptersDialog extends StatefulWidget {
  const _TrackChaptersDialog({required this.track});

  final Track track;

  @override
  State<_TrackChaptersDialog> createState() => _TrackChaptersDialogState();
}

class _TrackChaptersDialogState extends State<_TrackChaptersDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatTrackChapters(widget.track.chapters),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final chapters = parseTrackChapters(
        _controller.text,
        maximum: widget.track.duration,
      );
      Navigator.of(context).pop(chapters);
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Chapters for ${widget.track.title}'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          key: const Key('now-playing-chapters-input'),
          controller: _controller,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: 'Chapters',
            hintText: '0:00 Introduction',
            helperText: 'Timestamp and title per line',
            errorText: _errorText,
          ),
          onChanged: (_) {
            if (_errorText != null) {
              setState(() => _errorText = null);
            }
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _controller.clear,
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

Duration _remaining(Duration duration, Duration position) {
  if (position >= duration) {
    return Duration.zero;
  }
  return duration - position;
}

String _formatPlaybackTime(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours;
  final minutes = safe.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = safe.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '${safe.inMinutes}:$seconds';
}

LoopMode _nextLoopMode(LoopMode mode) {
  switch (mode) {
    case LoopMode.off:
      return LoopMode.all;
    case LoopMode.all:
      return LoopMode.one;
    case LoopMode.one:
      return LoopMode.off;
  }
}

String _repeatTooltip(LoopMode mode) {
  switch (mode) {
    case LoopMode.off:
      return 'Enable repeat all';
    case LoopMode.all:
      return 'Enable repeat one';
    case LoopMode.one:
      return 'Disable repeat';
  }
}

String _formatPlaybackSpeed(double speed) {
  final value = speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();
  return '${value}x';
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
