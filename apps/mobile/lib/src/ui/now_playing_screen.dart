import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/flac_vorbis_comment_writer.dart';
import '../data/library_store.dart';
import '../data/m4a_metadata_writer.dart';
import '../data/ogg_vorbis_comment_writer.dart';
import '../data/podcast_transcript_loader.dart';
import '../data/sponsorblock_segment_provider.dart';
import '../domain/track_lyrics.dart';
import '../domain/track.dart';
import '../domain/track_bookmark.dart';
import '../domain/track_chapter.dart';
import '../domain/track_skip_segment.dart';
import '../player/offline_playback_policy.dart';
import '../player/player_controller.dart';
import 'platform_image_share.dart';
import 'widgets/artwork_palette_backdrop.dart';
import 'widgets/track_artwork.dart';
import 'widgets/track_share_card.dart';

bool _canImportSponsorBlockSegments(Track? track) =>
    track?.sourceId == 'youtube-data-metadata' &&
    track?.externalId != null &&
    track!.externalId!.trim().isNotEmpty &&
    track.duration > Duration.zero;

bool _canWriteChapterMarkers(Track track) {
  final path = track.localPath?.toLowerCase();
  return path != null &&
      (path.endsWith('.flac') ||
          path.endsWith('.m4a') ||
          path.endsWith('.m4b') ||
          path.endsWith('.m4r') ||
          path.endsWith('.alac') ||
          path.endsWith('.ogg') ||
          path.endsWith('.oga') ||
          path.endsWith('.opus'));
}

Future<void> _writeChapterMarkers(Track track) async {
  final path = track.localPath;
  if (path == null || path.trim().isEmpty) {
    throw const FormatException('The local file path is unavailable.');
  }
  if (path.toLowerCase().endsWith('.flac')) {
    await const FlacVorbisCommentWriter().write(
      path: path,
      title: track.title,
      artist: track.artist,
      album: track.album,
      genre: track.genre,
      albumArtist: track.albumArtist,
      year: track.year,
      trackNumber: track.trackNumber,
      chapters: track.chapters,
    );
    return;
  }
  final normalized = path.toLowerCase();
  if (normalized.endsWith('.m4a') ||
      normalized.endsWith('.m4b') ||
      normalized.endsWith('.m4r') ||
      normalized.endsWith('.alac')) {
    await const M4aMetadataWriter().write(
      path: path,
      title: track.title,
      artist: track.artist,
      album: track.album,
      genre: track.genre,
      albumArtist: track.albumArtist,
      year: track.year,
      trackNumber: track.trackNumber,
      chapters: track.chapters,
    );
    return;
  }
  await const OggVorbisCommentWriter().write(
    path: path,
    title: track.title,
    artist: track.artist,
    album: track.album,
    genre: track.genre,
    albumArtist: track.albumArtist,
    year: track.year,
    trackNumber: track.trackNumber,
    chapters: track.chapters,
  );
}

Future<bool?> _confirmChapterFileWrite(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update embedded chapters?'),
      content: const Text('Replace chapter markers in this audio file.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Update file'),
        ),
      ],
    ),
  );
}

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({
    required this.onOpenQueue,
    required this.onOpenLyrics,
    this.podcastTranscriptLoader = loadPodcastTranscript,
    this.sponsorBlockSegmentLoader = loadSponsorBlockSegments,
    super.key,
  });

  final VoidCallback onOpenQueue;
  final VoidCallback onOpenLyrics;
  final PodcastTranscriptLoader podcastTranscriptLoader;
  final SponsorBlockSegmentLoader sponsorBlockSegmentLoader;

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
          if (current?.hasTranscript ?? false)
            IconButton(
              key: const Key('now-playing-podcast-transcript'),
              tooltip: 'Open podcast transcript',
              onPressed: () => _openPodcastTranscript(current!.transcriptUri!),
              icon: const Icon(Icons.article_outlined),
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
          if (savedCurrent != null)
            IconButton(
              key: const Key('now-playing-skip-segments-editor'),
              tooltip: 'Edit skip segments',
              onPressed: () => _showTrackSkipSegmentsEditor(savedCurrent),
              icon: const Icon(Icons.fast_forward_outlined),
            ),
          if (_canImportSponsorBlockSegments(savedCurrent))
            IconButton(
              key: const Key('now-playing-import-sponsorblock-segments'),
              tooltip: 'Import SponsorBlock segments',
              onPressed: () => _importSponsorBlockSegments(savedCurrent!),
              icon: const Icon(Icons.download_for_offline_outlined),
            ),
          if (current != null)
            _TrackPlaybackSpeedMenu(
              player: player,
              library: library,
              track: current,
            ),
          if (current != null && player.supportsPitch)
            _TrackPlaybackPitchMenu(player: player, track: current),
          _PlaybackSpeedMenu(
            player: player,
            trackPlaybackSpeedOverride: current == null
                ? null
                : library.playbackSpeedForTrack(current.id),
          ),
          if (player.supportsPitch)
            _PlaybackPitchMenu(
              player: player,
              trackPlaybackPitchOverride: current == null
                  ? null
                  : player.playbackPitchForTrack(current.id),
            ),
        ],
      ),
      body: current == null
          ? const Center(child: Text('No track is currently selected.'))
          : ArtworkPaletteBackdrop(
              artworkUri: current.artworkUri,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final savedTrack = _findTrack(library.tracks, current.id);
                  final bookmarks = savedTrack == null
                      ? const <TrackBookmark>[]
                      : library.bookmarksForTrack(current.id);
                  final currentQueueIndex = player.queue.indexWhere(
                    (track) => track.id == current.id,
                  );
                  final content = _NowPlayingContent(
                    track: current,
                    isFavorite: savedTrack?.isFavorite ?? false,
                    canFavorite: savedTrack != null,
                    player: player,
                    chapters: savedTrack?.chapters ?? current.chapters,
                    skipSegments:
                        savedTrack?.skipSegments ?? current.skipSegments,
                    bookmarks: bookmarks,
                    onToggleFavorite: savedTrack == null
                        ? null
                        : () => library.toggleFavorite(current.id),
                    onAddBookmark: savedTrack == null
                        ? null
                        : () => _addBookmark(library, current, player),
                    onManageBookmarks: savedTrack == null || bookmarks.isEmpty
                        ? null
                        : () => _showBookmarkManager(
                              library,
                              current.id,
                              player,
                            ),
                    onRemoveBookmark: savedTrack == null
                        ? null
                        : (bookmark) => library.removeTrackBookmark(
                              current.id,
                              bookmark.id,
                            ),
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
                              Expanded(
                                child: SingleChildScrollView(
                                  child: content.controls,
                                ),
                              ),
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

  Future<void> _openPodcastTranscript(Uri transcriptUri) async {
    final player = context.read<PlayerController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PodcastTranscriptSheet(
        transcriptUri: transcriptUri,
        loader: widget.podcastTranscriptLoader,
        player: player,
      ),
    );
  }

  Future<void> _importSponsorBlockSegments(Track track) async {
    final library = context.read<LibraryStore>();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import SponsorBlock segments?'),
        content: const Text(
          'This sends a four-character hash prefix of this YouTube video ID to SponsorBlock. It never runs in the background or submits data.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) return;
    try {
      final imported = await widget.sponsorBlockSegmentLoader(
        track.externalId!,
        maximum: track.duration,
        categories: library.sponsorBlockCategories,
      );
      if (!mounted) return;
      if (imported.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No matching SponsorBlock segments found.')),
        );
        return;
      }
      final saveImported = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review SponsorBlock segments'),
          content: SizedBox(
            width: 420,
            height: 260,
            child: ListView(
              children: <Widget>[
                for (final segment in imported)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.fast_forward_outlined),
                    title: Text(segment.label.replaceFirst('SponsorBlock: ', '')),
                    subtitle: Text(
                      '${formatTrackChapterTimestamp(segment.start)} - ${formatTrackChapterTimestamp(segment.end)}',
                    ),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Save ${imported.length} segment(s)'),
            ),
          ],
        ),
      );
      if (!mounted || saveImported != true) return;
      final updated = await library.updateTrackSkipSegments(
        track.id,
        <TrackSkipSegment>[...track.skipSegments, ...imported],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported ${updated?.skipSegments.length ?? 0} skip segment(s).')),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not import SponsorBlock segments.')),
        );
      }
    }
  }

  Future<void> _addBookmark(
    LibraryStore library,
    Track track,
    PlayerController player,
  ) async {
    final label = await _promptForBookmarkLabel(
      context,
      title: 'Add bookmark',
    );
    if (!mounted || label == null) {
      return;
    }
    final bookmark = await library.addTrackBookmark(
      track.id,
      player.position,
      label: label,
    );
    if (!mounted || bookmark == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bookmark saved at ${_formatPlaybackTime(bookmark.position)}.')),
    );
  }

  Future<void> _showBookmarkManager(
    LibraryStore library,
    String trackId,
    PlayerController player,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BookmarkManagerSheet(
        library: library,
        trackId: trackId,
        player: player,
        onRename: (bookmark, dialogContext) =>
            _renameBookmark(library, bookmark, dialogContext),
      ),
    );
  }

  Future<void> _renameBookmark(
    LibraryStore library,
    TrackBookmark bookmark,
    BuildContext context,
  ) async {
    final label = await _promptForBookmarkLabel(
      context,
      title: 'Rename bookmark',
      initialValue: bookmark.label,
    );
    if (label == null) {
      return;
    }
    await library.updateTrackBookmarkLabel(
      bookmark.trackId,
      bookmark.id,
      label,
    );
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
          OutlinedButton.icon(
            onPressed: () => _saveTrackShareCard(dialogContext, boundaryKey, track),
            icon: const Icon(Icons.save_alt_outlined),
            label: const Text('Save PNG'),
          ),
          FilledButton.icon(
            onPressed: () => _shareTrackShareCard(dialogContext, boundaryKey, track),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share'),
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
      if (outputPath == null || outputPath.isEmpty) {
        return;
      }
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
      }
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Saved $fileName.')));
      }
    } on Object catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text('Could not save track share card: $error')));
      }
    }
  }

  Future<void> _shareTrackShareCard(
    BuildContext context,
    GlobalKey boundaryKey,
    Track track,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final sharePositionOrigin = platformSharePositionOrigin(context);
    try {
      final status = await const SharePlusImageShareService().share(
        PlatformImageShareRequest(
          bytes: await captureTrackShareCardPng(boundaryKey),
          fileName: 'aethertune-track.png',
          title: '${track.title} - AetherTune',
          subject: 'AetherTune track share card',
          text: '${track.title} by ${track.artist}',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      if (!context.mounted || status == PlatformImageShareStatus.dismissed) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            status == PlatformImageShareStatus.shared
                ? 'Shared track share card.'
                : 'Sharing is unavailable. Save the PNG instead.',
          ),
        ),
      );
    } on Object catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not share track share card: $error')),
        );
      }
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

    var message = updated == null
        ? 'Track is no longer in the library.'
        : 'Saved ${updated.chapters.length} chapter(s).';
    if (updated != null && _canWriteChapterMarkers(updated)) {
      final writeToFile = await _confirmChapterFileWrite(context);
      if (!mounted) {
        return;
      }
      if (writeToFile == true) {
        try {
          await _writeChapterMarkers(updated);
          message = 'Saved ${updated.chapters.length} chapter(s) and updated the file.';
        } on Object catch (error) {
          message = 'Saved chapters locally, but could not update the file: $error';
        }
      }
    }

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  Future<void> _showTrackSkipSegmentsEditor(Track track) async {
    final segments = await _promptForTrackSkipSegments(context, track);
    if (!mounted || segments == null) {
      return;
    }
    final updated = await context.read<LibraryStore>().updateTrackSkipSegments(
      track.id,
      segments,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated == null
              ? 'Track is no longer in the library.'
              : 'Saved ${updated.skipSegments.length} skip segment(s).',
        ),
      ),
    );
  }
}

class _PodcastTranscriptSheet extends StatefulWidget {
  const _PodcastTranscriptSheet({
    required this.transcriptUri,
    required this.loader,
    required this.player,
  });

  final Uri transcriptUri;
  final PodcastTranscriptLoader loader;
  final PlayerController player;

  @override
  State<_PodcastTranscriptSheet> createState() =>
      _PodcastTranscriptSheetState();
}

class _PodcastTranscriptSheetState extends State<_PodcastTranscriptSheet> {
  late Future<PodcastTranscriptDocument> _transcript =
      widget.loader(widget.transcriptUri);

  void _retry() {
    setState(() {
      _transcript = widget.loader(widget.transcriptUri);
    });
  }

  Future<void> _openInBrowser() async {
    final opened = await launchUrl(
      widget.transcriptUri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the podcast transcript.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Podcast transcript'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Open in browser',
                    onPressed: _openInBrowser,
                    icon: const Icon(Icons.open_in_new),
                  ),
                  IconButton(
                    key: const Key('podcast-transcript-close'),
                    tooltip: 'Close transcript',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<PodcastTranscriptDocument>(
                future: _transcript,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            const Text('Could not load the podcast transcript.'),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              children: <Widget>[
                                FilledButton(
                                  onPressed: _retry,
                                  child: const Text('Retry'),
                                ),
                                OutlinedButton(
                                  onPressed: _openInBrowser,
                                  child: const Text('Open in browser'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final transcript = snapshot.requireData;
                  final timedLines = transcript.timedLines;
                  if (timedLines.isNotEmpty) {
                    return StreamBuilder<Duration>(
                      stream: widget.player.positionStream,
                      initialData: widget.player.position,
                      builder: (context, positionSnapshot) {
                        final activeIndex = syncedLyricLineIndexAt(
                          timedLines,
                          positionSnapshot.data ?? Duration.zero,
                        );
                        return ListView.builder(
                          key: const Key('podcast-transcript-reader'),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: timedLines.length,
                          itemBuilder: (context, index) {
                            final line = timedLines[index];
                            return ListTile(
                              key: Key(
                                'podcast-transcript-cue-${line.timestamp.inMilliseconds}',
                              ),
                              selected: index == activeIndex,
                              leading: Text(
                                formatSyncedLyricTimestamp(line.timestamp),
                              ),
                              title: Text(line.text),
                              onTap: () => widget.player.seek(line.timestamp),
                            );
                          },
                        );
                      },
                    );
                  }
                  return SingleChildScrollView(
                    key: const Key('podcast-transcript-reader'),
                    padding: const EdgeInsets.all(20),
                    child: SelectableText(
                      transcript.displayText,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                },
              ),
            ),
          ],
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
    required List<TrackSkipSegment> skipSegments,
    required List<TrackBookmark> bookmarks,
    required Future<void> Function()? onToggleFavorite,
    required Future<void> Function()? onAddBookmark,
    required Future<void> Function()? onManageBookmarks,
    required Future<bool> Function(TrackBookmark bookmark)? onRemoveBookmark,
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
          skipSegments: skipSegments,
          bookmarks: bookmarks,
          onToggleFavorite: onToggleFavorite,
          onAddBookmark: onAddBookmark,
          onManageBookmarks: onManageBookmarks,
          onRemoveBookmark: onRemoveBookmark,
          onOpenQueue: onOpenQueue,
          onOpenLyrics: onOpenLyrics,
        );

  final Widget artwork;
  final Widget controls;
}

Future<String?> _promptForBookmarkLabel(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _BookmarkLabelDialog(
      title: title,
      initialValue: initialValue,
    ),
  );
}

class _BookmarkLabelDialog extends StatefulWidget {
  const _BookmarkLabelDialog({
    required this.title,
    required this.initialValue,
  });

  final String title;
  final String initialValue;

  @override
  State<_BookmarkLabelDialog> createState() => _BookmarkLabelDialogState();
}

class _BookmarkLabelDialogState extends State<_BookmarkLabelDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const Key('now-playing-bookmark-label'),
        controller: _controller,
        autofocus: true,
        maxLength: TrackBookmark.maxLabelLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Label (optional)',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.title == 'Add bookmark' ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}

Future<String?> _promptForBookmarkFolder(
  BuildContext context, {
  required String title,
  required List<String> folders,
  String initialValue = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _BookmarkFolderDialog(
      title: title,
      folders: folders,
      initialValue: initialValue,
    ),
  );
}

class _BookmarkFolderDialog extends StatefulWidget {
  const _BookmarkFolderDialog({
    required this.title,
    required this.folders,
    required this.initialValue,
  });

  final String title;
  final List<String> folders;
  final String initialValue;

  @override
  State<_BookmarkFolderDialog> createState() => _BookmarkFolderDialogState();
}

class _BookmarkFolderDialogState extends State<_BookmarkFolderDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setFolder(String folder) {
    _controller.value = TextEditingValue(
      text: folder,
      selection: TextSelection.collapsed(offset: folder.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            key: const Key('now-playing-bookmark-folder'),
            controller: _controller,
            autofocus: true,
            maxLength: TrackBookmark.maxFolderLength,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Folder (optional)'),
          ),
          if (widget.folders.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text('Existing folders', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                ActionChip(
                  avatar: const Icon(Icons.folder_off_outlined, size: 18),
                  label: const Text('No folder'),
                  onPressed: () => _setFolder(''),
                ),
                for (final folder in widget.folders)
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: Text(folder),
                    onPressed: () => _setFolder(folder),
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Move'),
        ),
      ],
    );
  }
}

class _BookmarkManagerSheet extends StatefulWidget {
  const _BookmarkManagerSheet({
    required this.library,
    required this.trackId,
    required this.player,
    required this.onRename,
  });

  final LibraryStore library;
  final String trackId;
  final PlayerController player;
  final Future<void> Function(TrackBookmark bookmark, BuildContext dialogContext)
  onRename;

  @override
  State<_BookmarkManagerSheet> createState() => _BookmarkManagerSheetState();
}

class _BookmarkManagerSheetState extends State<_BookmarkManagerSheet> {
  final Set<String> _selectedIds = <String>{};

  void _toggleSelection(String bookmarkId, {bool? selected}) {
    setState(() {
      if (selected ?? !_selectedIds.contains(bookmarkId)) {
        _selectedIds.add(bookmarkId);
      } else {
        _selectedIds.remove(bookmarkId);
      }
    });
  }

  Future<void> _moveBookmarks(
    Iterable<String> bookmarkIds, {
    String initialFolder = '',
  }) async {
    final ids = bookmarkIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final folder = await _promptForBookmarkFolder(
      context,
      title: ids.length == 1 ? 'Move bookmark' : 'Move bookmarks',
      folders: widget.library.bookmarkFoldersForTrack(widget.trackId),
      initialValue: initialFolder,
    );
    if (!mounted || folder == null) {
      return;
    }
    await widget.library.updateTrackBookmarksFolder(widget.trackId, ids, folder);
    if (mounted) {
      setState(() => _selectedIds.removeAll(ids));
    }
  }

  Future<void> _removeSelected() async {
    if (_selectedIds.isEmpty) {
      return;
    }
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove $count bookmarks?'),
        content: const Text('This removes the selected timestamps from this track.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    final ids = Set<String>.from(_selectedIds);
    await widget.library.removeTrackBookmarks(widget.trackId, ids);
    if (mounted) {
      setState(() => _selectedIds.removeAll(ids));
    }
  }

  Future<void> _seekToBookmark(TrackBookmark bookmark) async {
    Navigator.of(context).pop();
    widget.player.clearABRepeat();
    await widget.player.seek(bookmark.position);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.library,
      builder: (context, _) {
        final bookmarks = widget.library.bookmarksForTrack(widget.trackId);
        final bookmarkIds = bookmarks.map((bookmark) => bookmark.id).toSet();
        final selectedIds = _selectedIds.intersection(bookmarkIds);
        final folders = widget.library.bookmarkFoldersForTrack(widget.trackId);
        final groups = <String>[
          if (bookmarks.any((bookmark) => bookmark.folder.isEmpty)) '',
          ...folders,
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Bookmarks',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (bookmarks.isNotEmpty)
                      IconButton(
                        tooltip: selectedIds.length == bookmarks.length
                            ? 'Clear bookmark selection'
                            : 'Select all bookmarks',
                        onPressed: () => setState(() {
                          if (selectedIds.length == bookmarks.length) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds
                              ..clear()
                              ..addAll(bookmarkIds);
                          }
                        }),
                        icon: Icon(
                          selectedIds.length == bookmarks.length
                              ? Icons.deselect_outlined
                              : Icons.select_all,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Close bookmarks',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (selectedIds.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Text('${selectedIds.length} selected'),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Move selected bookmarks',
                        onPressed: () => unawaited(_moveBookmarks(selectedIds)),
                        icon: const Icon(Icons.drive_file_move_outline),
                      ),
                      IconButton(
                        tooltip: 'Remove selected bookmarks',
                        onPressed: () => unawaited(_removeSelected()),
                        icon: const Icon(Icons.delete_sweep_outlined),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                if (bookmarks.isEmpty)
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bookmark_border),
                    title: Text('No bookmarks for this track'),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final folder in groups) ...<Widget>[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 2),
                            child: Text(
                              folder.isEmpty ? 'Unfiled' : folder,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          for (final bookmark in bookmarks.where(
                            (bookmark) => bookmark.folder == folder,
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Checkbox(
                                key: Key('bookmark-manager-select-${bookmark.id}'),
                                value: selectedIds.contains(bookmark.id),
                                onChanged: (selected) => _toggleSelection(
                                  bookmark.id,
                                  selected: selected,
                                ),
                              ),
                              title: Text(_bookmarkLabel(bookmark)),
                              subtitle: Text(
                                _formatPlaybackTime(bookmark.position),
                              ),
                              onTap: selectedIds.isEmpty
                                  ? () => unawaited(_seekToBookmark(bookmark))
                                  : () => _toggleSelection(bookmark.id),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  IconButton(
                                    tooltip: 'Move bookmark',
                                    onPressed: () => unawaited(
                                      _moveBookmarks(
                                        <String>[bookmark.id],
                                        initialFolder: bookmark.folder,
                                      ),
                                    ),
                                    icon: const Icon(Icons.folder_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Rename bookmark',
                                    onPressed: () => unawaited(
                                      widget.onRename(bookmark, context),
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove bookmark',
                                    onPressed: () => unawaited(
                                      widget.library.removeTrackBookmark(
                                        widget.trackId,
                                        bookmark.id,
                                      ),
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _bookmarkLabel(TrackBookmark bookmark) {
  return bookmark.label.isEmpty
      ? _formatPlaybackTime(bookmark.position)
      : bookmark.label;
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
                artworkCrop: track.artworkCrop,
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
    required this.skipSegments,
    required this.bookmarks,
    required this.onToggleFavorite,
    required this.onAddBookmark,
    required this.onManageBookmarks,
    required this.onRemoveBookmark,
    required this.onOpenQueue,
    required this.onOpenLyrics,
  });

  final Track track;
  final bool isFavorite;
  final bool canFavorite;
  final PlayerController player;
  final List<TrackChapter> chapters;
  final List<TrackSkipSegment> skipSegments;
  final List<TrackBookmark> bookmarks;
  final Future<void> Function()? onToggleFavorite;
  final Future<void> Function()? onAddBookmark;
  final Future<void> Function()? onManageBookmarks;
  final Future<bool> Function(TrackBookmark bookmark)? onRemoveBookmark;
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
          if (player.hasABRepeatStart)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.repeat, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    player.isABRepeatActive
                        ? 'A ${_formatPlaybackTime(player.aBRepeatStart!)} '
                            'B ${_formatPlaybackTime(player.aBRepeatEnd!)}'
                        : 'A ${_formatPlaybackTime(player.aBRepeatStart!)} '
                            'Choose B',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          if (chapters.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            _ChapterMarkers(player: player, chapters: chapters),
          ],
          if (skipSegments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Semantics(
              key: const Key('now-playing-skip-segments'),
              label: '${skipSegments.length} automatic skip segments',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(Icons.fast_forward_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Auto-skip ${skipSegments.length} section(s)',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
            ),
          ],
          if (bookmarks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            _TrackBookmarks(
              player: player,
              bookmarks: bookmarks,
              onRemove: onRemoveBookmark,
            ),
          ],
          if (player.supportsVisualizer) ...<Widget>[
            const SizedBox(height: 12),
            _PlaybackVisualizer(player: player),
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
              TextButton.icon(
                key: const Key('now-playing-ab-repeat'),
                onPressed: player.duration > Duration.zero
                    ? () {
                        if (!player.hasABRepeatStart) {
                          player.setABRepeatStart();
                          return;
                        }
                        if (!player.isABRepeatActive) {
                          if (!player.setABRepeatEnd()) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Choose a point at least half a second after A.'),
                              ),
                            );
                          }
                          return;
                        }
                        player.clearABRepeat();
                      }
                    : null,
                icon: Icon(
                  player.isABRepeatActive ? Icons.repeat_one : Icons.repeat,
                ),
                label: Text(_aBRepeatLabel(player)),
              ),
              TextButton.icon(
                key: const Key('now-playing-add-bookmark'),
                onPressed: onAddBookmark == null
                    ? null
                    : () => unawaited(onAddBookmark!()),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Bookmark'),
              ),
              if (onManageBookmarks != null)
                TextButton.icon(
                  key: const Key('now-playing-manage-bookmarks'),
                  onPressed: () => unawaited(onManageBookmarks!()),
                  icon: const Icon(Icons.bookmarks_outlined),
                  label: const Text('Bookmarks'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackBookmarks extends StatelessWidget {
  const _TrackBookmarks({
    required this.player,
    required this.bookmarks,
    required this.onRemove,
  });

  final PlayerController player;
  final List<TrackBookmark> bookmarks;
  final Future<bool> Function(TrackBookmark bookmark)? onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Bookmarks', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: bookmarks
              .map(
                (bookmark) => InputChip(
                  key: Key('now-playing-bookmark-${bookmark.id}'),
                  avatar: const Icon(Icons.bookmark_outline, size: 18),
                  label: Text(_bookmarkLabel(bookmark)),
                  tooltip:
                      'Seek to ${_bookmarkLabel(bookmark)} at ${_formatPlaybackTime(bookmark.position)}',
                  onPressed: () {
                    player.clearABRepeat();
                    unawaited(player.seek(bookmark.position));
                  },
                  onDeleted: onRemove == null
                      ? null
                      : () => unawaited(onRemove!(bookmark)),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _PlaybackVisualizer extends StatefulWidget {
  const _PlaybackVisualizer({required this.player});

  final PlayerController player;

  @override
  State<_PlaybackVisualizer> createState() => _PlaybackVisualizerState();
}

class _PlaybackVisualizerState extends State<_PlaybackVisualizer> {
  bool _enabled = false;
  bool _starting = false;

  @override
  void dispose() {
    unawaited(widget.player.stopVisualizer());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final enabled = await widget.player.startVisualizer();
      if (!mounted) {
        return;
      }
      setState(() => _enabled = enabled);
      if (!enabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Visualizer is unavailable until audio is ready.'),
          ),
        );
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not enable the visualizer.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _stop() async {
    await widget.player.stopVisualizer();
    if (mounted) {
      setState(() => _enabled = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('now-playing-enable-visualizer'),
          onPressed: _starting ? null : _start,
          icon: _starting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.graphic_eq),
          label: const Text('Enable visualizer'),
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Live playback visualizer',
      child: SizedBox(
        height: 72,
        child: Row(
          children: <Widget>[
            Expanded(
              child: StreamBuilder<List<double>>(
                stream: widget.player.visualizerBands,
                initialData: const <double>[],
                builder: (context, snapshot) => CustomPaint(
                  painter: _VisualizerBarsPainter(
                    bands: snapshot.data ?? const <double>[],
                    color: colors.primary,
                    mutedColor: colors.primaryContainer,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Disable visualizer',
              onPressed: _stop,
              icon: const Icon(Icons.graphic_eq_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisualizerBarsPainter extends CustomPainter {
  const _VisualizerBarsPainter({
    required this.bands,
    required this.color,
    required this.mutedColor,
  });

  final List<double> bands;
  final Color color;
  final Color mutedColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bandCount = 16;
    const gap = 3.0;
    final barWidth = (size.width - (bandCount - 1) * gap) / bandCount;
    final mutedPaint = Paint()..color = mutedColor;
    final activePaint = Paint()..color = color;
    for (var index = 0; index < bandCount; index += 1) {
      final x = index * (barWidth + gap);
      final level = index < bands.length
          ? bands[index].clamp(0.0, 1.0).toDouble()
          : 0.0;
      final activeHeight = 6 + (size.height - 6) * level;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, barWidth, size.height),
          const Radius.circular(2),
        ),
        mutedPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - activeHeight, barWidth, activeHeight),
          const Radius.circular(2),
        ),
        activePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_VisualizerBarsPainter oldDelegate) =>
      oldDelegate.bands != bands ||
      oldDelegate.color != color ||
      oldDelegate.mutedColor != mutedColor;
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
  const _PlaybackPitchMenu({
    required this.player,
    required this.trackPlaybackPitchOverride,
  });

  final PlayerController player;
  final double? trackPlaybackPitchOverride;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      key: const Key('now-playing-pitch'),
      tooltip: 'Pitch: ${_formatPlaybackSpeed(player.defaultPlaybackPitch)}',
      icon: const Icon(Icons.music_note_outlined),
      onSelected: (pitch) async {
        await player.setPlaybackPitch(pitch);
        final override = trackPlaybackPitchOverride;
        if (override != null) {
          await player.setTemporaryPlaybackPitch(override);
        }
      },
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

class _TrackPlaybackPitchMenu extends StatelessWidget {
  const _TrackPlaybackPitchMenu({required this.player, required this.track});

  final PlayerController player;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final override = player.playbackPitchForTrack(track.id);
    final activePitch = override ?? player.defaultPlaybackPitch;
    return PopupMenuButton<_TrackPlaybackPitchSelection>(
      key: const Key('now-playing-track-pitch'),
      tooltip: override == null
          ? 'Track pitch: Default (${_formatPlaybackSpeed(activePitch)})'
          : 'Track pitch: ${_formatPlaybackSpeed(activePitch)}',
      icon: const Icon(Icons.music_note_outlined),
      onSelected: (selection) async {
        final pitch = selection.pitch;
        if (pitch == null) {
          await player.clearTrackPlaybackPitch(track.id);
          return;
        }
        await player.setTrackPlaybackPitch(track.id, pitch);
      },
      itemBuilder: (context) =>
          <PopupMenuEntry<_TrackPlaybackPitchSelection>>[
            CheckedPopupMenuItem<_TrackPlaybackPitchSelection>(
              key: const Key('now-playing-track-pitch-default'),
              value: const _TrackPlaybackPitchSelection(),
              checked: override == null,
              child: Text(
                'Use default (${_formatPlaybackSpeed(player.defaultPlaybackPitch)})',
              ),
            ),
            const PopupMenuDivider(),
            for (final pitch in PlayerController.supportedPlaybackPitches)
              CheckedPopupMenuItem<_TrackPlaybackPitchSelection>(
                key: Key('now-playing-track-pitch-$pitch'),
                value: _TrackPlaybackPitchSelection(pitch),
                checked: override == pitch,
                child: Text(_formatPlaybackSpeed(pitch)),
              ),
          ],
    );
  }
}

class _TrackPlaybackPitchSelection {
  const _TrackPlaybackPitchSelection([this.pitch]);

  final double? pitch;
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

Future<List<TrackSkipSegment>?> _promptForTrackSkipSegments(
  BuildContext context,
  Track track,
) {
  return showDialog<List<TrackSkipSegment>>(
    context: context,
    builder: (_) => _TrackSkipSegmentsDialog(track: track),
  );
}

class _TrackSkipSegmentsDialog extends StatefulWidget {
  const _TrackSkipSegmentsDialog({required this.track});

  final Track track;

  @override
  State<_TrackSkipSegmentsDialog> createState() =>
      _TrackSkipSegmentsDialogState();
}

class _TrackSkipSegmentsDialogState extends State<_TrackSkipSegmentsDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: formatTrackSkipSegments(widget.track.skipSegments),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final segments = parseTrackSkipSegments(
        _controller.text,
        maximum: widget.track.duration,
      );
      Navigator.of(context).pop(segments);
    } on FormatException catch (error) {
      setState(() => _errorText = error.message);
    }
  }

  Future<void> _importFile() async {
    final file = await FilePicker.pickFile(
      allowedExtensions: supportedTrackSkipSegmentDocumentExtensions,
      dialogTitle: 'Import skip segments',
      type: FileType.custom,
    );
    if (!mounted || file == null) {
      return;
    }

    try {
      final source = decodeTrackSkipSegmentDocumentBytes(
        await file.readAsBytes(),
        fileName: file.name,
      );
      final segments = parseTrackSkipSegments(
        source,
        maximum: widget.track.duration,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _controller.text = formatTrackSkipSegments(segments);
        _errorText = null;
      });
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _errorText = 'Could not import skip segments: $error');
      }
    }
  }

  Future<void> _exportFile() async {
    try {
      final segments = parseTrackSkipSegments(
        _controller.text,
        maximum: widget.track.duration,
      );
      final contents = formatTrackSkipSegments(segments);
      final bytes = Uint8List.fromList(utf8.encode(contents));
      final outputPath = await FilePicker.saveFile(
        allowedExtensions: supportedTrackSkipSegmentDocumentExtensions,
        bytes: bytes,
        dialogTitle: 'Export skip segments',
        fileName: 'aethertune-skip-segments.txt',
        type: FileType.custom,
      );
      if (!mounted || outputPath == null || outputPath.isEmpty) {
        return;
      }
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exported skip segments.')),
      );
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _errorText = error.message);
      }
    } on FileSystemException catch (error) {
      if (mounted) {
        setState(() => _errorText = 'Could not export skip segments: $error');
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _errorText = 'Could not export skip segments: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Skip segments for ${widget.track.title}'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          key: const Key('now-playing-skip-segments-input'),
          controller: _controller,
          autofocus: true,
          minLines: 6,
          maxLines: 12,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            labelText: 'Skip segments',
            hintText: '0:30-0:45 Intro',
            helperText: 'Start-end timestamps and optional label per line',
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
        TextButton.icon(
          key: const Key('now-playing-skip-segments-import'),
          onPressed: _importFile,
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('Import'),
        ),
        TextButton.icon(
          key: const Key('now-playing-skip-segments-export'),
          onPressed: _exportFile,
          icon: const Icon(Icons.save_alt_outlined),
          label: const Text('Export'),
        ),
        TextButton.icon(
          key: const Key('now-playing-skip-segments-clear'),
          onPressed: _controller.clear,
          icon: const Icon(Icons.clear),
          label: const Text('Clear'),
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

String _aBRepeatLabel(PlayerController player) {
  if (!player.hasABRepeatStart) {
    return 'Set A';
  }
  if (!player.isABRepeatActive) {
    return 'Set B';
  }
  return 'Clear A-B';
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
