import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../data/demo_source_provider.dart';
import '../data/library_store.dart';
import '../domain/music_source_provider.dart';
import '../domain/playlist.dart';
import '../domain/sleep_timer_duration.dart';
import '../domain/track.dart';
import '../domain/track_lyrics.dart';
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
  int _tabIndex = 0;
  bool _favoritesOnly = false;
  String _query = '';
  LibrarySortMode _librarySortMode = LibrarySortMode.recentlyAdded;
  PlayerController? _historyPlayer;
  LibraryStore? _historyLibrary;
  int _lastRecordedPlaybackSerial = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final player = context.read<PlayerController>();
    if (_historyPlayer != player) {
      _historyPlayer?.removeListener(_recordPlaybackHistory);
      _historyPlayer = player;
      player.addListener(_recordPlaybackHistory);
    }

    _historyLibrary = context.read<LibraryStore>();
  }

  @override
  void dispose() {
    _historyPlayer?.removeListener(_recordPlaybackHistory);
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
                    sortMode: _librarySortMode,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onFavoritesOnlyChanged: (value) {
                      setState(() => _favoritesOnly = value);
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

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
                  await _showCustomSleepTimer(context, player);
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
                  onTap: () {
                    player.startSleepTimer(Duration(minutes: minutes));
                    Navigator.of(sheetContext).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showCustomSleepTimer(
    BuildContext context,
    PlayerController player,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final duration = await _promptForCustomSleepTimerDuration(context);
    if (!context.mounted || duration == null) {
      return;
    }

    player.startSleepTimer(duration);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Sleep timer set for ${duration.inMinutes} minute(s).',
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
    required this.sortMode,
    required this.onQueryChanged,
    required this.onFavoritesOnlyChanged,
    required this.onSortModeChanged,
    required this.onImport,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final TextEditingController searchController;
  final String query;
  final bool favoritesOnly;
  final LibrarySortMode sortMode;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onFavoritesOnlyChanged;
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
      sortMode: sortMode,
    );

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
            ],
            onChanged: onQueryChanged,
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
                  onPlay: () => player.playTrack(track, queue: tracks),
                  onFavorite: () => library.toggleFavorite(track.id),
                  onAddToPlaylist: () => onAddToPlaylist(track),
                  onLyrics: () => onLyrics(track),
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
                onPlay: () => player.playTrack(track, queue: tracks),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
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
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Smart playlists',
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
                            player.playTrack(tracks.first, queue: tracks);
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
                onPlay: () => player.playTrack(track, queue: tracks),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
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
                leading: const Icon(Icons.queue_music),
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
                          widget.player.playTrack(tracks.first, queue: tracks);
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

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.onOpen,
    required this.onExport,
    required this.onRename,
    required this.onDelete,
  });

  final Playlist playlist;
  final VoidCallback onOpen;
  final ValueChanged<PlaylistDocumentFormat> onExport;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.queue_music),
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

enum _PlaylistAction { exportJson, exportM3u, exportCsv, rename, delete }

enum _PlaylistTrackAction { moveUp, moveDown, remove }

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final recentlyPlayed = library.recentlyPlayedTracks();

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
              tooltip: 'Clear history',
              onPressed: library.playbackHistory.isEmpty
                  ? null
                  : library.clearPlaybackHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          ],
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
                '${library.playCountForTrack(track.id)} play(s)',
              ),
              trailing: Text(
                _formatHistoryTime(library.lastPlayedAt(track.id)),
              ),
              onTap: () => player.playTrack(
                track,
                queue: recentlyPlayed,
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

String _formatHistoryTime(DateTime? value) {
  if (value == null) {
    return '';
  }

  String twoDigits(int number) => number.toString().padLeft(2, '0');

  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.favoritesOnly,
    required this.onImport,
  });

  final bool favoritesOnly;
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
              favoritesOnly ? 'No favorite tracks yet' : 'Your library is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              favoritesOnly
                  ? 'Favorite a track from your library to see it here.'
                  : 'Import local audio files to start using the real player.',
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
}

class _SourcesTab extends StatefulWidget {
  const _SourcesTab();

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  final _provider = const DemoSourceProvider();
  List<Track> _demoTracks = <Track>[];

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
  Widget build(BuildContext context) {
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
            MusicSourceCapability.subscriptions,
          },
        ),
        const _ProviderCard(
          title: 'Radio Browser',
          status: 'Adapter foundation',
          description: 'Search an open radio directory and resolve public station streams.',
          icon: Icons.radio_outlined,
          capabilities: <MusicSourceCapability>{
            MusicSourceCapability.metadataSearch,
            MusicSourceCapability.radioDirectory,
            MusicSourceCapability.streamResolution,
            MusicSourceCapability.directPlayback,
          },
        ),
        const _ProviderCard(
          title: 'Jellyfin / Navidrome / Subsonic',
          status: 'Adapter roadmap',
          description: 'User-owned/self-hosted music server support belongs here.',
          icon: Icons.dns_outlined,
        ),
        const _ProviderCard(
          title: 'Podcasts / Radio / Internet Archive',
          status: 'Adapter roadmap',
          description: 'Open catalogs can provide discovery, streaming, and offline caching.',
          icon: Icons.public,
        ),
        const _ProviderCard(
          title: 'Commercial services',
          status: 'Official APIs only',
          description: 'No DRM bypass, scraping, or paid-service cloning is included.',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: 16),
        Text('Demo provider tracks', style: Theme.of(context).textTheme.titleMedium),
        for (final track in _demoTracks)
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(track.title),
            subtitle: Text('${track.artist} · ${track.album}'),
          ),
      ],
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
    parts.add('Caches media');
  }
  if (disclosure.supportsDownloads) {
    parts.add('Downloads allowed');
  }
  if (disclosure.dataSent.isNotEmpty) {
    parts.add('Sends ${disclosure.dataSent.join(', ')}');
  }

  return parts.join(' · ');
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();

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
