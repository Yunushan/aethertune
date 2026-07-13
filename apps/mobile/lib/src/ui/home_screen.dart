import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../data/demo_source_provider.dart';
import '../data/flac_vorbis_comment_writer.dart';
import '../data/internet_archive_provider.dart';
import '../data/jellyfin_provider.dart';
import '../data/library_store.dart';
import '../data/local_folder_watch_store.dart';
import '../data/local_library_provider.dart';
import '../data/local_folder_scanner.dart';
import '../data/lrclib_lyrics_provider.dart';
import '../data/mp3_id3v1_tag_writer.dart';
import '../data/offline_cache_manager.dart';
import '../data/offline_cache_pressure_enforcer.dart';
import '../data/podcast_rss_provider.dart';
import '../data/playlist_artwork_file_store.dart';
import '../data/radio_browser_provider.dart';
import '../data/self_hosted_provider_store.dart';
import '../data/subsonic_provider.dart';
import '../data/wav_riff_info_writer.dart';
import '../domain/backup_file_document.dart';
import '../domain/lyrics_document.dart';
import '../domain/music_source_provider.dart';
import '../domain/offline_cache_entry.dart';
import '../domain/playback_history_entry.dart';
import '../domain/playback_progress_entry.dart';
import '../domain/playlist.dart';
import '../domain/playlist_export_file.dart';
import '../domain/podcast_opml.dart';
import '../domain/podcast_subscription.dart';
import '../domain/provider_search.dart';
import '../domain/self_hosted_provider_account.dart';
import '../domain/sleep_timer_duration.dart';
import '../domain/track.dart';
import '../domain/track_lyrics.dart';
import '../player/offline_playback_policy.dart';
import '../player/player_controller.dart';
import 'now_playing_screen.dart';
import 'desktop_navigation_shortcuts.dart';
import 'internet_archive_item_screen.dart';
import 'platform_text_share.dart';
import 'responsive_layout.dart';
import 'self_hosted_browse_screen.dart';
import 'theme_colors.dart';
import 'widgets/listening_recap_card.dart';
import 'widgets/listening_heatmap.dart';
import 'widgets/listening_stats_bar_chart.dart';
import 'widgets/library_sync_panel.dart';
import 'widgets/desktop_queue_pane.dart';
import 'widgets/lyrics_share_card.dart';
import 'widgets/lyrics_search_sheet.dart';
import 'widgets/player_bar.dart';
import 'widgets/playlist_artwork.dart';
import 'widgets/self_hosted_account_editor.dart';
import 'widgets/self_hosted_credential_rotation_dialog.dart';
import 'widgets/track_tile.dart';

class _AetherTuneNavigationDestination {
  const _AetherTuneNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _aetherTuneNavigationDestinations = <_AetherTuneNavigationDestination>[
  _AetherTuneNavigationDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: 'Home',
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.my_library_music_outlined,
    selectedIcon: Icons.my_library_music,
    label: 'Library',
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.playlist_play_outlined,
    selectedIcon: Icons.playlist_play,
    label: 'Playlists',
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    label: 'History',
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
    label: 'Sources',
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    label: 'Options',
  ),
];

final _playlistArtworkFileStore = PlaylistArtworkFileStore();
const _platformTextShareService = SharePlusTextShareService();

List<NavigationDestination> _navigationBarDestinations() {
  return _aetherTuneNavigationDestinations.map((destination) {
    return NavigationDestination(
      icon: Icon(destination.icon),
      selectedIcon: Icon(destination.selectedIcon),
      label: destination.label,
    );
  }).toList(growable: false);
}

List<NavigationRailDestination> _navigationRailDestinations() {
  return _aetherTuneNavigationDestinations.map((destination) {
    return NavigationRailDestination(
      icon: Icon(destination.icon),
      selectedIcon: Icon(destination.selectedIcon),
      label: Text(destination.label),
    );
  }).toList(growable: false);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialTab = 0,
    this.onRestartOnboarding,
    this.internetArchiveProvider,
  }) : assert(
         initialTab >= 0 &&
             initialTab < _aetherTuneNavigationDestinations.length,
       );

  final int initialTab;
  final VoidCallback? onRestartOnboarding;
  final InternetArchiveProvider? internetArchiveProvider;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _radioClickProvider = RadioBrowserProvider();
  final _lyricsProvider = LrcLibLyricsProvider();
  late int _tabIndex;
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
  double? _desktopQueuePaneDragWidth;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
  }

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

    _applyTrackPlaybackSpeed(player, library, track);

    if (player.playbackStartSerial == _lastRecordedPlaybackSerial) {
      return;
    }

    _lastRecordedPlaybackSerial = player.playbackStartSerial;
    unawaited(library.recordPlayback(track.id));
    unawaited(_recordRadioStationClick(track));
  }

  void _applyTrackPlaybackSpeed(
    PlayerController player,
    LibraryStore library,
    Track track,
  ) {
    final speed =
        library.playbackSpeedForTrack(track.id) ?? player.defaultPlaybackSpeed;
    if ((player.playbackSpeed - speed).abs() < 0.0001) {
      return;
    }
    unawaited(player.setTemporaryPlaybackSpeed(speed));
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
    final useNavigationRail = usesDesktopNavigationRail(
      MediaQuery.of(context).size.width,
    );
    final useDesktopQueuePane = usesDesktopQueuePane(
      MediaQuery.of(context).size.width,
    );
    final savedDesktopQueuePaneWidth = context.select<LibraryStore, double>(
      (library) => library.desktopQueuePaneWidth,
    );
    final desktopQueuePaneWidth =
        _desktopQueuePaneDragWidth ?? savedDesktopQueuePaneWidth;
    final tabContent = Column(
      children: <Widget>[
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: <Widget>[
              _HomeTab(
                onImport: () => _importAudio(context),
                onImportFolder: () => _importAudioFolder(context),
                onAddToPlaylist: (track) => _showAddToPlaylist(
                  context,
                  track,
                ),
                onLyrics: (track) => _showLyricsEditor(
                  context,
                  track,
                ),
              ),
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
                onImportFolder: () => _importAudioFolder(context),
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
              _SourcesTab(archiveProvider: widget.internetArchiveProvider),
              _SettingsTab(
                onRestartOnboarding: widget.onRestartOnboarding,
              ),
            ],
          ),
        ),
        PlayerBar(
          onOpenNowPlaying: () => _openNowPlaying(context),
          onOpenQueue: () => _showQueue(context),
          onSaveQueue: () => _saveQueueAsPlaylist(context),
          onOpenLyrics: () => _showNowPlayingLyrics(context),
        ),
      ],
    );

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('AetherTune'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Import local audio',
            onPressed: () => _importAudio(context),
            icon: const Icon(Icons.library_add),
          ),
          IconButton(
            tooltip: 'Import audio folder',
            onPressed: () => _importAudioFolder(context),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
          IconButton(
            tooltip: 'Sleep timer',
            onPressed: () => _showSleepTimer(context),
            icon: const Icon(Icons.bedtime_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: useNavigationRail
            ? Row(
                children: <Widget>[
                  NavigationRail(
                    selectedIndex: _tabIndex,
                    onDestinationSelected: _selectTab,
                    labelType: NavigationRailLabelType.all,
                    minWidth: 88,
                    groupAlignment: -0.85,
                    scrollable: true,
                    destinations: _navigationRailDestinations(),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: tabContent),
                  if (useDesktopQueuePane) ...<Widget>[
                    DesktopQueuePaneResizeHandle(
                      onDragUpdate: (delta) => _resizeDesktopQueuePane(
                        delta,
                        savedDesktopQueuePaneWidth,
                      ),
                      onDragEnd: () => _persistDesktopQueuePaneWidth(context),
                    ),
                    SizedBox(
                      width: desktopQueuePaneWidth,
                      child: DesktopQueuePane(
                        onOpenNowPlaying: () => _openNowPlaying(context),
                        onOpenQueue: () => _showQueue(context),
                      ),
                    ),
                  ],
                ],
              )
            : tabContent,
      ),
      bottomNavigationBar: useNavigationRail
          ? null
          : NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: _selectTab,
              destinations: _navigationBarDestinations(),
            ),
    );

    return DesktopNavigationShortcutScope(
      enabled: useNavigationRail,
      onDestinationSelected: _selectTab,
      onPreviousDestination: _selectPreviousTab,
      onNextDestination: _selectNextTab,
      child: scaffold,
    );
  }

  void _selectTab(int index) {
    setState(() => _tabIndex = index);
  }

  void _resizeDesktopQueuePane(double horizontalDelta, double savedWidth) {
    final currentWidth = _desktopQueuePaneDragWidth ?? savedWidth;
    setState(() {
      _desktopQueuePaneDragWidth = (currentWidth - horizontalDelta)
          .clamp(
            LibraryStore.minDesktopQueuePaneWidth,
            LibraryStore.maxDesktopQueuePaneWidth,
          )
          .toDouble();
    });
  }

  void _persistDesktopQueuePaneWidth(BuildContext context) {
    final width = _desktopQueuePaneDragWidth;
    if (width == null) {
      return;
    }
    setState(() => _desktopQueuePaneDragWidth = null);
    unawaited(context.read<LibraryStore>().setDesktopQueuePaneWidth(width));
  }

  void _selectPreviousTab() {
    _selectTab(
      (_tabIndex - 1 + _aetherTuneNavigationDestinations.length) %
          _aetherTuneNavigationDestinations.length,
    );
  }

  void _selectNextTab() {
    _selectTab((_tabIndex + 1) % _aetherTuneNavigationDestinations.length);
  }

  Future<void> _openNowPlaying(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NowPlayingScreen(
          onOpenQueue: () => _showQueue(context),
          onOpenLyrics: () => _showNowPlayingLyrics(context),
        ),
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
    final existingLyrics = library.lyricsForTrack(track.id);
    final result = await _promptForLyrics(
      context,
      track: track,
      library: library,
      initialLyrics: existingLyrics,
    );

    if (!context.mounted || result == null) {
      return;
    }

    await library.setLyrics(
      track.id,
      result.plainText,
      sourceId: result.sourceId,
      sourceName: result.sourceName,
      sourceExternalId: result.sourceExternalId,
      sourceUri: result.sourceUri,
    );

    if (!context.mounted) {
      return;
    }

    final saved = result.plainText.trim().isNotEmpty;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved ? 'Saved lyrics for ${track.title}.' : 'Removed lyrics.',
        ),
      ),
    );
  }

  Future<_LyricsEditorResult?> _promptForLyrics(
    BuildContext context, {
    required Track track,
    required LibraryStore library,
    required TrackLyrics? initialLyrics,
  }) async {
    final initialValue = initialLyrics?.plainText ?? '';
    final controller = TextEditingController(text: initialValue);
    var sourceId = initialLyrics?.sourceId ?? 'manual';
    var sourceName = initialLyrics?.sourceName ?? '';
    var sourceExternalId = initialLyrics?.sourceExternalId ?? '';
    var sourceUri = initialLyrics?.sourceUri;

    try {
      return showDialog<_LyricsEditorResult>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (_, setDialogState) {
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
                          onChanged: (_) {
                            sourceId = 'manual';
                            sourceName = '';
                            sourceExternalId = '';
                            sourceUri = null;
                            setDialogState(() {});
                          },
                        ),
                        if (sourceName.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              const Icon(Icons.verified_outlined, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Source: $sourceName'
                                  '${sourceExternalId.trim().isEmpty ? '' : ' #$sourceExternalId'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (syncedLines.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _SyncedLyricsPreview(lines: syncedLines),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  Tooltip(
                    message: library.offlineModeEnabled
                        ? 'Search cached ${_lyricsProvider.name} results'
                        : 'Search ${_lyricsProvider.name}',
                    child: TextButton.icon(
                      onPressed: () async {
                              final selected = await showLyricsSearchSheet(
                                dialogContext,
                                track: track,
                                provider: _lyricsProvider,
                                offlineOnly: library.offlineModeEnabled,
                              );
                              final lyrics = selected?.preferredLyrics;
                              if (!dialogContext.mounted || lyrics == null) {
                                return;
                              }

                              controller.text = lyrics;
                              controller.selection = TextSelection.collapsed(
                                offset: controller.text.length,
                              );
                              sourceId = selected!.providerId;
                              sourceName = selected.providerName;
                              sourceExternalId = selected.externalId;
                              sourceUri = selected.sourceUri;
                              setDialogState(() {});
                            },
                      icon: const Icon(Icons.travel_explore),
                      label: const Text('Search online'),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final imported = await _importLyricsDocument(context);
                      if (!dialogContext.mounted || imported == null) {
                        return;
                      }

                      controller.text = imported;
                      controller.selection = TextSelection.collapsed(
                        offset: controller.text.length,
                      );
                      sourceId = 'manual';
                      sourceName = '';
                      sourceExternalId = '';
                      sourceUri = null;
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.upload_file_outlined),
                    label: const Text('Import file'),
                  ),
                  TextButton.icon(
                    onPressed: () => unawaited(
                      _copyLyricsDraftExportDocument(
                        context,
                        track,
                        controller.text,
                      ),
                    ),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Copy export'),
                  ),
                  Tooltip(
                    message: 'Save lyrics file',
                    child: IconButton(
                      onPressed: () => unawaited(
                        _saveLyricsDraftExportDocument(
                          context,
                          track,
                          controller.text,
                        ),
                      ),
                      icon: const Icon(Icons.save_alt_outlined),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => unawaited(
                      _copyLyricsDraftShareText(
                        context,
                        library,
                        track,
                        controller.text,
                      ),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Copy share text'),
                  ),
                  Tooltip(
                    message: 'Save lyrics share card',
                    child: IconButton(
                      onPressed: () => unawaited(
                        _showLyricsShareCard(
                          context,
                          library,
                          track,
                          controller.text,
                        ),
                      ),
                      icon: const Icon(Icons.image_outlined),
                    ),
                  ),
                  if (initialValue.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(
                        const _LyricsEditorResult(plainText: ''),
                      ),
                      child: const Text('Delete'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop(
                        _LyricsEditorResult(
                          plainText: controller.text,
                          sourceId: sourceId,
                          sourceName: sourceName,
                          sourceExternalId: sourceExternalId,
                          sourceUri: sourceUri,
                        ),
                      );
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

  Future<String?> _importLyricsDocument(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await FilePicker.pickFile(
      allowedExtensions: supportedLyricsDocumentExtensions,
      dialogTitle: 'Import lyrics file',
      type: FileType.custom,
    );

    if (!context.mounted || file == null) {
      return null;
    }

    if (!isSupportedLyricsDocumentName(file.name)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Choose a .txt or .lrc lyrics file.')),
      );
      return null;
    }

    try {
      final bytes = await file.readAsBytes();
      return decodeLyricsDocumentBytes(bytes, fileName: file.name);
    } on Object catch (error) {
      if (!context.mounted) {
        return null;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not import lyrics: $error')),
      );
      return null;
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
          onShare: () => unawaited(
            _copyLyricsShareText(context, library, track),
          ),
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

    final result = await FilePicker.pickFiles(type: FileType.audio);

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

  Future<void> _importAudioFolder(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    final folderPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Import audio folder',
    );
    if (!context.mounted || folderPath == null) {
      return;
    }

    try {
      final scanResult = await const LocalFolderScanner().scan(
        folderPath,
        importedAt: DateTime.now(),
      );
      if (scanResult.tracks.isNotEmpty) {
        await library.addTracks(scanResult.tracks);
        for (final entry in scanResult.sidecarLyricsByTrackId.entries) {
          await library.setLyricsIfAbsent(entry.key, entry.value);
        }
      }
      await library.watchLocalFolder(folderPath);

      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(_folderImportSummary(scanResult))),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(_folderImportErrorMessage(error))),
      );
    }
  }

  Future<void> _showSleepTimer(BuildContext context) async {
    final player = context.read<PlayerController>();
    final durations = <int>[5, 15, 30, 60, 90];
    var fadeOut = player.sleepTimerFadeOutEnabled;
    var fadeDuration =
        sleepTimerFadeDurationOptions.contains(player.sleepTimerFadeDuration)
            ? player.sleepTimerFadeDuration
            : defaultSleepTimerFadeDuration;

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
                    subtitle: Text(
                      'Lower volume during the final '
                      '${sleepTimerFadeDurationLabel(fadeDuration)}.',
                    ),
                    value: fadeOut,
                    onChanged: (value) {
                      setSheetState(() {
                        fadeOut = value;
                      });
                    },
                  ),
                  if (fadeOut)
                    ListTile(
                      leading: const Icon(Icons.timelapse_outlined),
                      title: const Text('Fade duration'),
                      subtitle: Text(sleepTimerFadeDurationLabel(fadeDuration)),
                      trailing: DropdownButton<Duration>(
                        value: fadeDuration,
                        items: <DropdownMenuItem<Duration>>[
                          for (final option in sleepTimerFadeDurationOptions)
                            DropdownMenuItem<Duration>(
                              value: option,
                              child: Text(sleepTimerFadeDurationLabel(option)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setSheetState(() {
                            fadeDuration = value;
                          });
                        },
                      ),
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
                        fadeDuration: fadeDuration,
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
                          ? Text(
                              'Fade out in the final '
                              '${sleepTimerFadeDurationLabel(fadeDuration)}.',
                            )
                          : null,
                      onTap: () {
                        player.startSleepTimer(
                          Duration(minutes: minutes),
                          fadeOut: fadeOut,
                          fadeDuration: fadeDuration,
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
    required Duration fadeDuration,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final duration = await _promptForCustomSleepTimerDuration(context);
    if (!context.mounted || duration == null) {
      return;
    }

    player.startSleepTimer(
      duration,
      fadeOut: fadeOut,
      fadeDuration: fadeDuration,
    );

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          fadeOut
              ? 'Sleep timer set for ${duration.inMinutes} minute(s) '
                  'with ${sleepTimerFadeDurationLabel(fadeDuration)} fade-out.'
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

  if (updated != null && _canWriteEmbeddedMetadata(updated)) {
    final writeFile = await _confirmEmbeddedTagWrite(context, updated);
    if (!context.mounted) {
      return;
    }
    if (writeFile == true) {
      try {
        if (_isLocalMp3(updated)) {
          await const Mp3Id3v1TagWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            genre: updated.genre,
          );
        } else if (_isLocalFlac(updated)) {
          await const FlacVorbisCommentWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            genre: updated.genre,
          );
        } else {
          await const WavRiffInfoWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            genre: updated.genre,
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Saved app metadata, but could not update MP3 tags: $error')),
          );
        }
        return;
      }
    }
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

class _LyricsEditorResult {
  const _LyricsEditorResult({
    required this.plainText,
    this.sourceId = 'manual',
    this.sourceName = '',
    this.sourceExternalId = '',
    this.sourceUri,
  });

  final String plainText;
  final String sourceId;
  final String sourceName;
  final String sourceExternalId;
  final Uri? sourceUri;
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
    required this.onShare,
  });

  final Track track;
  final TrackLyrics? lyrics;
  final PlayerController player;
  final VoidCallback onEdit;
  final VoidCallback onShare;

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
        sourceLabel: currentLyrics.attributionLabel,
        onEdit: onEdit,
        onShare: onShare,
      );
    }

    return _SyncedNowPlayingLyrics(
      track: track,
      lines: syncedLines,
      sourceLabel: currentLyrics.attributionLabel,
      player: player,
      onEdit: onEdit,
      onShare: onShare,
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
    required this.sourceLabel,
    required this.onEdit,
    required this.onShare,
  });

  final Track track;
  final String lyrics;
  final String? sourceLabel;
  final VoidCallback onEdit;
  final VoidCallback onShare;

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
                subtitle: _lyricsSubtitle('Plain lyrics', sourceLabel),
                onEdit: onEdit,
                onShare: onShare,
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
    required this.sourceLabel,
    required this.player,
    required this.onEdit,
    required this.onShare,
  });

  final Track track;
  final List<SyncedLyricLine> lines;
  final String? sourceLabel;
  final PlayerController player;
  final VoidCallback onEdit;
  final VoidCallback onShare;

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
                      subtitle: _lyricsSubtitle(
                        activeIndex == -1
                            ? 'Synced lyrics'
                            : 'Line ${activeIndex + 1} of ${widget.lines.length}',
                        widget.sourceLabel,
                      ),
                      onEdit: widget.onEdit,
                      onShare: widget.onShare,
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
    this.onShare,
  });

  final Track track;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.subtitles_outlined),
      title: Text(track.title),
      subtitle: Text('${track.artist} · $subtitle'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onShare != null)
            IconButton(
              tooltip: 'Copy share text',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
            ),
          IconButton(
            tooltip: 'Edit lyrics',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }
}

String _lyricsSubtitle(String base, String? sourceLabel) {
  final source = sourceLabel?.trim() ?? '';
  return source.isEmpty ? base : '$base - $source';
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

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    required this.onImport,
    required this.onImportFolder,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final VoidCallback onImport;
  final VoidCallback onImportFolder;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  LibraryChartRange _chartRange = LibraryChartRange.thirtyDays;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = library.homeFeedSections();
    final charts = library.localCharts(range: _chartRange);
    final recommendations = library.personalizedRecommendations(limit: 6);
    final moodMixes = library.localMoodMixes(limit: 5);
    if (sections.isEmpty) {
      return _EmptyHomeFeed(
        onImport: widget.onImport,
        onImportFolder: widget.onImportFolder,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text('Home', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        ..._homeTrackPreviewWidgets(
          context: context,
          player: player,
          library: library,
          icon: Icons.auto_awesome,
          title: 'For you',
          subtitle: 'Local recommendations',
          tracks: recommendations,
        ),
        for (final mix in moodMixes)
          ..._homeTrackPreviewWidgets(
            context: context,
            player: player,
            library: library,
            icon: _moodMixIcon(mix.type),
            title: mix.name,
            subtitle: mix.description,
            tracks: mix.tracks,
          ),
        for (final section in sections) ...[
          _HomeSectionHeader(section: section),
          const SizedBox(height: 4),
          for (final track in section.tracks)
            TrackTile(
              track: track,
              onPlay: () => _playTrackWithResume(
                context,
                player,
                library,
                track,
                queue: section.tracks,
              ),
              onStartRadio: () => unawaited(
                _startTrackRadio(context, player, library, track),
              ),
              onSimilarTracks: () => unawaited(
                _showSimilarTracks(
                  context,
                  track,
                  onAddToPlaylist: widget.onAddToPlaylist,
                  onLyrics: widget.onLyrics,
                ),
              ),
              onShare: () => unawaited(
                _copyTrackShareText(context, library, track),
              ),
              onFavorite: () => library.toggleFavorite(track.id),
              onAddToPlaylist: () => widget.onAddToPlaylist(track),
              onLyrics: () => widget.onLyrics(track),
              onEditMetadata: () => unawaited(
                _showTrackMetadataEditor(context, track),
              ),
              onRemove: () => library.removeTrack(track.id),
            ),
          const SizedBox(height: 12),
        ],
        if (charts.stats.playbackCount > 0)
          _LocalChartsPreview(
            snapshot: charts,
            selectedRange: _chartRange,
            onRangeChanged: (range) {
              setState(() => _chartRange = range);
            },
          ),
      ],
    );
  }

  List<Widget> _homeTrackPreviewWidgets({
    required BuildContext context,
    required PlayerController player,
    required LibraryStore library,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Track> tracks,
  }) {
    if (tracks.isEmpty) {
      return <Widget>[];
    }

    return <Widget>[
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Text('${tracks.length}'),
      ),
      const SizedBox(height: 4),
      for (final track in tracks)
        TrackTile(
          track: track,
          onPlay: () => _playTrackWithResume(
            context,
            player,
            library,
            track,
            queue: tracks,
          ),
          onStartRadio: () => unawaited(
            _startTrackRadio(context, player, library, track),
          ),
          onSimilarTracks: () => unawaited(
            _showSimilarTracks(
              context,
              track,
              onAddToPlaylist: widget.onAddToPlaylist,
              onLyrics: widget.onLyrics,
            ),
          ),
          onShare: () => unawaited(
            _copyTrackShareText(context, library, track),
          ),
          onFavorite: () => library.toggleFavorite(track.id),
          onAddToPlaylist: () => widget.onAddToPlaylist(track),
          onLyrics: () => widget.onLyrics(track),
          onEditMetadata: () => unawaited(
            _showTrackMetadataEditor(context, track),
          ),
          onRemove: () => library.removeTrack(track.id),
        ),
      const SizedBox(height: 12),
    ];
  }
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.section});

  final LibraryHomeSection section;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_homeSectionIcon(section.type)),
      title: Text(_homeSectionTitle(section.type)),
      subtitle: Text(_homeSectionSubtitle(section.type)),
      trailing: Text('${section.tracks.length}'),
    );
  }
}

class _LocalChartsPreview extends StatelessWidget {
  const _LocalChartsPreview({
    required this.snapshot,
    required this.selectedRange,
    required this.onRangeChanged,
  });

  final LibraryChartsSnapshot snapshot;
  final LibraryChartRange selectedRange;
  final ValueChanged<LibraryChartRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final stats = snapshot.stats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 4),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Local charts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<LibraryChartRange>(
                initialValue: selectedRange,
                decoration: const InputDecoration(
                  labelText: 'Range',
                  prefixIcon: Icon(Icons.bar_chart),
                ),
                items: <DropdownMenuItem<LibraryChartRange>>[
                  for (final range in LibraryChartRange.values)
                    DropdownMenuItem<LibraryChartRange>(
                      value: range,
                      child: Text(_libraryChartRangeLabel(range)),
                    ),
                ],
                onChanged: (range) {
                  if (range != null) {
                    onRangeChanged(range);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _LibraryStatsOverview(stats: stats),
        const SizedBox(height: 16),
        _LibraryStatsCharts(stats: stats),
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
    );
  }
}

class _EmptyHomeFeed extends StatelessWidget {
  const _EmptyHomeFeed({
    required this.onImport,
    required this.onImportFolder,
  });

  final VoidCallback onImport;
  final VoidCallback onImportFolder;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.home_outlined, size: 56),
            const SizedBox(height: 16),
            Text('Home is empty', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Import music to build your local feed.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.library_add),
                  label: const Text('Import audio'),
                ),
                OutlinedButton.icon(
                  onPressed: onImportFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Import folder'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData _homeSectionIcon(LibraryHomeSectionType type) {
  switch (type) {
    case LibraryHomeSectionType.continueListening:
      return Icons.play_circle_outline;
    case LibraryHomeSectionType.recentlyPlayed:
      return Icons.history_outlined;
    case LibraryHomeSectionType.radioSeeds:
      return Icons.radio_outlined;
    case LibraryHomeSectionType.mostPlayed:
      return Icons.trending_up;
    case LibraryHomeSectionType.favorites:
      return Icons.favorite_border;
    case LibraryHomeSectionType.subscribedEpisodes:
      return Icons.podcasts_outlined;
    case LibraryHomeSectionType.recentlyAdded:
      return Icons.new_releases_outlined;
  }
}

String _homeSectionTitle(LibraryHomeSectionType type) {
  switch (type) {
    case LibraryHomeSectionType.continueListening:
      return 'Continue listening';
    case LibraryHomeSectionType.recentlyPlayed:
      return 'Recently played';
    case LibraryHomeSectionType.radioSeeds:
      return 'Start radio';
    case LibraryHomeSectionType.mostPlayed:
      return 'Most played';
    case LibraryHomeSectionType.favorites:
      return 'Favorites';
    case LibraryHomeSectionType.subscribedEpisodes:
      return 'Subscribed episodes';
    case LibraryHomeSectionType.recentlyAdded:
      return 'Recently added';
  }
}

String _homeSectionSubtitle(LibraryHomeSectionType type) {
  switch (type) {
    case LibraryHomeSectionType.continueListening:
      return 'Saved playback progress';
    case LibraryHomeSectionType.recentlyPlayed:
      return 'Latest library plays';
    case LibraryHomeSectionType.radioSeeds:
      return 'Seeds with local matches';
    case LibraryHomeSectionType.mostPlayed:
      return 'Highest play counts';
    case LibraryHomeSectionType.favorites:
      return 'Hearted tracks';
    case LibraryHomeSectionType.subscribedEpisodes:
      return 'Saved episodes from your podcast feeds';
    case LibraryHomeSectionType.recentlyAdded:
      return 'Newest imports';
  }
}

String _libraryChartRangeLabel(LibraryChartRange range) {
  switch (range) {
    case LibraryChartRange.allTime:
      return 'All time';
    case LibraryChartRange.sevenDays:
      return 'Last 7 days';
    case LibraryChartRange.thirtyDays:
      return 'Last 30 days';
    case LibraryChartRange.year:
      return 'Last year';
  }
}

IconData _moodMixIcon(LibraryMoodMixType type) {
  switch (type) {
    case LibraryMoodMixType.focus:
      return Icons.center_focus_strong;
    case LibraryMoodMixType.energy:
      return Icons.bolt_outlined;
    case LibraryMoodMixType.chill:
      return Icons.spa_outlined;
    case LibraryMoodMixType.workout:
      return Icons.fitness_center;
    case LibraryMoodMixType.sleep:
      return Icons.nightlight_round;
  }
}

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
    required this.onImportFolder,
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
  final VoidCallback onImportFolder;
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
              onImportFolder: onImportFolder,
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
                  onStartRadio: () => unawaited(
                    _startTrackRadio(context, player, library, track),
                  ),
                  onSimilarTracks: () => unawaited(
                    _showSimilarTracks(
                      context,
                      track,
                      onAddToPlaylist: onAddToPlaylist,
                      onLyrics: onLyrics,
                    ),
                  ),
                  onShare: () => unawaited(
                    _copyTrackShareText(context, library, track),
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

Future<void> _showLibraryFolderNodeTracks(
  BuildContext context, {
  required LibraryFolderNode node,
  required ValueChanged<Track> onAddToPlaylist,
  required ValueChanged<Track> onLyrics,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) {
      return _LibraryFolderNodeTracksSheet(
        node: node,
        onAddToPlaylist: onAddToPlaylist,
        onLyrics: onLyrics,
      );
    },
  );
}

Future<void> _showSimilarTracks(
  BuildContext context,
  Track seedTrack, {
  required ValueChanged<Track> onAddToPlaylist,
  required ValueChanged<Track> onLyrics,
}) async {
  final player = context.read<PlayerController>();

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) {
      return _SimilarTracksSheet(
        seedTrackId: seedTrack.id,
        player: player,
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
    if (type == LibraryBrowseType.folder) {
      final folderNodes = library.folderTree();
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: Icon(_libraryBrowseTypeIcon(type)),
              title: Text(_libraryBrowseTypeLabel(type)),
              subtitle: Text('${folderNodes.length} folder node(s)'),
            ),
            const Divider(height: 1),
            if (folderNodes.isEmpty)
              ListTile(
                leading: Icon(_libraryBrowseTypeIcon(type)),
                title: const Text('Nothing to browse yet'),
                subtitle: const Text(
                  'Import a local audio folder to build the tree.',
                ),
              )
            else
              for (final node in folderNodes)
                _LibraryFolderNodeTile(
                  rootContext: rootContext,
                  node: node,
                  onAddToPlaylist: onAddToPlaylist,
                  onLyrics: onLyrics,
                ),
          ],
        ),
      );
    }

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

class _LibraryFolderNodeTile extends StatelessWidget {
  const _LibraryFolderNodeTile({
    required this.rootContext,
    required this.node,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final BuildContext rootContext;
  final LibraryFolderNode node;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final indent = node.depth > 6 ? 72.0 : 12.0 * node.depth;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent),
      child: ListTile(
        leading: Icon(
          node.childCount > 0
              ? Icons.folder_open_outlined
              : Icons.folder_outlined,
        ),
        title: Text(node.label),
        subtitle: Text(_libraryFolderNodeSubtitle(node)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).pop();
          unawaited(
            _showLibraryFolderNodeTracks(
              rootContext,
              node: node,
              onAddToPlaylist: onAddToPlaylist,
              onLyrics: onLyrics,
            ),
          );
        },
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
                  trailing: IconButton(
                    tooltip: 'Copy share text',
                    onPressed: () => unawaited(
                      _copyBrowseGroupShareText(
                        context,
                        library,
                        type,
                        group,
                      ),
                    ),
                    icon: const Icon(Icons.ios_share),
                  ),
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
                onStartRadio: () => unawaited(
                  _startTrackRadio(context, player, library, track),
                ),
                onSimilarTracks: () => unawaited(
                  _showSimilarTracks(
                    context,
                    track,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                onShare: () => unawaited(
                  _copyTrackShareText(context, library, track),
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

class _LibraryFolderNodeTracksSheet extends StatelessWidget {
  const _LibraryFolderNodeTracksSheet({
    required this.node,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final LibraryFolderNode node;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final tracks = library.tracksForFolderNode(node.key);

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
                  leading: const Icon(Icons.folder_open_outlined),
                  title: Text(node.path),
                  subtitle: Text(_libraryFolderNodeSubtitle(node)),
                  trailing: IconButton(
                    tooltip: 'Copy share text',
                    onPressed: () => unawaited(
                      _copyFolderNodeShareText(context, library, node),
                    ),
                    icon: const Icon(Icons.ios_share),
                  ),
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
                onStartRadio: () => unawaited(
                  _startTrackRadio(context, player, library, track),
                ),
                onSimilarTracks: () => unawaited(
                  _showSimilarTracks(
                    context,
                    track,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                onShare: () => unawaited(
                  _copyTrackShareText(context, library, track),
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

class _SimilarTracksSheet extends StatelessWidget {
  const _SimilarTracksSheet({
    required this.seedTrackId,
    required this.player,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final String seedTrackId;
  final PlayerController player;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final seedTrack = _trackById(library, seedTrackId);
    final matches = library.similarTracksForTrack(seedTrackId);
    final tracks = matches.map((match) => match.track).toList(growable: false);
    var itemCount = 1;
    if (seedTrack != null) {
      itemCount = matches.isEmpty ? 2 : matches.length + 1;
    }

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView.separated(
            controller: controller,
            itemCount: itemCount,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (seedTrack == null) {
                return const ListTile(
                  leading: Icon(Icons.hub_outlined),
                  title: Text('Track is no longer in the library'),
                );
              }

              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text('Similar to ${seedTrack.title}'),
                  subtitle: Text(
                    '${seedTrack.artist} · ${seedTrack.album} · '
                    '${seedTrack.genre}',
                  ),
                );
              }

              if (matches.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.travel_explore_outlined),
                  title: Text('No similar local tracks yet'),
                  subtitle: Text('Import or edit metadata to build matches.'),
                );
              }

              final match = matches[index - 1];
              final track = match.track;
              return TrackTile(
                track: track,
                detailText: _similarityReasonText(match.reasons),
                onPlay: () => _playTrackWithResume(
                  context,
                  player,
                  library,
                  track,
                  queue: tracks,
                ),
                onStartRadio: () => unawaited(
                  _startTrackRadio(context, player, library, track),
                ),
                onSimilarTracks: () => unawaited(
                  _showSimilarTracks(
                    context,
                    track,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                onShare: () => unawaited(
                  _copyTrackShareText(context, library, track),
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

  Track? _trackById(LibraryStore library, String id) {
    for (final track in library.tracks) {
      if (track.id == id) {
        return track;
      }
    }

    return null;
  }
}

String _similarityReasonText(List<LibrarySimilarityReason> reasons) {
  if (reasons.isEmpty) {
    return 'Matched local metadata';
  }

  final labels = reasons.map(_similarityReasonLabel).toList(growable: false);
  return 'Matches ${labels.join(', ')}';
}

String _similarityReasonLabel(LibrarySimilarityReason reason) {
  switch (reason) {
    case LibrarySimilarityReason.artist:
      return 'artist';
    case LibrarySimilarityReason.album:
      return 'album';
    case LibrarySimilarityReason.genre:
      return 'genre';
    case LibrarySimilarityReason.folder:
      return 'folder';
    case LibrarySimilarityReason.source:
      return 'source';
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

String _libraryFolderNodeSubtitle(LibraryFolderNode node) {
  final parts = <String>['${node.trackCount} track(s)'];
  if (node.childCount > 0) {
    parts.add('${node.childCount} folder(s)');
  }
  if (node.directTrackCount > 0) {
    parts.add('${node.directTrackCount} here');
  }
  if (node.totalDuration > Duration.zero) {
    parts.add(_formatBrowseDuration(node.totalDuration));
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

bool _canWriteEmbeddedMetadata(Track track) {
  return _isLocalMp3(track) || _isLocalFlac(track) || _isLocalWav(track);
}

bool _isLocalMp3(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.mp3');
}

bool _isLocalFlac(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.flac');
}

bool _isLocalWav(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.wav');
}

Future<bool?> _confirmEmbeddedTagWrite(BuildContext context, Track track) {
  final format = _isLocalMp3(track)
      ? 'MP3'
      : _isLocalFlac(track)
      ? 'FLAC'
      : 'WAV';
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Update $format file tags?'),
      content: Text(
        format == 'MP3'
            ? 'This writes title, artist, album, and genre to standard ID3v2 MP3 text tags, with an ID3v1 compatibility tag. Artwork and other supported ID3v2 frames are preserved. Unsupported tag layouts are left unchanged.'
            : format == 'FLAC'
            ? 'This writes title, artist, album, and genre to standard FLAC Vorbis comments. Artwork and other FLAC metadata blocks are preserved.'
            : 'This writes title, artist, album, and genre to standard WAV RIFF INFO fields. Other RIFF chunks and audio bytes are preserved. Characters outside legacy Latin-1 are replaced with question marks in the file tag.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep app-only'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.save_outlined),
          label: Text('Update $format'),
        ),
      ],
    ),
  );
}

String _playlistDocumentFormatFileExtension(PlaylistDocumentFormat format) {
  switch (format) {
    case PlaylistDocumentFormat.json:
      return 'json';
    case PlaylistDocumentFormat.m3u:
      return 'm3u';
    case PlaylistDocumentFormat.csv:
      return 'csv';
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
  if (rule.sourceId.trim().isNotEmpty) {
    parts.add('Source: ${rule.sourceId}');
  }
  if (rule.artist.trim().isNotEmpty) {
    parts.add('Artist: ${rule.artist}');
  }
  if (rule.album.trim().isNotEmpty) {
    parts.add('Album: ${rule.album}');
  }
  if (rule.genre.trim().isNotEmpty) {
    parts.add('Genre: ${rule.genre}');
  }
  if (rule.minimumDurationSeconds > 0) {
    parts.add('${rule.minimumDurationSeconds}s+');
  }
  if (rule.maximumDurationSeconds > 0) {
    parts.add('up to ${rule.maximumDurationSeconds}s');
  }
  if (rule.favoritesOnly) {
    parts.add('Favorites');
  }
  if (rule.minimumPlayCount > 0) {
    parts.add('${rule.minimumPlayCount}+ plays');
  }
  if (rule.minimumDaysSinceLastPlayed > 0) {
    parts.add('${rule.minimumDaysSinceLastPlayed}+ days since played');
  }
  parts.add(_customSmartPlaylistSortLabel(rule.sortMode));
  parts.add('Limit ${rule.limit}');

  return parts.join(' · ');
}

class _CustomSmartPlaylistDraft {
  const _CustomSmartPlaylistDraft({
    required this.name,
    required this.query,
    required this.sourceId,
    required this.artist,
    required this.album,
    required this.genre,
    required this.minimumDurationSeconds,
    required this.maximumDurationSeconds,
    required this.favoritesOnly,
    required this.minimumPlayCount,
    required this.minimumDaysSinceLastPlayed,
    required this.sortMode,
    required this.limit,
  });

  final String name;
  final String query;
  final String sourceId;
  final String artist;
  final String album;
  final String genre;
  final int minimumDurationSeconds;
  final int maximumDurationSeconds;
  final bool favoritesOnly;
  final int minimumPlayCount;
  final int minimumDaysSinceLastPlayed;
  final CustomSmartPlaylistSortMode sortMode;
  final int limit;
}

class _PlaylistsTab extends StatefulWidget {
  const _PlaylistsTab({
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  State<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<_PlaylistsTab> {
  String? _folderFilter;

  ValueChanged<Track> get onAddToPlaylist => widget.onAddToPlaylist;
  ValueChanged<Track> get onLyrics => widget.onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final smartPlaylists = library.smartPlaylists();
    final customSmartPlaylists = library.customSmartPlaylists;
    final folders = library.playlistFolders;
    final hasUnfiledPlaylists = library.playlists.any(
      (playlist) => playlist.folder.trim().isEmpty,
    );
    final activeFolder = _folderFilter != null &&
            _folderFilter != '' &&
            !folders.contains(_folderFilter)
        ? null
        : _folderFilter;
    final manualPlaylists = library.playlists.where((playlist) {
      if (activeFolder == null) {
        return true;
      }
      return playlist.folder.trim() == activeFolder;
    }).toList(growable: false);

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
        if (folders.isNotEmpty || hasUnfiledPlaylists) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('All'),
                selected: activeFolder == null,
                onSelected: (_) => setState(() => _folderFilter = null),
              ),
              if (hasUnfiledPlaylists)
                ChoiceChip(
                  label: const Text('Unfiled'),
                  selected: activeFolder == '',
                  onSelected: (_) => setState(() => _folderFilter = ''),
                ),
              for (final folder in folders)
                ChoiceChip(
                  label: Text(folder),
                  selected: activeFolder == folder,
                  onSelected: (_) => setState(() => _folderFilter = folder),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (library.playlists.isEmpty)
          _EmptyPlaylists(onCreate: () => _createPlaylist(context))
        else if (manualPlaylists.isEmpty)
          const ListTile(
            leading: Icon(Icons.folder_off_outlined),
            title: Text('No playlists in this folder'),
          )
        else
          for (final playlist in manualPlaylists)
            _PlaylistCard(
              playlist: playlist,
              tracks: library.tracksForPlaylist(playlist.id),
              onOpen: () => _showPlaylist(context, playlist.id),
              onExport: (format) => _showPlaylistExport(
                context,
                playlist,
                format,
              ),
              onShare: () => unawaited(
                _copyPlaylistShareText(context, library, playlist),
              ),
              onArtwork: () => _editPlaylistArtwork(context, playlist),
              onRename: () => _renamePlaylist(context, playlist),
              onMoveToFolder: () => _movePlaylistToFolder(context, playlist),
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text('Choose ${_playlistDocumentFormatLabel(format)} file'),
                subtitle: Text(
                  'Import a .${_playlistDocumentFormatFileExtension(format)} playlist file.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importPlaylistFile(context, format);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_outlined),
                title: Text('Paste ${_playlistDocumentFormatLabel(format)} content'),
                subtitle: const Text('Import a copied playlist document.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importPlaylistText(context, format);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importPlaylistFile(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final extension = _playlistDocumentFormatFileExtension(format);
    final file = await FilePicker.pickFile(
      allowedExtensions: <String>[extension],
      dialogTitle: 'Import ${_playlistDocumentFormatLabel(format)} playlist',
      type: FileType.custom,
    );
    if (!context.mounted || file == null) {
      return;
    }
    if (!file.name.toLowerCase().endsWith('.$extension')) {
      messenger.showSnackBar(
        SnackBar(content: Text('Choose a .$extension playlist file.')),
      );
      return;
    }

    try {
      final document = utf8.decode(
        await file.readAsBytes(),
        allowMalformed: false,
      );
      if (!context.mounted) {
        return;
      }
      await _importPlaylistDocument(context, format, document);
    } on FormatException {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Playlist files must be valid UTF-8 text.')),
      );
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read playlist file: $error')),
      );
    }
  }

  Future<void> _importPlaylistText(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    final document = await _promptForPlaylistDocument(context, format);
    if (!context.mounted || document == null) {
      return;
    }
    await _importPlaylistDocument(context, format, document);
  }

  Future<void> _importPlaylistDocument(
    BuildContext context,
    PlaylistDocumentFormat format,
    String document,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

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
      sourceId: draft.sourceId,
      artist: draft.artist,
      album: draft.album,
      genre: draft.genre,
      minimumDurationSeconds: draft.minimumDurationSeconds,
      maximumDurationSeconds: draft.maximumDurationSeconds,
      favoritesOnly: draft.favoritesOnly,
      minimumPlayCount: draft.minimumPlayCount,
      minimumDaysSinceLastPlayed: draft.minimumDaysSinceLastPlayed,
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
      sourceId: draft.sourceId,
      artist: draft.artist,
      album: draft.album,
      genre: draft.genre,
      minimumDurationSeconds: draft.minimumDurationSeconds,
      maximumDurationSeconds: draft.maximumDurationSeconds,
      favoritesOnly: draft.favoritesOnly,
      minimumPlayCount: draft.minimumPlayCount,
      minimumDaysSinceLastPlayed: draft.minimumDaysSinceLastPlayed,
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

  Future<void> _movePlaylistToFolder(
    BuildContext context,
    Playlist playlist,
  ) async {
    final controller = TextEditingController(text: playlist.folder);
    try {
      final folder = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Move ${playlist.name}'),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Folder',
                hintText: 'Leave empty for Unfiled',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
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
                child: const Text('Move'),
              ),
            ],
          );
        },
      );
      if (!context.mounted || folder == null) {
        return;
      }
      await context.read<LibraryStore>().updatePlaylistFolder(
        playlist.id,
        folder,
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editPlaylistArtwork(
    BuildContext context,
    Playlist playlist,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose image file'),
                subtitle: const Text('Store a private PNG, JPEG, GIF, or WebP image.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickPlaylistArtworkFile(context, playlist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Set image URL'),
                subtitle: const Text('Use an http or https image URL.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _setPlaylistArtworkUrl(context, playlist);
                },
              ),
              if (playlist.artworkUri != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove artwork'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _removePlaylistArtwork(context, playlist);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickPlaylistArtworkFile(
    BuildContext context,
    Playlist playlist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await FilePicker.pickFile(
      type: FileType.image,
      dialogTitle: 'Choose playlist artwork',
    );
    if (!context.mounted || file == null) {
      return;
    }

    try {
      final artworkUri = await _playlistArtworkFileStore.save(
        await file.readAsBytes(),
      );
      if (!context.mounted) {
        return;
      }
      final updated = await context.read<LibraryStore>().updatePlaylistArtwork(
        playlist.id,
        artworkUri,
      );
      if (!context.mounted || updated == null) {
        return;
      }
      await _playlistArtworkFileStore.delete(playlist.artworkUri);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Updated artwork for ${updated.name}.')),
      );
    } on FormatException catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Exception catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save artwork: $error')),
        );
      }
    }
  }

  Future<void> _setPlaylistArtworkUrl(
    BuildContext context,
    Playlist playlist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final initialValue = playlist.artworkUri != null &&
            _isNetworkImageUri(playlist.artworkUri!)
        ? playlist.artworkUri!.toString()
        : '';
    final value = await _promptForPlaylistArtwork(context, initialValue);
    if (!context.mounted || value == null) {
      return;
    }

    final normalized = value.trim();
    final artworkUri = Uri.tryParse(normalized);
    if (artworkUri == null || !_isNetworkImageUri(artworkUri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter an http or https image URL.')),
      );
      return;
    }

    final updated = await context.read<LibraryStore>().updatePlaylistArtwork(
      playlist.id,
      artworkUri,
    );
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(playlist.artworkUri);
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Updated artwork for ${updated.name}.')),
    );
  }

  Future<void> _removePlaylistArtwork(
    BuildContext context,
    Playlist playlist,
  ) async {
    final updated = await context.read<LibraryStore>().updatePlaylistArtwork(
      playlist.id,
      null,
    );
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(playlist.artworkUri);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed artwork for ${updated.name}.')),
    );
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.deletePlaylist(playlist.id);
    await _playlistArtworkFileStore.delete(playlist.artworkUri);

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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: Text('Save ${_playlistDocumentFormatLabel(format)} file'),
                subtitle: const Text('Write a portable playlist to a chosen location.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _savePlaylistExportFile(context, playlist, format);
                },
              ),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: Text('View ${_playlistDocumentFormatLabel(format)} content'),
                subtitle: const Text('Inspect or copy the playlist document.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showPlaylistExportDocument(context, playlist, format);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePlaylistExportFile(
    BuildContext context,
    Playlist playlist,
    PlaylistDocumentFormat format,
  ) async {
    final library = context.read<LibraryStore>();
    final document = library.exportPlaylistDocument(
      playlist.id,
      format: format,
    );
    final extension = _playlistDocumentFormatFileExtension(format);
    final fileName = playlistExportFileName(
      playlistName: playlist.name,
      extension: extension,
    );
    final messenger = ScaffoldMessenger.of(context);
    final bytes = Uint8List.fromList(utf8.encode(document));

    try {
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save ${_playlistDocumentFormatLabel(format)} playlist',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: <String>[extension],
        bytes: bytes,
      );
      if (outputPath == null || outputPath.isEmpty) {
        return;
      }
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
      }
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName.')));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save playlist file: $error')),
      );
    }
  }

  Future<void> _showPlaylistExportDocument(
    BuildContext context,
    Playlist playlist,
    PlaylistDocumentFormat format,
  ) async {
    final document = context.read<LibraryStore>().exportPlaylistDocument(
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
    final sourceIdController = TextEditingController(
      text: initialRule?.sourceId ?? '',
    );
    final artistController = TextEditingController(
      text: initialRule?.artist ?? '',
    );
    final albumController = TextEditingController(
      text: initialRule?.album ?? '',
    );
    final genreController = TextEditingController(
      text: initialRule?.genre ?? '',
    );
    final minimumDurationController = TextEditingController(
      text: (initialRule?.minimumDurationSeconds ?? 0).toString(),
    );
    final maximumDurationController = TextEditingController(
      text: (initialRule?.maximumDurationSeconds ?? 0).toString(),
    );
    final minimumPlayCountController = TextEditingController(
      text: (initialRule?.minimumPlayCount ?? 0).toString(),
    );
    final minimumDaysSinceLastPlayedController = TextEditingController(
      text: (initialRule?.minimumDaysSinceLastPlayed ?? 0).toString(),
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
                  sourceId: sourceIdController.text.trim(),
                  artist: artistController.text.trim(),
                  album: albumController.text.trim(),
                  genre: genreController.text.trim(),
                  minimumDurationSeconds:
                      int.tryParse(minimumDurationController.text.trim()) ?? 0,
                  maximumDurationSeconds:
                      int.tryParse(maximumDurationController.text.trim()) ?? 0,
                  favoritesOnly: favoritesOnly,
                  minimumPlayCount:
                      int.tryParse(minimumPlayCountController.text.trim()) ??
                          0,
                  minimumDaysSinceLastPlayed:
                      int.tryParse(
                        minimumDaysSinceLastPlayedController.text.trim(),
                      ) ??
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
                        TextField(
                          controller: sourceIdController,
                          decoration: const InputDecoration(
                            labelText: 'Exact source ID',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: artistController,
                          decoration: const InputDecoration(
                            labelText: 'Exact artist',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: albumController,
                          decoration: const InputDecoration(
                            labelText: 'Exact album',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: genreController,
                          decoration: const InputDecoration(
                            labelText: 'Exact genre',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: minimumDurationController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum duration (seconds)',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: maximumDurationController,
                          decoration: const InputDecoration(
                            labelText: 'Maximum duration (seconds)',
                          ),
                          keyboardType: TextInputType.number,
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
                        TextField(
                          controller: minimumDaysSinceLastPlayedController,
                          decoration: const InputDecoration(
                            labelText: 'Not played in at least (days)',
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
      sourceIdController.dispose();
      artistController.dispose();
      albumController.dispose();
      genreController.dispose();
      minimumDurationController.dispose();
      maximumDurationController.dispose();
      minimumPlayCountController.dispose();
      minimumDaysSinceLastPlayedController.dispose();
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
                onStartRadio: () => unawaited(
                  _startTrackRadio(context, player, library, track),
                ),
                onSimilarTracks: () => unawaited(
                  _showSimilarTracks(
                    context,
                    track,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                onShare: () => unawaited(
                  _copyTrackShareText(context, library, track),
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
                onStartRadio: () => unawaited(
                  _startTrackRadio(context, player, library, track),
                ),
                onSimilarTracks: () => unawaited(
                  _showSimilarTracks(
                    context,
                    track,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                onShare: () => unawaited(
                  _copyTrackShareText(context, library, track),
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
                leading: PlaylistArtwork(
                  playlist: playlist,
                  tracks: allTracks,
                  size: 48,
                ),
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
    required this.tracks,
    required this.onOpen,
    required this.onExport,
    required this.onShare,
    required this.onArtwork,
    required this.onRename,
    required this.onMoveToFolder,
    required this.onDelete,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final VoidCallback onOpen;
  final ValueChanged<PlaylistDocumentFormat> onExport;
  final VoidCallback onShare;
  final VoidCallback onArtwork;
  final VoidCallback onRename;
  final VoidCallback onMoveToFolder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: PlaylistArtwork(playlist: playlist, tracks: tracks),
        title: Text(playlist.name),
        subtitle: Text(
          playlist.folder.trim().isEmpty
              ? '${playlist.trackCount} track(s)'
              : '${playlist.folder} · ${playlist.trackCount} track(s)',
        ),
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
              case _PlaylistAction.share:
                onShare();
                break;
              case _PlaylistAction.rename:
                onRename();
                break;
              case _PlaylistAction.folder:
                onMoveToFolder();
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
            PopupMenuItem(
              value: _PlaylistAction.share,
              child: ListTile(
                leading: Icon(Icons.ios_share),
                title: Text('Copy share text'),
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
              value: _PlaylistAction.folder,
              child: ListTile(
                leading: Icon(Icons.drive_folder_upload_outlined),
                title: Text('Move to folder'),
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
  share,
  rename,
  folder,
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
  final _historySearchController = TextEditingController();

  ListeningHistoryRange _statsRange = ListeningHistoryRange.all;
  String _historyQuery = '';

  @override
  void dispose() {
    _historySearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final now = DateTime.now();
    final statsFrom = _historyStatsRangeStart(_statsRange, now);
    final statsTo = _statsRange == ListeningHistoryRange.all ? null : now;
    final historyQuery = _historyQuery.trim();
    final hasHistorySearch = historyQuery.isNotEmpty;
    final recentlyPlayed = library.recentlyPlayedTracks(
      from: statsFrom,
      to: statsTo,
      query: historyQuery,
    );
    final historyEntries = library.playbackHistoryEntries(
      from: statsFrom,
      to: statsTo,
      query: historyQuery,
    );
    final historyTracksById = <String, Track>{
      for (final track in library.tracks) track.id: track,
    };
    final stats = library.libraryStats(from: statsFrom, to: statsTo);
    final heatmapFrom = statsFrom ?? now.subtract(const Duration(days: 83));
    final heatmapDays = library.listeningHeatmap(
      from: heatmapFrom,
      to: now,
    );
    final monthlyRecaps = library.listeningRecaps(
      period: LibraryRecapPeriod.month,
      limit: 6,
      statsLimit: 1,
    );
    final yearlyRecaps = library.listeningRecaps(
      period: LibraryRecapPeriod.year,
      limit: 3,
      statsLimit: 1,
    );

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
              tooltip: 'Saved history views',
              onPressed: () => _showSavedHistoryViews(context),
              icon: const Icon(Icons.bookmarks_outlined),
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
        SwitchListTile(
          secondary: const Icon(Icons.pause_circle_outline),
          title: const Text('Pause listening history'),
          subtitle: const Text(
            'Stop saving new plays and resume progress. Existing history stays until cleared.',
          ),
          value: library.pauseListeningHistory,
          onChanged: (value) {
            unawaited(library.setPauseListeningHistory(value));
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _historySearchController,
          decoration: InputDecoration(
            labelText: 'Search listening history',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: hasHistorySearch
                ? IconButton(
                    tooltip: 'Clear history search',
                    onPressed: () {
                      _historySearchController.clear();
                      setState(() => _historyQuery = '');
                    },
                    icon: const Icon(Icons.close),
                  )
                : null,
          ),
          textInputAction: TextInputAction.search,
          onChanged: (value) {
            setState(() => _historyQuery = value);
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<ListeningHistoryRange>(
          key: ValueKey<ListeningHistoryRange>(_statsRange),
          initialValue: _statsRange,
          decoration: const InputDecoration(
            labelText: 'Stats range',
            prefixIcon: Icon(Icons.date_range),
          ),
          items: <DropdownMenuItem<ListeningHistoryRange>>[
            for (final range in ListeningHistoryRange.values)
              DropdownMenuItem<ListeningHistoryRange>(
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
          _LibraryStatsCharts(stats: stats),
          const SizedBox(height: 16),
          _StatsSection(
            title: 'Listening calendar',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: ListeningHeatmap(days: heatmapDays),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ListeningRecapSection(
            title: 'Monthly recaps',
            icon: Icons.calendar_month_outlined,
            recaps: monthlyRecaps,
            onShare: (recap) => _showListeningRecapPreview(context, recap),
          ),
          const SizedBox(height: 12),
          _ListeningRecapSection(
            title: 'Yearly recaps',
            icon: Icons.event_note_outlined,
            recaps: yearlyRecaps,
            onShare: (recap) => _showListeningRecapPreview(context, recap),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          _PlaybackHistoryEntrySection(
            entries: historyEntries,
            tracksById: historyTracksById,
            onPlay: (track) => _playTrackWithResume(
              context,
              player,
              library,
              track,
              queue: recentlyPlayed.isEmpty ? <Track>[track] : recentlyPlayed,
            ),
            onRemove: (entry) {
              unawaited(library.removePlaybackHistoryEntry(entry));
            },
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Recently played',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (recentlyPlayed.isEmpty)
          _EmptyHistory(
            title: hasHistorySearch
                ? 'No matching history'
                : 'No listening history yet',
            message: hasHistorySearch
                ? 'Try a different title, artist, album, genre, source, folder, or saved lyric.'
                : 'Played library tracks will appear here.',
          )
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

  Future<void> _showSavedHistoryViews(BuildContext context) async {
    final currentQuery = _historyQuery.trim();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Consumer<LibraryStore>(
            builder: (_, library, child) {
              return ListView(
                shrinkWrap: true,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.bookmark_add_outlined),
                    title: const Text('Save current view'),
                    subtitle: Text(
                      _savedHistoryViewDescription(
                        range: _statsRange,
                        query: currentQuery,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(_createSavedHistoryView(context));
                    },
                  ),
                  if (library.savedHistoryViews.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 12, 24, 20),
                      child: Text(
                        'Saved views keep a date range and history search together.',
                      ),
                    )
                  else
                    for (final view in library.savedHistoryViews)
                      ListTile(
                        leading: Icon(
                          view.range == _statsRange &&
                                  view.query == currentQuery
                              ? Icons.bookmark
                              : Icons.bookmark_border,
                        ),
                        title: Text(view.name),
                        subtitle: Text(
                          _savedHistoryViewDescription(
                            range: view.range,
                            query: view.query,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<_SavedHistoryViewAction>(
                          tooltip: 'Edit saved history view',
                          onSelected: (action) async {
                            switch (action) {
                              case _SavedHistoryViewAction.update:
                                await library.updateSavedHistoryView(
                                  view.id,
                                  name: view.name,
                                  query: _historyQuery,
                                  range: _statsRange,
                                );
                                break;
                              case _SavedHistoryViewAction.rename:
                                Navigator.of(sheetContext).pop();
                                await _renameSavedHistoryView(context, view);
                                break;
                              case _SavedHistoryViewAction.delete:
                                await library.deleteSavedHistoryView(view.id);
                                break;
                            }
                          },
                          itemBuilder: (_) => const <
                              PopupMenuEntry<_SavedHistoryViewAction>>[
                            PopupMenuItem<_SavedHistoryViewAction>(
                              value: _SavedHistoryViewAction.update,
                              child: ListTile(
                                leading: Icon(Icons.save_outlined),
                                title: Text('Update to current'),
                              ),
                            ),
                            PopupMenuItem<_SavedHistoryViewAction>(
                              value: _SavedHistoryViewAction.rename,
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Rename'),
                              ),
                            ),
                            PopupMenuItem<_SavedHistoryViewAction>(
                              value: _SavedHistoryViewAction.delete,
                              child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('Delete'),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _applySavedHistoryView(view);
                        },
                      ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _applySavedHistoryView(SavedHistoryView view) {
    _historySearchController.value = TextEditingValue(
      text: view.query,
      selection: TextSelection.collapsed(offset: view.query.length),
    );
    setState(() {
      _historyQuery = view.query;
      _statsRange = view.range;
    });
  }

  Future<void> _createSavedHistoryView(BuildContext context) async {
    final name = await _showSavedHistoryViewNameDialog(
      context,
      title: 'Save history view',
      actionLabel: 'Save',
    );
    if (!context.mounted || name == null) {
      return;
    }

    try {
      await context.read<LibraryStore>().createSavedHistoryView(
            name: name,
            query: _historyQuery,
            range: _statsRange,
          );
    } on ArgumentError catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message?.toString() ?? '$error')),
      );
    }
  }

  Future<void> _renameSavedHistoryView(
    BuildContext context,
    SavedHistoryView view,
  ) async {
    final name = await _showSavedHistoryViewNameDialog(
      context,
      title: 'Rename history view',
      actionLabel: 'Rename',
      initialName: view.name,
    );
    if (!context.mounted || name == null) {
      return;
    }

    await context.read<LibraryStore>().updateSavedHistoryView(
          view.id,
          name: name,
          query: view.query,
          range: view.range,
        );
  }

  Future<String?> _showSavedHistoryViewNameDialog(
    BuildContext context, {
    required String title,
    required String actionLabel,
    String initialName = '',
  }) async {
    final controller = TextEditingController(text: initialName);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'View name'),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.of(dialogContext).pop(value.trim());
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
                  final value = controller.text.trim();
                  if (value.isNotEmpty) {
                    Navigator.of(dialogContext).pop(value);
                  }
                },
                child: Text(actionLabel),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
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

  Future<void> _showListeningRecapPreview(
    BuildContext context,
    LibraryListeningRecap recap,
  ) async {
    final boundaryKey = GlobalKey();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${listeningRecapLabel(recap)} recap'),
          content: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RepaintBoundary(
              key: boundaryKey,
              child: ListeningRecapCard(recap: recap),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () => _saveListeningRecapPng(
                dialogContext,
                recap: recap,
                boundaryKey: boundaryKey,
              ),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Save PNG'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveListeningRecapPng(
    BuildContext context, {
    required LibraryListeningRecap recap,
    required GlobalKey boundaryKey,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = await captureListeningRecapPng(boundaryKey);
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save listening recap image',
        fileName: listeningRecapPngFileName(recap),
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
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Saved ${listeningRecapPngFileName(recap)}.')),
      );
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save recap image: $error')),
      );
    }
  }
}

enum _SavedHistoryViewAction { update, rename, delete }

String _savedHistoryViewDescription({
  required ListeningHistoryRange range,
  required String query,
}) {
  final normalizedQuery = query.trim();
  if (normalizedQuery.isEmpty) {
    return _historyStatsRangeLabel(range);
  }
  return '${_historyStatsRangeLabel(range)} - "$normalizedQuery"';
}

String _historyStatsRangeLabel(ListeningHistoryRange range) {
  switch (range) {
    case ListeningHistoryRange.all:
      return 'All time';
    case ListeningHistoryRange.sevenDays:
      return 'Last 7 days';
    case ListeningHistoryRange.thirtyDays:
      return 'Last 30 days';
    case ListeningHistoryRange.year:
      return 'Last year';
  }
}

DateTime? _historyStatsRangeStart(ListeningHistoryRange range, DateTime now) {
  switch (range) {
    case ListeningHistoryRange.all:
      return null;
    case ListeningHistoryRange.sevenDays:
      return now.subtract(const Duration(days: 7));
    case ListeningHistoryRange.thirtyDays:
      return now.subtract(const Duration(days: 30));
    case ListeningHistoryRange.year:
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

class _LibraryStatsCharts extends StatelessWidget {
  const _LibraryStatsCharts({required this.stats});

  final LibraryStatsSummary stats;

  @override
  Widget build(BuildContext context) {
    final trackData = stats.topTracks
        .map(
          (trackStats) => ListeningStatsBarDatum(
            label: trackStats.track.title,
            value: trackStats.playCount,
            valueLabel: '${trackStats.playCount} play(s)',
          ),
        )
        .toList(growable: false);
    final artistData = stats.topArtists
        .map(
          (artistStats) => ListeningStatsBarDatum(
            label: artistStats.label,
            value: artistStats.playCount,
            valueLabel: '${artistStats.playCount} play(s)',
          ),
        )
        .toList(growable: false);
    if (trackData.isEmpty && artistData.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final trackChart = ListeningStatsBarChart(
      title: 'Top tracks chart',
      icon: Icons.music_note_outlined,
      color: colorScheme.primary,
      data: trackData,
    );
    final artistChart = ListeningStatsBarChart(
      title: 'Top artists chart',
      icon: Icons.person_outline,
      color: colorScheme.tertiary,
      data: artistData,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final showSideBySide = constraints.maxWidth >= 720 &&
            trackData.isNotEmpty &&
            artistData.isNotEmpty;
        if (showSideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: trackChart),
              const SizedBox(width: 28),
              Expanded(child: artistChart),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (trackData.isNotEmpty) trackChart,
            if (trackData.isNotEmpty && artistData.isNotEmpty)
              const SizedBox(height: 20),
            if (artistData.isNotEmpty) artistChart,
          ],
        );
      },
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

class _ListeningRecapSection extends StatelessWidget {
  const _ListeningRecapSection({
    required this.title,
    required this.icon,
    required this.recaps,
    required this.onShare,
  });

  final String title;
  final IconData icon;
  final List<LibraryListeningRecap> recaps;
  final ValueChanged<LibraryListeningRecap> onShare;

  @override
  Widget build(BuildContext context) {
    if (recaps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final recap in recaps)
              SizedBox(
                width: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(icon),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                listeningRecapLabel(recap),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Save recap image',
                              onPressed: () => onShare(recap),
                              icon: const Icon(Icons.image_outlined),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _listeningRecapSummary(recap.stats),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${recap.stats.uniquePlayedTrackCount} track(s)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

String _listeningRecapSummary(LibraryStatsSummary stats) {
  final parts = <String>[
    '${stats.playbackCount} play(s)',
    _formatStatsDuration(stats.estimatedListeningDuration),
  ];
  if (stats.topTracks.isNotEmpty) {
    parts.add('Top track: ${stats.topTracks.first.track.title}');
  } else if (stats.topArtists.isNotEmpty) {
    parts.add('Top artist: ${stats.topArtists.first.label}');
  }

  return parts.join(' · ');
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

class _PlaybackHistoryEntrySection extends StatelessWidget {
  const _PlaybackHistoryEntrySection({
    required this.entries,
    required this.tracksById,
    required this.onPlay,
    required this.onRemove,
  });

  final List<PlaybackHistoryEntry> entries;
  final Map<String, Track> tracksById;
  final ValueChanged<Track> onPlay;
  final ValueChanged<PlaybackHistoryEntry> onRemove;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (final entry in entries) {
      final track = tracksById[entry.trackId];
      if (track == null) {
        continue;
      }

      tiles.add(
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(track.title),
          subtitle: Text(
            '${track.artist} · ${_formatHistoryTime(entry.playedAt)}',
          ),
          trailing: IconButton(
            tooltip: 'Remove this play',
            onPressed: () => onRemove(entry),
            icon: const Icon(Icons.close),
          ),
          onTap: () => onPlay(track),
        ),
      );
    }

    return _StatsSection(
      title: 'Play history entries',
      children: tiles,
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          const Icon(Icons.history, size: 56),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
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
  await _tryPlayTrackWithResume(
    context,
    player,
    library,
    track,
    queue: queue,
  );
}

Future<bool> _tryPlayTrackWithResume(
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
      return false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(offlinePlaybackBlockedMessage(error.track))),
    );
    return false;
  }

  return true;
}

Future<void> _startTrackRadio(
  BuildContext context,
  PlayerController player,
  LibraryStore library,
  Track seedTrack,
) async {
  final radioQueue = library.radioQueueForTrack(seedTrack.id);
  if (radioQueue == null || radioQueue.tracks.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No playable radio queue for ${seedTrack.title}.'),
      ),
    );
    return;
  }

  final started = await _tryPlayTrackWithResume(
    context,
    player,
    library,
    radioQueue.seedTrack,
    queue: radioQueue.tracks,
  );

  if (!started || !context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Started ${radioQueue.tracks.length}-track radio from '
        '${seedTrack.title}.',
      ),
    ),
  );
}

Future<void> _copyTrackShareText(
  BuildContext context,
  LibraryStore library,
  Track track,
) {
  return _copyTextToClipboard(
    context,
    library.shareTrackText(track.id),
    copiedMessage: 'Copied share text for ${track.title}.',
    unavailableMessage: 'Share text is unavailable for ${track.title}.',
  );
}

Future<void> _copyBrowseGroupShareText(
  BuildContext context,
  LibraryStore library,
  LibraryBrowseType type,
  LibraryBrowseGroup group,
) {
  return _copyTextToClipboard(
    context,
    library.shareBrowseGroupText(type, group.key),
    copiedMessage: 'Copied share text for ${group.label}.',
    unavailableMessage:
        'Share text is unavailable for ${_libraryBrowseTypeLabel(type)}.',
  );
}

Future<void> _copyFolderNodeShareText(
  BuildContext context,
  LibraryStore library,
  LibraryFolderNode node,
) {
  return _copyTextToClipboard(
    context,
    library.shareFolderNodeText(node.key),
    copiedMessage: 'Copied share text for ${node.label}.',
    unavailableMessage: 'Share text is unavailable for ${node.label}.',
  );
}

Future<void> _copyPlaylistShareText(
  BuildContext context,
  LibraryStore library,
  Playlist playlist,
) {
  return _copyTextToClipboard(
    context,
    library.sharePlaylistText(playlist.id),
    copiedMessage: 'Copied share text for ${playlist.name}.',
    unavailableMessage: 'Share text is unavailable for ${playlist.name}.',
  );
}

Future<void> _copyLyricsShareText(
  BuildContext context,
  LibraryStore library,
  Track track,
) {
  return _copyTextToClipboard(
    context,
    library.shareLyricsText(track.id),
    copiedMessage: 'Copied lyrics share text for ${track.title}.',
    unavailableMessage: 'Lyrics share text is unavailable for ${track.title}.',
  );
}

Future<void> _copyLyricsDraftShareText(
  BuildContext context,
  LibraryStore library,
  Track track,
  String plainText,
) {
  return _copyTextToClipboard(
    context,
    library.shareLyricsText(track.id, plainText: plainText),
    copiedMessage: 'Copied lyrics share text for ${track.title}.',
    unavailableMessage: 'Add lyrics before copying share text.',
  );
}

Future<void> _showLyricsShareCard(
  BuildContext context,
  LibraryStore library,
  Track track,
  String plainText,
) async {
  final shareText =
      library.shareLyricsText(track.id, plainText: plainText) ?? '';
  if (shareText.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add lyrics before saving a share card.')),
    );
    return;
  }
  final boundaryKey = GlobalKey();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Lyrics share card'),
      content: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: RepaintBoundary(
          key: boundaryKey,
          child: LyricsShareCard(
            title: track.title,
            artist: track.artist,
            shareText: shareText,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => unawaited(
            _saveLyricsShareCard(dialogContext, boundaryKey, track),
          ),
          icon: const Icon(Icons.image_outlined),
          label: const Text('Save PNG'),
        ),
      ],
    ),
  );
}

Future<void> _saveLyricsShareCard(
  BuildContext context,
  GlobalKey boundaryKey,
  Track track,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await captureLyricsShareCardPng(boundaryKey);
    final fileName = 'aethertune-lyrics-${track.id}.png';
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save lyrics share card',
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
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save lyrics share card: $error')),
      );
    }
  }
}

Future<void> _copyLyricsDraftExportDocument(
  BuildContext context,
  Track track,
  String plainText,
) {
  final export = buildLyricsDocumentExport(
    title: track.title,
    artist: track.artist,
    plainText: plainText,
  );

  return _copyTextToClipboard(
    context,
    export?.text,
    copiedMessage: export == null
        ? 'Copied lyrics export text.'
        : 'Copied ${export.fileName} export text.',
    unavailableMessage: 'Add lyrics before copying export text.',
  );
}

Future<void> _saveLyricsDraftExportDocument(
  BuildContext context,
  Track track,
  String plainText,
) async {
  final export = buildLyricsDocumentExport(
    title: track.title,
    artist: track.artist,
    plainText: plainText,
  );
  if (export == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add lyrics before saving an export file.')),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final bytes = Uint8List.fromList(export.bytes);
  try {
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save lyrics file',
      fileName: export.fileName,
      type: FileType.custom,
      allowedExtensions: <String>[export.extension],
      bytes: bytes,
    );
    if (outputPath == null || outputPath.isEmpty) {
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(outputPath).writeAsBytes(bytes, flush: true);
    }
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(SnackBar(content: Text('Saved ${export.fileName}.')));
  } on Exception catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Could not save lyrics file: $error')),
    );
  }
}

Future<void> _copyTextToClipboard(
  BuildContext context,
  String? value, {
  required String copiedMessage,
  required String unavailableMessage,
}) async {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(unavailableMessage)),
    );
    return;
  }

  await Clipboard.setData(ClipboardData(text: text));

  if (!context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(copiedMessage),
      action: SnackBarAction(
        label: 'Share',
        onPressed: () => unawaited(_shareCopiedText(context, text)),
      ),
    ),
  );
}

Future<void> _shareCopiedText(BuildContext context, String text) async {
  if (!context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final renderBox = context.findRenderObject() as RenderBox?;
  final origin = renderBox == null || !renderBox.hasSize
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  try {
    final status = await _platformTextShareService.share(
      PlatformTextShareRequest(
        text: text,
        sharePositionOrigin: origin,
      ),
    );
    if (!context.mounted || status != PlatformTextShareStatus.unavailable) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Native sharing is unavailable here.')),
    );
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open the share sheet: $error')),
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

String _folderImportSummary(LocalFolderScanResult result) {
  if (result.tracks.isEmpty) {
    return 'No supported audio files found in folder.';
  }

  final details = <String>[
    'Imported ${result.tracks.length} audio file(s) from folder.',
  ];
  if (result.sidecarLyricsCount > 0) {
    details.add('Imported lyrics for ${result.sidecarLyricsCount} track(s).');
  }
  if (result.ignoredFileCount > 0) {
    details.add('Skipped ${result.ignoredFileCount} non-audio file(s).');
  }
  if (result.inaccessibleDirectoryCount > 0) {
    details.add(
      'Skipped ${result.inaccessibleDirectoryCount} inaccessible folder(s).',
    );
  }

  return details.join(' ');
}

String _folderImportErrorMessage(Object error) {
  final message = error.toString();
  if (message.length <= 120) {
    return message;
  }

  return '${message.substring(0, 117)}...';
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.favoritesOnly,
    required this.offlineOnly,
    required this.onImport,
    required this.onImportFolder,
  });

  final bool favoritesOnly;
  final bool offlineOnly;
  final VoidCallback onImport;
  final VoidCallback onImportFolder;

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
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.library_add),
                  label: const Text('Import audio'),
                ),
                OutlinedButton.icon(
                  onPressed: onImportFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Import folder'),
                ),
              ],
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

    return 'Import audio files or scan a folder to start using the real player.';
  }
}

enum _SelfHostedAccountAction { browse, edit, rotateCredential, remove }

class _SourcesTab extends StatefulWidget {
  const _SourcesTab({this.archiveProvider});

  final InternetArchiveProvider? archiveProvider;

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  final _provider = const DemoSourceProvider();
  late final InternetArchiveProvider _archiveProvider;
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
  List<InternetArchiveItem> _archiveItems = <InternetArchiveItem>[];
  List<Track> _demoTracks = <Track>[];
  List<Track> _podcastEpisodeTracks = <Track>[];
  List<ProviderSearchResult> _providerSearchResults = <ProviderSearchResult>[];
  List<ProviderSearchError> _providerSearchErrors = <ProviderSearchError>[];
  List<Track> _radioTracks = <Track>[];
  final Map<String, RadioBrowserStreamValidation> _radioValidationByTrackId =
      <String, RadioBrowserStreamValidation>{};
  final Set<String> _radioValidatingTrackIds = <String>{};
  List<InternetArchiveFacet> _archiveFacets = <InternetArchiveFacet>[];
  int _archivePage = 0;
  int? _archiveTotalResults;
  int _archiveRequestSerial = 0;
  bool _archiveHasMore = false;
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
    _archiveProvider = widget.archiveProvider ?? InternetArchiveProvider();
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
    final selfHosted = context.watch<SelfHostedProviderStore>();
    final podcastSubscriptions = library.podcastSubscriptions;
    final offlineModeEnabled = library.offlineModeEnabled;
    final selfHostedActionsEnabled = selfHosted.loaded &&
        selfHosted.loadError == null &&
        !offlineModeEnabled;

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
        _ProviderCard(
          title: _radioProvider.name,
          status: 'Enabled',
          description: _radioProvider.description,
          icon: Icons.radio_outlined,
          capabilities: _radioProvider.capabilities,
          disclosure: _radioProvider.disclosure,
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
        const SizedBox(height: 16),
        Text(
          'Self-hosted servers',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: selfHostedActionsEnabled
                  ? () => _editSelfHostedAccount(
                        context,
                        SelfHostedProviderKind.jellyfin,
                      )
                  : null,
              icon: const Icon(Icons.storage_outlined),
              label: const Text('Add Jellyfin'),
            ),
            OutlinedButton.icon(
              onPressed: selfHostedActionsEnabled
                  ? () => _editSelfHostedAccount(
                        context,
                        SelfHostedProviderKind.subsonic,
                      )
                  : null,
              icon: const Icon(Icons.dns_outlined),
              label: const Text('Add Navidrome'),
            ),
          ],
        ),
        if (!selfHosted.loaded) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (selfHosted.loadError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Secure credential storage unavailable'),
            subtitle: Text(selfHosted.loadError!),
          ),
        ],
        if (selfHosted.loaded && selfHosted.accounts.isEmpty)
          const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('No self-hosted server configured'),
            subtitle: Text(
              'Add a user-owned Jellyfin, Navidrome, or Subsonic-compatible server.',
            ),
          )
        else
          for (final account in selfHosted.accounts)
            _ProviderCard(
              title: account.name,
              status: selfHosted.hasCredential(account.id)
                  ? 'Enabled'
                  : 'Credential missing',
              description:
                  '${account.kind.label} at ${account.baseUri} / '
                  '${account.kind.identityLabel}: ${account.identity}',
              icon: account.kind == SelfHostedProviderKind.jellyfin
                  ? Icons.storage_outlined
                  : Icons.dns_outlined,
              capabilities: account.kind == SelfHostedProviderKind.jellyfin
                  ? JellyfinProvider.defaultCapabilities
                  : SubsonicProvider.defaultCapabilities,
              disclosure: _selfHostedDisclosure(account),
              onTap: selfHostedActionsEnabled &&
                      selfHosted.hasCredential(account.id)
                  ? () => _browseSelfHostedAccount(context, account)
                  : null,
              actions: PopupMenuButton<_SelfHostedAccountAction>(
                tooltip: 'Manage ${account.name}',
                onSelected: (action) {
                  switch (action) {
                    case _SelfHostedAccountAction.browse:
                      if (selfHostedActionsEnabled &&
                          selfHosted.hasCredential(account.id)) {
                        unawaited(
                          _browseSelfHostedAccount(context, account),
                        );
                      }
                      break;
                    case _SelfHostedAccountAction.edit:
                      if (selfHostedActionsEnabled) {
                        unawaited(
                          _editSelfHostedAccount(
                            context,
                            account.kind,
                            account: account,
                          ),
                        );
                      }
                      break;
                    case _SelfHostedAccountAction.rotateCredential:
                      if (selfHostedActionsEnabled &&
                          selfHosted.hasCredential(account.id)) {
                        unawaited(
                          _rotateSelfHostedCredential(context, account),
                        );
                      }
                      break;
                    case _SelfHostedAccountAction.remove:
                      unawaited(_removeSelfHostedAccount(context, account));
                      break;
                  }
                },
                itemBuilder: (_) => <PopupMenuEntry<_SelfHostedAccountAction>>[
                  PopupMenuItem<_SelfHostedAccountAction>(
                    value: _SelfHostedAccountAction.browse,
                    enabled: selfHostedActionsEnabled &&
                        selfHosted.hasCredential(account.id),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.library_music_outlined),
                      title: Text('Browse library'),
                    ),
                  ),
                  PopupMenuItem<_SelfHostedAccountAction>(
                    value: _SelfHostedAccountAction.edit,
                    enabled: selfHostedActionsEnabled,
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit and test'),
                    ),
                  ),
                  PopupMenuItem<_SelfHostedAccountAction>(
                    value: _SelfHostedAccountAction.rotateCredential,
                    enabled: selfHostedActionsEnabled &&
                        selfHosted.hasCredential(account.id),
                    child: const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.key_outlined),
                      title: Text('Rotate credential'),
                    ),
                  ),
                  const PopupMenuItem<_SelfHostedAccountAction>(
                    value: _SelfHostedAccountAction.remove,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Remove'),
                    ),
                  ),
                ],
              ),
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
                decoration: const InputDecoration(
                  labelText: 'Search library and providers',
                  prefixIcon: Icon(Icons.search),
                ),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchProviderCatalogs(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Search library and providers',
              onPressed:
                  _providerSearchLoading ? null : _searchProviderCatalogs,
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
            title: Text('No search results loaded'),
            subtitle: Text(
              'Search Local Library, Demo Provider, Radio Browser, and Internet Archive.',
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
                  _offlineQueueMenu(
                    context: context,
                    track: result.track,
                    decisionFor: (action) =>
                        _providerSearchCoordinator.offlineDecision(
                      result.track,
                      action,
                    ),
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
            OutlinedButton.icon(
              onPressed: _podcastLoading ||
                      offlineModeEnabled ||
                      podcastSubscriptions.isEmpty
                  ? null
                  : () => _refreshAllPodcastFeeds(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh all'),
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
              onTap: () => _selectPodcastSubscription(context, subscription),
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
                    _offlineQueueMenu(
                      context: context,
                      track: track,
                      decisionFor: (action) => _podcastOfflineDecision(
                        context,
                        track,
                        action,
                      ),
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
              subtitle: Text(_radioStationSubtitle(track)),
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
                    tooltip: 'Validate stream',
                    onPressed: _radioValidatingTrackIds.contains(track.id) ||
                            offlineModeEnabled
                        ? null
                        : () => _validateRadioStation(context, track),
                    icon: _radioValidatingTrackIds.contains(track.id)
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_radioValidationIcon(track)),
                  ),
                  _offlineQueueMenu(
                    context: context,
                    track: track,
                    decisionFor: (action) =>
                        _providerSearchCoordinator.offlineDecision(
                      track,
                      action,
                    ),
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
                onSubmitted: offlineModeEnabled || _archiveLoading
                    ? null
                    : (_) => _searchArchiveItems(),
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
              onPressed: _archiveLoading ? null : _clearArchiveFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear'),
            ),
          ],
        ),
        if (_archiveFacets.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _archiveFacetChips(
              offlineModeEnabled: offlineModeEnabled,
            ),
          ),
        ],
        if (_archiveLoading) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_archiveError != null && _archiveItems.isEmpty) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Archive search failed'),
            subtitle: Text(_archiveError!),
          ),
        ] else if (_archiveItems.isEmpty && !_archiveLoading) ...<Widget>[
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
          for (final item in _archiveItems)
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(item.title),
              subtitle: Text(_archiveItemSubtitle(item)),
              onTap: () => _openArchiveItem(context, item),
              trailing: const Icon(Icons.chevron_right),
            ),
        ],
        if (_archiveItems.isNotEmpty && _archiveError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Could not load more archive audio'),
            subtitle: Text(_archiveError!),
            trailing: IconButton(
              tooltip: 'Retry loading archive results',
              onPressed: _archiveLoading || offlineModeEnabled
                  ? null
                  : _loadMoreArchiveItems,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
        if (_archiveItems.isNotEmpty && _archiveHasMore) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _archiveLoading || offlineModeEnabled
                  ? null
                  : _loadMoreArchiveItems,
              icon: const Icon(Icons.expand_more),
              label: Text(_archiveLoadMoreLabel),
            ),
          ),
        ] else if (_archiveItems.isNotEmpty && _archiveTotalResults != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'All $_archiveTotalResults archive results loaded.',
            style: Theme.of(context).textTheme.bodySmall,
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

  Future<void> _browseSelfHostedAccount(
    BuildContext context,
    SelfHostedProviderAccount account,
  ) async {
    final provider = context
        .read<SelfHostedProviderStore>()
        .catalogProviderFor(account.id);
    if (provider == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This account has no available credential.'),
        ),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelfHostedBrowseScreen(provider: provider),
      ),
    );
  }

  Future<void> _editSelfHostedAccount(
    BuildContext context,
    SelfHostedProviderKind kind, {
    SelfHostedProviderAccount? account,
  }) async {
    final store = context.read<SelfHostedProviderStore>();
    final saved = await showSelfHostedAccountEditor(
      context,
      kind: kind,
      account: account,
      onSave: store.testAndSave,
    );
    if (!context.mounted || saved != true) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${account == null ? 'Added' : 'Updated'} '
          '${account?.name ?? kind.label}.',
        ),
      ),
    );
  }

  Future<void> _removeSelfHostedAccount(
    BuildContext context,
    SelfHostedProviderAccount account,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${account.name}?'),
        content: const Text(
          'The account metadata and its secure credential will be deleted from this device.',
        ),
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
    if (!context.mounted || confirmed != true) {
      return;
    }

    final library = context.read<LibraryStore>();
    final player = context.read<PlayerController>();
    final selfHosted = context.read<SelfHostedProviderStore>();
    await player.removeTracksFromSource(account.providerId);
    await selfHosted.remove(account.id);
    final pendingEntries = library.offlineCacheQueue
        .where(
          (entry) =>
              entry.track.sourceId == account.providerId &&
              entry.status != OfflineCacheEntryStatus.cached,
        )
        .toList(growable: false);
    for (final entry in pendingEntries) {
      await library.removeOfflineCacheEntry(entry.id);
    }
    if (!context.mounted) {
      return;
    }
    setState(() {
      _providerSearchResults.removeWhere(
        (result) => result.providerId == account.providerId,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${account.name}.')),
    );
  }

  Future<void> _rotateSelfHostedCredential(
    BuildContext context,
    SelfHostedProviderAccount account,
  ) async {
    final selfHosted = context.read<SelfHostedProviderStore>();
    final player = context.read<PlayerController>();
    final rotated = await showSelfHostedCredentialRotationDialog(
      context,
      account: account,
      onRotate: (newSecret) async {
        await selfHosted.rotateCredential(account.id, newSecret);
        await player.refreshTracksFromSource(account.providerId);
      },
    );
    if (!context.mounted || rotated != true) {
      return;
    }
    setState(() {
      _providerSearchResults.removeWhere(
        (result) => result.providerId == account.providerId,
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rotated credential for ${account.name}.')),
    );
  }

  List<MusicSourceProvider> _providerSearchSources({bool localOnly = false}) {
    final library = context.read<LibraryStore>();
    final localLibraryProvider = LocalLibraryProvider(
      searchTracks: (query) => library.search(query),
    );
    if (localOnly) {
      return <MusicSourceProvider>[localLibraryProvider];
    }

    return <MusicSourceProvider>[
      localLibraryProvider,
      _provider,
      _radioProvider,
      _archiveProvider,
      ...context.read<SelfHostedProviderStore>().musicProviders,
    ];
  }

  ProviderSearchCoordinator get _providerSearchCoordinator {
    return _providerSearchCoordinatorFor();
  }

  ProviderSearchCoordinator _providerSearchCoordinatorFor({
    bool localOnly = false,
  }) {
    return ProviderSearchCoordinator(
      _providerSearchSources(localOnly: localOnly),
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

  Widget _offlineQueueMenu({
    required BuildContext context,
    required Track track,
    required OfflineMediaPolicyDecision Function(OfflineMediaAction action)
        decisionFor,
  }) {
    return PopupMenuButton<OfflineMediaAction>(
      tooltip: 'Queue offline media',
      icon: const Icon(Icons.download_for_offline_outlined),
      onSelected: (action) {
        unawaited(
          _queueOfflineTrack(
            context,
            track,
            decisionFor(action),
          ),
        );
      },
      itemBuilder: (_) => const <PopupMenuEntry<OfflineMediaAction>>[
        PopupMenuItem<OfflineMediaAction>(
          value: OfflineMediaAction.cache,
          child: ListTile(
            leading: Icon(Icons.offline_pin_outlined),
            title: Text('Queue cache'),
          ),
        ),
        PopupMenuItem<OfflineMediaAction>(
          value: OfflineMediaAction.download,
          child: ListTile(
            leading: Icon(Icons.download_outlined),
            title: Text('Queue download'),
          ),
        ),
      ],
    );
  }

  OfflineMediaPolicyDecision _podcastOfflineDecision(
    BuildContext context,
    Track track,
    OfflineMediaAction action,
  ) {
    final subscriptionId = _selectedPodcastSubscriptionId;
    if (subscriptionId == null) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: false,
        reason: 'No podcast feed is selected for this episode.',
      );
    }

    final subscription =
        context.read<LibraryStore>().podcastSubscriptionById(subscriptionId);
    final feedUri = Uri.tryParse(subscription?.feedUrl ?? '');
    if (feedUri == null) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: false,
        reason: 'No valid podcast feed is selected for this episode.',
      );
    }

    final provider = PodcastRssProvider(feedUri: feedUri, id: track.sourceId);
    return OfflineMediaPolicy(
      <MusicSourceProvider>[provider],
    ).evaluate(track, action);
  }

  Future<void> _queueOfflineTrack(
    BuildContext context,
    Track track,
    OfflineMediaPolicyDecision decision,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!decision.isAllowed) {
      messenger.showSnackBar(SnackBar(content: Text(decision.reason)));
      return;
    }

    final library = context.read<LibraryStore>();
    try {
      final entry = await library.queueOfflineCache(
        track,
        decision.action,
        decision,
      );
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Queued ${entry.track.title} for '
            '${entry.action.label.toLowerCase()}.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Could not queue ${track.title}: $error')),
      );
    }
  }

  Future<void> _searchProviderCatalogs() async {
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
      final localOnly = context.read<LibraryStore>().offlineModeEnabled;
      final response = await _providerSearchCoordinatorFor(
        localOnly: localOnly,
      ).search(query);
      if (!mounted) {
        return;
      }

      setState(() {
        _providerSearchResults = response.results;
        _providerSearchErrors = response.errors;
        _providerSearchLoading = false;
        _providerSearchMessage = _providerSearchCompletionMessage(
          hasResults: response.results.isNotEmpty,
          localOnly: localOnly,
        );
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
        .where(_providerSearchCoordinator.canResolve)
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

  String? _providerSearchCompletionMessage({
    required bool hasResults,
    required bool localOnly,
  }) {
    if (!hasResults) {
      return localOnly
          ? 'No local library results found while offline.'
          : 'No provider results found.';
    }

    if (localOnly) {
      return 'Offline mode: showing local library results only.';
    }

    return null;
  }

  IconData _providerSearchIcon(String providerId) {
    if (providerId.startsWith('self-hosted-jellyfin-')) {
      return Icons.storage_outlined;
    }
    if (providerId.startsWith('self-hosted-subsonic-')) {
      return Icons.dns_outlined;
    }
    switch (providerId) {
      case LocalLibraryProvider.providerId:
        return Icons.library_music_outlined;
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

  void _selectPodcastSubscription(
    BuildContext context,
    PodcastSubscription subscription,
  ) {
    setState(() {
      _selectedPodcastSubscriptionId = subscription.id;
      _podcastEpisodeTracks = subscription.episodes;
      _podcastError = null;
    });
    if (!context.read<LibraryStore>().offlineModeEnabled) {
      _loadPodcastEpisodes(context, subscription);
    }
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
      final tracks = feed.episodes
          .map((episode) => episode.toTrack(sourceId: provider.id, feed: feed))
          .toList(growable: false);
      final saved = await library.savePodcastSubscription(
        PodcastSubscription(
          id: stablePodcastSubscriptionId(feed.feedUri.toString()),
          feedUrl: feed.feedUri.toString(),
          title: feed.title,
          description: feed.description,
          author: feed.author,
          artworkUri: feed.artworkUri,
          episodes: tracks,
        ),
      );
      final refreshed =
          await library.markPodcastSubscriptionFetched(saved.id) ?? saved;

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

  Future<void> _refreshAllPodcastFeeds(BuildContext context) async {
    if (_offlineModeBlocksSourceNetwork(context)) {
      return;
    }
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final subscriptions = library.podcastSubscriptions;
    if (subscriptions.isEmpty) {
      return;
    }

    setState(() {
      _podcastLoading = true;
      _podcastError = null;
    });

    var refreshed = 0;
    var failed = 0;
    for (final subscription in subscriptions) {
      final feedUri = Uri.tryParse(subscription.feedUrl);
      if (feedUri == null) {
        failed += 1;
        await library.markPodcastSubscriptionFetchFailed(
          subscription.id,
          'Saved feed URL is invalid.',
        );
        continue;
      }
      try {
        final provider = PodcastRssProvider(feedUri: feedUri);
        final feed = await provider.fetchFeed();
        final tracks = feed.episodes
            .map(
              (episode) => episode.toTrack(sourceId: provider.id, feed: feed),
            )
            .toList(growable: false);
        final saved = await library.savePodcastSubscription(
          PodcastSubscription(
            id: stablePodcastSubscriptionId(feed.feedUri.toString()),
            feedUrl: feed.feedUri.toString(),
            title: feed.title,
            description: feed.description,
            author: feed.author,
            artworkUri: feed.artworkUri,
            episodes: tracks,
          ),
        );
        await library.markPodcastSubscriptionFetched(saved.id);
        refreshed += 1;
      } catch (error) {
        failed += 1;
        await library.markPodcastSubscriptionFetchFailed(subscription.id, error);
      }
    }

    if (!context.mounted) {
      return;
    }
    setState(() {
      _podcastLoading = false;
      _podcastError = failed == 0
          ? null
          : '$failed podcast feed(s) could not be refreshed.';
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'Refreshed $refreshed podcast feed(s).'
              : 'Refreshed $refreshed feed(s); $failed failed.',
        ),
      ),
    );
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
    await _loadArchiveItems(reset: true);
  }

  Future<void> _loadMoreArchiveItems() async {
    await _loadArchiveItems(reset: false);
  }

  Future<void> _loadArchiveItems({required bool reset}) async {
    if (_archiveLoading || (!reset && !_archiveHasMore)) {
      return;
    }

    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _archiveRequestSerial += 1;
        _archiveItems = <InternetArchiveItem>[];
        _archiveFacets = <InternetArchiveFacet>[];
        _archivePage = 0;
        _archiveTotalResults = null;
        _archiveHasMore = false;
        _archiveLoading = false;
        _archiveError = 'Offline mode is on.';
      });
      return;
    }

    final requestSerial =
        reset ? ++_archiveRequestSerial : _archiveRequestSerial;
    final requestedPage = reset ? 1 : _archivePage + 1;

    setState(() {
      _archiveLoading = true;
      _archiveError = null;
      if (reset) {
        _archiveItems = <InternetArchiveItem>[];
        _archiveFacets = <InternetArchiveFacet>[];
        _archivePage = 0;
        _archiveTotalResults = null;
        _archiveHasMore = false;
      }
    });

    try {
      final page = await _archiveProvider.searchAudioPage(
        _archiveSearchController.text,
        filters: _archiveFilters(),
        page: requestedPage,
        includeFacets: reset,
      );
      if (!mounted || requestSerial != _archiveRequestSerial) {
        return;
      }

      setState(() {
        _archiveItems = reset
            ? page.items
            : _mergeArchiveItems(_archiveItems, page.items);
        if (reset) {
          _archiveFacets = page.facets;
        }
        _archivePage = page.page;
        _archiveTotalResults = page.totalResults;
        _archiveHasMore = page.hasMore;
        _archiveLoading = false;
      });
    } catch (error) {
      if (!mounted || requestSerial != _archiveRequestSerial) {
        return;
      }

      setState(() {
        if (reset) {
          _archiveItems = <InternetArchiveItem>[];
          _archiveFacets = <InternetArchiveFacet>[];
          _archivePage = 0;
          _archiveTotalResults = null;
          _archiveHasMore = false;
        }
        _archiveLoading = false;
        _archiveError = error.toString();
      });
    }
  }

  List<InternetArchiveItem> _mergeArchiveItems(
    List<InternetArchiveItem> current,
    List<InternetArchiveItem> incoming,
  ) {
    final identifiers = current.map((item) => item.identifier).toSet();
    return <InternetArchiveItem>[
      ...current,
      for (final item in incoming)
        if (identifiers.add(item.identifier)) item,
    ];
  }

  String get _archiveLoadMoreLabel {
    final totalResults = _archiveTotalResults;
    if (totalResults == null) {
      return 'Load more archive results';
    }

    final remaining = totalResults - _archiveItems.length;
    return remaining > 0
        ? 'Load more archive results ($remaining remaining)'
        : 'Load more archive results';
  }

  String _archiveItemSubtitle(InternetArchiveItem item) {
    final playableFileCount =
        item.files.where((file) => file.isPlayableAudio).length;
    final parts = <String>[
      if (item.creator.isNotEmpty) item.creator,
      if (item.year.isNotEmpty) item.year,
      '$playableFileCount playable ${playableFileCount == 1 ? 'file' : 'files'}',
    ];
    return parts.join(' / ');
  }

  Future<void> _openArchiveItem(
    BuildContext context,
    InternetArchiveItem item,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveItemScreen(
          item: item,
          provider: _archiveProvider,
        ),
      ),
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

  List<Widget> _archiveFacetChips({required bool offlineModeEnabled}) {
    final chips = <Widget>[];
    for (final field in <String>['collection', 'subject', 'creator', 'year']) {
      chips.addAll(
        _archiveFacets
            .where((facet) => facet.field == field)
            .take(4)
            .map(
              (facet) => ActionChip(
                avatar: Icon(_archiveFacetIcon(facet.field), size: 18),
                label: Text(
                  '${_archiveFacetLabel(facet.field)}: ${facet.value} '
                  '(${facet.count})',
                ),
                tooltip: 'Filter ${_archiveFacetLabel(facet.field)}',
                onPressed: offlineModeEnabled || _archiveLoading
                    ? null
                    : () => _applyArchiveFacet(facet),
              ),
            ),
      );
    }

    return chips;
  }

  TextEditingController? _archiveFacetController(String field) {
    switch (field) {
      case 'collection':
        return _archiveCollectionController;
      case 'subject':
        return _archiveSubjectController;
      case 'creator':
        return _archiveCreatorController;
      case 'year':
        return _archiveYearController;
    }

    return null;
  }

  IconData _archiveFacetIcon(String field) {
    switch (field) {
      case 'collection':
        return Icons.collections_bookmark_outlined;
      case 'subject':
        return Icons.sell_outlined;
      case 'creator':
        return Icons.person_search_outlined;
      case 'year':
        return Icons.calendar_month_outlined;
    }

    return Icons.filter_alt_outlined;
  }

  String _archiveFacetLabel(String field) {
    switch (field) {
      case 'collection':
        return 'Collection';
      case 'subject':
        return 'Subject';
      case 'creator':
        return 'Creator';
      case 'year':
        return 'Year';
    }

    return 'Facet';
  }

  void _applyArchiveFacet(InternetArchiveFacet facet) {
    final controller = _archiveFacetController(facet.field);
    if (controller == null) {
      return;
    }

    controller.text = facet.value;
    unawaited(_searchArchiveItems());
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
    setState(() {
      _archiveCollectionController.clear();
      _archiveSubjectController.clear();
      _archiveCreatorController.clear();
      _archiveYearController.clear();
      _archiveRequestSerial += 1;
      _archiveItems = <InternetArchiveItem>[];
      _archiveFacets = <InternetArchiveFacet>[];
      _archivePage = 0;
      _archiveTotalResults = null;
      _archiveHasMore = false;
      _archiveError = null;
    });
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

  String _radioStationSubtitle(Track track) {
    final parts = <String>[track.artist, track.genre];
    if (_radioValidatingTrackIds.contains(track.id)) {
      parts.add('Validating stream...');
      return parts.join(' / ');
    }

    final validation = _radioValidationByTrackId[track.id];
    if (validation != null) {
      parts.add(validation.isPlayable ? 'Stream validated' : validation.reason);
    }

    return parts.join(' / ');
  }

  IconData _radioValidationIcon(Track track) {
    final validation = _radioValidationByTrackId[track.id];
    if (validation == null) {
      return Icons.fact_check_outlined;
    }

    return validation.isPlayable
        ? Icons.check_circle_outline
        : Icons.error_outline;
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
        _radioValidationByTrackId.clear();
        _radioValidatingTrackIds.clear();
        _radioLoading = false;
        _radioError = 'Offline mode is on.';
      });
      return;
    }

    setState(() {
      _radioLoading = true;
      _radioError = null;
      _radioValidationByTrackId.clear();
      _radioValidatingTrackIds.clear();
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
        _radioValidationByTrackId.clear();
        _radioValidatingTrackIds.clear();
        _radioLoading = false;
        _radioError = error.toString();
      });
    }
  }

  Future<void> _validateRadioStation(BuildContext context, Track track) async {
    if (_offlineModeBlocksSourceNetwork(context)) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _radioValidatingTrackIds.add(track.id));

    final validation = await _radioProvider.validateStream(track);
    if (!mounted) {
      return;
    }

    setState(() {
      _radioValidatingTrackIds.remove(track.id);
      _radioValidationByTrackId[track.id] = validation;
    });

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          validation.isPlayable
              ? 'Validated ${track.title}.'
              : 'Could not validate ${track.title}: ${validation.reason}',
        ),
      ),
    );
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
    this.onTap,
    this.actions,
  });

  final String title;
  final String status;
  final String description;
  final IconData icon;
  final Set<MusicSourceCapability> capabilities;
  final ProviderPrivacyDisclosure? disclosure;
  final VoidCallback? onTap;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        onTap: onTap,
        title: actions == null
            ? Text(title)
            : Row(
                children: <Widget>[
                  Expanded(child: Text(title)),
                  actions!,
                ],
              ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (actions != null) ...<Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(label: Text(status)),
              ),
              const SizedBox(height: 4),
            ],
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
        trailing: actions == null ? Chip(label: Text(status)) : null,
      ),
    );
  }
}

ProviderPrivacyDisclosure _selfHostedDisclosure(
  SelfHostedProviderAccount account,
) {
  return ProviderPrivacyDisclosure(
    networkDomains: <String>[account.baseUri.host],
    dataSent: <String>[
      account.kind == SelfHostedProviderKind.jellyfin
          ? 'API key, user ID, search query, media item IDs, and artwork IDs'
          : 'username, salted token, search query, media item IDs, and artwork IDs',
    ],
    requiresUserCredentials: true,
    cachesMetadata: true,
    cachesMedia: true,
    supportsDownloads: true,
  );
}

String _providerDisclosureSummary(ProviderPrivacyDisclosure disclosure) {
  final parts = <String>[disclosure.networkSummary];
  if (disclosure.requiresUserCredentials) {
    parts.add('Credentials required');
  }
  if (disclosure.readsLocalFiles) {
    parts.add('Reads selected local files');
  }
  if (disclosure.cachesMetadata) {
    parts.add('Can cache metadata');
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
    case DuplicateMatchType.contentHash:
      return 'Same file content';
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
    if (track.contentHash != null) 'hash ${track.contentHash!}',
    if (track.localPath != null) track.localPath!,
    if (track.streamUrl != null) track.streamUrl!,
  ].where((part) => part.trim().isNotEmpty).toList(growable: false);

  return parts.join(' · ');
}

IconData _offlineCacheEntryIcon(OfflineCacheEntry entry) {
  switch (entry.action) {
    case OfflineMediaAction.cache:
      return Icons.offline_pin_outlined;
    case OfflineMediaAction.download:
      return Icons.download_outlined;
  }
}

String _offlineCacheEntrySubtitle(OfflineCacheEntry entry) {
  final reason = entry.reason.trim();
  final parts = <String>[
    entry.action.label,
    entry.status.label,
    entry.track.artist,
    if (entry.cachedByteCount > 0) _formatByteCount(entry.cachedByteCount),
    if (entry.cachedMediaChecksum.isNotEmpty)
      'checksum ${entry.cachedMediaChecksum}',
    if (reason.isNotEmpty) reason,
  ];

  return parts.join(' · ');
}

bool _canProcessOfflineCacheEntry(OfflineCacheEntry entry) {
  return entry.status == OfflineCacheEntryStatus.queued ||
      entry.status == OfflineCacheEntryStatus.failed;
}

bool _canPauseOfflineCacheEntry(OfflineCacheEntry entry) {
  return entry.status == OfflineCacheEntryStatus.queued ||
      entry.status == OfflineCacheEntryStatus.failed;
}

bool _canResumeOfflineCacheEntry(OfflineCacheEntry entry) {
  return entry.status == OfflineCacheEntryStatus.paused;
}

bool _canExportOfflineCacheEntry(OfflineCacheEntry entry) {
  return entry.status == OfflineCacheEntryStatus.cached &&
      entry.track.hasLocalSource &&
      entry.cachedByteCount > 0;
}

List<String> _offlineCacheProviderIds(List<OfflineCacheEntry> entries) {
  final sourceIds = <String>{};
  for (final entry in entries) {
    final sourceId = entry.track.sourceId.trim().toLowerCase();
    if (sourceId.isNotEmpty) {
      sourceIds.add(sourceId);
    }
  }

  return sourceIds.toList(growable: false)..sort();
}

String _formatByteCount(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _offlineCacheProviderLimitLabel(
  LibraryStore library,
  String sourceId,
) {
  final limitBytes = library.offlineCacheProviderLimitBytesFor(sourceId);
  if (limitBytes == null) {
    return 'No provider quota';
  }

  return _formatByteCount(limitBytes);
}

String _offlineCacheErrorMessage(Object error) {
  final message = error.toString();
  if (message.length <= 120) {
    return message;
  }

  return '${message.substring(0, 117)}...';
}

String _offlineCacheResultMessage({
  required int cached,
  required int failed,
  required int evicted,
  required int evictedBytes,
}) {
  final parts = <String>[];
  if (cached > 0) {
    parts.add('Cached $cached offline item(s)');
  }
  if (failed > 0) {
    parts.add('could not cache $failed offline item(s)');
  }
  if (evicted > 0) {
    parts.add(
      'auto-evicted ${_formatByteCount(evictedBytes)} from '
      '$evicted cached item(s)',
    );
  }
  if (parts.isEmpty) {
    return 'No offline items were cached.';
  }

  return '${parts.join('; ')}.';
}

class _AccentColorDropdownLabel extends StatelessWidget {
  const _AccentColorDropdownLabel({required this.accentColor});

  final AppAccentColor accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            color: seedColorForAccent(accentColor),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: const SizedBox.square(dimension: 16),
        ),
        const SizedBox(width: 8),
        Text(accentColor.label),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({this.onRestartOnboarding});

  final VoidCallback? onRestartOnboarding;

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    final library = context.watch<LibraryStore>();
    final folderWatcher = context.watch<LocalFolderWatchStore?>();
    final duplicateGroups = library.duplicateTrackGroups();
    final offlineQueue = library.offlineCacheQueue;
    final offlineCacheLimitBytes = library.offlineCacheLimitBytes;
    final pendingOfflineQueue = offlineQueue
        .where(_canProcessOfflineCacheEntry)
        .toList(growable: false);
    final pausedOfflineQueueCount = offlineQueue
        .where((entry) => entry.status == OfflineCacheEntryStatus.paused)
        .length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('Options', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (onRestartOnboarding != null)
          ListTile(
            leading: const Icon(Icons.rocket_launch_outlined),
            title: const Text('Run setup again'),
            subtitle: const Text(
              'Choose a local-library or legal-source starting point.',
            ),
            onTap: onRestartOnboarding,
          ),
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
        ListTile(
          title: const Text('Playback speed'),
          subtitle: const Text(
            'Sets the default for future playback; track overrides stay separate.',
          ),
          trailing: DropdownButton<double>(
            value: player.defaultPlaybackSpeed,
            items: <DropdownMenuItem<double>>[
              for (final speed in PlayerController.supportedPlaybackSpeeds)
                DropdownMenuItem<double>(
                  value: speed,
                  child: Text(
                    speed == speed.roundToDouble()
                        ? '${speed.toStringAsFixed(0)}x'
                        : '${speed}x',
                  ),
                ),
            ],
            onChanged: (speed) async {
              if (speed == null) {
                return;
              }
              await player.setPlaybackSpeed(speed);
              final current = player.current;
              final override = current == null
                  ? null
                  : library.playbackSpeedForTrack(current.id);
              if (override != null) {
                await player.setTemporaryPlaybackSpeed(override);
              }
            },
          ),
        ),
        ListTile(
          title: const Text('Skip backward'),
          subtitle: const Text('Interval used by the full player rewind control.'),
          trailing: DropdownButton<Duration>(
            value: player.skipBackwardInterval,
            items: <DropdownMenuItem<Duration>>[
              for (final interval in PlayerController.supportedSkipIntervals)
                DropdownMenuItem<Duration>(
                  value: interval,
                  child: Text('${interval.inSeconds}s'),
                ),
            ],
            onChanged: (interval) {
              if (interval != null) {
                unawaited(player.setSkipBackwardInterval(interval));
              }
            },
          ),
        ),
        ListTile(
          title: const Text('Skip forward'),
          subtitle: const Text('Interval used by the full player forward control.'),
          trailing: DropdownButton<Duration>(
            value: player.skipForwardInterval,
            items: <DropdownMenuItem<Duration>>[
              for (final interval in PlayerController.supportedSkipIntervals)
                DropdownMenuItem<Duration>(
                  value: interval,
                  child: Text('${interval.inSeconds}s'),
                ),
            ],
            onChanged: (interval) {
              if (interval != null) {
                unawaited(player.setSkipForwardInterval(interval));
              }
            },
          ),
        ),
        ListTile(
          leading: Icon(
            player.volume == 0
                ? Icons.volume_off_outlined
                : Icons.volume_up_outlined,
          ),
          title: const Text('Playback volume'),
          subtitle: Slider(
            value: player.volume,
            semanticFormatterCallback: (value) =>
                'Playback volume ${PlayerController.formatVolume(value)}',
            onChanged: player.isSleepFadeActive
                ? null
                : (value) => unawaited(player.previewVolume(value)),
            onChangeEnd: player.isSleepFadeActive
                ? null
                : (value) => unawaited(player.setVolume(value)),
          ),
          trailing: Text(PlayerController.formatVolume(player.volume)),
        ),
        if (library.watchedLocalFolderPaths.isNotEmpty) ...<Widget>[
          const Divider(),
          Text(
            'Watched folders',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          for (final rootPath in library.watchedLocalFolderPaths)
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(
                p.basename(rootPath),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                folderWatcher?.errorFor(rootPath) ??
                    (folderWatcher?.isRefreshing(rootPath) ?? false
                        ? 'Refreshing library changes...'
                        : rootPath),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Refresh folder',
                    onPressed: folderWatcher == null ||
                            folderWatcher.isRefreshing(rootPath)
                        ? null
                        : () => folderWatcher.refresh(rootPath),
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Stop watching folder',
                    onPressed: () => unawaited(
                      library.unwatchLocalFolder(rootPath),
                    ),
                    icon: const Icon(Icons.folder_off_outlined),
                  ),
                ],
              ),
            ),
        ],
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Theme'),
          subtitle: Text(library.themePreference.label),
          trailing: DropdownButton<AppThemePreference>(
            value: library.themePreference,
            items: const <DropdownMenuItem<AppThemePreference>>[
              DropdownMenuItem(
                value: AppThemePreference.system,
                child: Text('System'),
              ),
              DropdownMenuItem(
                value: AppThemePreference.light,
                child: Text('Light'),
              ),
              DropdownMenuItem(
                value: AppThemePreference.dark,
                child: Text('Dark'),
              ),
              DropdownMenuItem(
                value: AppThemePreference.amoled,
                child: Text('AMOLED'),
              ),
            ],
            onChanged: (preference) {
              if (preference != null) {
                unawaited(library.setThemePreference(preference));
              }
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.color_lens_outlined),
          title: const Text('Accent color'),
          subtitle: Text(library.accentColor.label),
          trailing: DropdownButton<AppAccentColor>(
            value: library.accentColor,
            items: <DropdownMenuItem<AppAccentColor>>[
              for (final accentColor in AppAccentColor.values)
                DropdownMenuItem<AppAccentColor>(
                  value: accentColor,
                  child: _AccentColorDropdownLabel(accentColor: accentColor),
                ),
            ],
            onChanged: (accentColor) {
              if (accentColor != null) {
                unawaited(library.setAccentColor(accentColor));
              }
            },
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.pause_circle_outline),
          title: const Text('Pause listening history'),
          subtitle: const Text(
            'Stop saving new plays and resume progress until this is turned off.',
          ),
          value: library.pauseListeningHistory,
          onChanged: (value) {
            unawaited(library.setPauseListeningHistory(value));
          },
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
        SwitchListTile(
          secondary: const Icon(Icons.download_for_offline_outlined),
          title: const Text('Automatic foreground downloads'),
          subtitle: const Text(
            'Process approved queued items one at a time while the app is open.',
          ),
          value: library.automaticOfflineQueueEnabled,
          onChanged: library.offlineModeEnabled
              ? null
              : (value) {
                  unawaited(library.setAutomaticOfflineQueueEnabled(value));
                },
        ),
        ListTile(
          leading: const Icon(Icons.download_for_offline_outlined),
          title: const Text('Offline queue'),
          subtitle: Text(
            offlineQueue.isEmpty
                ? 'No queued cache or download requests'
                : '${offlineQueue.length} queued cache/download request(s), '
                    '${pendingOfflineQueue.length} ready, '
                    '$pausedOfflineQueueCount paused',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Cache queued media',
                onPressed: pendingOfflineQueue.isEmpty
                    ? null
                    : () => unawaited(
                          _processOfflineCacheEntries(
                            context,
                            pendingOfflineQueue,
                          ),
                        ),
                icon: const Icon(Icons.cloud_download_outlined),
              ),
              IconButton(
                tooltip: 'Clear offline queue',
                onPressed: offlineQueue.isEmpty
                    ? null
                    : () => unawaited(library.clearOfflineCacheQueue()),
                icon: const Icon(Icons.clear_all),
              ),
            ],
          ),
        ),
        FutureBuilder<OfflineCacheUsage>(
          future: _offlineCacheUsage(offlineQueue),
          builder: (context, snapshot) {
            final usage = snapshot.data;
            final offlineCacheLimitLabel =
                _formatByteCount(offlineCacheLimitBytes);
            final canTrim =
                usage != null && usage.byteCount > offlineCacheLimitBytes;
            final canClear = usage != null && usage.byteCount > 0;
            final subtitle = snapshot.hasError
                ? 'Could not read cache usage.'
                : usage == null
                    ? 'Calculating private cache usage...'
                    : '${_formatByteCount(usage.byteCount)} across '
                        '${usage.cachedEntryCount} cached item(s) · '
                        'Limit: $offlineCacheLimitLabel';

            return ListTile(
              leading: const Icon(Icons.storage_outlined),
              title: const Text('Offline cache storage'),
              subtitle: Text(subtitle),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    tooltip: 'Set cache limit',
                    onPressed: () => unawaited(
                      _showOfflineCacheLimitDialog(context),
                    ),
                    icon: const Icon(Icons.tune_outlined),
                  ),
                  IconButton(
                    tooltip: 'Trim cache to $offlineCacheLimitLabel',
                    onPressed: canTrim
                        ? () => unawaited(
                              _trimOfflineCache(
                                context,
                                offlineCacheLimitBytes,
                              ),
                            )
                        : null,
                    icon: const Icon(Icons.cleaning_services_outlined),
                  ),
                  IconButton(
                    tooltip: 'Clear cached media',
                    onPressed: canClear
                        ? () => unawaited(_trimOfflineCache(context, 0))
                        : null,
                    icon: const Icon(Icons.delete_sweep_outlined),
                  ),
                ],
              ),
            );
          },
        ),
        for (final sourceId in _offlineCacheProviderIds(offlineQueue))
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: Text('Provider cache limit: $sourceId'),
            subtitle: Text(_offlineCacheProviderLimitLabel(library, sourceId)),
            trailing: IconButton(
              tooltip: 'Set $sourceId cache limit',
              onPressed: () => unawaited(
                _showOfflineCacheProviderLimitDialog(context, sourceId),
              ),
              icon: const Icon(Icons.tune_outlined),
            ),
          ),
        for (final entry in offlineQueue.take(5))
          ListTile(
            dense: true,
            leading: Icon(_offlineCacheEntryIcon(entry)),
            title: Text(
              entry.track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _offlineCacheEntrySubtitle(entry),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'Cache media',
                  onPressed: _canProcessOfflineCacheEntry(entry)
                      ? () => unawaited(
                            _processOfflineCacheEntries(
                              context,
                              <OfflineCacheEntry>[entry],
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.cloud_download_outlined),
                ),
                IconButton(
                  tooltip: _canResumeOfflineCacheEntry(entry)
                      ? 'Resume offline request'
                      : 'Pause offline request',
                  onPressed: _canResumeOfflineCacheEntry(entry)
                      ? () => unawaited(
                            library.resumeOfflineCacheEntry(entry.id),
                          )
                      : _canPauseOfflineCacheEntry(entry)
                          ? () => unawaited(
                                library.pauseOfflineCacheEntry(entry.id),
                              )
                          : null,
                  icon: Icon(
                    _canResumeOfflineCacheEntry(entry)
                        ? Icons.play_arrow_outlined
                        : Icons.pause_outlined,
                  ),
                ),
                IconButton(
                  tooltip: 'Export cached media',
                  onPressed: _canExportOfflineCacheEntry(entry)
                      ? () => unawaited(
                            _exportOfflineCacheEntry(context, entry),
                          )
                      : null,
                  icon: const Icon(Icons.file_download_outlined),
                ),
                IconButton(
                  tooltip: 'Remove from offline queue',
                  onPressed: () => unawaited(
                    library.removeOfflineCacheEntry(entry.id),
                  ),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        if (offlineQueue.length > 5)
          ListTile(
            dense: true,
            leading: const Icon(Icons.more_horiz),
            title: Text('${offlineQueue.length - 5} more queued item(s)'),
          ),
        const Divider(),
        const LibrarySyncPanel(),
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

  Future<OfflineCacheUsage> _offlineCacheUsage(
    List<OfflineCacheEntry> entries,
  ) async {
    final cacheRoot = await getApplicationDocumentsDirectory();
    return OfflineCacheManager(cacheRoot: cacheRoot).usage(entries);
  }

  Future<void> _showOfflineCacheLimitDialog(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(
      text: library.offlineCacheLimitMegabytes.toString(),
    );

    int? parseLimit() {
      return int.tryParse(controller.text.trim());
    }

    try {
      final selectedLimit = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Offline cache limit'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Limit in MB',
                helperText: 'Allowed range: 50-51200 MB',
              ),
              onSubmitted: (_) {
                Navigator.of(dialogContext).pop(parseLimit());
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(parseLimit());
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (!context.mounted || selectedLimit == null) {
        return;
      }

      await library.setOfflineCacheLimitMegabytes(selectedLimit);
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Offline cache limit set to '
            '${_formatByteCount(library.offlineCacheLimitBytes)}.',
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showOfflineCacheProviderLimitDialog(
    BuildContext context,
    String sourceId,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final currentLimit = library.offlineCacheProviderLimitMegabytesFor(
      sourceId,
    );
    final controller = TextEditingController(
      text: currentLimit?.toString() ?? '0',
    );

    int? parseLimit() {
      return int.tryParse(controller.text.trim());
    }

    try {
      final selectedLimit = await showDialog<int>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('$sourceId cache limit'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: const InputDecoration(
                labelText: 'Limit in MB',
                helperText: '0 clears quota. Allowed range: 1-51200 MB',
              ),
              onSubmitted: (_) {
                Navigator.of(dialogContext).pop(parseLimit());
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop(parseLimit());
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (!context.mounted || selectedLimit == null) {
        return;
      }

      await library.setOfflineCacheProviderLimitMegabytes(
        sourceId,
        selectedLimit <= 0 ? null : selectedLimit,
      );
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$sourceId cache limit: '
            '${_offlineCacheProviderLimitLabel(library, sourceId)}.',
          ),
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _trimOfflineCache(
    BuildContext context,
    int maxBytes,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final cacheRoot = await getApplicationDocumentsDirectory();
    final manager = OfflineCacheManager(cacheRoot: cacheRoot);
    final result = await manager.evictToSize(
      entries: library.offlineCacheQueue,
      maxBytes: maxBytes,
    );
    final reason = maxBytes <= 0
        ? 'Cached media cleared.'
        : 'Evicted to keep cache under ${_formatByteCount(maxBytes)}.';

    for (final entryId in result.evictedEntryIds) {
      await library.markOfflineCacheEntryEvicted(entryId, reason: reason);
    }

    if (!context.mounted) {
      return;
    }

    final message = result.evictedEntryIds.isEmpty
        ? maxBytes <= 0
            ? 'No cached media to clear.'
            : 'Offline cache already under ${_formatByteCount(maxBytes)}.'
        : 'Cleared ${_formatByteCount(result.evictedBytes)} from '
            '${result.evictedEntryIds.length} cached item(s).';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exportOfflineCacheEntry(
    BuildContext context,
    OfflineCacheEntry queuedEntry,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final entry = library.offlineCacheEntryById(queuedEntry.id) ?? queuedEntry;
    if (!_canExportOfflineCacheEntry(entry)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Cache this media before exporting it.')),
      );
      return;
    }

    final destinationPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Export cached media',
    );
    if (!context.mounted || destinationPath == null) {
      return;
    }

    final cacheRoot = await getApplicationDocumentsDirectory();
    final manager = OfflineCacheManager(cacheRoot: cacheRoot);
    try {
      final export = await manager.exportCachedMedia(
        entry: entry,
        destinationDirectory: Directory(destinationPath),
      );
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${p.basename(export.file.path)} '
            '(${_formatByteCount(export.byteCount)}).',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(_offlineCacheErrorMessage(error))),
      );
    }
  }

  Future<void> _processOfflineCacheEntries(
    BuildContext context,
    List<OfflineCacheEntry> entries,
  ) async {
    final library = context.read<LibraryStore>();
    final selfHosted = context.read<SelfHostedProviderStore>();
    final messenger = ScaffoldMessenger.of(context);
    final cacheRoot = await getApplicationDocumentsDirectory();
    if (!context.mounted) {
      return;
    }

    final manager = OfflineCacheManager(cacheRoot: cacheRoot);
    var cached = 0;
    var failed = 0;
    var evicted = 0;
    var evictedBytes = 0;

    for (final queuedEntry in entries) {
      final entry = library.offlineCacheEntryById(queuedEntry.id);
      if (entry == null || !_canProcessOfflineCacheEntry(entry)) {
        continue;
      }

      await library.markOfflineCacheEntryProcessing(entry.id);
      final processingEntry = library.offlineCacheEntryById(entry.id) ?? entry;

      try {
        final resolvedTrack = await selfHosted.resolveTrack(
          processingEntry.track,
        );
        final materialization = await manager.materialize(
          processingEntry.copyWith(track: resolvedTrack),
        );
        final cacheReason = materialization.checksum.isEmpty
            ? 'Cached ${_formatByteCount(materialization.byteCount)}.'
            : 'Cached ${_formatByteCount(materialization.byteCount)}; checksum verified.';
        await library.markOfflineCacheEntryCached(
          entry.id,
          materialization.track,
          reason: cacheReason,
          byteCount: materialization.byteCount,
          checksum: materialization.checksum,
        );
        final evictionResult = await enforceOfflineCacheLimit(
          library: library,
          manager: manager,
        );
        evicted += evictionResult.evictedEntryIds.length;
        evictedBytes += evictionResult.evictedBytes;
        cached += 1;
      } on Object catch (error) {
        await library.markOfflineCacheEntryFailed(
          entry.id,
          reason: _offlineCacheErrorMessage(error),
        );
        failed += 1;
      }
    }

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          _offlineCacheResultMessage(
            cached: cached,
            failed: failed,
            evicted: evicted,
            evictedBytes: evictedBytes,
          ),
        ),
      ),
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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: const Text('Save backup file'),
                subtitle: const Text(
                  'Write a portable JSON backup to a chosen location.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _saveBackupFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: const Text('View backup JSON'),
                subtitle: const Text('Inspect or copy the backup text.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showBackupJson(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveBackupFile(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final backupJson = library.exportBackupJson();
    final fileName = aetherTuneBackupFileName(DateTime.now());
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = encodeAetherTuneBackupFile(backupJson);
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save AetherTune backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>[aetherTuneBackupFileExtension],
        bytes: bytes,
      );
      if (outputPath == null || outputPath.isEmpty) {
        return;
      }

      if (!Platform.isAndroid && !Platform.isIOS) {
        await File(outputPath).writeAsBytes(bytes, flush: true);
      }
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName.')));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save backup file: $error')),
      );
    }
  }

  Future<void> _showBackupJson(BuildContext context) async {
    final backupJson = context.read<LibraryStore>().exportBackupJson();

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
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('Choose backup file'),
                subtitle: const Text(
                  'Restore an AetherTune JSON backup from storage.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _restoreBackupFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_outlined),
                title: const Text('Paste backup JSON'),
                subtitle: const Text('Restore from copied backup text.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _restoreBackupFromText(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _restoreBackupFile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>[aetherTuneBackupFileExtension],
      );
      final files = result?.files;
      if (files == null || files.isEmpty) {
        return;
      }

      final file = files.first;
      final bytes = await file.readAsBytes();
      if (!context.mounted) {
        return;
      }
      await _restoreBackupJson(context, decodeAetherTuneBackupFile(bytes));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read backup file: $error')),
      );
    }
  }

  Future<void> _restoreBackupFromText(BuildContext context) async {
    final backupJson = await _promptForBackupJson(context);
    if (!context.mounted || backupJson == null) {
      return;
    }
    await _restoreBackupJson(context, backupJson);
  }

  Future<void> _restoreBackupJson(
    BuildContext context,
    String backupJson,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

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
