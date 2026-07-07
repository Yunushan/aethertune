import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/demo_source_provider.dart';
import '../data/internet_archive_provider.dart';
import '../data/library_store.dart';
import '../data/podcast_rss_provider.dart';
import '../data/radio_browser_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/playback_progress_entry.dart';
import '../domain/playlist.dart';
import '../domain/podcast_opml.dart';
import '../domain/podcast_subscription.dart';
import '../domain/provider_search.dart';
import '../domain/sleep_timer_duration.dart';
import '../domain/track.dart';
import '../domain/track_lyrics.dart';
import '../player/offline_playback_policy.dart';
import '../player/player_controller.dart';
import 'widgets/player_bar.dart';
import 'widgets/track_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _radioClickProvider = RadioBrowserProvider();
  int _tabIndex = 0;
  bool _favoritesOnly = false;
  bool _offlineLibraryOnly = false;
  String _query = '';
  LibrarySortMode _librarySortMode = LibrarySortMode.recentlyAdded;
  PlayerController? _historyPlayer;
  LibraryStore? _historyLibrary;
  StreamSubscription<Duration>? _progressSub;
  String? _lastProgressTrackId;
  Duration _lastRecordedProgressPosition = Duration.zero;
  int _lastRecordedPlaybackSerial = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final player = context.read<PlayerController>();
    if (_historyPlayer != player) {
      _historyPlayer?.removeListener(_recordPlaybackHistory);
      _progressSub?.cancel();
      _historyPlayer = player;
      player.addListener(_recordPlaybackHistory);
      _progressSub = player.positionStream.listen(_recordPlaybackProgress);
    }

    _historyLibrary = context.read<LibraryStore>();
  }

  @override
  void dispose() {
    _historyPlayer?.removeListener(_recordPlaybackHistory);
    _progressSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _recordPlaybackHistory() {
    final player = _historyPlayer;
    final library = _historyLibrary;
    final track = player?.current;
    if (player == null || library == null || track == null) {
      return;
    }

    if (player.playbackStartSerial == _lastRecordedPlaybackSerial) {
      return;
    }

    _lastRecordedPlaybackSerial = player.playbackStartSerial;
    unawaited(library.recordPlayback(track.id));
    unawaited(_recordRadioStationClick(track));
  }

  Future<void> _recordRadioStationClick(Track track) async {
    try {
      await _radioClickProvider.recordStationClick(track);
    } catch (_) {
      // Playback should not depend on Radio Browser click accounting.
    }
  }

  void _recordPlaybackProgress(Duration position) {
    final player = _historyPlayer;
    final library = _historyLibrary;
    final track = player?.current;
    if (player == null ||
        library == null ||
        track == null ||
        !_tracksPodcastProgress(track)) {
      return;
    }

    if (_lastProgressTrackId != track.id) {
      _lastProgressTrackId = track.id;
      if (position < const Duration(seconds: 5)) {
        _lastRecordedProgressPosition = position;
        return;
      }
      _lastRecordedProgressPosition = Duration.zero;
    }

    final delta = position - _lastRecordedProgressPosition;
    if (delta.inSeconds.abs() < 10 && position.inSeconds >= 10) {
      return;
    }

    _lastRecordedProgressPosition = position;
    unawaited(
      library.recordPlaybackProgress(track.id, position, player.duration),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AetherTune'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Import local audio',
            onPressed: () => _importAudio(context),
            icon: const Icon(Icons.library_add),
          ),
          IconButton(
            tooltip: 'Sleep timer',
            onPressed: () => _showSleepTimer(context),
            icon: const Icon(Icons.bedtime_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: <Widget>[
                  _LibraryTab(
                    searchController: _searchController,
                    query: _query,
                    favoritesOnly: _favoritesOnly,
                    offlineOnly: _offlineLibraryOnly,
                    sortMode: _librarySortMode,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onQuerySubmitted: (value) {
                      setState(() => _query = value);
                      unawaited(
                        context.read<LibraryStore>().recordSearchQuery(value),
                      );
                    },
                    onFavoritesOnlyChanged: (value) {
                      setState(() => _favoritesOnly = value);
                    },
                    onOfflineOnlyChanged: (value) {
                      setState(() => _offlineLibraryOnly = value);
                    },
                    onSortModeChanged: (value) {
                      setState(() => _librarySortMode = value);
                    },
                    onImport: () => _importAudio(context),
                    onAddToPlaylist: (track) => _showAddToPlaylist(
                      context,
                      track,
                    ),
                    onLyrics: (track) => _showLyricsEditor(
                      context,
                      track,
                    ),
                  ),
                  _PlaylistsTab(
                    onAddToPlaylist: (track) => _showAddToPlaylist(
                      context,
                      track,
                    ),
                    onLyrics: (track) => _showLyricsEditor(
                      context,
                      track,
                    ),
                  ),
                  const _HistoryTab(),
                  const _SourcesTab(),
                  const _SettingsTab(),
                ],
              ),
            ),
            PlayerBar(
              onOpenQueue: () => _showQueue(context),
              onSaveQueue: () => _saveQueueAsPlaylist(context),
              onOpenLyrics: () => _showNowPlayingLyrics(context),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.my_library_music_outlined),
            selectedIcon: Icon(Icons.my_library_music),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_play_outlined),
            selectedIcon: Icon(Icons.playlist_play),
            label: 'Playlists',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension_outlined),
            selectedIcon: Icon(Icons.extension),
            label: 'Sources',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Options',
          ),
        ],
      ),
    );
  }

  Future<void> _showAddToPlaylist(BuildContext context, Track track) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    if (library.playlists.isEmpty) {
      await _createPlaylist(context, seedTrack: track);
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('New playlist'),
                subtitle: Text('Create a playlist with ${track.title}.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _createPlaylist(context, seedTrack: track);
                },
              ),
              const Divider(height: 1),
              for (final playlist in library.playlists)
                ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(playlist.name),
                  subtitle: Text('${playlist.trackCount} track(s)'),
                  enabled: !playlist.containsTrack(track.id),
                  onTap: playlist.containsTrack(track.id)
                      ? null
                      : () async {
                          Navigator.of(sheetContext).pop();
                          await library.addTrackToPlaylist(
                            playlist.id,
                            track.id,
                          );

                          if (!context.mounted) {
                            return;
                          }

                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Added to ${playlist.name}.'),
                            ),
                          );
                        },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showLyricsEditor(BuildContext context, Track track) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final existingLyrics = library.lyricsForTrack(track.id)?.plainText ?? '';
    final plainText = await _promptForLyrics(
      context,
      track: track,
      initialValue: existingLyrics,
    );

    if (!context.mounted || plainText == null) {
      return;
    }

    await library.setLyrics(track.id, plainText);

    if (!context.mounted) {
      return;
    }

    final saved = plainText.trim().isNotEmpty;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Saved lyrics for ${track.title}.' : 'Removed lyrics.',
        ),
      ),
    );
  }

  Future<String?> _promptForLyrics(
    BuildContext context, {
    required Track track,
    required String initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue);

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final syncedLines = parseSyncedLyricLines(controller.text);

              return AlertDialog(
                title: Text(track.title),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextField(
                          autofocus: initialValue.isEmpty,
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: 'Lyrics',
                          ),
                          keyboardType: TextInputType.multiline,
                          minLines: 8,
                          maxLines: 14,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                        if (syncedLines.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _SyncedLyricsPreview(lines: syncedLines),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  if (initialValue.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(''),
                      child: const Text('Delete'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(controller.text);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createPlaylist(
    BuildContext context, {
    Track? seedTrack,
  }) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptForPlaylistName(context);
    if (!context.mounted || name == null) {
      return;
    }

    final playlist = await library.createPlaylist(
      name,
      trackIds: seedTrack == null ? const <String>[] : <String>[seedTrack.id],
    );

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Created ${playlist.name}.')),
    );
  }

  Future<void> _saveQueueAsPlaylist(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final player = context.read<PlayerController>();
    final messenger = ScaffoldMessenger.of(context);
    final queue = player.queue;
    if (queue.isEmpty) {
      return;
    }

    final name = await _promptForPlaylistName(
      context,
      title: 'Save queue as playlist',
    );
    if (!context.mounted || name == null) {
      return;
    }

    final playlist = await library.createPlaylist(
      name,
      trackIds: queue.map((track) => track.id),
    );

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Saved queue as ${playlist.name}.')),
    );
  }

  Future<void> _showQueue(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _QueueSheet(),
    );
  }

  Future<void> _showNowPlayingLyrics(BuildContext context) async {
    final player = context.read<PlayerController>();
    final library = context.read<LibraryStore>();
    final track = player.current;
    if (track == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return _NowPlayingLyricsSheet(
          track: track,
          lyrics: library.lyricsForTrack(track.id),
          player: player,
          onEdit: () {
            Navigator.of(sheetContext).pop();
            unawaited(_showLyricsEditor(context, track));
          },
        );
      },
    );
  }

  Future<String?> _promptForPlaylistName(
    BuildContext context, {
    String title = 'New playlist',
  }) async {
    final controller = TextEditingController();

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Playlist name',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                final normalized = value.trim();
                if (normalized.isNotEmpty) {
                  Navigator.of(dialogContext).pop(normalized);
                }
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final normalized = controller.text.trim();
                  if (normalized.isNotEmpty) {
                    Navigator.of(dialogContext).pop(normalized);
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _importAudio(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.audio,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final tracks = result.files
        .where((file) => file.path != null)
        .map(
          (file) => Track(
            id: Track.stableLocalId(file.path!),
            title: p.basenameWithoutExtension(file.name),
            artist: 'Local File',
            album: p.dirname(file.path!),
            localPath: file.path,
            sourceId: 'local',
            addedAt: now,
          ),
        )
        .toList(growable: false);

    await library.addTracks(tracks);

    messenger.showSnackBar(
      SnackBar(content: Text('Imported ${tracks.length} audio file(s).')),
    );
  }

  Future<void> _showSleepTimer(BuildContext context) async {
    final player = context.read<PlayerController>();
    final durations = <int>[5, 15, 30, 60, 90];
    var fadeOut = player.sleepTimerFadeOutEnabled;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  SwitchListTile(
                    secondary: const Icon(Icons.volume_down_outlined),
                    title: const Text('Fade out before stopping'),
                    subtitle: const Text(
                      'Lower volume during the final 30 seconds.',
                    ),
                    value: fadeOut,
                    onChanged: (value) {
                      setSheetState(() {
                        fadeOut = value;
                      });
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.timer_off_outlined),
                    title: const Text('Cancel sleep timer'),
                    onTap: () {
                      player.cancelSleepTimer();
                      Navigator.of(sheetContext).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Custom duration'),
                    subtitle: const Text(
                      'Choose any duration from 1 minute to 24 hours.',
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _showCustomSleepTimer(
                        context,
                        player,
                        fadeOut: fadeOut,
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: const Text('Stop at end of current track'),
                    subtitle: const Text(
                      'Finish this track, then stop playback.',
                    ),
                    enabled: player.current != null,
                    onTap: player.current == null
                        ? null
                        : () {
                            player.stopAtEndOfTrack();
                            Navigator.of(sheetContext).pop();
                          },
                  ),
                  for (final minutes in durations)
                    ListTile(
                      leading: const Icon(Icons.bedtime_outlined),
                      title: Text('Stop playback in $minutes minutes'),
                      subtitle: fadeOut
                          ? const Text('Fade out in the final 30 seconds.')
                          : null,
                      onTap: () {
                        player.startSleepTimer(
                          Duration(minutes: minutes),
                          fadeOut: fadeOut,
                        );
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCustomSleepTimer(
    BuildContext context,
    PlayerController player, {
    required bool fadeOut,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final duration = await _promptForCustomSleepTimerDuration(context);
    if (!context.mounted || duration == null) {
      return;
    }

    player.startSleepTimer(duration, fadeOut: fadeOut);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          fadeOut
              ? 'Sleep timer set for ${duration.inMinutes} minute(s) '
                  'with fade-out.'
              : 'Sleep timer set for ${duration.inMinutes} minute(s).',
        ),
      ),
    );
  }

  Future<Duration?> _promptForCustomSleepTimerDuration(
    BuildContext context,
  ) async {
    final controller = TextEditingController();
    String? errorText;

    try {
      return showDialog<Duration>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              void submit(String value) {
                final duration = parseCustomSleepTimerDuration(value);
                if (duration == null) {
                  setDialogState(() {
                    errorText = 'Enter a whole number from '
                        '$minCustomSleepTimerMinutes to '
                        '$maxCustomSleepTimerMinutes.';
                  });
                  return;
                }

                Navigator.of(dialogContext).pop(duration);
              }

              return AlertDialog(
                title: const Text('Custom sleep timer'),
                content: TextField(
                  autofocus: true,
                  controller: controller,
                  decoration: InputDecoration(
                    errorText: errorText,
                    helperText: '$minCustomSleepTimerMinutes to '
                        '$maxCustomSleepTimerMinutes minutes',
                    labelText: 'Minutes',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: submit,
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      submit(controller.text);
                    },
                    child: const Text('Start'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}

class _TrackMetadataDraft {
  const _TrackMetadataDraft({
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
  });

  final String title;
  final String artist;
  final String album;
  final String genre;
}

Future<void> _showTrackMetadataEditor(
  BuildContext context,
  Track track,
) async {
  final library = context.read<LibraryStore>();
  final messenger = ScaffoldMessenger.of(context);
  final draft = await _promptForTrackMetadata(context, track);

  if (!context.mounted || draft == null) {
    return;
  }

  final updated = await library.updateTrackMetadata(
    track.id,
    title: draft.title,
    artist: draft.artist,
    album: draft.album,
    genre: draft.genre,
  );

  if (!context.mounted) {
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        updated == null
            ? 'Track is no longer in the library.'
            : 'Saved metadata for ${updated.title}.',
      ),
    ),
  );
}

Future<_TrackMetadataDraft?> _promptForTrackMetadata(
  BuildContext context,
  Track track,
) async {
  final titleController = TextEditingController(text: track.title);
  final artistController = TextEditingController(text: track.artist);
  final albumController = TextEditingController(text: track.album);
  final genreController = TextEditingController(text: track.genre);
  String? titleErrorText;

  try {
    return showDialog<_TrackMetadataDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void submit() {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                setDialogState(() {
                  titleErrorText = 'Title is required';
                });
                return;
              }

              Navigator.of(dialogContext).pop(
                _TrackMetadataDraft(
                  title: title,
                  artist: artistController.text,
                  album: albumController.text,
                  genre: genreController.text,
                ),
              );
            }

            return AlertDialog(
              title: const Text('Edit metadata'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        autofocus: true,
                        controller: titleController,
                        decoration: InputDecoration(
                          errorText: titleErrorText,
                          labelText: 'Title',
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (titleErrorText != null) {
                            setDialogState(() {
                              titleErrorText = null;
                            });
                          }
                        },
                      ),
                      TextField(
                        controller: artistController,
                        decoration: const InputDecoration(labelText: 'Artist'),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: albumController,
                        decoration: const InputDecoration(labelText: 'Album'),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: genreController,
                        decoration: const InputDecoration(labelText: 'Genre'),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  } finally {
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    genreController.dispose();
  }
}

class _SyncedLyricsPreview extends StatelessWidget {
  const _SyncedLyricsPreview({required this.lines});

  final List<SyncedLyricLine> lines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timestampStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colorScheme.primary,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 180,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: lines.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final line = lines[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 48,
                    child: Text(
                      formatSyncedLyricTimestamp(line.timestamp),
                      textAlign: TextAlign.end,
                      style: timestampStyle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(line.text)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

}

class _NowPlayingLyricsSheet extends StatelessWidget {
  const _NowPlayingLyricsSheet({
    required this.track,
    required this.lyrics,
    required this.player,
    required this.onEdit,
  });

  final Track track;
  final TrackLyrics? lyrics;
  final PlayerController player;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final currentLyrics = lyrics;
    if (currentLyrics == null || currentLyrics.isEmpty) {
      return _EmptyNowPlayingLyrics(track: track, onEdit: onEdit);
    }

    final syncedLines = currentLyrics.syncedLines;
    if (syncedLines.isEmpty) {
      return _PlainNowPlayingLyrics(
        track: track,
        lyrics: currentLyrics.plainText,
        onEdit: onEdit,
      );
    }

    return _SyncedNowPlayingLyrics(
      track: track,
      lines: syncedLines,
      player: player,
      onEdit: onEdit,
    );
  }
}

class _EmptyNowPlayingLyrics extends StatelessWidget {
  const _EmptyNowPlayingLyrics({
    required this.track,
    required this.onEdit,
  });

  final Track track;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          _NowPlayingLyricsHeader(
            track: track,
            subtitle: 'No lyrics saved',
            onEdit: onEdit,
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.subtitles_outlined),
            title: Text('No lyrics yet'),
            subtitle: Text('Add plain lyrics or paste LRC timestamped lyrics.'),
          ),
        ],
      ),
    );
  }
}

class _PlainNowPlayingLyrics extends StatelessWidget {
  const _PlainNowPlayingLyrics({
    required this.track,
    required this.lyrics,
    required this.onEdit,
  });

  final Track track;
  final String lyrics;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            children: <Widget>[
              _NowPlayingLyricsHeader(
                track: track,
                subtitle: 'Plain lyrics',
                onEdit: onEdit,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(lyrics),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SyncedNowPlayingLyrics extends StatefulWidget {
  const _SyncedNowPlayingLyrics({
    required this.track,
    required this.lines,
    required this.player,
    required this.onEdit,
  });

  final Track track;
  final List<SyncedLyricLine> lines;
  final PlayerController player;
  final VoidCallback onEdit;

  @override
  State<_SyncedNowPlayingLyrics> createState() =>
      _SyncedNowPlayingLyricsState();
}

class _SyncedNowPlayingLyricsState extends State<_SyncedNowPlayingLyrics> {
  static const _estimatedLineExtent = 72.0;
  int _lastScrolledIndex = -1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return StreamBuilder<Duration>(
            stream: widget.player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final activeIndex = syncedLyricLineIndexAt(
                widget.lines,
                position,
              );
              _scrollToActiveLine(controller, activeIndex);

              return ListView.separated(
                controller: controller,
                itemCount: widget.lines.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _NowPlayingLyricsHeader(
                      track: widget.track,
                      subtitle: activeIndex == -1
                          ? 'Synced lyrics'
                          : 'Line ${activeIndex + 1} of ${widget.lines.length}',
                      onEdit: widget.onEdit,
                    );
                  }

                  final lineIndex = index - 1;
                  final line = widget.lines[lineIndex];
                  return _SyncedNowPlayingLyricLine(
                    line: line,
                    isActive: lineIndex == activeIndex,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _scrollToActiveLine(ScrollController controller, int activeIndex) {
    if (activeIndex < 0 || activeIndex == _lastScrolledIndex) {
      return;
    }

    _lastScrolledIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) {
        return;
      }

      final targetOffset = (activeIndex * _estimatedLineExtent).clamp(
        0.0,
        controller.position.maxScrollExtent,
      ).toDouble();
      controller.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}

class _NowPlayingLyricsHeader extends StatelessWidget {
  const _NowPlayingLyricsHeader({
    required this.track,
    required this.subtitle,
    required this.onEdit,
  });

  final Track track;
  final String subtitle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.subtitles_outlined),
      title: Text(track.title),
      subtitle: Text('${track.artist} · $subtitle'),
      trailing: IconButton(
        tooltip: 'Edit lyrics',
        onPressed: onEdit,
        icon: const Icon(Icons.edit_outlined),
      ),
    );
  }
}

class _SyncedNowPlayingLyricLine extends StatelessWidget {
  const _SyncedNowPlayingLyricLine({
    required this.line,
    required this.isActive,
  });

  final SyncedLyricLine line;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final backgroundColor = isActive
        ? colorScheme.primaryContainer
        : Colors.transparent;
    final textStyle = isActive
        ? textTheme.titleMedium?.copyWith(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          )
        : textTheme.bodyLarge;

    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 52,
              child: Text(
                formatSyncedLyricTimestamp(line.timestamp),
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                line.text,
                style: textStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final queue = player.queue;
    final current = player.current;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.queue_music),
            title: const Text('Queue'),
            subtitle: Text('${queue.length} track(s)'),
          ),
          const Divider(height: 1),
          if (queue.isEmpty)
            const ListTile(
              leading: Icon(Icons.queue_music_outlined),
              title: Text('Queue is empty'),
              subtitle: Text('Play tracks from Library, Playlists, or History.'),
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
      leading: Icon(
        isCurrent ? Icons.graphic_eq : Icons.music_note_outlined,
      ),
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

class _LibraryTab extends StatelessWidget {
  const _LibraryTab({
    required this.searchController,
    required this.query,
    required this.favoritesOnly,
    required this.offlineOnly,
    required this.sortMode,
    required this.onQueryChanged,
    required this.onQuerySubmitted,
    required this.onFavoritesOnlyChanged,
    required this.onOfflineOnlyChanged,
    required this.onSortModeChanged,
    required this.onImport,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final TextEditingController searchController;
  final String query;
  final bool favoritesOnly;
  final bool offlineOnly;
  final LibrarySortMode sortMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onQuerySubmitted;
  final ValueChanged<bool> onFavoritesOnlyChanged;
  final ValueChanged<bool> onOfflineOnlyChanged;
  final ValueChanged<LibrarySortMode> onSortModeChanged;
  final VoidCallback onImport;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final tracks = library.search(
      query,
      favoritesOnly: favoritesOnly,
      offlineOnly: offlineOnly,
      sortMode: sortMode,
    );
    final suggestions = library.searchSuggestions(query);

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: searchController,
            hintText: 'Search title, artist, album, or genre',
            leading: const Icon(Icons.search),
            trailing: <Widget>[
              PopupMenuButton<LibrarySortMode>(
                tooltip: 'Sort library',
                icon: const Icon(Icons.sort),
                initialValue: sortMode,
                onSelected: onSortModeChanged,
                itemBuilder: (context) => LibrarySortMode.values
                    .map(
                      (mode) => PopupMenuItem<LibrarySortMode>(
                        value: mode,
                        child: ListTile(
                          leading: Icon(_librarySortIcon(mode)),
                          title: Text(_librarySortLabel(mode)),
                          trailing: mode == sortMode
                              ? const Icon(Icons.check)
                              : null,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              IconButton(
                tooltip: favoritesOnly ? 'Showing favorites' : 'Show favorites',
                onPressed: () => onFavoritesOnlyChanged(!favoritesOnly),
                icon: Icon(
                  favoritesOnly ? Icons.favorite : Icons.favorite_border,
                ),
              ),
              IconButton(
                tooltip: offlineOnly
                    ? 'Showing local files only'
                    : 'Show local files only',
                onPressed: () => onOfflineOnlyChanged(!offlineOnly),
                icon: Icon(
                  offlineOnly ? Icons.cloud_off : Icons.cloud_off_outlined,
                ),
              ),
            ],
            onChanged: onQueryChanged,
            onSubmitted: onQuerySubmitted,
          ),
        ),
        if (suggestions.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final suggestion in suggestions) ...[
                  ActionChip(
                    avatar: Icon(_searchSuggestionIcon(suggestion.type)),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        suggestion.value,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    tooltip: 'Search ${suggestion.value}',
                    onPressed: () {
                      searchController
                        ..text = suggestion.value
                        ..selection = TextSelection.collapsed(
                          offset: suggestion.value.length,
                        );
                      onQueryChanged(suggestion.value);
                      onQuerySubmitted(suggestion.value);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        SizedBox(
          height: 48,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final type in LibraryBrowseType.values) ...[
                ActionChip(
                  avatar: Icon(_libraryBrowseTypeIcon(type), size: 18),
                  label: Text(_libraryBrowseTypeLabel(type)),
                  onPressed: () => _showLibraryBrowseGroups(
                    context,
                    type,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        if (tracks.isEmpty)
          Expanded(
            child: _EmptyLibrary(
              favoritesOnly: favoritesOnly,
              offlineOnly: offlineOnly,
              onImport: onImport,
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: tracks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final track = tracks[index];
                return TrackTile(
                  track: track,
                  onPlay: () => _playTrackWithResume(
                    context,
                    player,
                    library,
                    track,
                    queue: tracks,
                  ),
                  onFavorite: () => library.toggleFavorite(track.id),
                  onAddToPlaylist: () => onAddToPlaylist(track),
                  onLyrics: () => onLyrics(track),
                  onEditMetadata: () => unawaited(
                    _showTrackMetadataEditor(context, track),
                  ),
                  onRemove: () => library.removeTrack(track.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

Future<void> _showLibraryBrowseGroups(
  BuildContext context,
  LibraryBrowseType type, {
  required ValueChanged<Track> onAddToPlaylist,
  required ValueChanged<Track> onLyrics,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return _LibraryBrowseGroupsSheet(
        rootContext: context,
        type: type,
        onAddToPlaylist: onAddToPlaylist,
        onLyrics: onLyrics,
      );
    },
  );
}

Future<void> _showLibraryBrowseTracks(
  BuildContext context, {
  required LibraryBrowseType type,
  required LibraryBrowseGroup group,
  required ValueChanged<Track> onAddToPlaylist,
  required ValueChanged<Track> onLyrics,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) {
      return _LibraryBrowseTracksSheet(
        type: type,
        group: group,
        onAddToPlaylist: onAddToPlaylist,
        onLyrics: onLyrics,
      );
    },
  );
}

class _LibraryBrowseGroupsSheet extends StatelessWidget {
  const _LibraryBrowseGroupsSheet({
    required this.rootContext,
    required this.type,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final BuildContext rootContext;
  final LibraryBrowseType type;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final groups = library.browseGroups(type);

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          ListTile(
            leading: Icon(_libraryBrowseTypeIcon(type)),
            title: Text(_libraryBrowseTypeLabel(type)),
            subtitle: Text('${groups.length} group(s)'),
          ),
          const Divider(height: 1),
          if (groups.isEmpty)
            ListTile(
              leading: Icon(_libraryBrowseTypeIcon(type)),
              title: const Text('Nothing to browse yet'),
              subtitle: const Text('Import local audio to build your library.'),
            )
          else
            for (final group in groups)
              ListTile(
                leading: Icon(_libraryBrowseTypeIcon(type)),
                title: Text(group.label),
                subtitle: Text(_libraryBrowseGroupSubtitle(group)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(
                    _showLibraryBrowseTracks(
                      rootContext,
                      type: type,
                      group: group,
                      onAddToPlaylist: onAddToPlaylist,
                      onLyrics: onLyrics,
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _LibraryBrowseTracksSheet extends StatelessWidget {
  const _LibraryBrowseTracksSheet({
    required this.type,
    required this.group,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final LibraryBrowseType type;
  final LibraryBrowseGroup group;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final tracks = library.tracksForBrowseGroup(type, group.key);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView.separated(
            controller: controller,
            itemCount: tracks.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: Icon(_libraryBrowseTypeIcon(type)),
                  title: Text(group.label),
                  subtitle: Text(_libraryBrowseGroupSubtitle(group)),
                );
              }

              final track = tracks[index - 1];
              return TrackTile(
                track: track,
                onPlay: () => _playTrackWithResume(
                  context,
                  player,
                  library,
                  track,
                  queue: tracks,
                ),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
                onEditMetadata: () => unawaited(
                  _showTrackMetadataEditor(context, track),
                ),
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
  }
}

IconData _searchSuggestionIcon(SearchSuggestionType type) {
  switch (type) {
    case SearchSuggestionType.query:
      return Icons.manage_search_outlined;
    case SearchSuggestionType.recent:
      return Icons.history;
    case SearchSuggestionType.title:
      return Icons.music_note_outlined;
    case SearchSuggestionType.artist:
      return Icons.person_outline;
    case SearchSuggestionType.album:
      return Icons.album_outlined;
    case SearchSuggestionType.genre:
      return Icons.category_outlined;
    case SearchSuggestionType.source:
      return Icons.source_outlined;
    case SearchSuggestionType.folder:
      return Icons.folder_outlined;
  }
}

String _libraryBrowseTypeLabel(LibraryBrowseType type) {
  switch (type) {
    case LibraryBrowseType.artist:
      return 'Artists';
    case LibraryBrowseType.album:
      return 'Albums';
    case LibraryBrowseType.genre:
      return 'Genres';
    case LibraryBrowseType.source:
      return 'Sources';
    case LibraryBrowseType.folder:
      return 'Folders';
  }
}

IconData _libraryBrowseTypeIcon(LibraryBrowseType type) {
  switch (type) {
    case LibraryBrowseType.artist:
      return Icons.person_outline;
    case LibraryBrowseType.album:
      return Icons.album_outlined;
    case LibraryBrowseType.genre:
      return Icons.category_outlined;
    case LibraryBrowseType.source:
      return Icons.source_outlined;
    case LibraryBrowseType.folder:
      return Icons.folder_outlined;
  }
}

String _libraryBrowseGroupSubtitle(LibraryBrowseGroup group) {
  final duration = group.totalDuration;
  final parts = <String>['${group.trackCount} track(s)'];
  if (duration > Duration.zero) {
    parts.add(_formatBrowseDuration(duration));
  }

  return parts.join(' · ');
}

String _formatBrowseDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }

  return '${minutes}m';
}

String _librarySortLabel(LibrarySortMode sortMode) {
  switch (sortMode) {
    case LibrarySortMode.recentlyAdded:
      return 'Recently added';
    case LibrarySortMode.title:
      return 'Title';
    case LibrarySortMode.artist:
      return 'Artist';
    case LibrarySortMode.album:
      return 'Album';
  }
}

IconData _librarySortIcon(LibrarySortMode sortMode) {
  switch (sortMode) {
    case LibrarySortMode.recentlyAdded:
      return Icons.new_releases_outlined;
    case LibrarySortMode.title:
      return Icons.sort_by_alpha;
    case LibrarySortMode.artist:
      return Icons.person_outline;
    case LibrarySortMode.album:
      return Icons.album_outlined;
  }
}

String _playlistDocumentFormatLabel(PlaylistDocumentFormat format) {
  switch (format) {
    case PlaylistDocumentFormat.json:
      return 'JSON';
    case PlaylistDocumentFormat.m3u:
      return 'M3U';
    case PlaylistDocumentFormat.csv:
      return 'CSV';
  }
}

String _playlistDocumentFormatExtension(PlaylistDocumentFormat format) {
  switch (format) {
    case PlaylistDocumentFormat.json:
      return 'JSON';
    case PlaylistDocumentFormat.m3u:
      return 'M3U';
    case PlaylistDocumentFormat.csv:
      return 'CSV';
  }
}

IconData _playlistDocumentFormatIcon(PlaylistDocumentFormat format) {
  switch (format) {
    case PlaylistDocumentFormat.json:
      return Icons.data_object;
    case PlaylistDocumentFormat.m3u:
      return Icons.queue_music;
    case PlaylistDocumentFormat.csv:
      return Icons.table_chart_outlined;
  }
}

IconData _smartPlaylistIcon(SmartPlaylistType type) {
  switch (type) {
    case SmartPlaylistType.favorites:
      return Icons.favorite_border;
    case SmartPlaylistType.recentlyAdded:
      return Icons.new_releases_outlined;
    case SmartPlaylistType.recentlyPlayed:
      return Icons.history;
    case SmartPlaylistType.mostPlayed:
      return Icons.trending_up;
  }
}

String _customSmartPlaylistSortLabel(CustomSmartPlaylistSortMode sortMode) {
  switch (sortMode) {
    case CustomSmartPlaylistSortMode.recentlyAdded:
      return 'Recently added';
    case CustomSmartPlaylistSortMode.title:
      return 'Title';
    case CustomSmartPlaylistSortMode.artist:
      return 'Artist';
    case CustomSmartPlaylistSortMode.album:
      return 'Album';
    case CustomSmartPlaylistSortMode.recentlyPlayed:
      return 'Recently played';
    case CustomSmartPlaylistSortMode.mostPlayed:
      return 'Most played';
  }
}

String _customSmartPlaylistSubtitle(
  CustomSmartPlaylist rule,
  int trackCount,
) {
  final parts = <String>['$trackCount track(s)'];
  if (rule.query.trim().isNotEmpty) {
    parts.add('Search: ${rule.query}');
  }
  if (rule.favoritesOnly) {
    parts.add('Favorites');
  }
  if (rule.minimumPlayCount > 0) {
    parts.add('${rule.minimumPlayCount}+ plays');
  }
  parts.add(_customSmartPlaylistSortLabel(rule.sortMode));
  parts.add('Limit ${rule.limit}');

  return parts.join(' · ');
}

class _CustomSmartPlaylistDraft {
  const _CustomSmartPlaylistDraft({
    required this.name,
    required this.query,
    required this.favoritesOnly,
    required this.minimumPlayCount,
    required this.sortMode,
    required this.limit,
  });

  final String name;
  final String query;
  final bool favoritesOnly;
  final int minimumPlayCount;
  final CustomSmartPlaylistSortMode sortMode;
  final int limit;
}

class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab({
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final smartPlaylists = library.smartPlaylists();
    final customSmartPlaylists = library.customSmartPlaylists;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Playlists',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Import playlist',
              onPressed: () => _showPlaylistImportFormatPicker(context),
              icon: const Icon(Icons.upload_file),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Create playlist',
              onPressed: () => _createPlaylist(context),
              icon: const Icon(Icons.playlist_add),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Create smart playlist',
              onPressed: () => _createCustomSmartPlaylist(context),
              icon: const Icon(Icons.filter_alt_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Built-in smart playlists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final smartPlaylist in smartPlaylists)
          _SmartPlaylistCard(
            smartPlaylist: smartPlaylist,
            onOpen: () => _showSmartPlaylist(context, smartPlaylist.type),
          ),
        const SizedBox(height: 16),
        Text(
          'Custom smart playlists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (customSmartPlaylists.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: const Text('No custom smart playlists'),
              trailing: IconButton(
                tooltip: 'Create smart playlist',
                onPressed: () => _createCustomSmartPlaylist(context),
                icon: const Icon(Icons.add),
              ),
            ),
          )
        else
          for (final rule in customSmartPlaylists)
            _CustomSmartPlaylistCard(
              rule: rule,
              trackCount: library.tracksForCustomSmartPlaylist(rule.id).length,
              onOpen: () => _showCustomSmartPlaylist(context, rule.id),
              onEdit: () => _editCustomSmartPlaylist(context, rule),
              onDelete: () => _deleteCustomSmartPlaylist(context, rule),
            ),
        const SizedBox(height: 16),
        Text(
          'Manual playlists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (library.playlists.isEmpty)
          _EmptyPlaylists(onCreate: () => _createPlaylist(context))
        else
          for (final playlist in library.playlists)
            _PlaylistCard(
              playlist: playlist,
              onOpen: () => _showPlaylist(context, playlist.id),
              onExport: (format) => _showPlaylistExport(
                context,
                playlist,
                format,
              ),
              onArtwork: () => _editPlaylistArtwork(context, playlist),
              onRename: () => _renamePlaylist(context, playlist),
              onDelete: () => _deletePlaylist(context, playlist),
            ),
      ],
    );
  }

  Future<void> _showPlaylistImportFormatPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final format in PlaylistDocumentFormat.values)
                ListTile(
                  leading: Icon(_playlistDocumentFormatIcon(format)),
                  title: Text('Import ${_playlistDocumentFormatLabel(format)}'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _importPlaylist(context, format);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importPlaylist(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final document = await _promptForPlaylistDocument(context, format);
    if (!context.mounted || document == null) {
      return;
    }

    try {
      final playlist = await library.importPlaylistDocument(
        document,
        format: format,
      );

      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Imported ${playlist.name}.')),
      );
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<String?> _promptForPlaylistDocument(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    final controller = TextEditingController();

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Import ${_playlistDocumentFormatLabel(format)}'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                autofocus: true,
                controller: controller,
                decoration: InputDecoration(
                  labelText:
                      '${_playlistDocumentFormatExtension(format)} content',
                ),
                keyboardType: TextInputType.multiline,
                minLines: 8,
                maxLines: 14,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text,
                ),
                child: const Text('Import'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptForPlaylistName(context, title: 'New playlist');
    if (!context.mounted || name == null) {
      return;
    }

    final playlist = await library.createPlaylist(name);
    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Created ${playlist.name}.')),
    );
  }

  Future<void> _createCustomSmartPlaylist(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final draft = await _promptForCustomSmartPlaylistRule(
      context,
      title: 'New smart playlist',
    );
    if (!context.mounted || draft == null) {
      return;
    }

    final rule = await library.createCustomSmartPlaylist(
      name: draft.name,
      query: draft.query,
      favoritesOnly: draft.favoritesOnly,
      minimumPlayCount: draft.minimumPlayCount,
      sortMode: draft.sortMode,
      limit: draft.limit,
    );
    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Created ${rule.name}.')),
    );
  }

  Future<void> _editCustomSmartPlaylist(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final library = context.read<LibraryStore>();
    final draft = await _promptForCustomSmartPlaylistRule(
      context,
      title: 'Edit smart playlist',
      initialRule: rule,
    );
    if (!context.mounted || draft == null) {
      return;
    }

    await library.updateCustomSmartPlaylist(
      rule.id,
      name: draft.name,
      query: draft.query,
      favoritesOnly: draft.favoritesOnly,
      minimumPlayCount: draft.minimumPlayCount,
      sortMode: draft.sortMode,
      limit: draft.limit,
    );
  }

  Future<void> _deleteCustomSmartPlaylist(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.deleteCustomSmartPlaylist(rule.id);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${rule.name}.')),
    );
  }

  Future<void> _renamePlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    final library = context.read<LibraryStore>();
    final name = await _promptForPlaylistName(
      context,
      title: 'Rename playlist',
      initialValue: playlist.name,
    );
    if (!context.mounted || name == null) {
      return;
    }

    await library.renamePlaylist(playlist.id, name);
  }

  Future<void> _editPlaylistArtwork(
    BuildContext context,
    Playlist playlist,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final value = await _promptForPlaylistArtwork(
      context,
      playlist.artworkUri?.toString() ?? '',
    );
    if (!context.mounted || value == null) {
      return;
    }

    final normalized = value.trim();
    Uri? artworkUri;
    if (normalized.isNotEmpty) {
      artworkUri = Uri.tryParse(normalized);
      if (artworkUri == null || !_isNetworkImageUri(artworkUri)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Enter an http or https image URL.')),
        );
        return;
      }
    }

    final updated = await library.updatePlaylistArtwork(
      playlist.id,
      artworkUri,
    );
    if (!context.mounted || updated == null) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          artworkUri == null
              ? 'Removed artwork for ${updated.name}.'
              : 'Updated artwork for ${updated.name}.',
        ),
      ),
    );
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.deletePlaylist(playlist.id);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${playlist.name}.')),
    );
  }

  Future<void> _showPlaylistExport(
    BuildContext context,
    Playlist playlist,
    PlaylistDocumentFormat format,
  ) async {
    final library = context.read<LibraryStore>();
    final document = library.exportPlaylistDocument(
      playlist.id,
      format: format,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Export ${_playlistDocumentFormatLabel(format)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(document),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSmartPlaylist(
    BuildContext context,
    SmartPlaylistType type,
  ) async {
    final player = context.read<PlayerController>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return _SmartPlaylistSheet(
          type: type,
          player: player,
          onAddToPlaylist: onAddToPlaylist,
          onLyrics: onLyrics,
        );
      },
    );
  }

  Future<void> _showCustomSmartPlaylist(
    BuildContext context,
    String ruleId,
  ) async {
    final player = context.read<PlayerController>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return _CustomSmartPlaylistSheet(
          ruleId: ruleId,
          player: player,
          onAddToPlaylist: onAddToPlaylist,
          onLyrics: onLyrics,
        );
      },
    );
  }

  Future<void> _showPlaylist(BuildContext context, String playlistId) async {
    final player = context.read<PlayerController>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return _PlaylistSheet(
          playlistId: playlistId,
          player: player,
        );
      },
    );
  }

  Future<String?> _promptForPlaylistName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Playlist name',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                final normalized = value.trim();
                if (normalized.isNotEmpty) {
                  Navigator.of(dialogContext).pop(normalized);
                }
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final normalized = controller.text.trim();
                  if (normalized.isNotEmpty) {
                    Navigator.of(dialogContext).pop(normalized);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _promptForPlaylistArtwork(
    BuildContext context,
    String initialValue,
  ) async {
    final controller = TextEditingController(text: initialValue);

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Playlist artwork'),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                hintText: 'https://example.com/cover.jpg',
              ),
              autofillHints: const <String>[AutofillHints.url],
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value);
              },
            ),
            actions: <Widget>[
              if (initialValue.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(''),
                  child: const Text('Clear'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text,
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<_CustomSmartPlaylistDraft?> _promptForCustomSmartPlaylistRule(
    BuildContext context, {
    required String title,
    CustomSmartPlaylist? initialRule,
  }) async {
    final nameController = TextEditingController(text: initialRule?.name ?? '');
    final queryController = TextEditingController(
      text: initialRule?.query ?? '',
    );
    final minimumPlayCountController = TextEditingController(
      text: (initialRule?.minimumPlayCount ?? 0).toString(),
    );
    final limitController = TextEditingController(
      text: (initialRule?.limit ?? 50).toString(),
    );
    var favoritesOnly = initialRule?.favoritesOnly ?? false;
    var sortMode =
        initialRule?.sortMode ?? CustomSmartPlaylistSortMode.recentlyAdded;

    try {
      return showDialog<_CustomSmartPlaylistDraft>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              _CustomSmartPlaylistDraft? draftFromControllers() {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  return null;
                }

                return _CustomSmartPlaylistDraft(
                  name: name,
                  query: queryController.text.trim(),
                  favoritesOnly: favoritesOnly,
                  minimumPlayCount:
                      int.tryParse(minimumPlayCountController.text.trim()) ??
                          0,
                  sortMode: sortMode,
                  limit: int.tryParse(limitController.text.trim()) ?? 50,
                );
              }

              return AlertDialog(
                title: Text(title),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextField(
                          autofocus: true,
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: queryController,
                          decoration: const InputDecoration(
                            labelText: 'Search text',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Favorites only'),
                          value: favoritesOnly,
                          onChanged: (value) {
                            setDialogState(() => favoritesOnly = value);
                          },
                        ),
                        TextField(
                          controller: minimumPlayCountController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum plays',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                        DropdownButtonFormField<CustomSmartPlaylistSortMode>(
                          initialValue: sortMode,
                          decoration: const InputDecoration(
                            labelText: 'Sort by',
                          ),
                          items: CustomSmartPlaylistSortMode.values
                              .map(
                                (mode) => DropdownMenuItem(
                                  value: mode,
                                  child: Text(
                                    _customSmartPlaylistSortLabel(mode),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => sortMode = value);
                            }
                          },
                        ),
                        TextField(
                          controller: limitController,
                          decoration: const InputDecoration(
                            labelText: 'Result limit',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final draft = draftFromControllers();
                      if (draft != null) {
                        Navigator.of(dialogContext).pop(draft);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameController.dispose();
      queryController.dispose();
      minimumPlayCountController.dispose();
      limitController.dispose();
    }
  }
}

class _SmartPlaylistSheet extends StatelessWidget {
  const _SmartPlaylistSheet({
    required this.type,
    required this.player,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final SmartPlaylistType type;
  final PlayerController player;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final smartPlaylist = library.smartPlaylists().firstWhere(
      (playlist) => playlist.type == type,
    );
    final tracks = library.tracksForSmartPlaylist(type);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView.separated(
            controller: controller,
            itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: Icon(_smartPlaylistIcon(type)),
                  title: Text(smartPlaylist.name),
                  subtitle: Text('${smartPlaylist.trackCount} track(s)'),
                  trailing: FilledButton.tonalIcon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _playTrackWithResume(
                              context,
                              player,
                              library,
                              tracks.first,
                              queue: tracks,
                            );
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                );
              }

              if (tracks.isEmpty) {
                return ListTile(
                  leading: Icon(_smartPlaylistIcon(type)),
                  title: const Text('No tracks yet'),
                  subtitle: Text(smartPlaylist.description),
                );
              }

              final track = tracks[index - 1];
              return TrackTile(
                track: track,
                onPlay: () => _playTrackWithResume(
                  context,
                  player,
                  library,
                  track,
                  queue: tracks,
                ),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
                onEditMetadata: () => unawaited(
                  _showTrackMetadataEditor(context, track),
                ),
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _CustomSmartPlaylistSheet extends StatelessWidget {
  const _CustomSmartPlaylistSheet({
    required this.ruleId,
    required this.player,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final String ruleId;
  final PlayerController player;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final rule = library.customSmartPlaylistById(ruleId);
    if (rule == null) {
      return const SizedBox.shrink();
    }

    final tracks = library.tracksForCustomSmartPlaylist(ruleId);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView.separated(
            controller: controller,
            itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.filter_alt_outlined),
                  title: Text(rule.name),
                  subtitle: Text(
                    _customSmartPlaylistSubtitle(rule, tracks.length),
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _playTrackWithResume(
                              context,
                              player,
                              library,
                              tracks.first,
                              queue: tracks,
                            );
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                );
              }

              if (tracks.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.filter_alt_outlined),
                  title: Text('No matching tracks'),
                );
              }

              final track = tracks[index - 1];
              return TrackTile(
                track: track,
                onPlay: () => _playTrackWithResume(
                  context,
                  player,
                  library,
                  track,
                  queue: tracks,
                ),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
                onEditMetadata: () => unawaited(
                  _showTrackMetadataEditor(context, track),
                ),
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistSheet extends StatefulWidget {
  const _PlaylistSheet({
    required this.playlistId,
    required this.player,
  });

  final String playlistId;
  final PlayerController player;

  @override
  State<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends State<_PlaylistSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryStore>(
      builder: (context, library, _) {
        final playlist = library.playlistById(widget.playlistId);
        if (playlist == null) {
          return const SizedBox.shrink();
        }

        final allTracks = library.tracksForPlaylist(widget.playlistId);
        final tracks = library.tracksForPlaylist(
          widget.playlistId,
          query: _query,
        );
        final trackEntries = tracks
            .map(
              (track) => MapEntry<int, Track>(
                allTracks.indexWhere((candidate) => candidate.id == track.id),
                track,
              ),
            )
            .where((entry) => entry.key != -1)
            .toList(growable: false);
        final hasQuery = _query.trim().isNotEmpty;

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: _PlaylistArtwork(playlist: playlist, size: 48),
                title: Text(playlist.name),
                subtitle: Text(
                  hasQuery
                      ? '${tracks.length} of ${playlist.trackCount} track(s)'
                      : '${playlist.trackCount} track(s)',
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: tracks.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _playTrackWithResume(
                            context,
                            widget.player,
                            library,
                            tracks.first,
                            queue: tracks,
                          );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              if (allTracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Find in playlist',
                    leading: const Icon(Icons.search),
                    trailing: <Widget>[
                      if (hasQuery)
                        IconButton(
                          tooltip: 'Clear playlist search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              const Divider(height: 1),
              if (allTracks.isEmpty)
                const ListTile(
                  leading: Icon(Icons.playlist_remove),
                  title: Text('No tracks yet'),
                  subtitle: Text('Add tracks from the Library tab.'),
                )
              else if (trackEntries.isEmpty)
                const ListTile(
                  leading: Icon(Icons.search_off),
                  title: Text('No matching tracks'),
                  subtitle: Text('Try another title, artist, or album.'),
                )
              else
                for (final entry in trackEntries)
                  ListTile(
                    leading: const Icon(Icons.music_note_outlined),
                    title: Text(entry.value.title),
                    subtitle: Text(
                      '${entry.value.artist} · ${entry.value.album}',
                    ),
                    trailing: PopupMenuButton<_PlaylistTrackAction>(
                      onSelected: (action) {
                        switch (action) {
                          case _PlaylistTrackAction.moveUp:
                            library.moveTrackInPlaylist(
                              playlist.id,
                              entry.key,
                              entry.key - 1,
                            );
                            break;
                          case _PlaylistTrackAction.moveDown:
                            library.moveTrackInPlaylist(
                              playlist.id,
                              entry.key,
                              entry.key + 1,
                            );
                            break;
                          case _PlaylistTrackAction.editMetadata:
                            unawaited(
                              _showTrackMetadataEditor(context, entry.value),
                            );
                            break;
                          case _PlaylistTrackAction.remove:
                            library.removeTrackFromPlaylist(
                              playlist.id,
                              entry.value.id,
                            );
                            break;
                        }
                      },
                      itemBuilder: (context) =>
                          <PopupMenuEntry<_PlaylistTrackAction>>[
                        PopupMenuItem(
                          value: _PlaylistTrackAction.moveUp,
                          enabled: entry.key > 0,
                          child: const ListTile(
                            leading: Icon(Icons.arrow_upward),
                            title: Text('Move up'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _PlaylistTrackAction.moveDown,
                          enabled: entry.key < allTracks.length - 1,
                          child: const ListTile(
                            leading: Icon(Icons.arrow_downward),
                            title: Text('Move down'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _PlaylistTrackAction.editMetadata,
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Edit metadata'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _PlaylistTrackAction.remove,
                          child: ListTile(
                            leading: Icon(Icons.playlist_remove),
                            title: Text('Remove from playlist'),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

}

class _SmartPlaylistCard extends StatelessWidget {
  const _SmartPlaylistCard({
    required this.smartPlaylist,
    required this.onOpen,
  });

  final SmartPlaylist smartPlaylist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_smartPlaylistIcon(smartPlaylist.type)),
        title: Text(smartPlaylist.name),
        subtitle: Text(
          '${smartPlaylist.trackCount} track(s) · '
          '${smartPlaylist.description}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _CustomSmartPlaylistCard extends StatelessWidget {
  const _CustomSmartPlaylistCard({
    required this.rule,
    required this.trackCount,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomSmartPlaylist rule;
  final int trackCount;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.filter_alt_outlined),
        title: Text(rule.name),
        subtitle: Text(_customSmartPlaylistSubtitle(rule, trackCount)),
        onTap: onOpen,
        trailing: PopupMenuButton<_CustomSmartPlaylistAction>(
          onSelected: (action) {
            switch (action) {
              case _CustomSmartPlaylistAction.edit:
                onEdit();
                break;
              case _CustomSmartPlaylistAction.delete:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) =>
              const <PopupMenuEntry<_CustomSmartPlaylistAction>>[
            PopupMenuItem(
              value: _CustomSmartPlaylistAction.edit,
              child: ListTile(
                leading: Icon(Icons.tune),
                title: Text('Edit rules'),
              ),
            ),
            PopupMenuItem(
              value: _CustomSmartPlaylistAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.onOpen,
    required this.onExport,
    required this.onArtwork,
    required this.onRename,
    required this.onDelete,
  });

  final Playlist playlist;
  final VoidCallback onOpen;
  final ValueChanged<PlaylistDocumentFormat> onExport;
  final VoidCallback onArtwork;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _PlaylistArtwork(playlist: playlist),
        title: Text(playlist.name),
        subtitle: Text('${playlist.trackCount} track(s)'),
        onTap: onOpen,
        trailing: PopupMenuButton<_PlaylistAction>(
          onSelected: (action) {
            switch (action) {
              case _PlaylistAction.exportJson:
                onExport(PlaylistDocumentFormat.json);
                break;
              case _PlaylistAction.exportM3u:
                onExport(PlaylistDocumentFormat.m3u);
                break;
              case _PlaylistAction.exportCsv:
                onExport(PlaylistDocumentFormat.csv);
                break;
              case _PlaylistAction.rename:
                onRename();
                break;
              case _PlaylistAction.artwork:
                onArtwork();
                break;
              case _PlaylistAction.delete:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => const <PopupMenuEntry<_PlaylistAction>>[
            PopupMenuItem(
              value: _PlaylistAction.exportJson,
              child: ListTile(
                leading: Icon(Icons.data_object),
                title: Text('Export JSON'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.exportM3u,
              child: ListTile(
                leading: Icon(Icons.queue_music),
                title: Text('Export M3U'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.exportCsv,
              child: ListTile(
                leading: Icon(Icons.table_chart_outlined),
                title: Text('Export CSV'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: _PlaylistAction.rename,
              child: ListTile(
                leading: Icon(Icons.drive_file_rename_outline),
                title: Text('Rename'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.artwork,
              child: ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Artwork'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({
    required this.playlist,
    this.size = 40,
  });

  final Playlist playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final uri = playlist.artworkUri;
    final fallback = _PlaylistArtworkFallback(size: size);
    if (uri == null || !_isNetworkImageUri(uri)) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        uri.toString(),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }

          return fallback;
        },
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

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          const Icon(Icons.queue_music, size: 56),
          const SizedBox(height: 16),
          Text(
            'No playlists yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Create manual playlists and add tracks from your library.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Create playlist'),
          ),
        ],
      ),
    );
  }
}

bool _isNetworkImageUri(Uri uri) {
  return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
}

enum _PlaylistAction {
  exportJson,
  exportM3u,
  exportCsv,
  rename,
  artwork,
  delete,
}

enum _CustomSmartPlaylistAction { edit, delete }

enum _PlaylistTrackAction { moveUp, moveDown, editMetadata, remove }

class _HistoryTab extends StatefulWidget {
  const _HistoryTab();

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  _HistoryStatsRange _statsRange = _HistoryStatsRange.all;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final now = DateTime.now();
    final statsFrom = _historyStatsRangeStart(_statsRange, now);
    final statsTo = _statsRange == _HistoryStatsRange.all ? null : now;
    final recentlyPlayed = library.recentlyPlayedTracks(
      from: statsFrom,
      to: statsTo,
    );
    final stats = library.libraryStats(from: statsFrom, to: statsTo);

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'History',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton(
              tooltip: 'Export stats',
              onPressed: () => _showStatsExportPicker(
                context,
                from: statsFrom,
                to: statsTo,
              ),
              icon: const Icon(Icons.ios_share),
            ),
            IconButton(
              tooltip: 'Clear history',
              onPressed: library.playbackHistory.isEmpty
                  ? null
                  : library.clearPlaybackHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<_HistoryStatsRange>(
          initialValue: _statsRange,
          decoration: const InputDecoration(
            labelText: 'Stats range',
            prefixIcon: Icon(Icons.date_range),
          ),
          items: <DropdownMenuItem<_HistoryStatsRange>>[
            for (final range in _HistoryStatsRange.values)
              DropdownMenuItem<_HistoryStatsRange>(
                value: range,
                child: Text(_historyStatsRangeLabel(range)),
              ),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }

            setState(() => _statsRange = value);
          },
        ),
        const SizedBox(height: 12),
        _LibraryStatsOverview(stats: stats),
        if (stats.playbackCount > 0) ...<Widget>[
          const SizedBox(height: 16),
          _LibraryStatsTrackSection(stats: stats),
          const SizedBox(height: 12),
          _LibraryStatsGroupSection(
            title: 'Top artists',
            icon: Icons.person_outline,
            groups: stats.topArtists,
          ),
          const SizedBox(height: 12),
          _LibraryStatsGroupSection(
            title: 'Top albums',
            icon: Icons.album_outlined,
            groups: stats.topAlbums,
          ),
          const SizedBox(height: 12),
          _LibraryStatsGroupSection(
            title: 'Top genres',
            icon: Icons.category_outlined,
            groups: stats.topGenres,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Recently played',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (recentlyPlayed.isEmpty)
          const _EmptyHistory()
        else
          for (final track in recentlyPlayed)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(track.title),
              subtitle: Text(
                '${track.artist} · '
                '${library.playCountForTrack(
                  track.id,
                  from: statsFrom,
                  to: statsTo,
                )} play(s)',
              ),
              trailing: Text(
                _formatHistoryTime(
                  library.lastPlayedAt(
                    track.id,
                    from: statsFrom,
                    to: statsTo,
                  ),
                ),
              ),
              onTap: () => _playTrackWithResume(
                context,
                player,
                library,
                track,
                queue: recentlyPlayed,
              ),
            ),
      ],
    );
  }

  Future<void> _showStatsExportPicker(
    BuildContext context, {
    required DateTime? from,
    required DateTime? to,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final format in LibraryStatsExportFormat.values)
                ListTile(
                  leading: Icon(_statsExportFormatIcon(format)),
                  title: Text('Export ${_statsExportFormatLabel(format)}'),
                  subtitle: Text(_historyStatsRangeLabel(_statsRange)),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _showStatsExportDocument(
                      context,
                      format: format,
                      from: from,
                      to: to,
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showStatsExportDocument(
    BuildContext context, {
    required LibraryStatsExportFormat format,
    required DateTime? from,
    required DateTime? to,
  }) async {
    final library = context.read<LibraryStore>();
    final document = library.exportLibraryStatsDocument(
      format: format,
      from: from,
      to: to,
    );

    if (!context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Export ${_statsExportFormatLabel(format)} stats'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(document),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}

enum _HistoryStatsRange { all, sevenDays, thirtyDays, year }

String _historyStatsRangeLabel(_HistoryStatsRange range) {
  switch (range) {
    case _HistoryStatsRange.all:
      return 'All time';
    case _HistoryStatsRange.sevenDays:
      return 'Last 7 days';
    case _HistoryStatsRange.thirtyDays:
      return 'Last 30 days';
    case _HistoryStatsRange.year:
      return 'Last year';
  }
}

DateTime? _historyStatsRangeStart(_HistoryStatsRange range, DateTime now) {
  switch (range) {
    case _HistoryStatsRange.all:
      return null;
    case _HistoryStatsRange.sevenDays:
      return now.subtract(const Duration(days: 7));
    case _HistoryStatsRange.thirtyDays:
      return now.subtract(const Duration(days: 30));
    case _HistoryStatsRange.year:
      return now.subtract(const Duration(days: 365));
  }
}

String _statsExportFormatLabel(LibraryStatsExportFormat format) {
  switch (format) {
    case LibraryStatsExportFormat.json:
      return 'JSON';
    case LibraryStatsExportFormat.csv:
      return 'CSV';
  }
}

IconData _statsExportFormatIcon(LibraryStatsExportFormat format) {
  switch (format) {
    case LibraryStatsExportFormat.json:
      return Icons.data_object;
    case LibraryStatsExportFormat.csv:
      return Icons.table_chart_outlined;
  }
}

class _LibraryStatsOverview extends StatelessWidget {
  const _LibraryStatsOverview({required this.stats});

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
          value: _formatStatsDuration(stats.estimatedListeningDuration),
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
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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

class _LibraryStatsTrackSection extends StatelessWidget {
  const _LibraryStatsTrackSection({required this.stats});

  final LibraryStatsSummary stats;

  @override
  Widget build(BuildContext context) {
    return _StatsSection(
      title: 'Top tracks',
      children: <Widget>[
        for (final trackStats in stats.topTracks)
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(trackStats.track.title),
            subtitle: Text(
              '${trackStats.track.artist} · '
              '${trackStats.playCount} play(s) · '
              '${_formatStatsDuration(trackStats.estimatedListeningDuration)}',
            ),
            trailing: Text(_formatHistoryTime(trackStats.lastPlayedAt)),
          ),
      ],
    );
  }
}

class _LibraryStatsGroupSection extends StatelessWidget {
  const _LibraryStatsGroupSection({
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

    return _StatsSection(
      title: title,
      children: <Widget>[
        for (final group in groups)
          ListTile(
            leading: Icon(icon),
            title: Text(group.label),
            subtitle: Text(
              '${group.playCount} play(s) · '
              '${group.trackCount} track(s) · '
              '${_formatStatsDuration(group.estimatedListeningDuration)}',
            ),
            trailing: Text(_formatHistoryTime(group.lastPlayedAt)),
          ),
      ],
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({
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
        Card(
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          const Icon(Icons.history, size: 56),
          const SizedBox(height: 16),
          Text(
            'No listening history yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Played library tracks will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _formatStatsDuration(Duration duration) {
  if (duration <= Duration.zero) {
    return '0m';
  }

  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0 && minutes > 0) {
    return '${hours}h ${minutes}m';
  }
  if (hours > 0) {
    return '${hours}h';
  }

  return '${duration.inMinutes}m';
}

String _formatHistoryTime(DateTime? value) {
  if (value == null) {
    return '';
  }

  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

bool _tracksPodcastProgress(Track track) {
  return track.genre.toLowerCase() == 'podcast' ||
      track.sourceId.startsWith('podcast-');
}

Future<void> _playTrackWithResume(
  BuildContext context,
  PlayerController player,
  LibraryStore library,
  Track track, {
  required List<Track> queue,
}) async {
  final initialPosition = _tracksPodcastProgress(track)
      ? library.playbackProgressForTrack(track.id)?.position
      : null;

  try {
    await player.playTrack(
      track,
      queue: queue,
      initialPosition: initialPosition,
    );
  } on OfflinePlaybackBlockedException catch (error) {
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(offlinePlaybackBlockedMessage(error.track))),
    );
  }
}

String _formatDurationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }

  return '${duration.inMinutes}:$seconds';
}

String _formatRefreshAge(Duration age) {
  if (age.inMinutes < 1) {
    return 'just now';
  }
  if (age.inHours < 1) {
    return '${age.inMinutes}m ago';
  }
  if (age.inDays < 1) {
    return '${age.inHours}h ago';
  }

  return '${age.inDays}d ago';
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.favoritesOnly,
    required this.offlineOnly,
    required this.onImport,
  });

  final bool favoritesOnly;
  final bool offlineOnly;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.music_note, size: 56),
            const SizedBox(height: 16),
            Text(
              _emptyLibraryTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _emptyLibrarySubtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.library_add),
              label: const Text('Import audio'),
            ),
          ],
        ),
      ),
    );
  }

  String get _emptyLibraryTitle {
    if (offlineOnly) {
      return 'No local files match';
    }

    if (favoritesOnly) {
      return 'No favorite tracks yet';
    }

    return 'Your library is empty';
  }

  String get _emptyLibrarySubtitle {
    if (offlineOnly) {
      return 'Turn off the local-files-only filter or import audio files for offline playback.';
    }

    if (favoritesOnly) {
      return 'Favorite a track from your library to see it here.';
    }

    return 'Import local audio files to start using the real player.';
  }
}

class _SourcesTab extends StatefulWidget {
  const _SourcesTab();

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  final _provider = const DemoSourceProvider();
  final _archiveProvider = InternetArchiveProvider();
  final _providerSearchController = TextEditingController();
  final _archiveSearchController = TextEditingController();
  final _archiveCollectionController = TextEditingController();
  final _archiveSubjectController = TextEditingController();
  final _archiveCreatorController = TextEditingController();
  final _archiveYearController = TextEditingController();
  final _podcastFeedController = TextEditingController();
  final _radioProvider = RadioBrowserProvider();
  final _radioSearchController = TextEditingController();
  final _radioCountryCodeController = TextEditingController();
  final _radioLanguageController = TextEditingController();
  final _radioTagController = TextEditingController();
  final _radioCodecController = TextEditingController();
  final _radioMinBitrateController = TextEditingController();
  final _radioMaxBitrateController = TextEditingController();
  List<Track> _archiveTracks = <Track>[];
  List<Track> _demoTracks = <Track>[];
  List<Track> _podcastEpisodeTracks = <Track>[];
  List<ProviderSearchResult> _providerSearchResults = <ProviderSearchResult>[];
  List<ProviderSearchError> _providerSearchErrors = <ProviderSearchError>[];
  List<Track> _radioTracks = <Track>[];
  bool _archiveLoading = false;
  String? _archiveError;
  bool _podcastLoading = false;
  String? _podcastError;
  String? _selectedPodcastSubscriptionId;
  bool _providerSearchLoading = false;
  String? _providerSearchMessage;
  bool _radioLoading = false;
  String? _radioError;

  @override
  void initState() {
    super.initState();
    _provider.search('').then((tracks) {
      if (mounted) {
        setState(() => _demoTracks = tracks);
      }
    });
  }

  @override
  void dispose() {
    _providerSearchController.dispose();
    _archiveSearchController.dispose();
    _archiveCollectionController.dispose();
    _archiveSubjectController.dispose();
    _archiveCreatorController.dispose();
    _archiveYearController.dispose();
    _podcastFeedController.dispose();
    _radioSearchController.dispose();
    _radioCountryCodeController.dispose();
    _radioLanguageController.dispose();
    _radioTagController.dispose();
    _radioCodecController.dispose();
    _radioMinBitrateController.dispose();
    _radioMaxBitrateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final podcastSubscriptions = library.podcastSubscriptions;
    final offlineModeEnabled = library.offlineModeEnabled;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Provider plugins',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'AetherTune separates the open-source player from source adapters. Add legal providers for local files, self-hosted music, podcasts, radio, Internet Archive, or official APIs.',
        ),
        if (offlineModeEnabled) ...<Widget>[
          const SizedBox(height: 12),
          const Card(
            child: ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text(
                'Network-backed source searches and feed refreshes are paused.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        const _ProviderCard(
          title: 'Local Files',
          status: 'Enabled',
          description: 'Import and play files selected through the native picker.',
          icon: Icons.folder_open,
          capabilities: <MusicSourceCapability>{
            MusicSourceCapability.directPlayback,
            MusicSourceCapability.libraryBrowse,
          },
          disclosure: ProviderPrivacyDisclosure(readsLocalFiles: true),
        ),
        _ProviderCard(
          title: _provider.name,
          status: 'Template',
          description: _provider.description,
          icon: Icons.code,
          capabilities: _provider.capabilities,
          disclosure: _provider.disclosure,
        ),
        const _ProviderCard(
          title: 'Podcast RSS',
          status: 'Adapter foundation',
          description: 'Parse legal RSS feeds with audio enclosures into playable episode tracks.',
          icon: Icons.rss_feed,
          capabilities: <MusicSourceCapability>{
            MusicSourceCapability.metadataSearch,
            MusicSourceCapability.streamResolution,
            MusicSourceCapability.directPlayback,
            MusicSourceCapability.offlineCache,
            MusicSourceCapability.downloads,
            MusicSourceCapability.subscriptions,
          },
        ),
        const _ProviderCard(
          title: 'Radio Browser',
          status: 'Enabled',
          description:
              'Search and filter an open radio directory, then resolve public station streams.',
          icon: Icons.radio_outlined,
          capabilities: <MusicSourceCapability>{
            MusicSourceCapability.metadataSearch,
            MusicSourceCapability.radioDirectory,
            MusicSourceCapability.streamResolution,
            MusicSourceCapability.directPlayback,
          },
        ),
        _ProviderCard(
          title: _archiveProvider.name,
          status: 'Adapter foundation',
          description:
              'Search and filter public audio items, then resolve playable archive files.',
          icon: Icons.archive_outlined,
          capabilities: _archiveProvider.capabilities,
          disclosure: _archiveProvider.disclosure,
        ),
        const _ProviderCard(
          title: 'Jellyfin / Navidrome / Subsonic',
          status: 'Adapter roadmap',
          description: 'User-owned/self-hosted music server support belongs here.',
          icon: Icons.dns_outlined,
        ),
        const _ProviderCard(
          title: 'More open catalogs',
          status: 'Adapter roadmap',
          description:
              'Additional legal catalogs can provide discovery, streaming, and offline caching.',
          icon: Icons.public,
        ),
        const _ProviderCard(
          title: 'Commercial services',
          status: 'Official APIs only',
          description: 'No DRM bypass, scraping, or paid-service cloning is included.',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: 16),
        Text(
          'Provider search',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _providerSearchController,
                enabled: !offlineModeEnabled,
                decoration: const InputDecoration(
                  labelText: 'Search providers',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: offlineModeEnabled
                    ? null
                    : (_) => _searchProviderCatalogs(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Search providers',
              onPressed: _providerSearchLoading || offlineModeEnabled
                  ? null
                  : _searchProviderCatalogs,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        if (_providerSearchLoading) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_providerSearchMessage != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Provider search'),
            subtitle: Text(_providerSearchMessage!),
          ),
        ],
        for (final error in _providerSearchErrors) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text('${error.providerName} failed'),
            subtitle: Text(error.message),
          ),
        ],
        if (_providerSearchResults.isEmpty &&
            !_providerSearchLoading &&
            _providerSearchMessage == null &&
            _providerSearchErrors.isEmpty) ...<Widget>[
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.public),
            title: Text('No provider results loaded'),
            subtitle: Text(
              'Search Demo Provider, Radio Browser, and Internet Archive.',
            ),
          ),
        ],
        if (_providerSearchResults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final result in _providerSearchResults)
            ListTile(
              leading: Icon(_providerSearchIcon(result.providerId)),
              title: Text(result.track.title),
              subtitle: Text(
                '${result.providerName} / ${result.track.artist} / '
                '${result.track.album}',
              ),
              onTap: _canPlayProviderSearchTrack(result.track)
                  ? () => _playProviderSearchTrack(context, result.track)
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Save result',
                    onPressed: () => _saveProviderSearchTrack(
                      context,
                      result.track,
                    ),
                    icon: const Icon(Icons.library_add_outlined),
                  ),
                  IconButton(
                    tooltip: _canPlayProviderSearchTrack(result.track)
                        ? 'Play result'
                        : 'No playable stream',
                    onPressed: _canPlayProviderSearchTrack(result.track)
                        ? () => _playProviderSearchTrack(context, result.track)
                        : null,
                    icon: const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Podcast RSS feeds',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _podcastFeedController,
                enabled: !offlineModeEnabled,
                decoration: const InputDecoration(
                  labelText: 'Feed URL',
                  prefixIcon: Icon(Icons.rss_feed),
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted:
                    offlineModeEnabled ? null : (_) => _addPodcastFeed(context),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Add podcast feed',
              onPressed: _podcastLoading || offlineModeEnabled
                  ? null
                  : () => _addPodcastFeed(context),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: () => _importPodcastOpml(context),
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Import OPML'),
            ),
            OutlinedButton.icon(
              onPressed: podcastSubscriptions.isEmpty
                  ? null
                  : () => _showPodcastOpmlExport(context),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Export OPML'),
            ),
          ],
        ),
        if (_podcastLoading) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_podcastError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Podcast feed failed'),
            subtitle: Text(_podcastError!),
          ),
        ],
        if (podcastSubscriptions.isEmpty && !_podcastLoading) ...<Widget>[
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.rss_feed),
            title: Text('No podcast feeds yet'),
            subtitle: Text('Add a legal RSS feed URL to browse episodes.'),
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          for (final subscription in podcastSubscriptions)
            ListTile(
              leading: const Icon(Icons.rss_feed),
              selected: subscription.id == _selectedPodcastSubscriptionId,
              title: Text(subscription.title),
              subtitle: Text(_podcastSubscriptionSubtitle(subscription)),
              onTap: offlineModeEnabled
                  ? null
                  : () => _loadPodcastEpisodes(context, subscription),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Refresh episodes',
                    onPressed: _podcastLoading || offlineModeEnabled
                        ? null
                        : () => _loadPodcastEpisodes(context, subscription),
                    icon: const Icon(Icons.list_alt_outlined),
                  ),
                  IconButton(
                    tooltip: 'Remove feed',
                    onPressed: () => _removePodcastFeed(context, subscription),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
        if (_selectedPodcastSubscriptionId != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Podcast episodes',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_podcastEpisodeTracks.isEmpty && !_podcastLoading)
            const ListTile(
              leading: Icon(Icons.podcasts_outlined),
              title: Text('No playable episodes loaded'),
              subtitle: Text('This feed may not expose audio enclosures.'),
            )
          else
            for (final track in _podcastEpisodeTracks)
              ListTile(
                leading: const Icon(Icons.podcasts_outlined),
                title: Text(track.title),
                subtitle: Text(
                  _podcastEpisodeSubtitle(
                    track,
                    library.playbackProgressForTrack(track.id),
                  ),
                ),
                onTap: () => _playPodcastEpisode(context, track),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Save episode',
                      onPressed: () => _savePodcastEpisode(context, track),
                      icon: const Icon(Icons.library_add_outlined),
                    ),
                    IconButton(
                      tooltip: 'Play episode',
                      onPressed: () => _playPodcastEpisode(context, track),
                      icon: const Icon(Icons.play_arrow),
                    ),
                  ],
                ),
              ),
        ],
        const SizedBox(height: 16),
        Text(
          'Radio Browser search',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _radioSearchController,
                enabled: !offlineModeEnabled,
                decoration: const InputDecoration(
                  labelText: 'Station search',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted:
                    offlineModeEnabled ? null : (_) => _searchRadioStations(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Search stations',
              onPressed: _radioLoading || offlineModeEnabled
                  ? null
                  : _searchRadioStations,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _radioFilterField(
              controller: _radioCountryCodeController,
              labelText: 'Country',
              icon: Icons.flag_outlined,
              textCapitalization: TextCapitalization.characters,
            ),
            _radioFilterField(
              controller: _radioLanguageController,
              labelText: 'Language',
              icon: Icons.translate_outlined,
            ),
            _radioFilterField(
              controller: _radioTagController,
              labelText: 'Tag',
              icon: Icons.sell_outlined,
            ),
            _radioFilterField(
              controller: _radioCodecController,
              labelText: 'Codec',
              icon: Icons.graphic_eq_outlined,
              textCapitalization: TextCapitalization.characters,
            ),
            _radioFilterField(
              controller: _radioMinBitrateController,
              labelText: 'Min kbps',
              icon: Icons.speed_outlined,
              keyboardType: TextInputType.number,
            ),
            _radioFilterField(
              controller: _radioMaxBitrateController,
              labelText: 'Max kbps',
              icon: Icons.speed,
              keyboardType: TextInputType.number,
            ),
            OutlinedButton.icon(
              onPressed: _clearRadioFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear'),
            ),
          ],
        ),
        if (_radioLoading) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_radioError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Radio search failed'),
            subtitle: Text(_radioError!),
          ),
        ] else if (_radioTracks.isEmpty && !_radioLoading) ...<Widget>[
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.radio_outlined),
            title: Text('No stations loaded'),
            subtitle: Text(
              'Search by station name, country, language, tag, codec, or '
              'bitrate.',
            ),
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          for (final track in _radioTracks)
            ListTile(
              leading: const Icon(Icons.radio_outlined),
              title: Text(track.title),
              subtitle: Text('${track.artist} / ${track.genre}'),
              onTap: () => _playRadioStation(context, track),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Save station',
                    onPressed: () => _saveRadioStation(context, track),
                    icon: const Icon(Icons.library_add_outlined),
                  ),
                  IconButton(
                    tooltip: 'Play station',
                    onPressed: () => _playRadioStation(context, track),
                    icon: const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Internet Archive audio',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _archiveSearchController,
                enabled: !offlineModeEnabled,
                decoration: const InputDecoration(
                  labelText: 'Archive search',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted:
                    offlineModeEnabled ? null : (_) => _searchArchiveItems(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Search archive audio',
              onPressed: _archiveLoading || offlineModeEnabled
                  ? null
                  : _searchArchiveItems,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            _archiveFilterField(
              controller: _archiveCollectionController,
              labelText: 'Collection',
              icon: Icons.collections_bookmark_outlined,
            ),
            _archiveFilterField(
              controller: _archiveSubjectController,
              labelText: 'Subject',
              icon: Icons.sell_outlined,
            ),
            _archiveFilterField(
              controller: _archiveCreatorController,
              labelText: 'Creator',
              icon: Icons.person_search_outlined,
            ),
            _archiveFilterField(
              controller: _archiveYearController,
              labelText: 'Year',
              icon: Icons.calendar_month_outlined,
              keyboardType: TextInputType.number,
            ),
            OutlinedButton.icon(
              onPressed: _clearArchiveFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear'),
            ),
          ],
        ),
        if (_archiveLoading) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_archiveError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Archive search failed'),
            subtitle: Text(_archiveError!),
          ),
        ] else if (_archiveTracks.isEmpty && !_archiveLoading) ...<Widget>[
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.archive_outlined),
            title: Text('No archive audio loaded'),
            subtitle: Text(
              'Search by keyword, collection, subject, creator, or year.',
            ),
          ),
        ] else ...<Widget>[
          const SizedBox(height: 8),
          for (final track in _archiveTracks)
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(track.title),
              subtitle: Text('${track.artist} / ${track.genre}'),
              onTap: () => _playArchiveTrack(context, track),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Save archive track',
                    onPressed: () => _saveArchiveTrack(context, track),
                    icon: const Icon(Icons.library_add_outlined),
                  ),
                  IconButton(
                    tooltip: 'Play archive track',
                    onPressed: () => _playArchiveTrack(context, track),
                    icon: const Icon(Icons.play_arrow),
                  ),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Demo provider tracks',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final track in _demoTracks)
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(track.title),
            subtitle: Text('${track.artist} · ${track.album}'),
          ),
      ],
    );
  }

  List<MusicSourceProvider> get _providerSearchSources {
    return <MusicSourceProvider>[
      _provider,
      _radioProvider,
      _archiveProvider,
    ];
  }

  ProviderSearchCoordinator get _providerSearchCoordinator {
    return ProviderSearchCoordinator(
      _providerSearchSources,
      maxResultsPerProvider: 8,
    );
  }

  bool _offlineModeBlocksSourceNetwork(BuildContext context) {
    if (!context.read<LibraryStore>().offlineModeEnabled) {
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Offline mode is on. Network sources are paused.'),
      ),
    );
    return true;
  }

  bool _offlineModeBlocksStream(BuildContext context, Track track) {
    if (!context.read<LibraryStore>().offlineModeEnabled ||
        track.hasLocalSource) {
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Offline mode is on. Stream playback is paused.'),
      ),
    );
    return true;
  }

  Future<void> _searchProviderCatalogs() async {
    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _providerSearchResults = <ProviderSearchResult>[];
        _providerSearchErrors = <ProviderSearchError>[];
        _providerSearchLoading = false;
        _providerSearchMessage = 'Offline mode is on.';
      });
      return;
    }

    final query = _providerSearchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _providerSearchResults = <ProviderSearchResult>[];
        _providerSearchErrors = <ProviderSearchError>[];
        _providerSearchLoading = false;
        _providerSearchMessage = 'Enter a search term.';
      });
      return;
    }

    setState(() {
      _providerSearchLoading = true;
      _providerSearchMessage = null;
      _providerSearchErrors = <ProviderSearchError>[];
      _providerSearchResults = <ProviderSearchResult>[];
    });

    try {
      final response = await _providerSearchCoordinator.search(query);
      if (!mounted) {
        return;
      }

      setState(() {
        _providerSearchResults = response.results;
        _providerSearchErrors = response.errors;
        _providerSearchLoading = false;
        _providerSearchMessage = response.results.isEmpty
            ? 'No provider results found.'
            : null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _providerSearchResults = <ProviderSearchResult>[];
        _providerSearchErrors = <ProviderSearchError>[];
        _providerSearchLoading = false;
        _providerSearchMessage = error.toString();
      });
    }
  }

  List<Track> get _providerSearchPlayableQueue {
    return _providerSearchResults
        .map((result) => result.track)
        .where((track) => track.isPlayable)
        .toList(growable: false);
  }

  Future<void> _playProviderSearchTrack(
    BuildContext context,
    Track track,
  ) async {
    if (_offlineModeBlocksStream(context, track)) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<PlayerController>();

    try {
      final playableTrack =
          await _providerSearchCoordinator.resolvePlayableTrack(track);
      if (!context.mounted) {
        return;
      }
      if (!playableTrack.isPlayable) {
        messenger.showSnackBar(
          SnackBar(content: Text('No playable stream for ${track.title}.')),
        );
        return;
      }

      await player.playTrack(
        playableTrack,
        queue: _providerSearchPlayableQueue,
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not play ${track.title}.')),
      );
    }
  }

  Future<void> _saveProviderSearchTrack(
    BuildContext context,
    Track track,
  ) async {
    if (!track.isPlayable && _offlineModeBlocksSourceNetwork(context)) {
      return;
    }

    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final savedTrack =
          await _providerSearchCoordinator.resolvePlayableTrack(track);
      if (!context.mounted) {
        return;
      }

      await library.addTracks(<Track>[savedTrack]);
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${savedTrack.title}.')),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not save ${track.title}.')),
      );
    }
  }

  bool _canPlayProviderSearchTrack(Track track) {
    return _providerSearchCoordinator.canResolve(track);
  }

  IconData _providerSearchIcon(String providerId) {
    switch (providerId) {
      case 'demo':
        return Icons.code;
      case 'radio-browser':
        return Icons.radio_outlined;
      case 'internet-archive':
        return Icons.archive_outlined;
      default:
        return Icons.public;
    }
  }

  Future<void> _addPodcastFeed(BuildContext context) async {
    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _podcastLoading = false;
        _podcastError = 'Offline mode is on.';
      });
      return;
    }

    final rawUrl = _podcastFeedController.text.trim();
    final feedUri = Uri.tryParse(rawUrl);
    if (feedUri == null || !feedUri.hasScheme || feedUri.host.isEmpty) {
      setState(() {
        _podcastError = 'Enter a full RSS feed URL.';
      });
      return;
    }

    await _loadAndSavePodcastFeed(context, feedUri);
  }

  Future<void> _importPodcastOpml(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final opml = await _promptForPodcastOpml(context);
    if (!context.mounted || opml == null) {
      return;
    }

    try {
      final subscriptions = parsePodcastOpml(opml);
      for (final subscription in subscriptions) {
        await library.savePodcastSubscription(subscription);
      }

      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text('Imported ${subscriptions.length} podcast feed(s).'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not import OPML: $error')),
      );
    }
  }

  Future<void> _showPodcastOpmlExport(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final opml = exportPodcastOpml(library.podcastSubscriptions);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export OPML'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(opml),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptForPodcastOpml(BuildContext context) async {
    final controller = TextEditingController();

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Import OPML'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                autofocus: true,
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'OPML',
                ),
                keyboardType: TextInputType.multiline,
                minLines: 8,
                maxLines: 14,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text,
                ),
                child: const Text('Import'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _loadPodcastEpisodes(
    BuildContext context,
    PodcastSubscription subscription,
  ) async {
    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _podcastLoading = false;
        _podcastError = 'Offline mode is on.';
      });
      return;
    }

    final feedUri = Uri.tryParse(subscription.feedUrl);
    if (feedUri == null) {
      setState(() {
        _podcastError = 'Saved feed URL is invalid.';
      });
      return;
    }

    await _loadAndSavePodcastFeed(context, feedUri);
  }

  Future<void> _loadAndSavePodcastFeed(
    BuildContext context,
    Uri feedUri,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final provider = PodcastRssProvider(feedUri: feedUri);

    setState(() {
      _podcastLoading = true;
      _podcastError = null;
    });

    try {
      final feed = await provider.fetchFeed();
      final saved = await library.savePodcastSubscription(
        PodcastSubscription(
          id: stablePodcastSubscriptionId(feed.feedUri.toString()),
          feedUrl: feed.feedUri.toString(),
          title: feed.title,
          description: feed.description,
          author: feed.author,
          artworkUri: feed.artworkUri,
        ),
      );
      final refreshed =
          await library.markPodcastSubscriptionFetched(saved.id) ?? saved;
      final tracks = feed.episodes
          .map((episode) => episode.toTrack(sourceId: provider.id, feed: feed))
          .toList(growable: false);

      if (!context.mounted) {
        return;
      }

      setState(() {
        _podcastEpisodeTracks = tracks;
        _selectedPodcastSubscriptionId = refreshed.id;
        _podcastLoading = false;
      });

      messenger.showSnackBar(
        SnackBar(content: Text('Loaded ${feed.title}.')),
      );
    } catch (error) {
      await library.markPodcastSubscriptionFetchFailed(
        stablePodcastSubscriptionId(feedUri.toString()),
        error,
      );
      if (!context.mounted) {
        return;
      }

      setState(() {
        _podcastEpisodeTracks = <Track>[];
        _podcastLoading = false;
        _podcastError = error.toString();
      });
    }
  }

  String _podcastSubscriptionSubtitle(PodcastSubscription subscription) {
    final details = subscription.author.isEmpty
        ? subscription.feedUrl
        : '${subscription.author} / ${subscription.feedUrl}';
    return '$details / ${_podcastRefreshStatus(subscription)}';
  }

  String _podcastRefreshStatus(PodcastSubscription subscription) {
    if (subscription.lastFetchError.isNotEmpty) {
      return 'Refresh failed';
    }

    final fetchedAt = subscription.lastFetchedAt;
    if (fetchedAt == null) {
      return 'Never refreshed';
    }

    final now = DateTime.now();
    final age = _formatRefreshAge(now.difference(fetchedAt));
    return subscription.isRefreshDue(now) ? 'Refresh due $age' : 'Fresh $age';
  }

  Future<void> _removePodcastFeed(
    BuildContext context,
    PodcastSubscription subscription,
  ) async {
    final library = context.read<LibraryStore>();
    await library.deletePodcastSubscription(subscription.id);

    if (!context.mounted) {
      return;
    }

    if (_selectedPodcastSubscriptionId == subscription.id) {
      setState(() {
        _selectedPodcastSubscriptionId = null;
        _podcastEpisodeTracks = <Track>[];
      });
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${subscription.title}.')),
    );
  }

  Future<void> _playPodcastEpisode(BuildContext context, Track track) async {
    if (_offlineModeBlocksStream(context, track)) {
      return;
    }

    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<PlayerController>();

    try {
      await library.addTracks(<Track>[track]);
      if (!context.mounted) {
        return;
      }

      await _playTrackWithResume(
        context,
        player,
        library,
        track,
        queue: _podcastEpisodeTracks,
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not play ${track.title}.')),
      );
    }
  }

  String _podcastEpisodeSubtitle(
    Track track,
    PlaybackProgressEntry? progress,
  ) {
    final base = '${track.artist} / ${track.album}';
    if (progress == null) {
      return base;
    }

    return '$base / Resume ${_formatDurationLabel(progress.position)}';
  }

  Future<void> _savePodcastEpisode(BuildContext context, Track track) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.addTracks(<Track>[track]);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${track.title}.')),
    );
  }

  Future<void> _searchArchiveItems() async {
    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _archiveTracks = <Track>[];
        _archiveLoading = false;
        _archiveError = 'Offline mode is on.';
      });
      return;
    }

    setState(() {
      _archiveLoading = true;
      _archiveError = null;
    });

    try {
      final tracks = await _archiveProvider.searchAudio(
        _archiveSearchController.text,
        filters: _archiveFilters(),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _archiveTracks = tracks;
        _archiveLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _archiveTracks = <Track>[];
        _archiveLoading = false;
        _archiveError = error.toString();
      });
    }
  }

  Future<void> _playArchiveTrack(BuildContext context, Track track) async {
    if (_offlineModeBlocksStream(context, track)) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<PlayerController>();

    try {
      await player.playTrack(track, queue: _archiveTracks);
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not play ${track.title}.')),
      );
    }
  }

  Future<void> _saveArchiveTrack(BuildContext context, Track track) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.addTracks(<Track>[track]);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${track.title}.')),
    );
  }

  Widget _archiveFilterField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      width: 168,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: Icon(icon),
        ),
        keyboardType: keyboardType,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchArchiveItems(),
      ),
    );
  }

  InternetArchiveSearchFilters _archiveFilters() {
    return InternetArchiveSearchFilters(
      collection: _archiveCollectionController.text,
      subject: _archiveSubjectController.text,
      creator: _archiveCreatorController.text,
      year: _archiveYearController.text,
    );
  }

  void _clearArchiveFilters() {
    _archiveCollectionController.clear();
    _archiveSubjectController.clear();
    _archiveCreatorController.clear();
    _archiveYearController.clear();
  }

  Widget _radioFilterField({
    required TextEditingController controller,
    required String labelText,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return SizedBox(
      width: 156,
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: labelText,
          prefixIcon: Icon(icon),
        ),
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchRadioStations(),
      ),
    );
  }

  RadioBrowserSearchFilters _radioFilters() {
    return RadioBrowserSearchFilters(
      countryCode: _radioCountryCodeController.text,
      language: _radioLanguageController.text,
      tag: _radioTagController.text,
      codec: _radioCodecController.text,
      minBitrateKbps: _positiveInt(_radioMinBitrateController.text),
      maxBitrateKbps: _positiveInt(_radioMaxBitrateController.text),
    );
  }

  int? _positiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }

    return parsed;
  }

  void _clearRadioFilters() {
    _radioCountryCodeController.clear();
    _radioLanguageController.clear();
    _radioTagController.clear();
    _radioCodecController.clear();
    _radioMinBitrateController.clear();
    _radioMaxBitrateController.clear();
  }

  Future<void> _searchRadioStations() async {
    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _radioTracks = <Track>[];
        _radioLoading = false;
        _radioError = 'Offline mode is on.';
      });
      return;
    }

    setState(() {
      _radioLoading = true;
      _radioError = null;
    });

    try {
      final tracks = await _radioProvider.searchStations(
        _radioSearchController.text,
        filters: _radioFilters(),
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _radioTracks = tracks;
        _radioLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _radioTracks = <Track>[];
        _radioLoading = false;
        _radioError = error.toString();
      });
    }
  }

  Future<void> _playRadioStation(BuildContext context, Track track) async {
    if (_offlineModeBlocksStream(context, track)) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final player = context.read<PlayerController>();

    try {
      await player.playTrack(track, queue: _radioTracks);
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not play ${track.title}.')),
      );
    }
  }

  Future<void> _saveRadioStation(BuildContext context, Track track) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.addTracks(<Track>[track]);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${track.title}.')),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.title,
    required this.status,
    required this.description,
    required this.icon,
    this.capabilities = const <MusicSourceCapability>{},
    this.disclosure,
  });

  final String title;
  final String status;
  final String description;
  final IconData icon;
  final Set<MusicSourceCapability> capabilities;
  final ProviderPrivacyDisclosure? disclosure;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(description),
            if (capabilities.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final capability in capabilities)
                    Chip(
                      label: Text(capability.label),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            if (disclosure != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _providerDisclosureSummary(disclosure!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
        trailing: Chip(label: Text(status)),
      ),
    );
  }

}

String _providerDisclosureSummary(ProviderPrivacyDisclosure disclosure) {
  final parts = <String>[disclosure.networkSummary];
  if (disclosure.requiresUserCredentials) {
    parts.add('Credentials required');
  }
  if (disclosure.readsLocalFiles) {
    parts.add('Reads selected local files');
  }
  if (disclosure.cachesMedia) {
    parts.add('Can cache media');
  }
  if (disclosure.supportsDownloads) {
    parts.add('Downloads allowed');
  }
  if (disclosure.dataSent.isNotEmpty) {
    parts.add('Sends ${disclosure.dataSent.join(', ')}');
  }

  return parts.join(' · ');
}

class _DuplicateResolverSheet extends StatelessWidget {
  const _DuplicateResolverSheet();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final groups = library.duplicateTrackGroups();

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.merge_type_outlined),
                title: const Text('Duplicate resolver'),
                subtitle: Text('${groups.length} duplicate group(s)'),
              ),
              const Divider(height: 1),
              if (groups.isEmpty)
                const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No duplicate groups found'),
                )
              else
                for (final group in groups) ...<Widget>[
                  ListTile(
                    leading: const Icon(Icons.merge_type_outlined),
                    title: Text(_duplicateMatchLabel(group.type)),
                    subtitle: Text('${group.tracks.length} matching tracks'),
                  ),
                  for (final track in group.tracks)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.music_note_outlined),
                      title: Text(track.title),
                      subtitle: Text(
                        _duplicateTrackSubtitle(track),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () {
                          unawaited(
                            _keepDuplicateTrack(
                              context,
                              library,
                              group,
                              track,
                            ),
                          );
                        },
                        child: const Text('Keep'),
                      ),
                    ),
                  const Divider(height: 1),
                ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _keepDuplicateTrack(
    BuildContext context,
    LibraryStore library,
    DuplicateTrackGroup group,
    Track keepTrack,
  ) async {
    final removed = await library.resolveDuplicateTracks(
      keepTrackId: keepTrack.id,
      duplicateTrackIds: group.tracks
          .where((track) => track.id != keepTrack.id)
          .map((track) => track.id),
    );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Merged $removed duplicate(s) into ${keepTrack.title}.'),
      ),
    );
  }
}

String _duplicateMatchLabel(DuplicateMatchType type) {
  switch (type) {
    case DuplicateMatchType.localPath:
      return 'Same file path';
    case DuplicateMatchType.sourceExternalId:
      return 'Same provider item';
    case DuplicateMatchType.streamUrl:
      return 'Same stream URL';
    case DuplicateMatchType.metadata:
      return 'Same metadata and duration';
  }
}

String _duplicateTrackSubtitle(Track track) {
  final parts = <String>[
    track.artist,
    track.album,
    if (track.localPath != null) track.localPath!,
    if (track.streamUrl != null) track.streamUrl!,
  ].where((part) => part.trim().isNotEmpty).toList(growable: false);

  return parts.join(' · ');
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final library = context.watch<LibraryStore>();
    final duplicateGroups = library.duplicateTrackGroups();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Options', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text('Shuffle queue'),
          subtitle: const Text('Randomize playback order when supported by the queue.'),
          value: player.shuffleEnabled,
          onChanged: player.setShuffleEnabled,
        ),
        ListTile(
          title: const Text('Repeat mode'),
          subtitle: Text(player.loopMode.name),
          trailing: DropdownButton<LoopMode>(
            value: player.loopMode,
            items: const <DropdownMenuItem<LoopMode>>[
              DropdownMenuItem(value: LoopMode.off, child: Text('Off')),
              DropdownMenuItem(value: LoopMode.one, child: Text('One')),
              DropdownMenuItem(value: LoopMode.all, child: Text('All')),
            ],
            onChanged: (mode) {
              if (mode != null) {
                player.setLoopMode(mode);
              }
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.cloud_off_outlined),
          title: const Text('Offline mode'),
          subtitle: const Text(
            'Pause network-backed source searches, feed refreshes, and stream playback.',
          ),
          value: library.offlineModeEnabled,
          onChanged: (value) {
            unawaited(library.setOfflineModeEnabled(value));
          },
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: const Text('Export backup'),
          onTap: () => _showBackupExport(context),
        ),
        ListTile(
          leading: const Icon(Icons.restore_page_outlined),
          title: const Text('Restore backup'),
          onTap: () => _showBackupRestore(context),
        ),
        ListTile(
          leading: const Icon(Icons.merge_type_outlined),
          title: const Text('Resolve duplicates'),
          subtitle: Text(
            duplicateGroups.isEmpty
                ? 'No duplicate groups found'
                : '${duplicateGroups.length} duplicate group(s) found',
          ),
          enabled: library.loaded && duplicateGroups.isNotEmpty,
          onTap: library.loaded && duplicateGroups.isNotEmpty
              ? () => _showDuplicateResolver(context)
              : null,
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.privacy_tip_outlined),
          title: Text('Privacy'),
          subtitle: Text('No ads, no telemetry, no forced account in the core app.'),
        ),
        const ListTile(
          leading: Icon(Icons.balance_outlined),
          title: Text('Legal source policy'),
          subtitle: Text('Provider adapters must use legal, documented, user-owned, or official APIs.'),
        ),
      ],
    );
  }

  Future<void> _showDuplicateResolver(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _DuplicateResolverSheet(),
    );
  }

  Future<void> _showBackupExport(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final backupJson = library.exportBackupJson();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Export backup'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(backupJson),
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBackupRestore(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final backupJson = await _promptForBackupJson(context);
    if (!context.mounted || backupJson == null) {
      return;
    }

    try {
      await library.restoreBackupJson(backupJson);
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
      return;
    }

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      const SnackBar(content: Text('Restored backup.')),
    );
  }

  Future<String?> _promptForBackupJson(BuildContext context) async {
    final controller = TextEditingController();

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Restore backup'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                autofocus: true,
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Backup JSON',
                ),
                keyboardType: TextInputType.multiline,
                minLines: 8,
                maxLines: 14,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(
                  controller.text,
                ),
                child: const Text('Restore'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}
