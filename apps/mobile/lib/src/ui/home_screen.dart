import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aethertune/l10n/app_localizations.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../data/demo_source_provider.dart';
import '../data/custom_catalog_provider.dart';
import '../data/custom_catalog_store.dart';
import '../data/flac_vorbis_comment_writer.dart';
import '../data/internet_archive_provider.dart';
import '../data/jellyfin_provider.dart';
import '../data/library_store.dart';
import '../data/local_diagnostic_log.dart';
import '../data/local_folder_watch_store.dart';
import '../data/local_library_provider.dart';
import '../data/local_folder_scanner.dart';
import '../data/lrclib_lyrics_provider.dart';
import '../data/lyrics_translation_settings_store.dart';
import '../data/m4a_metadata_writer.dart';
import '../data/mp3_id3v1_tag_writer.dart';
import '../data/ogg_vorbis_comment_writer.dart';
import '../data/offline_cache_manager.dart';
import '../data/offline_cache_pressure_enforcer.dart';
import '../data/podcast_rss_provider.dart';
import '../data/podcast_subscription_refresh_worker.dart';
import '../data/playlist_artwork_file_store.dart';
import '../data/radio_browser_provider.dart';
import '../data/self_hosted_provider_store.dart';
import '../data/subsonic_provider.dart';
import '../data/track_artwork_file_store.dart';
import '../data/wav_riff_info_writer.dart';
import '../data/youtube_data_settings_store.dart';
import '../domain/backup_file_document.dart';
import '../domain/custom_catalog_definition.dart';
import '../domain/lyrics_document.dart';
import '../domain/lyrics_translator.dart';
import '../domain/music_catalog_discovery_provider.dart';
import '../domain/music_catalog_provider.dart';
import '../domain/replay_gain.dart';
import '../domain/music_source_provider.dart';
import '../domain/offline_cache_cancellation.dart';
import '../domain/offline_cache_entry.dart';
import '../domain/playback_history_entry.dart';
import '../domain/playback_progress_entry.dart';
import '../domain/playlist.dart';
import '../domain/playlist_export_file.dart';
import '../domain/podcast_opml.dart';
import '../domain/podcast_subscription.dart';
import '../domain/provider_search.dart';
import '../domain/provider_home_feed.dart';
import '../domain/self_hosted_provider_account.dart';
import '../domain/sleep_timer_duration.dart';
import '../domain/track.dart';
import '../domain/track_lyrics.dart';
import '../player/offline_playback_policy.dart';
import '../player/android_pinned_shortcut_bridge.dart';
import '../player/player_controller.dart';
import 'now_playing_screen.dart';
import 'desktop_navigation_shortcuts.dart';
import 'internet_archive_item_screen.dart';
import 'platform_audio_route_picker.dart';
import 'platform_text_share.dart';
import 'radio_browser_station_screen.dart';
import 'responsive_layout.dart';
import 'self_hosted_browse_screen.dart';
import 'theme_colors.dart';
import 'widgets/listening_recap_card.dart';
import 'widgets/artwork_crop_editor.dart';
import 'widgets/audio_effects_settings.dart';
import 'widgets/collection_share_card.dart';
import 'widgets/listening_heatmap.dart';
import 'widgets/listening_stats_bar_chart.dart';
import 'widgets/library_sync_panel.dart';
import 'widgets/desktop_queue_pane.dart';
import 'widgets/desktop_tray_controls.dart';
import 'widgets/lyrics_share_card.dart';
import 'widgets/lyrics_search_sheet.dart';
import 'widgets/player_bar.dart';
import 'widgets/playlist_artwork.dart';
import 'widgets/self_hosted_account_editor.dart';
import 'widgets/self_hosted_credential_rotation_dialog.dart';
import 'widgets/track_tile.dart';
import 'widgets/track_artwork.dart';

class _AetherTuneNavigationDestination {
  const _AetherTuneNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String Function(AppLocalizations localizations) label;
}

const _aetherTuneNavigationDestinationCount = 6;

Future<void> _showMobileAudioRoutePicker(BuildContext context) async {
  final opened = await showPlatformAudioRoutePicker();
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Audio output selection is unavailable on this device.'),
      ),
    );
  }
}

Future<void> _configureLyricsTranslation(BuildContext context) async {
  final store = context.read<LyricsTranslationSettingsStore?>();
  if (store == null) {
    return;
  }
  final endpointController = TextEditingController(
    text: store.endpoint?.toString() ?? '',
  );
  final targetLanguageController = TextEditingController(
    text: store.targetLanguage,
  );
  final apiKeyController = TextEditingController();
  String? validationError;
  try {
    final draft = await showDialog<_LyricsTranslationConfiguration>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Configure lyrics translation'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'AetherTune sends lyric text only to the LibreTranslate-compatible service you choose. Translation is shown separately and never replaces the original timed lyrics.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('lyrics-translation-endpoint'),
                    controller: endpointController,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Service URL',
                      hintText: 'https://translate.example',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('lyrics-translation-target-language'),
                    controller: targetLanguageController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Target language',
                      hintText: 'en, tr, de, ...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('lyrics-translation-api-key'),
                    controller: apiKeyController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'API key (optional)',
                      helperText: 'Leave empty to use no API key.',
                    ),
                  ),
                  if (validationError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ],
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
                final endpoint = endpointController.text.trim();
                final targetLanguage = targetLanguageController.text.trim();
                if (endpoint.isEmpty || targetLanguage.isEmpty) {
                  setDialogState(
                    () => validationError =
                        'Enter a service URL and target language.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(
                  _LyricsTranslationConfiguration(
                    endpoint: endpoint,
                    targetLanguage: targetLanguage,
                    apiKey: apiKeyController.text,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || draft == null) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!context.mounted) {
      return;
    }
    await store.save(
      endpoint: draft.endpoint,
      targetLanguage: draft.targetLanguage,
      apiKey: draft.apiKey,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lyrics translation configured.')),
      );
    }
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  } finally {
    endpointController.dispose();
    targetLanguageController.dispose();
    apiKeyController.dispose();
  }
}

Future<void> _removeLyricsTranslation(BuildContext context) async {
  final store = context.read<LyricsTranslationSettingsStore?>();
  if (store == null || !store.isConfigured) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Remove lyrics translation service?'),
      content: const Text(
        'This removes the endpoint, target language, and any API key from this device. Saved lyrics remain unchanged.',
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
  await store.remove();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Lyrics translation service removed.')),
    );
  }
}

class _LyricsTranslationConfiguration {
  const _LyricsTranslationConfiguration({
    required this.endpoint,
    required this.targetLanguage,
    required this.apiKey,
  });

  final String endpoint;
  final String targetLanguage;
  final String apiKey;
}

final AndroidPinnedShortcutBridge _androidPinnedShortcutBridge =
    AndroidPinnedShortcutBridge();

Future<void> _requestAndroidPinnedShortcut(
  BuildContext context,
  AndroidPinnedShortcut shortcut,
) async {
  final requested = await _androidPinnedShortcutBridge.requestPin(shortcut);
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        requested
            ? 'Confirm the launcher prompt to pin ${shortcut.label}.'
            : 'Pinned shortcuts are unavailable in this launcher.',
      ),
    ),
  );
}

final _aetherTuneNavigationDestinations = <_AetherTuneNavigationDestination>[
  _AetherTuneNavigationDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: (localizations) => localizations.home,
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.my_library_music_outlined,
    selectedIcon: Icons.my_library_music,
    label: (localizations) => localizations.library,
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.playlist_play_outlined,
    selectedIcon: Icons.playlist_play,
    label: (localizations) => localizations.playlists,
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    label: (localizations) => localizations.history,
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension,
    label: (localizations) => localizations.sources,
  ),
  _AetherTuneNavigationDestination(
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    label: (localizations) => localizations.options,
  ),
];

final _playlistArtworkFileStore = PlaylistArtworkFileStore();
final _trackArtworkFileStore = TrackArtworkFileStore();
const _platformTextShareService = SharePlusTextShareService();

List<NavigationDestination> _navigationBarDestinations(
  AppLocalizations localizations,
) {
  return _aetherTuneNavigationDestinations.map((destination) {
    return NavigationDestination(
      icon: Icon(destination.icon),
      selectedIcon: Icon(destination.selectedIcon),
      label: destination.label(localizations),
    );
  }).toList(growable: false);
}

List<NavigationRailDestination> _navigationRailDestinations(
  AppLocalizations localizations,
) {
  return _aetherTuneNavigationDestinations.map((destination) {
    return NavigationRailDestination(
      icon: Icon(destination.icon),
      selectedIcon: Icon(destination.selectedIcon),
      label: Text(destination.label(localizations)),
    );
  }).toList(growable: false);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialTab = 0,
    this.onRestartOnboarding,
    this.internetArchiveProvider,
    this.providerSearchProviders,
  }) : assert(
         initialTab >= 0 &&
             initialTab < _aetherTuneNavigationDestinationCount,
       );

  final int initialTab;
  final VoidCallback? onRestartOnboarding;
  final InternetArchiveProvider? internetArchiveProvider;
  final List<MusicSourceProvider>? providerSearchProviders;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _radioClickProvider = RadioBrowserProvider();
  final _lyricsProvider = LrcLibLyricsProvider();
  final _lyricsCacheSettings = LyricsSearchCacheSettingsStore();
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
  Duration _lyricsSearchCacheLifetime = defaultLyricsSearchCacheLifetime;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
    unawaited(_loadLyricsSearchCacheLifetime());
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

  Future<void> _clearLyricsSearchCache(BuildContext context) async {
    try {
      await _lyricsProvider.clearCachedSearchResults();
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not clear cached lyrics searches.')),
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cached lyrics searches cleared.')),
    );
  }

  Future<void> _loadLyricsSearchCacheLifetime() async {
    final retention = await _lyricsCacheSettings.loadRetention();
    if (!mounted) {
      return;
    }
    _lyricsProvider.setCacheLifetime(retention);
    setState(() => _lyricsSearchCacheLifetime = retention);
  }

  Future<void> _setLyricsSearchCacheLifetime(
    BuildContext context,
    Duration retention,
  ) async {
    try {
      await _lyricsCacheSettings.saveRetention(retention);
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save lyrics cache retention.')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    _lyricsProvider.setCacheLifetime(retention);
    setState(() => _lyricsSearchCacheLifetime = retention);
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
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
              _SourcesTab(
                archiveProvider: widget.internetArchiveProvider,
                providerSearchProviders: widget.providerSearchProviders,
              ),
              _SettingsTab(
                onRestartOnboarding: widget.onRestartOnboarding,
                onClearLyricsSearchCache: () => _clearLyricsSearchCache(context),
                lyricsSearchCacheLifetime: _lyricsSearchCacheLifetime,
                onLyricsSearchCacheLifetimeChanged: (retention) {
                  unawaited(_setLyricsSearchCacheLifetime(context, retention));
                },
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
        title: Text(localizations.appTitle),
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
                    destinations: _navigationRailDestinations(localizations),
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
              destinations: _navigationBarDestinations(localizations),
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
                  TextButton.icon(
                    onPressed: () => unawaited(
                      _copyLyricsSelectedRangeShareText(
                        dialogContext,
                        library,
                        track,
                        plainText: controller.text,
                      ),
                    ),
                    icon: const Icon(Icons.format_line_spacing),
                    label: const Text('Share selected lines'),
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
        const SnackBar(content: Text('Choose a .txt, .lrc, or .ttml lyrics file.')),
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
    final translationSettings =
        context.read<LyricsTranslationSettingsStore?>();
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
          translator: translationSettings?.translator,
          translationTargetLanguage:
              translationSettings?.targetLanguage ?? 'en',
          onEdit: () {
            Navigator.of(sheetContext).pop();
            unawaited(_showLyricsEditor(context, track));
          },
          onShare: () => unawaited(
            _copyLyricsShareText(context, library, track),
          ),
          onShareRange: () => unawaited(
            _copyLyricsSelectedRangeShareText(context, library, track),
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
          await library.setLyricsIfAbsent(
            entry.key,
            entry.value,
            sourceId: 'sidecar',
            sourceName: 'Local lyric sidecar',
          );
        }
        for (final entry in scanResult.embeddedLyricsByTrackId.entries) {
          await library.setLyricsIfAbsent(
            entry.key,
            entry.value,
            sourceId: 'embedded',
            sourceName: 'Embedded ID3 lyrics',
          );
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
        } else if (_isLocalM4a(updated)) {
          await const M4aMetadataWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            genre: updated.genre,
          );
        } else if (_isLocalOggOrOpus(updated)) {
          await const OggVorbisCommentWriter().write(
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
            SnackBar(content: Text('Saved app metadata, but could not update embedded tags: $error')),
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

Future<void> _editTrackArtwork(BuildContext context, Track track) async {
  if (track.sourceId != 'local') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Artwork editing is available for local library tracks.'),
      ),
    );
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
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose image file'),
              subtitle: const Text(
                'Store a private PNG, JPEG, GIF, or WebP image.',
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickTrackArtworkFile(context, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Set image URL'),
              subtitle: const Text('Use an http or https image URL.'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _setTrackArtworkUrl(context, track);
              },
            ),
            if (_isLocalM4a(track))
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: const Text('Write cover to M4A file'),
                subtitle: const Text(
                  'Replace the embedded cover with a PNG or JPEG under 512 KiB.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _writeM4aArtwork(context, track);
                },
              ),
            if (track.artworkIsUserManaged)
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Restore scanned artwork'),
                subtitle: const Text(
                  'Remove the saved cover and use the embedded artwork again.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _restoreTrackArtwork(context, track);
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _pickTrackArtworkFile(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await FilePicker.pickFile(
    type: FileType.image,
    dialogTitle: 'Choose track artwork',
  );
  if (!context.mounted || file == null) {
    return;
  }

  Uri? savedArtwork;
  try {
    savedArtwork = await _trackArtworkFileStore.save(await file.readAsBytes());
    if (!context.mounted) {
      await _trackArtworkFileStore.delete(savedArtwork);
      return;
    }
    final updated = await context.read<LibraryStore>().updateTrackArtwork(
      track.id,
      savedArtwork,
    );
    if (!context.mounted || updated == null) {
      await _trackArtworkFileStore.delete(savedArtwork);
      return;
    }
    await _trackArtworkFileStore.delete(
      track.artworkIsUserManaged ? track.artworkUri : null,
    );
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Updated artwork for ${updated.title}.')),
    );
  } on FormatException catch (error) {
    await _trackArtworkFileStore.delete(savedArtwork);
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on Object catch (error) {
    await _trackArtworkFileStore.delete(savedArtwork);
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save artwork: $error')),
      );
    }
  }
}

Future<void> _writeM4aArtwork(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final library = context.read<LibraryStore>();
  final file = await FilePicker.pickFile(
    type: FileType.image,
    dialogTitle: 'Choose M4A cover artwork',
  );
  if (!context.mounted || file == null) {
    return;
  }

  final artwork = await file.readAsBytes();
  if (!context.mounted) {
    return;
  }
  final confirmed = await _confirmM4aArtworkWrite(context);
  if (!context.mounted || confirmed != true) {
    return;
  }

  try {
    await const M4aMetadataWriter().writeArtwork(
      path: track.localPath!,
      artwork: artwork,
    );
    final updated = await library.updateEmbeddedTrackArtwork(
      track.id,
      _m4aArtworkDataUri(artwork),
    );
    if (!context.mounted || updated == null) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Wrote embedded artwork for ${updated.title}.')),
    );
  } on FormatException catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not update embedded M4A artwork: $error')),
      );
    }
  }
}

Future<bool?> _confirmM4aArtworkWrite(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update M4A embedded artwork?'),
      content: const Text(
        'This replaces the file cover with the selected PNG or JPEG. Other M4A metadata is preserved. Standard front-loaded M4A files repair validated chunk offsets; malformed or fragmented layouts are left unchanged.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Update M4A'),
        ),
      ],
    ),
  );
}

Uri _m4aArtworkDataUri(List<int> artwork) {
  final mimeType = artwork.length >= 8 &&
          artwork[0] == 0x89 &&
          artwork[1] == 0x50 &&
          artwork[2] == 0x4e &&
          artwork[3] == 0x47 &&
          artwork[4] == 0x0d &&
          artwork[5] == 0x0a &&
          artwork[6] == 0x1a &&
          artwork[7] == 0x0a
      ? 'image/png'
      : 'image/jpeg';
  return Uri.parse('data:$mimeType;base64,${base64Encode(artwork)}');
}

Future<void> _setTrackArtworkUrl(BuildContext context, Track track) async {
  final initialValue = track.artworkIsUserManaged &&
          track.artworkUri != null &&
          _isNetworkImageUri(track.artworkUri!)
      ? track.artworkUri!.toString()
      : '';
  final value = await _promptForTrackArtworkUrl(context, initialValue);
  if (!context.mounted || value == null) {
    return;
  }

  final artworkUri = Uri.tryParse(value.trim());
  if (artworkUri == null || !_isNetworkImageUri(artworkUri)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enter an http or https image URL.')),
    );
    return;
  }

  try {
    final updated = await context.read<LibraryStore>().updateTrackArtwork(
      track.id,
      artworkUri,
    );
    if (!context.mounted || updated == null) {
      return;
    }
    await _trackArtworkFileStore.delete(
      track.artworkIsUserManaged ? track.artworkUri : null,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated artwork for ${updated.title}.')),
    );
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save artwork: $error')),
      );
    }
  }
}

Future<void> _restoreTrackArtwork(BuildContext context, Track track) async {
  final updated = await context.read<LibraryStore>().updateTrackArtwork(
    track.id,
    null,
  );
  if (!context.mounted || updated == null) {
    return;
  }
  await _trackArtworkFileStore.delete(track.artworkUri);
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Restored scanned artwork for ${updated.title}.')),
  );
}

Future<String?> _promptForTrackArtworkUrl(
  BuildContext context,
  String initialValue,
) async {
  final controller = TextEditingController(text: initialValue);
  try {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Track artwork URL'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Image URL',
              hintText: 'https://example.com/cover.png',
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text),
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
    required this.translator,
    required this.translationTargetLanguage,
    required this.onEdit,
    required this.onShare,
    required this.onShareRange,
  });

  final Track track;
  final TrackLyrics? lyrics;
  final PlayerController player;
  final LyricsTranslator? translator;
  final String translationTargetLanguage;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;

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
        onShareRange: onShareRange,
        onTranslate: _translationAction(
          context,
          currentLyrics.plainText,
        ),
      );
    }

    return _SyncedNowPlayingLyrics(
      track: track,
      lines: syncedLines,
      sourceLabel: currentLyrics.attributionLabel,
      player: player,
      onEdit: onEdit,
      onShare: onShare,
      onShareRange: onShareRange,
      onTranslate: _translationAction(
        context,
        syncedLines.map((line) => line.text).join('\n'),
      ),
    );
  }

  VoidCallback? _translationAction(BuildContext context, String lyricsText) {
    final currentTranslator = translator;
    if (currentTranslator == null || lyricsText.trim().isEmpty) {
      return null;
    }
    return () => unawaited(
      _showLyricsTranslation(
        context,
        translator: currentTranslator,
        lyrics: lyricsText,
        targetLanguage: translationTargetLanguage,
      ),
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
            subtitle: Text(
              'Add plain lyrics or import LRC, SRT, or TTML timed lyrics.',
            ),
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
    required this.onShareRange,
    this.onTranslate,
  });

  final Track track;
  final String lyrics;
  final String? sourceLabel;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback? onTranslate;

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
                onShareRange: onShareRange,
                onTranslate: onTranslate,
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
    required this.onShareRange,
    this.onTranslate,
  });

  final Track track;
  final List<SyncedLyricLine> lines;
  final String? sourceLabel;
  final PlayerController player;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback? onTranslate;

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
                      onShareRange: widget.onShareRange,
                      onTranslate: widget.onTranslate,
                    );
                  }

                  final lineIndex = index - 1;
                  final line = widget.lines[lineIndex];
                  return _SyncedNowPlayingLyricLine(
                    line: line,
                    isActive: lineIndex == activeIndex,
                    position: position,
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
    this.onShareRange,
    this.onTranslate,
  });

  final Track track;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onShareRange;
  final VoidCallback? onTranslate;

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
          if (onShareRange != null)
            IconButton(
              tooltip: 'Share selected lines',
              onPressed: onShareRange,
              icon: const Icon(Icons.format_line_spacing),
            ),
          if (onTranslate != null)
            IconButton(
              tooltip: 'Translate lyrics',
              onPressed: onTranslate,
              icon: const Icon(Icons.translate_outlined),
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

Future<void> _showLyricsTranslation(
  BuildContext context, {
  required LyricsTranslator translator,
  required String lyrics,
  required String targetLanguage,
}) async {
  final navigator = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 16),
          Expanded(child: Text('Translating lyrics...')),
        ],
      ),
    ),
  );

  try {
    final translated = await translator.translate(
      lyrics,
      targetLanguage: targetLanguage,
    );
    if (!context.mounted) {
      return;
    }
    navigator.pop();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _TranslatedLyricsSheet(
        lyrics: translated,
        targetLanguage: targetLanguage,
      ),
    );
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    navigator.pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not translate lyrics: $error')),
    );
  }
}

class _TranslatedLyricsSheet extends StatelessWidget {
  const _TranslatedLyricsSheet({
    required this.lyrics,
    required this.targetLanguage,
  });

  final String lyrics;
  final String targetLanguage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.translate_outlined),
              title: const Text('Translated lyrics'),
              subtitle: Text('Target language: $targetLanguage'),
              trailing: IconButton(
                tooltip: 'Copy translated lyrics',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: lyrics));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Translated lyrics copied.')),
                    );
                  }
                },
                icon: const Icon(Icons.content_copy_outlined),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(lyrics),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncedNowPlayingLyricLine extends StatelessWidget {
  const _SyncedNowPlayingLyricLine({
    required this.line,
    required this.isActive,
    required this.position,
  });

  final SyncedLyricLine line;
  final bool isActive;
  final Duration position;

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
              child: line.hasWordTiming
                  ? _KaraokeLyricText(
                      words: line.words,
                      activeWordIndex: syncedLyricWordIndexAt(
                        line.words,
                        position,
                      ),
                      activeStyle: textStyle?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                      inactiveStyle: textStyle,
                    )
                  : Text(line.text, style: textStyle),
            ),
          ],
        ),
      ),
    );
  }
}

class _KaraokeLyricText extends StatelessWidget {
  const _KaraokeLyricText({
    required this.words,
    required this.activeWordIndex,
    required this.activeStyle,
    required this.inactiveStyle,
  });

  final List<SyncedLyricWord> words;
  final int activeWordIndex;
  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: List<InlineSpan>.generate(words.length, (index) {
          final prefix = index == 0 ? '' : ' ';
          return TextSpan(
            text: '$prefix${words[index].text}',
            style: index == activeWordIndex ? activeStyle : inactiveStyle,
          );
        }),
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
    final savedQueues = player.savedQueues;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Queues'),
            subtitle: Text('${savedQueues.length} saved · ${player.activeQueueName} active'),
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
                  : () => unawaited(
                        player.switchSavedQueue(savedQueue.id),
                      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Use a unique queue name (up to 80 characters).')),
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
        if (context.mounted && !renamed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Use a unique queue name (up to 80 characters).')),
          );
        }
        return;
      case _SavedQueueAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete queue?'),
            content: Text('Delete ${player.activeQueueName} and its saved tracks?'),
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

enum _SavedQueueAction { rename, delete }

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
  static const ProviderHomeFeedCoordinator _providerHomeCoordinator =
      ProviderHomeFeedCoordinator();

  LibraryChartRange _chartRange = LibraryChartRange.thirtyDays;
  FollowingFeedSource _followingFeedSource = FollowingFeedSource.all;
  ProviderHomeFeed? _providerHomeFeed;
  String? _providerHomeSignature;
  bool _providerHomeLoading = false;
  final Set<String> _providerHomeLoadingMoreSections = <String>{};
  final Set<String> _providerHomeLoadMoreFailures = <String>{};
  int _providerHomeRequest = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final providerStore = context.watch<SelfHostedProviderStore>();
    final signature = _providerHomeStoreSignature(providerStore);
    if (_providerHomeSignature != null &&
        _providerHomeSignature != signature) {
      _providerHomeRequest += 1;
      _providerHomeFeed = null;
      _providerHomeLoading = false;
      _providerHomeLoadingMoreSections.clear();
      _providerHomeLoadMoreFailures.clear();
    }
    _providerHomeSignature = signature;
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final providerStore = context.watch<SelfHostedProviderStore>();
    final player = context.read<PlayerController>();

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = library.homeFeedSections();
    final followingTracks = library.followingFeedTracks(
      source: _followingFeedSource,
    );
    final charts = library.localCharts(range: _chartRange);
    final recommendationMatches = library.personalizedRecommendationMatches(
      limit: 6,
    );
    final recommendations = recommendationMatches
        .map((match) => match.track)
        .toList(growable: false);
    final recommendationReasons = <String, List<LibraryRecommendationReason>>{
      for (final match in recommendationMatches)
        match.track.id: match.reasons,
    };
    final moodMixes = library.localMoodMixes(limit: 5);
    final providerCatalogs = _providerHomeCatalogs(providerStore);
    if (sections.isEmpty && providerCatalogs.isEmpty) {
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
        if (providerCatalogs.isNotEmpty) ...<Widget>[
          _ProviderHomeDiscovery(
            providerCount: providerCatalogs.length,
            feed: _providerHomeFeed,
            loading: _providerHomeLoading,
            offline: library.offlineModeEnabled,
            onRefresh: _loadProviderHome,
            onLoadMore: _loadMoreProviderHome,
            loadingMoreSectionKeys: _providerHomeLoadingMoreSections,
            failedLoadMoreSectionKeys: _providerHomeLoadMoreFailures,
            onOpen: (provider, collection) => unawaited(
              _openProviderHomeCollection(provider, collection),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (sections.isEmpty)
          _EmptyHomeFeed(
            title: 'Your local feed is empty',
            message: 'Import music to add local recommendations and history.',
            onImport: widget.onImport,
            onImportFolder: widget.onImportFolder,
          ),
        ..._followingFeedWidgets(
          context: context,
          player: player,
          library: library,
          tracks: followingTracks,
        ),
        ..._homeTrackPreviewWidgets(
          context: context,
          player: player,
          library: library,
          icon: Icons.auto_awesome,
          title: 'Quick picks',
          subtitle: 'Personalized local recommendations',
          tracks: recommendations,
          detailTextForTrack: (track) => _recommendationReasonText(
            recommendationReasons[track.id] ??
                const <LibraryRecommendationReason>[],
          ),
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
            onOpen: () => unawaited(
              _showMoodMix(
                context,
                mix,
                onAddToPlaylist: widget.onAddToPlaylist,
                onLyrics: widget.onLyrics,
              ),
            ),
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
              onEditArtwork: track.sourceId == 'local'
                  ? () => unawaited(_editTrackArtwork(context, track))
                  : null,
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
    VoidCallback? onOpen,
    String? Function(Track track)? detailTextForTrack,
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('${tracks.length}'),
            if (onOpen != null) const Icon(Icons.chevron_right),
          ],
        ),
        onTap: onOpen,
      ),
      const SizedBox(height: 4),
      for (final track in tracks)
        TrackTile(
          track: track,
          detailText: detailTextForTrack?.call(track),
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
          onEditArtwork: track.sourceId == 'local'
              ? () => unawaited(_editTrackArtwork(context, track))
              : null,
          onRemove: () => library.removeTrack(track.id),
        ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _followingFeedWidgets({
    required BuildContext context,
    required PlayerController player,
    required LibraryStore library,
    required List<Track> tracks,
  }) {
    final hasFollowingContent = library
        .followingFeedTracks(limit: 1)
        .isNotEmpty;
    if (!hasFollowingContent) {
      return <Widget>[];
    }

    return <Widget>[
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.dynamic_feed_outlined),
        title: const Text('Following'),
        subtitle: const Text('Newest updates from artists and podcasts'),
        trailing: Text('${tracks.length}'),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final source in FollowingFeedSource.values)
            ChoiceChip(
              label: Text(_followingFeedSourceLabel(source)),
              selected: _followingFeedSource == source,
              onSelected: (_) {
                setState(() => _followingFeedSource = source);
              },
            ),
        ],
      ),
      const SizedBox(height: 4),
      if (tracks.isEmpty)
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.filter_alt_off_outlined),
          title: Text('No updates for this filter'),
        )
      else
        for (final track in tracks)
          TrackTile(
            track: track,
            detailText: _followingFeedTrackDetail(track),
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
            onEditArtwork: track.sourceId == 'local'
                ? () => unawaited(_editTrackArtwork(context, track))
                : null,
            onRemove: () => library.removeTrack(track.id),
          ),
      const SizedBox(height: 12),
    ];
  }

  Future<void> _loadProviderHome() async {
    final library = context.read<LibraryStore>();
    if (library.offlineModeEnabled || _providerHomeLoading) {
      return;
    }

    final providerStore = context.read<SelfHostedProviderStore>();
    final providers = _providerHomeCatalogs(providerStore);
    if (providers.isEmpty) {
      return;
    }

    final signature = _providerHomeStoreSignature(providerStore);
    final request = ++_providerHomeRequest;
    setState(() => _providerHomeLoading = true);
    final feed = await _providerHomeCoordinator.load(
      providers,
      followedArtists: library.followedArtists,
    );
    if (!mounted ||
        request != _providerHomeRequest ||
        signature != _providerHomeStoreSignature(
          context.read<SelfHostedProviderStore>(),
        )) {
      return;
    }

    setState(() {
      _providerHomeFeed = feed;
      _providerHomeLoading = false;
      _providerHomeLoadingMoreSections.clear();
      _providerHomeLoadMoreFailures.clear();
    });
  }

  Future<void> _loadMoreProviderHome(ProviderHomeSection section) async {
    final library = context.read<LibraryStore>();
    final sectionKey = _providerHomeSectionKey(section);
    if (library.offlineModeEnabled ||
        !section.hasMore ||
        _providerHomeLoading ||
        _providerHomeLoadingMoreSections.contains(sectionKey)) {
      return;
    }

    final providerStore = context.read<SelfHostedProviderStore>();
    final signature = _providerHomeStoreSignature(providerStore);
    final request = _providerHomeRequest;
    setState(() {
      _providerHomeLoadingMoreSections.add(sectionKey);
      _providerHomeLoadMoreFailures.remove(sectionKey);
    });
    final continuation = await _providerHomeCoordinator.loadMore(section);
    if (!mounted ||
        request != _providerHomeRequest ||
        signature != _providerHomeStoreSignature(
          context.read<SelfHostedProviderStore>(),
        )) {
      return;
    }

    setState(() {
      _providerHomeLoadingMoreSections.remove(sectionKey);
      final updated = continuation.section;
      if (updated == null) {
        _providerHomeLoadMoreFailures.add(sectionKey);
        return;
      }
      _providerHomeLoadMoreFailures.remove(sectionKey);
      final feed = _providerHomeFeed;
      if (feed == null) {
        return;
      }
      _providerHomeFeed = ProviderHomeFeed(
        sections: feed.sections
            .map(
              (candidate) => _providerHomeSectionKey(candidate) == sectionKey
                  ? updated
                  : candidate,
            )
            .toList(growable: false),
        errors: feed.errors,
      );
    });
  }

  Future<void> _openProviderHomeCollection(
    MusicCatalogProvider provider,
    MusicCatalogCollection collection,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelfHostedCollectionScreen(
          provider: provider,
          collection: collection,
        ),
      ),
    );
  }
}

List<MusicCatalogProvider> _providerHomeCatalogs(
  SelfHostedProviderStore store,
) {
  final providers = <MusicCatalogProvider>[];
  for (final account in store.accounts) {
    final provider = store.catalogProviderFor(account.id);
    if (provider != null) {
      providers.add(provider);
    }
  }
  return providers;
}

String _providerHomeSectionKey(ProviderHomeSection section) {
  return '${section.provider.id}:${section.kind.name}:'
      '${section.discoveryKind?.name ?? ''}:${section.sectionId}';
}

String _providerHomeStoreSignature(SelfHostedProviderStore store) {
  final accounts = store.accounts.map(
    (account) => <Object?>[
      account.id,
      account.kind.name,
      account.name,
      account.baseUri.toString(),
      account.identity,
      account.allowInsecureHttp,
      store.hasCredential(account.id),
    ].join(':'),
  );
  return '${store.artworkRevision}|${accounts.join('|')}';
}

class _ProviderHomeDiscovery extends StatelessWidget {
  const _ProviderHomeDiscovery({
    required this.providerCount,
    required this.feed,
    required this.loading,
    required this.offline,
    required this.onRefresh,
    required this.onLoadMore,
    required this.loadingMoreSectionKeys,
    required this.failedLoadMoreSectionKeys,
    required this.onOpen,
  });

  final int providerCount;
  final ProviderHomeFeed? feed;
  final bool loading;
  final bool offline;
  final VoidCallback onRefresh;
  final ValueChanged<ProviderHomeSection> onLoadMore;
  final Set<String> loadingMoreSectionKeys;
  final Set<String> failedLoadMoreSectionKeys;
  final void Function(
    MusicCatalogProvider provider,
    MusicCatalogCollection collection,
  ) onOpen;

  @override
  Widget build(BuildContext context) {
    final loadedSections = feed?.sections.length ?? 0;
    final subtitle = offline
        ? 'Offline mode'
        : loadedSections > 0
            ? '$loadedSections server section(s) loaded'
            : '$providerCount configured server(s)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          key: const ValueKey<String>('provider-home-header'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('From your servers'),
          subtitle: Text(subtitle),
          trailing: loading
              ? const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  key: const ValueKey<String>('provider-home-refresh'),
                  tooltip: offline
                      ? 'Server discovery unavailable offline'
                      : 'Refresh server discovery',
                  onPressed: offline ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
        ),
        if (feed != null && !feed!.hasContent && feed!.errors.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.inbox_outlined),
            title: Text('No server albums or playlists found'),
          ),
        if ((feed?.errors.length ?? 0) > 0)
          ListTile(
            key: const ValueKey<String>('provider-home-errors'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(
              '${feed!.errors.length} server section(s) unavailable',
            ),
            subtitle: feed!.hasContent
                ? const Text('Available server results are shown below.')
                : const Text('Refresh to retry the configured servers.'),
          ),
        for (final section in feed?.sections ?? const <ProviderHomeSection>[])
          _ProviderHomeSectionShelf(
            section: section,
            onOpen: (collection) => onOpen(section.provider, collection),
            onLoadMore: offline ? null : () => onLoadMore(section),
            loadingMore: loadingMoreSectionKeys.contains(
              _providerHomeSectionKey(section),
            ),
            loadMoreFailed: failedLoadMoreSectionKeys.contains(
              _providerHomeSectionKey(section),
            ),
          ),
      ],
    );
  }
}

class _ProviderHomeSectionShelf extends StatelessWidget {
  const _ProviderHomeSectionShelf({
    required this.section,
    required this.onOpen,
    required this.onLoadMore,
    required this.loadingMore,
    required this.loadMoreFailed,
  });

  final ProviderHomeSection section;
  final ValueChanged<MusicCatalogCollection> onOpen;
  final VoidCallback? onLoadMore;
  final bool loadingMore;
  final bool loadMoreFailed;

  @override
  Widget build(BuildContext context) {
    final discoveryKind = section.discoveryKind;
    final sectionLabel = section.titleOverride ??
        (discoveryKind == null
            ? _providerHomeKindLabel(section.kind)
            : _providerHomeDiscoveryLabel(discoveryKind));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            section.isFollowedArtistShelf
                ? Icons.favorite_outline
                : discoveryKind == null
                    ? _providerHomeKindIcon(section.kind)
                    : _providerHomeDiscoveryIcon(discoveryKind),
          ),
          title: Text('${section.provider.name} $sectionLabel'),
          subtitle: Text(
            section.subtitleOverride ??
                (discoveryKind == null
                    ? 'Configured self-hosted catalog'
                    : _providerHomeDiscoverySubtitle(discoveryKind)),
          ),
          trailing: Text('${section.collections.length}'),
        ),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: section.collections.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final collection = section.collections[index];
              return _ProviderHomeCollectionTile(
                provider: section.provider,
                collection: collection,
                onTap: () => onOpen(collection),
              );
            },
          ),
        ),
        if (section.hasMore)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              key: ValueKey<String>(
                'provider-home-load-more-${section.provider.id}-'
                '${discoveryKind?.name ?? section.kind.name}'
                '${section.sectionId.isEmpty ? '' : '-${section.sectionId}'}',
              ),
              onPressed: loadingMore ? null : onLoadMore,
              icon: loadingMore
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: Text(loadingMore ? 'Loading more' : 'Load more'),
            ),
          ),
        if (loadMoreFailed)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Unable to load more. Try again.'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ProviderHomeCollectionTile extends StatelessWidget {
  const _ProviderHomeCollectionTile({
    required this.provider,
    required this.collection,
    required this.onTap,
  });

  final MusicCatalogProvider provider;
  final MusicCatalogCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final artworkId = collection.artworkId;
    final subtitle = collection.subtitle.trim().isNotEmpty
        ? collection.subtitle.trim()
        : collection.itemCount > 0
            ? '${collection.itemCount} item(s)'
            : _providerHomeKindSingularLabel(collection.kind);

    return SizedBox(
      width: 148,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          key: ValueKey<String>(
            'provider-home-collection-${provider.id}-'
            '${collection.kind.name}-${collection.id}',
          ),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TrackArtwork(
                  artworkUri: null,
                  providerId: provider.id,
                  providerArtworkId: artworkId,
                  providerArtworkVersion: collection.artworkVersion,
                  loadProviderArtwork: artworkId == null
                      ? null
                      : (maxWidth) => provider.loadArtwork(
                            artworkId,
                            version: collection.artworkVersion,
                            maxWidth: maxWidth,
                          ),
                  size: 130,
                  borderRadius: 4,
                  fallbackIcon: _providerHomeKindIcon(collection.kind),
                ),
                const SizedBox(height: 8),
                Text(
                  collection.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _providerHomeKindLabel(MusicCatalogCollectionKind kind) {
  return switch (kind) {
    MusicCatalogCollectionKind.artist => 'artists',
    MusicCatalogCollectionKind.album => 'albums',
    MusicCatalogCollectionKind.playlist => 'playlists',
  };
}

String _providerHomeKindSingularLabel(MusicCatalogCollectionKind kind) {
  return switch (kind) {
    MusicCatalogCollectionKind.artist => 'Artist',
    MusicCatalogCollectionKind.album => 'Album',
    MusicCatalogCollectionKind.playlist => 'Playlist',
  };
}

IconData _providerHomeKindIcon(MusicCatalogCollectionKind kind) {
  return switch (kind) {
    MusicCatalogCollectionKind.artist => Icons.people_outline,
    MusicCatalogCollectionKind.album => Icons.album_outlined,
    MusicCatalogCollectionKind.playlist => Icons.queue_music_outlined,
  };
}

String _providerHomeDiscoveryLabel(MusicCatalogDiscoveryKind kind) {
  return switch (kind) {
    MusicCatalogDiscoveryKind.recentlyAdded => 'recently added',
    MusicCatalogDiscoveryKind.frequentlyPlayed => 'frequently played',
    MusicCatalogDiscoveryKind.recentlyPlayed => 'recently played',
    MusicCatalogDiscoveryKind.random => 'random albums',
  };
}

String _providerHomeDiscoverySubtitle(MusicCatalogDiscoveryKind kind) {
  return switch (kind) {
    MusicCatalogDiscoveryKind.recentlyAdded =>
      'Newest albums reported by this server',
    MusicCatalogDiscoveryKind.frequentlyPlayed =>
      'Most-played albums reported by this server',
    MusicCatalogDiscoveryKind.recentlyPlayed =>
      'Recently played albums reported by this server',
    MusicCatalogDiscoveryKind.random =>
      'Random albums selected by this server',
  };
}

IconData _providerHomeDiscoveryIcon(MusicCatalogDiscoveryKind kind) {
  return switch (kind) {
    MusicCatalogDiscoveryKind.recentlyAdded => Icons.new_releases_outlined,
    MusicCatalogDiscoveryKind.frequentlyPlayed => Icons.trending_up,
    MusicCatalogDiscoveryKind.recentlyPlayed => Icons.history_outlined,
    MusicCatalogDiscoveryKind.random => Icons.shuffle,
  };
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
    this.title = 'Home is empty',
    this.message = 'Import music to build your local feed.',
  });

  final VoidCallback onImport;
  final VoidCallback onImportFolder;
  final String title;
  final String message;

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
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
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
    case LibraryHomeSectionType.followedArtists:
      return Icons.people_outline;
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
    case LibraryHomeSectionType.followedArtists:
      return 'From artists you follow';
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
    case LibraryHomeSectionType.followedArtists:
      return 'Newest local additions by followed artists';
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

String _followingFeedSourceLabel(FollowingFeedSource source) {
  return switch (source) {
    FollowingFeedSource.all => 'All',
    FollowingFeedSource.artists => 'Artists',
    FollowingFeedSource.podcasts => 'Podcasts',
  };
}

String _followingFeedTrackDetail(Track track) {
  return track.sourceId.startsWith('podcast-')
      ? 'Podcast subscription'
      : 'Followed artist';
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
                  onEditArtwork: track.sourceId == 'local'
                      ? () => unawaited(_editTrackArtwork(context, track))
                      : null,
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

Future<void> _showMoodMix(
  BuildContext context,
  LibraryMoodMix mix, {
  required ValueChanged<Track> onAddToPlaylist,
  required ValueChanged<Track> onLyrics,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) {
      return _MoodMixSheet(
        mix: mix,
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
  if (type == LibraryBrowseType.artist || type == LibraryBrowseType.album) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _LibraryCollectionDetailScreen(
          type: type,
          group: group,
          onAddToPlaylist: onAddToPlaylist,
          onLyrics: onLyrics,
        ),
      ),
    );
    return;
  }

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

class _MoodMixSheet extends StatelessWidget {
  const _MoodMixSheet({
    required this.mix,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final LibraryMoodMix mix;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final player = context.read<PlayerController>();
    final tracks = library.tracksForMoodMix(mix.type);

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
                  leading: Icon(_moodMixIcon(mix.type)),
                  title: Text(mix.name),
                  subtitle: Text(
                    '${mix.description} · ${tracks.length} generated track(s)',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: 'Play mix',
                        onPressed: tracks.isEmpty
                            ? null
                            : () => unawaited(
                                  _playTrackWithResume(
                                    context,
                                    player,
                                    library,
                                    tracks.first,
                                    queue: tracks,
                                  ),
                                ),
                        icon: const Icon(Icons.play_arrow),
                      ),
                      IconButton(
                        tooltip: 'Save mix as playlist',
                        onPressed: tracks.isEmpty
                            ? null
                            : () => unawaited(
                                  _saveMoodMix(context, library),
                                ),
                        icon: const Icon(Icons.playlist_add),
                      ),
                    ],
                  ),
                );
              }

              if (tracks.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.music_off_outlined),
                  title: Text('No matching local tracks'),
                  subtitle: Text(
                    'Import or edit track metadata to rebuild this mix.',
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
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _saveMoodMix(
    BuildContext context,
    LibraryStore library,
  ) async {
    final playlist = await library.saveMoodMixAsPlaylist(mix.type);
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          playlist == null
              ? '${mix.name} has no playable tracks.'
              : 'Saved ${playlist.trackIds.length} tracks as ${playlist.name}.',
        ),
      ),
    );
  }
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
                key: ValueKey<String>('browse-${type.name}-${group.key}'),
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
                final canFollowArtist =
                    type == LibraryBrowseType.artist &&
                    library.canFollowArtist(group.label);
                final isFollowed = library.isArtistFollowed(group.label);
                return ListTile(
                  leading: Icon(_libraryBrowseTypeIcon(type)),
                  title: Text(group.label),
                  subtitle: Text(_libraryBrowseGroupSubtitle(group)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (canFollowArtist)
                        IconButton(
                          tooltip: isFollowed
                              ? 'Unfollow artist'
                              : 'Follow artist',
                          onPressed: () => unawaited(
                            library.setArtistFollowed(
                              group.label,
                              !isFollowed,
                            ),
                          ),
                          icon: Icon(
                            isFollowed
                                ? Icons.person_remove_outlined
                                : Icons.person_add_alt_1_outlined,
                          ),
                        ),
                      IconButton(
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
                      if (type == LibraryBrowseType.album)
                        IconButton(
                          tooltip: 'Save album share card',
                          onPressed: tracks.isEmpty
                              ? null
                              : () => unawaited(
                                  _showAlbumShareCard(context, group, tracks),
                                ),
                          icon: const Icon(Icons.image_outlined),
                        ),
                    ],
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
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _LibraryCollectionDetailScreen extends StatelessWidget {
  const _LibraryCollectionDetailScreen({
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
    final playableTracks = tracks
        .where((track) => track.isPlayable)
        .toList(growable: false);
    final representative = _collectionRepresentativeTrack(tracks);
    final artistNames = _collectionMetadataValues(
      tracks.map((track) => track.artist),
    );
    final genreNames = _collectionMetadataValues(
      tracks.map((track) => track.genre),
    );
    final artistAlbums = type == LibraryBrowseType.artist
        ? library.albumGroupsForArtist(group.key)
        : const <LibraryBrowseGroup>[];
    final related = library.relatedBrowseGroups(type, group.key);
    final albumArtistGroup = type == LibraryBrowseType.album
        ? _singleAlbumArtistGroup(library, artistNames)
        : null;
    final isFollowed = library.isArtistFollowed(group.label);
    final canFollowArtist =
        type == LibraryBrowseType.artist &&
        library.canFollowArtist(group.label);
    final kind = type == LibraryBrowseType.artist ? 'Artist' : 'Album';
    final metadata = type == LibraryBrowseType.artist
        ? (genreNames.isEmpty ? 'Local artist' : genreNames.take(3).join(' · '))
        : _albumArtistLabel(artistNames);
    final totalDuration = tracks.fold<Duration>(
      Duration.zero,
      (total, track) => total + track.duration,
    );
    final favoriteCount = tracks.where((track) => track.isFavorite).length;
    final playCount = tracks.fold<int>(
      0,
      (total, track) => total + library.playCountForTrack(track.id),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(group.label),
        actions: <Widget>[
          if (canFollowArtist)
            IconButton(
              tooltip: isFollowed ? 'Unfollow artist' : 'Follow artist',
              onPressed: () => unawaited(
                library.setArtistFollowed(group.label, !isFollowed),
              ),
              icon: Icon(
                isFollowed
                    ? Icons.person_remove_outlined
                    : Icons.person_add_alt_1_outlined,
              ),
            ),
          IconButton(
            tooltip: 'Copy share text',
            onPressed: tracks.isEmpty
                ? null
                : () => unawaited(
                      _copyBrowseGroupShareText(
                        context,
                        library,
                        type,
                        group,
                      ),
                    ),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Save ${kind.toLowerCase()} share card',
            onPressed: tracks.isEmpty
                ? null
                : () => unawaited(
                      _showBrowseGroupShareCard(context, type, group, tracks),
                    ),
            icon: const Icon(Icons.image_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          _LibraryCollectionDetailHeader(
            kind: kind,
            title: group.label,
            metadata: metadata,
            stats: _collectionStatsLabel(
              trackCount: tracks.length,
              favoriteCount: favoriteCount,
              playCount: playCount,
              totalDuration: totalDuration,
            ),
            representative: representative,
            onPlay: playableTracks.isEmpty
                ? null
                : () => unawaited(
                      _playLibraryCollection(
                        context,
                        player,
                        library,
                        playableTracks,
                        shuffle: false,
                      ),
                    ),
            onShuffle: playableTracks.isEmpty
                ? null
                : () => unawaited(
                      _playLibraryCollection(
                        context,
                        player,
                        library,
                        playableTracks,
                        shuffle: true,
                      ),
                    ),
            onRadio: playableTracks.isEmpty
                ? null
                : () => unawaited(
                      _startBrowseGroupRadio(
                        context,
                        player,
                        library,
                        type,
                        group,
                      ),
                    ),
            onSavePlaylist: tracks.isEmpty
                ? null
                : () => unawaited(_saveLibraryCollection(context, library)),
          ),
          if (albumArtistGroup != null) ...<Widget>[
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey<String>('view-album-artist'),
                onPressed: () => unawaited(
                  _showLibraryBrowseTracks(
                    context,
                    type: LibraryBrowseType.artist,
                    group: albumArtistGroup,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                icon: const Icon(Icons.person_outline),
                label: Text('View ${albumArtistGroup.label}'),
              ),
            ),
          ],
          if (artistAlbums.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            _LibraryCollectionSectionHeader(
              title: 'Albums',
              subtitle: '${artistAlbums.length} local album(s)',
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 174,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: artistAlbums.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final album = artistAlbums[index];
                  final albumTracks = library.tracksForBrowseGroup(
                    LibraryBrowseType.album,
                    album.key,
                  );
                  return _LibraryAlbumTile(
                    group: album,
                    representative: _collectionRepresentativeTrack(albumTracks),
                    onTap: () => unawaited(
                      _showLibraryBrowseTracks(
                        context,
                        type: LibraryBrowseType.album,
                        group: album,
                        onAddToPlaylist: onAddToPlaylist,
                        onLyrics: onLyrics,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 20),
          _LibraryCollectionSectionHeader(
            title: type == LibraryBrowseType.artist ? 'Tracks' : 'Track list',
            subtitle: '${tracks.length} in this ${kind.toLowerCase()}',
          ),
          const SizedBox(height: 6),
          if (tracks.isEmpty)
            const ListTile(
              leading: Icon(Icons.music_off_outlined),
              title: Text('No tracks remain in this collection'),
            )
          else
            for (var index = 0; index < tracks.length; index += 1) ...<Widget>[
              if (index > 0) const Divider(height: 1),
              _collectionTrackTile(
                context,
                library,
                player,
                tracks[index],
                tracks,
              ),
            ],
          if (related.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            _LibraryCollectionSectionHeader(
              title: type == LibraryBrowseType.artist
                  ? 'Related artists'
                  : 'Related albums',
              subtitle: 'Matched from local library metadata',
            ),
            const SizedBox(height: 6),
            for (final match in related)
              ListTile(
                key: ValueKey<String>(
                  'related-${type.name}-${match.group.key}',
                ),
                leading: Icon(_libraryBrowseTypeIcon(type)),
                title: Text(match.group.label),
                subtitle: Text(
                  '${_collectionSimilarityLabel(match.reasons)} · '
                  '${_libraryBrowseGroupSubtitle(match.group)}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => unawaited(
                  _showLibraryBrowseTracks(
                    context,
                    type: type,
                    group: match.group,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _collectionTrackTile(
    BuildContext context,
    LibraryStore library,
    PlayerController player,
    Track track,
    List<Track> tracks,
  ) {
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
      onEditArtwork: track.sourceId == 'local'
          ? () => unawaited(_editTrackArtwork(context, track))
          : null,
      onRemove: () => library.removeTrack(track.id),
    );
  }

  LibraryBrowseGroup? _singleAlbumArtistGroup(
    LibraryStore library,
    List<String> artistNames,
  ) {
    if (artistNames.length != 1) {
      return null;
    }

    final key = artistNames.single.toLowerCase();
    for (final group in library.browseGroups(LibraryBrowseType.artist)) {
      if (group.key == key) {
        return group;
      }
    }
    return null;
  }

  Future<void> _saveLibraryCollection(
    BuildContext context,
    LibraryStore library,
  ) async {
    final playlist = await library.saveBrowseGroupAsPlaylist(type, group.key);
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          playlist == null
              ? '${group.label} has no tracks to save.'
              : 'Saved ${playlist.trackIds.length} tracks as ${playlist.name}.',
        ),
      ),
    );
  }
}

class _LibraryCollectionDetailHeader extends StatelessWidget {
  const _LibraryCollectionDetailHeader({
    required this.kind,
    required this.title,
    required this.metadata,
    required this.stats,
    required this.representative,
    required this.onPlay,
    required this.onShuffle,
    required this.onRadio,
    required this.onSavePlaylist,
  });

  final String kind;
  final String title;
  final String metadata;
  final String stats;
  final Track? representative;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback? onRadio;
  final VoidCallback? onSavePlaylist;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final artworkSize = wide ? 176.0 : 112.0;
        final track = representative;
        final artwork = TrackArtwork(
          artworkUri: track?.artworkUri,
          providerId: track?.sourceId,
          providerArtworkId: track?.providerArtworkId,
          providerArtworkVersion: track?.providerArtworkVersion,
          size: artworkSize,
          borderRadius: 8,
          fallbackIcon: kind == 'Artist'
              ? Icons.person_outline
              : Icons.album_outlined,
        );
        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              kind,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              metadata,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              stats,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onPlay,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
            OutlinedButton.icon(
              onPressed: onShuffle,
              icon: const Icon(Icons.shuffle),
              label: const Text('Shuffle'),
            ),
            OutlinedButton.icon(
              onPressed: onRadio,
              icon: const Icon(Icons.radio),
              label: const Text('Radio'),
            ),
            OutlinedButton.icon(
              onPressed: onSavePlaylist,
              icon: const Icon(Icons.playlist_add),
              label: const Text('Save playlist'),
            ),
          ],
        );

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              artwork,
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    titleBlock,
                    const SizedBox(height: 18),
                    actions,
                  ],
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                artwork,
                const SizedBox(width: 14),
                Expanded(child: titleBlock),
              ],
            ),
            const SizedBox(height: 14),
            actions,
          ],
        );
      },
    );
  }
}

class _LibraryCollectionSectionHeader extends StatelessWidget {
  const _LibraryCollectionSectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _LibraryAlbumTile extends StatelessWidget {
  const _LibraryAlbumTile({
    required this.group,
    required this.representative,
    required this.onTap,
  });

  final LibraryBrowseGroup group;
  final Track? representative;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track = representative;
    return SizedBox(
      key: ValueKey<String>('artist-album-${group.key}'),
      width: 124,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TrackArtwork(
              artworkUri: track?.artworkUri,
              providerId: track?.sourceId,
              providerArtworkId: track?.providerArtworkId,
              providerArtworkVersion: track?.providerArtworkVersion,
              size: 124,
              borderRadius: 8,
              fallbackIcon: Icons.album_outlined,
            ),
            const SizedBox(height: 6),
            Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              '${group.trackCount} track(s)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
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
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
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
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
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

String _recommendationReasonText(
  List<LibraryRecommendationReason> reasons,
) {
  if (reasons.isEmpty) {
    return 'Selected from your local library';
  }

  final labels = reasons
      .map(_recommendationReasonLabel)
      .toList(growable: false);
  return 'Because of ${labels.join(', ')}';
}

String _recommendationReasonLabel(LibraryRecommendationReason reason) {
  switch (reason) {
    case LibraryRecommendationReason.favoriteArtist:
      return 'a favorite artist';
    case LibraryRecommendationReason.favoriteAlbum:
      return 'a favorite album';
    case LibraryRecommendationReason.favoriteGenre:
      return 'a favorite genre';
    case LibraryRecommendationReason.recentlyPlayedArtist:
      return 'an artist you played';
    case LibraryRecommendationReason.recentlyPlayedAlbum:
      return 'an album you played';
    case LibraryRecommendationReason.recentlyPlayedGenre:
      return 'a genre you played';
    case LibraryRecommendationReason.favoriteTrack:
      return 'this favorite';
    case LibraryRecommendationReason.unplayed:
      return 'an unplayed track';
    case LibraryRecommendationReason.recentlyAdded:
      return 'a recent addition';
  }
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

Track? _collectionRepresentativeTrack(List<Track> tracks) {
  for (final track in tracks) {
    if (track.artworkUri != null ||
        (track.providerArtworkId?.trim().isNotEmpty ?? false)) {
      return track;
    }
  }
  return tracks.isEmpty ? null : tracks.first;
}

List<String> _collectionMetadataValues(Iterable<String> rawValues) {
  final valuesByKey = <String, String>{};
  for (final rawValue in rawValues) {
    final value = rawValue.trim();
    final key = value.toLowerCase();
    if (key.isEmpty || key == 'unknown' || key.startsWith('unknown ')) {
      continue;
    }
    valuesByKey.putIfAbsent(key, () => value);
  }

  final values = valuesByKey.values.toList(growable: false);
  values.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return values;
}

String _albumArtistLabel(List<String> artistNames) {
  if (artistNames.isEmpty) {
    return 'Unknown artist';
  }
  if (artistNames.length == 1) {
    return artistNames.single;
  }
  return '${artistNames.length} artists';
}

String _collectionStatsLabel({
  required int trackCount,
  required int favoriteCount,
  required int playCount,
  required Duration totalDuration,
}) {
  final parts = <String>['$trackCount track(s)'];
  if (totalDuration > Duration.zero) {
    parts.add(_formatBrowseDuration(totalDuration));
  }
  if (favoriteCount > 0) {
    parts.add('$favoriteCount favorite(s)');
  }
  if (playCount > 0) {
    parts.add('$playCount play(s)');
  }
  return parts.join(' · ');
}

String _collectionSimilarityLabel(
  List<LibraryCollectionSimilarityReason> reasons,
) {
  final labels = reasons
      .map((reason) {
        switch (reason) {
          case LibraryCollectionSimilarityReason.artist:
            return 'artist';
          case LibraryCollectionSimilarityReason.album:
            return 'album';
          case LibraryCollectionSimilarityReason.genre:
            return 'genre';
        }
      })
      .toList(growable: false);
  return 'Shared ${labels.join(', ')}';
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
  return _isLocalMp3(track) ||
      _isLocalFlac(track) ||
      _isLocalM4a(track) ||
      _isLocalOggOrOpus(track) ||
      _isLocalWav(track);
}

bool _isLocalMp3(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.mp3');
}

bool _isLocalFlac(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.flac');
}

bool _isLocalM4a(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.m4a');
}

bool _isLocalOggOrOpus(Track track) {
  final path = (track.localPath?.trim() ?? '').toLowerCase();
  return path.endsWith('.ogg') || path.endsWith('.oga') || path.endsWith('.opus');
}

bool _isLocalWav(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.wav');
}

Future<bool?> _confirmEmbeddedTagWrite(BuildContext context, Track track) {
  final format = _isLocalMp3(track)
      ? 'MP3'
      : _isLocalFlac(track)
      ? 'FLAC'
      : _isLocalM4a(track)
      ? 'M4A'
      : _isLocalOggOrOpus(track)
      ? 'Ogg/Opus'
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
            : format == 'M4A'
            ? 'This writes title, artist, album, and genre to standard M4A metadata atoms while preserving artwork and other metadata items. Standard front-loaded M4A files repair validated chunk offsets; malformed or fragmented layouts are left unchanged.'
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

String _customSmartPlaylistMatchModeLabel(
  CustomSmartPlaylistMatchMode matchMode,
) {
  return switch (matchMode) {
    CustomSmartPlaylistMatchMode.all => 'Match all',
    CustomSmartPlaylistMatchMode.any => 'Match any',
  };
}

String _customSmartPlaylistRuleFieldLabel(
  CustomSmartPlaylistRuleField field,
) {
  return switch (field) {
    CustomSmartPlaylistRuleField.searchText => 'Search text',
    CustomSmartPlaylistRuleField.sourceId => 'Exact source ID',
    CustomSmartPlaylistRuleField.artist => 'Exact artist',
    CustomSmartPlaylistRuleField.album => 'Exact album',
    CustomSmartPlaylistRuleField.genre => 'Exact genre',
    CustomSmartPlaylistRuleField.minimumDurationSeconds =>
      'Minimum duration',
    CustomSmartPlaylistRuleField.maximumDurationSeconds =>
      'Maximum duration',
    CustomSmartPlaylistRuleField.favoritesOnly => 'Favorites only',
    CustomSmartPlaylistRuleField.minimumPlayCount => 'Minimum plays',
    CustomSmartPlaylistRuleField.minimumDaysSinceLastPlayed =>
      'Not played in at least (days)',
  };
}

String _customSmartPlaylistRuleSummary(CustomSmartPlaylistRule rule) {
  if (rule.field == CustomSmartPlaylistRuleField.favoritesOnly) {
    return _customSmartPlaylistRuleFieldLabel(rule.field);
  }
  return '${_customSmartPlaylistRuleFieldLabel(rule.field)}: ${rule.value}';
}

String _customSmartPlaylistRuleGroupSummary(
  CustomSmartPlaylistRuleGroup group,
) {
  final parts = <String>[_customSmartPlaylistMatchModeLabel(group.matchMode)];
  parts.addAll(group.rules.take(2).map(_customSmartPlaylistRuleSummary));
  if (group.rules.length > 2) {
    parts.add('+${group.rules.length - 2} rules');
  }
  if (group.groups.isNotEmpty) {
    parts.add('${group.groups.length} nested group(s)');
  }
  return parts.join(' - ');
}

String _customSmartPlaylistSubtitle(
  CustomSmartPlaylist rule,
  int trackCount,
) {
  final parts = <String>['$trackCount track(s)'];
  parts.add(_customSmartPlaylistMatchModeLabel(rule.matchMode));
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
  if (rule.ruleGroups.isNotEmpty) {
    parts.add('${rule.ruleGroups.length} nested group(s)');
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
    required this.matchMode,
    required this.ruleGroups,
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
  final CustomSmartPlaylistMatchMode matchMode;
  final List<CustomSmartPlaylistRuleGroup> ruleGroups;
  final CustomSmartPlaylistSortMode sortMode;
  final int limit;
}

class _TextEditingControllerOwner extends StatefulWidget {
  const _TextEditingControllerOwner({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_TextEditingControllerOwner> createState() =>
      _TextEditingControllerOwnerState();
}

class _TextEditingControllerOwnerState
    extends State<_TextEditingControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
              key: const Key('smart-playlist-create'),
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
              tracks: library.tracksForCustomSmartPlaylist(rule.id),
              onOpen: () => _showCustomSmartPlaylist(context, rule.id),
              onEdit: () => _editCustomSmartPlaylist(context, rule),
              onArtwork: () => _editCustomSmartPlaylistArtwork(context, rule),
              onCopyImportLink: () => unawaited(
                _copyCustomSmartPlaylistImportLink(context, library, rule),
              ),
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
              onCopyImportLink: () => unawaited(
                _copyPlaylistImportLink(context, library, playlist),
              ),
              onShareCard: () => unawaited(
                _showPlaylistShareCard(context, playlist),
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
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Paste AetherTune playlist link'),
                subtitle: const Text('Import a portable playlist shared from AetherTune.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importPlaylistLink(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.filter_alt_outlined),
                title: const Text('Paste AetherTune smart playlist link'),
                subtitle: const Text('Import portable smart-playlist rules from AetherTune.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importCustomSmartPlaylistLink(context);
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

  Future<void> _importPlaylistLink(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final link = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import AetherTune playlist link'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(labelText: 'Playlist link'),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (!context.mounted || link == null) {
        return;
      }
      final playlist = await context.read<LibraryStore>().importPlaylistLink(link);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${playlist.name}.')),
        );
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _importCustomSmartPlaylistLink(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final link = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import AetherTune smart playlist link'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(labelText: 'Smart playlist link'),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (!context.mounted || link == null) {
        return;
      }
      final playlist = await context
          .read<LibraryStore>()
          .importCustomSmartPlaylistLink(link);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${playlist.name}.')),
        );
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      controller.dispose();
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
      matchMode: draft.matchMode,
      ruleGroups: draft.ruleGroups,
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
      matchMode: draft.matchMode,
      ruleGroups: draft.ruleGroups,
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
    await _playlistArtworkFileStore.delete(rule.artworkUri);

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
                  leading: const Icon(Icons.crop_outlined),
                  title: const Text('Crop and position'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _editPlaylistArtworkCrop(context, playlist);
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

  Future<void> _editPlaylistArtworkCrop(
    BuildContext context,
    Playlist playlist,
  ) async {
    final artworkUri = playlist.artworkUri;
    if (artworkUri == null) {
      return;
    }
    final crop = await showArtworkCropEditor(
      context,
      artworkUri: artworkUri,
      initialCrop: playlist.artworkCrop,
    );
    if (!context.mounted || crop == null) {
      return;
    }
    final updated = await context
        .read<LibraryStore>()
        .updatePlaylistArtworkCrop(playlist.id, crop);
    if (!context.mounted || updated == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated artwork crop for ${updated.name}.')),
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

  Future<void> _editCustomSmartPlaylistArtwork(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose image file'),
              subtitle: const Text('Store a private PNG, JPEG, GIF, or WebP image.'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickCustomSmartPlaylistArtworkFile(context, rule);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Set image URL'),
              subtitle: const Text('Use an http or https image URL.'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _setCustomSmartPlaylistArtworkUrl(context, rule);
              },
            ),
            if (rule.artworkUri != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove artwork'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _removeCustomSmartPlaylistArtwork(context, rule);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomSmartPlaylistArtworkFile(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await FilePicker.pickFile(
      type: FileType.image,
      dialogTitle: 'Choose smart playlist artwork',
    );
    if (!context.mounted || file == null) {
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      if (!context.mounted) {
        return;
      }
      final artworkUri = await _playlistArtworkFileStore.save(bytes);
      if (!context.mounted) {
        return;
      }
      final updated = await context
          .read<LibraryStore>()
          .updateCustomSmartPlaylistArtwork(rule.id, artworkUri);
      if (!context.mounted || updated == null) {
        return;
      }
      await _playlistArtworkFileStore.delete(rule.artworkUri);
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Updated artwork for ${updated.name}.')),
        );
      }
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

  Future<void> _setCustomSmartPlaylistArtworkUrl(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final initialValue = rule.artworkUri != null &&
            _isNetworkImageUri(rule.artworkUri!)
        ? rule.artworkUri!.toString()
        : '';
    final value = await _promptForPlaylistArtwork(context, initialValue);
    if (!context.mounted || value == null) {
      return;
    }
    final artworkUri = Uri.tryParse(value.trim());
    if (artworkUri == null || !_isNetworkImageUri(artworkUri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter an http or https image URL.')),
      );
      return;
    }
    final updated = await context
        .read<LibraryStore>()
        .updateCustomSmartPlaylistArtwork(rule.id, artworkUri);
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(rule.artworkUri);
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Updated artwork for ${updated.name}.')),
      );
    }
  }

  Future<void> _removeCustomSmartPlaylistArtwork(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final updated = await context
        .read<LibraryStore>()
        .updateCustomSmartPlaylistArtwork(rule.id, null);
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(rule.artworkUri);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed artwork for ${updated.name}.')),
      );
    }
  }

  Future<void> _showPlaylistShareCard(
    BuildContext context,
    Playlist playlist,
  ) async {
    final tracks = context.read<LibraryStore>().tracksForPlaylist(playlist.id);
    await _showCollectionShareCard(
      context,
      kind: 'playlist',
      title: playlist.name,
      subtitle: playlist.folder.trim().isEmpty
          ? 'Your playlist'
          : playlist.folder.trim(),
      itemCount: tracks.length,
      totalDuration: tracks.fold<Duration>(
        Duration.zero,
        (total, track) => total + track.duration,
      ),
      artwork: PlaylistArtwork(playlist: playlist, tracks: tracks, size: 184),
      fileToken: playlist.id,
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
    var matchMode =
        initialRule?.matchMode ?? CustomSmartPlaylistMatchMode.all;
    var ruleGroups = List<CustomSmartPlaylistRuleGroup>.from(
      initialRule?.ruleGroups ?? const <CustomSmartPlaylistRuleGroup>[],
    );
    var sortMode =
        initialRule?.sortMode ?? CustomSmartPlaylistSortMode.recentlyAdded;

    return showDialog<_CustomSmartPlaylistDraft>(
      context: context,
      builder: (dialogContext) {
        return _TextEditingControllerOwner(
          controllers: <TextEditingController>[
            nameController,
            queryController,
            sourceIdController,
            artistController,
            albumController,
            genreController,
            minimumDurationController,
            maximumDurationController,
            minimumPlayCountController,
            minimumDaysSinceLastPlayedController,
            limitController,
          ],
          child: StatefulBuilder(
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
                  matchMode: matchMode,
                  ruleGroups: ruleGroups,
                  sortMode: sortMode,
                  limit: int.tryParse(limitController.text.trim()) ?? 50,
                );
              }

              return AlertDialog(
                key: const Key('smart-playlist-dialog'),
                title: Text(title),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextField(
                          key: const Key('smart-playlist-name'),
                          autofocus: true,
                          controller: nameController,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Rule matching',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<CustomSmartPlaylistMatchMode>(
                          segments: const <
                            ButtonSegment<CustomSmartPlaylistMatchMode>
                          >[
                            ButtonSegment<CustomSmartPlaylistMatchMode>(
                              value: CustomSmartPlaylistMatchMode.all,
                              label: Text('Match all'),
                            ),
                            ButtonSegment<CustomSmartPlaylistMatchMode>(
                              value: CustomSmartPlaylistMatchMode.any,
                              label: Text('Match any'),
                            ),
                          ],
                          selected: <CustomSmartPlaylistMatchMode>{matchMode},
                          onSelectionChanged: (selection) {
                            setDialogState(() => matchMode = selection.first);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Nested rule groups',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            IconButton(
                              key: const Key('smart-playlist-add-rule-group'),
                              tooltip: ruleGroups.length >=
                                      maxCustomSmartPlaylistGroupsPerGroup
                                  ? 'Rule group limit reached'
                                  : 'Add rule group',
                              icon: const Icon(Icons.account_tree_outlined),
                              onPressed: ruleGroups.length >=
                                      maxCustomSmartPlaylistGroupsPerGroup
                                  ? null
                                  : () async {
                                      final group =
                                          await _promptForCustomSmartPlaylistRuleGroup(
                                        context,
                                      );
                                      if (group != null) {
                                        setDialogState(() {
                                          ruleGroups =
                                              <CustomSmartPlaylistRuleGroup>[
                                            ...ruleGroups,
                                            group,
                                          ];
                                        });
                                      }
                                    },
                            ),
                          ],
                        ),
                        if (ruleGroups.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('No nested groups.'),
                          )
                        else
                          for (var index = 0;
                              index < ruleGroups.length;
                              index += 1)
                            ListTile(
                              key: ValueKey<String>(
                                'smart-playlist-rule-group-$index',
                              ),
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.account_tree_outlined),
                              title: Text(
                                _customSmartPlaylistRuleGroupSummary(
                                  ruleGroups[index],
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Remove rule group',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setDialogState(() {
                                    ruleGroups = <CustomSmartPlaylistRuleGroup>[
                                      for (var itemIndex = 0;
                                          itemIndex < ruleGroups.length;
                                          itemIndex += 1)
                                        if (itemIndex != index)
                                          ruleGroups[itemIndex],
                                    ];
                                  });
                                },
                              ),
                              onTap: () async {
                                final group =
                                    await _promptForCustomSmartPlaylistRuleGroup(
                                  context,
                                  initialGroup: ruleGroups[index],
                                );
                                if (group != null) {
                                  setDialogState(() {
                                    ruleGroups = <CustomSmartPlaylistRuleGroup>[
                                      for (var itemIndex = 0;
                                          itemIndex < ruleGroups.length;
                                          itemIndex += 1)
                                        if (itemIndex == index)
                                          group
                                        else
                                          ruleGroups[itemIndex],
                                    ];
                                  });
                                }
                              },
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
                          isExpanded: true,
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
                    key: const Key('smart-playlist-save'),
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
          ),
        );
      },
    );
  }

  Future<CustomSmartPlaylistRuleGroup?>
      _promptForCustomSmartPlaylistRuleGroup(
    BuildContext context, {
    CustomSmartPlaylistRuleGroup? initialGroup,
    int depth = 0,
  }) async {
    assert(depth >= 0 && depth < maxCustomSmartPlaylistRuleGroupDepth);
    var matchMode =
        initialGroup?.matchMode ?? CustomSmartPlaylistMatchMode.all;
    var rules = List<CustomSmartPlaylistRule>.from(
      initialGroup?.rules ?? const <CustomSmartPlaylistRule>[],
    );
    var groups = List<CustomSmartPlaylistRuleGroup>.from(
      initialGroup?.groups ?? const <CustomSmartPlaylistRuleGroup>[],
    );

    return showDialog<CustomSmartPlaylistRuleGroup>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canAddRule =
                rules.length < maxCustomSmartPlaylistRulesPerGroup;
            final atMaximumDepth =
                depth + 1 >= maxCustomSmartPlaylistRuleGroupDepth;
            final canAddNestedGroup = !atMaximumDepth &&
                groups.length < maxCustomSmartPlaylistGroupsPerGroup;
            return AlertDialog(
              key: ValueKey<String>('smart-playlist-rule-group-dialog-$depth'),
              title: const Text('Rule group'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SegmentedButton<CustomSmartPlaylistMatchMode>(
                        key: ValueKey<String>(
                          'smart-playlist-rule-group-match-mode-$depth',
                        ),
                        segments: const <
                          ButtonSegment<CustomSmartPlaylistMatchMode>
                        >[
                          ButtonSegment<CustomSmartPlaylistMatchMode>(
                            value: CustomSmartPlaylistMatchMode.all,
                            label: Text('Match all'),
                          ),
                          ButtonSegment<CustomSmartPlaylistMatchMode>(
                            value: CustomSmartPlaylistMatchMode.any,
                            label: Text('Match any'),
                          ),
                        ],
                        selected: <CustomSmartPlaylistMatchMode>{matchMode},
                        onSelectionChanged: (selection) {
                          setDialogState(() => matchMode = selection.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Rules',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (rules.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Add at least one rule or nested group.'),
                        )
                      else
                        for (var index = 0; index < rules.length; index += 1)
                          ListTile(
                            key: ValueKey<String>(
                              'smart-playlist-rule-$depth-$index',
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: Text(_customSmartPlaylistRuleSummary(rules[index])),
                            trailing: IconButton(
                              tooltip: 'Remove rule',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setDialogState(() {
                                  rules = <CustomSmartPlaylistRule>[
                                    for (var itemIndex = 0;
                                        itemIndex < rules.length;
                                        itemIndex += 1)
                                      if (itemIndex != index) rules[itemIndex],
                                  ];
                                });
                              },
                            ),
                            onTap: () async {
                              final rule =
                                  await _promptForCustomSmartPlaylistCondition(
                                context,
                                initialRule: rules[index],
                              );
                              if (rule != null) {
                                setDialogState(() => rules[index] = rule);
                              }
                            },
                          ),
                      OutlinedButton.icon(
                        key: ValueKey<String>(
                          'smart-playlist-add-rule-$depth',
                        ),
                        onPressed: canAddRule
                            ? () async {
                                final rule =
                                    await _promptForCustomSmartPlaylistCondition(
                                  context,
                                );
                                if (rule != null) {
                                  setDialogState(
                                    () => rules = <CustomSmartPlaylistRule>[
                                      ...rules,
                                      rule,
                                    ],
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.add),
                        label: Text(
                          canAddRule ? 'Add rule' : 'Rule limit reached',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nested groups',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      for (var index = 0; index < groups.length; index += 1)
                        ListTile(
                          key: ValueKey<String>(
                            'smart-playlist-nested-group-$depth-$index',
                          ),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_tree_outlined),
                          title: Text(
                            _customSmartPlaylistRuleGroupSummary(groups[index]),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove nested group',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setDialogState(() {
                                groups = <CustomSmartPlaylistRuleGroup>[
                                  for (var itemIndex = 0;
                                      itemIndex < groups.length;
                                      itemIndex += 1)
                                    if (itemIndex != index) groups[itemIndex],
                                ];
                              });
                            },
                          ),
                          onTap: () async {
                            final group =
                                await _promptForCustomSmartPlaylistRuleGroup(
                              context,
                              initialGroup: groups[index],
                              depth: depth + 1,
                            );
                            if (group != null) {
                              setDialogState(() => groups[index] = group);
                            }
                          },
                        ),
                      OutlinedButton.icon(
                        key: ValueKey<String>(
                          'smart-playlist-add-nested-group-$depth',
                        ),
                        onPressed: canAddNestedGroup
                            ? () async {
                                final group =
                                    await _promptForCustomSmartPlaylistRuleGroup(
                                  context,
                                  depth: depth + 1,
                                );
                                if (group != null) {
                                  setDialogState(
                                    () => groups =
                                        <CustomSmartPlaylistRuleGroup>[
                                      ...groups,
                                      group,
                                    ],
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.account_tree_outlined),
                        label: Text(
                          atMaximumDepth
                              ? 'Maximum nesting depth reached'
                              : canAddNestedGroup
                                  ? 'Add nested group'
                                  : 'Nested group limit reached',
                        ),
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
                  key: ValueKey<String>(
                    'smart-playlist-rule-group-save-$depth',
                  ),
                  onPressed: rules.isEmpty && groups.isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                            CustomSmartPlaylistRuleGroup(
                              matchMode: matchMode,
                              rules: rules,
                              groups: groups,
                            ),
                          ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<CustomSmartPlaylistRule?> _promptForCustomSmartPlaylistCondition(
    BuildContext context, {
    CustomSmartPlaylistRule? initialRule,
  }) async {
    var field = initialRule?.field ?? CustomSmartPlaylistRuleField.artist;
    final valueController = TextEditingController(text: initialRule?.value ?? '');
    return showDialog<CustomSmartPlaylistRule>(
      context: context,
      builder: (dialogContext) {
        return _TextEditingControllerOwner(
          controllers: <TextEditingController>[valueController],
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final isFavoriteRule =
                  field == CustomSmartPlaylistRuleField.favoritesOnly;
              return AlertDialog(
                key: const Key('smart-playlist-rule-dialog'),
                title: const Text('Rule'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<CustomSmartPlaylistRuleField>(
                      key: const Key('smart-playlist-rule-field'),
                      isExpanded: true,
                      initialValue: field,
                      decoration: const InputDecoration(labelText: 'Field'),
                      items: CustomSmartPlaylistRuleField.values
                          .map(
                            (candidate) => DropdownMenuItem(
                              value: candidate,
                              child: Text(
                                _customSmartPlaylistRuleFieldLabel(candidate),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => field = value);
                        }
                      },
                    ),
                    if (isFavoriteRule)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Matches favorite tracks.'),
                        ),
                      )
                    else
                      TextField(
                        key: const Key('smart-playlist-rule-value'),
                        controller: valueController,
                        decoration: InputDecoration(
                          labelText: _customSmartPlaylistRuleFieldLabel(field),
                        ),
                        keyboardType: field ==
                                    CustomSmartPlaylistRuleField
                                        .minimumDurationSeconds ||
                                field ==
                                    CustomSmartPlaylistRuleField
                                        .maximumDurationSeconds ||
                                field ==
                                    CustomSmartPlaylistRuleField
                                        .minimumPlayCount ||
                                field ==
                                    CustomSmartPlaylistRuleField
                                        .minimumDaysSinceLastPlayed
                            ? TextInputType.number
                            : TextInputType.text,
                      ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const Key('smart-playlist-rule-save'),
                    onPressed: () {
                      final rule = CustomSmartPlaylistRule(
                        field: field,
                        value: isFavoriteRule ? 'true' : valueController.text,
                      ).normalized();
                      if (rule != null) {
                        Navigator.of(dialogContext).pop(rule);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
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
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
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
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
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

class _CustomSmartPlaylistArtwork extends StatelessWidget {
  const _CustomSmartPlaylistArtwork({required this.rule, required this.tracks});

  final CustomSmartPlaylist rule;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final artworkUri = rule.artworkUri;
    if (artworkUri != null) {
      return TrackArtwork(
        artworkUri: artworkUri,
        size: 40,
        borderRadius: 10,
        fallbackIcon: Icons.filter_alt_outlined,
      );
    }
    if (tracks.isNotEmpty) {
      final track = tracks.first;
      return TrackArtwork(
        artworkUri: track.artworkUri,
        providerId: track.sourceId,
        providerArtworkId: track.providerArtworkId,
        providerArtworkVersion: track.providerArtworkVersion,
        size: 40,
        borderRadius: 10,
        fallbackIcon: Icons.filter_alt_outlined,
      );
    }
    return const Icon(Icons.filter_alt_outlined);
  }
}

class _CustomSmartPlaylistCard extends StatelessWidget {
  const _CustomSmartPlaylistCard({
    required this.rule,
    required this.tracks,
    required this.onOpen,
    required this.onEdit,
    required this.onArtwork,
    required this.onCopyImportLink,
    required this.onDelete,
  });

  final CustomSmartPlaylist rule;
  final List<Track> tracks;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onArtwork;
  final VoidCallback onCopyImportLink;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _CustomSmartPlaylistArtwork(rule: rule, tracks: tracks),
        title: Text(rule.name),
        subtitle: Text(_customSmartPlaylistSubtitle(rule, tracks.length)),
        onTap: onOpen,
        trailing: PopupMenuButton<_CustomSmartPlaylistAction>(
          key: ValueKey<String>('smart-playlist-actions-${rule.id}'),
          onSelected: (action) {
            switch (action) {
              case _CustomSmartPlaylistAction.edit:
                onEdit();
                break;
              case _CustomSmartPlaylistAction.artwork:
                onArtwork();
                break;
              case _CustomSmartPlaylistAction.copyImportLink:
                onCopyImportLink();
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
              value: _CustomSmartPlaylistAction.artwork,
              child: ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Artwork'),
              ),
            ),
            PopupMenuItem(
              value: _CustomSmartPlaylistAction.copyImportLink,
              child: ListTile(
                leading: Icon(Icons.link_outlined),
                title: Text('Copy import link'),
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
    required this.onCopyImportLink,
    required this.onShareCard,
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
  final VoidCallback onCopyImportLink;
  final VoidCallback onShareCard;
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
              case _PlaylistAction.copyImportLink:
                onCopyImportLink();
                break;
              case _PlaylistAction.shareCard:
                onShareCard();
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
            PopupMenuItem(
              value: _PlaylistAction.copyImportLink,
              child: ListTile(
                leading: Icon(Icons.link_outlined),
                title: Text('Copy import link'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.shareCard,
              child: ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Save share card'),
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
  copyImportLink,
  shareCard,
  rename,
  folder,
  artwork,
  delete,
}

enum _CustomSmartPlaylistAction { edit, artwork, copyImportLink, delete }

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
        return Consumer<LibraryStore>(
          builder: (context, library, child) {
            final visualTheme = library.listeningRecapVisualTheme;
            return AlertDialog(
              key: const Key('listening-recap-preview-dialog'),
              title: Text('${listeningRecapLabel(recap)} recap'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Visual theme',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      ListeningRecapThemePicker(
                        selectedTheme: visualTheme,
                        onChanged: (theme) {
                          unawaited(
                            library.setListeningRecapVisualTheme(theme),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: RepaintBoundary(
                          key: boundaryKey,
                          child: ListeningRecapCard(
                            recap: recap,
                            visualTheme: visualTheme,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Close'),
                ),
                FilledButton.icon(
                  key: const Key('listening-recap-save-png'),
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
                              key: ValueKey<String>(
                                'listening-recap-preview-'
                                '${recap.period.name}-'
                                '${recap.start.year}-'
                                '${recap.start.month}',
                              ),
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

Future<void> _playLibraryCollection(
  BuildContext context,
  PlayerController player,
  LibraryStore library,
  List<Track> tracks, {
  required bool shuffle,
}) async {
  if (tracks.isEmpty) {
    return;
  }

  await player.setShuffleEnabled(shuffle);
  if (!context.mounted) {
    return;
  }
  await _playTrackWithResume(
    context,
    player,
    library,
    tracks.first,
    queue: tracks,
  );
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
      action: SnackBarAction(
        label: 'Save playlist',
        onPressed: () => unawaited(
          _saveTrackRadioPlaylist(context, library, seedTrack),
        ),
      ),
    ),
  );
}

Future<void> _saveTrackRadioPlaylist(
  BuildContext context,
  LibraryStore library,
  Track seedTrack,
) async {
  final playlist = await library.saveTrackRadioPlaylist(seedTrack.id);
  if (!context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        playlist == null
            ? 'No playable radio queue for ${seedTrack.title}.'
            : 'Saved radio as ${playlist.name}.',
      ),
    ),
  );
}

Future<void> _startBrowseGroupRadio(
  BuildContext context,
  PlayerController player,
  LibraryStore library,
  LibraryBrowseType type,
  LibraryBrowseGroup group,
) async {
  final radioQueue = library.radioQueueForBrowseGroup(type, group.key);
  if (radioQueue == null || radioQueue.tracks.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No playable radio queue for ${group.label}.'),
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
        'Started ${radioQueue.tracks.length}-track ${radioQueue.label} radio.',
      ),
      action: SnackBarAction(
        label: 'Save playlist',
        onPressed: () => unawaited(
          _saveBrowseGroupRadioPlaylist(context, library, type, group),
        ),
      ),
    ),
  );
}

Future<void> _saveBrowseGroupRadioPlaylist(
  BuildContext context,
  LibraryStore library,
  LibraryBrowseType type,
  LibraryBrowseGroup group,
) async {
  final playlist = await library.saveBrowseGroupRadioPlaylist(type, group.key);
  if (!context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        playlist == null
            ? 'No playable radio queue for ${group.label}.'
            : 'Saved radio as ${playlist.name}.',
      ),
    ),
  );
}

Future<void> _exportLocalDiagnostics(
  BuildContext context,
  LocalDiagnosticLog diagnostics,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final bytes = Uint8List.fromList(utf8.encode(diagnostics.exportJson()));
  final outputPath = await FilePicker.saveFile(
    dialogTitle: 'Export local diagnostics',
    fileName: 'aethertune-local-diagnostics.json',
    type: FileType.custom,
    allowedExtensions: const <String>['json'],
    bytes: bytes,
  );
  if (!context.mounted || outputPath == null) {
    return;
  }

  try {
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(outputPath).writeAsBytes(bytes, flush: true);
    }
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved local diagnostics.')),
      );
    }
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save local diagnostics: $error')),
      );
    }
  }
}

Future<void> _clearLocalDiagnostics(
  BuildContext context,
  LocalDiagnosticLog diagnostics,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Clear local diagnostics?'),
      content: const Text(
        'This permanently removes the reports saved on this device.',
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
  await diagnostics.clear();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared local diagnostics.')),
    );
  }
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

Future<void> _copyPlaylistImportLink(
  BuildContext context,
  LibraryStore library,
  Playlist playlist,
) {
  return _copyTextToClipboard(
    context,
    library.playlistImportLink(playlist.id),
    copiedMessage: 'Copied import link for ${playlist.name}.',
    unavailableMessage:
        'This playlist is too large to share as an import link. Export a file instead.',
  );
}

Future<void> _copyCustomSmartPlaylistImportLink(
  BuildContext context,
  LibraryStore library,
  CustomSmartPlaylist playlist,
) {
  return _copyTextToClipboard(
    context,
    library.customSmartPlaylistImportLink(playlist.id),
    copiedMessage: 'Copied import link for ${playlist.name}.',
    unavailableMessage:
        'This smart playlist is too large to share as an import link.',
  );
}

Future<void> _showAlbumShareCard(
  BuildContext context,
  LibraryBrowseGroup group,
  List<Track> tracks,
) async {
  await _showBrowseGroupShareCard(
    context,
    LibraryBrowseType.album,
    group,
    tracks,
  );
}

Future<void> _showBrowseGroupShareCard(
  BuildContext context,
  LibraryBrowseType type,
  LibraryBrowseGroup group,
  List<Track> tracks,
) async {
  if (tracks.isEmpty) {
    return;
  }
  final representative = _collectionRepresentativeTrack(tracks)!;
  final kind = type == LibraryBrowseType.artist ? 'artist' : 'album';
  final metadata = type == LibraryBrowseType.artist
      ? _collectionMetadataValues(
          tracks.map((track) => track.genre),
        ).take(3).join(' · ')
      : _albumArtistLabel(
          _collectionMetadataValues(tracks.map((track) => track.artist)),
        );
  final totalDuration = tracks.fold<Duration>(
    Duration.zero,
    (total, track) => total + track.duration,
  );
  await _showCollectionShareCard(
    context,
    kind: kind,
    title: group.label,
    subtitle: metadata.isEmpty ? 'Local $kind' : metadata,
    itemCount: tracks.length,
    totalDuration: totalDuration,
    artwork: TrackArtwork(
      artworkUri: representative.artworkUri,
      providerId: representative.sourceId,
      providerArtworkId: representative.providerArtworkId,
      providerArtworkVersion: representative.providerArtworkVersion,
      size: 184,
      borderRadius: 12,
      fallbackIcon: type == LibraryBrowseType.artist
          ? Icons.person_outline
          : Icons.album_outlined,
    ),
    fileToken: '${type.name}-${group.key}',
  );
}

Future<void> _showCollectionShareCard(
  BuildContext context, {
  required String kind,
  required String title,
  required String subtitle,
  required int itemCount,
  required Duration totalDuration,
  required Widget artwork,
  required String fileToken,
}) async {
  final boundaryKey = GlobalKey();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('${kind[0].toUpperCase()}${kind.substring(1)} share card'),
      content: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: RepaintBoundary(
          key: boundaryKey,
          child: CollectionShareCard(
            kind: kind,
            title: title,
            subtitle: subtitle,
            itemCount: itemCount,
            totalDuration: totalDuration,
            artwork: artwork,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => _saveCollectionShareCard(
            dialogContext,
            boundaryKey,
            kind: kind,
            fileToken: fileToken,
          ),
          icon: const Icon(Icons.image_outlined),
          label: const Text('Save PNG'),
        ),
      ],
    ),
  );
}

Future<void> _saveCollectionShareCard(
  BuildContext context,
  GlobalKey boundaryKey, {
  required String kind,
  required String fileToken,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final fileName = 'aethertune-${_shareCardFileToken(kind)}-'
      '${_shareCardFileToken(fileToken)}.png';
  try {
    final bytes = await captureCollectionShareCardPng(boundaryKey);
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save $kind share card',
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
        SnackBar(content: Text('Could not save $kind share card: $error')),
      );
    }
  }
}

String _shareCardFileToken(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-');
  if (normalized.isEmpty) {
    return 'collection';
  }
  final end = normalized.length > 64 ? 64 : normalized.length;
  return normalized.substring(0, end);
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

const _maxLyricsShareRangeLines = 8;

class _LyricsShareRange {
  const _LyricsShareRange({required this.startLine, required this.endLine});

  final int startLine;
  final int endLine;
}

Future<void> _copyLyricsSelectedRangeShareText(
  BuildContext context,
  LibraryStore library,
  Track track, {
  String? plainText,
}) async {
  final lines = library.lyricsShareLines(track.id, plainText: plainText);
  if (lines.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add lyrics before sharing selected lines.')),
    );
    return;
  }
  final range = await _promptForLyricsShareRange(context, lines: lines);
  if (!context.mounted || range == null) {
    return;
  }

  await _copyTextToClipboard(
    context,
    library.shareLyricsText(
      track.id,
      plainText: plainText,
      startLine: range.startLine,
      endLine: range.endLine,
      maxLines: _maxLyricsShareRangeLines,
    ),
    copiedMessage: 'Copied selected lyrics for ${track.title}.',
    unavailableMessage: 'Selected lyrics are unavailable for ${track.title}.',
  );
}

Future<_LyricsShareRange?> _promptForLyricsShareRange(
  BuildContext context, {
  required List<String> lines,
}) async {
  var startLine = 0;
  var endLine = _lyricsShareRangeEndLimit(startLine, lines.length);

  return showDialog<_LyricsShareRange>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (_, setDialogState) {
          final maximumEndLine = _lyricsShareRangeEndLimit(
            startLine,
            lines.length,
          );
          final selectedLines = lines.sublist(startLine, endLine + 1);

          return AlertDialog(
            title: const Text('Share selected lines'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Choose up to 8 visible lyrics lines.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('lyrics-share-start-$startLine'),
                    initialValue: startLine,
                    decoration: const InputDecoration(labelText: 'Start line'),
                    items: <DropdownMenuItem<int>>[
                      for (var index = 0; index < lines.length; index++)
                        DropdownMenuItem<int>(
                          value: index,
                          child: Text('Line ${index + 1}'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        startLine = value;
                        final newMaximumEndLine = _lyricsShareRangeEndLimit(
                          startLine,
                          lines.length,
                        );
                        endLine = endLine
                            .clamp(startLine, newMaximumEndLine)
                            .toInt();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('lyrics-share-end-$startLine-$endLine'),
                    initialValue: endLine,
                    decoration: const InputDecoration(labelText: 'End line'),
                    items: <DropdownMenuItem<int>>[
                      for (
                        var index = startLine;
                        index <= maximumEndLine;
                        index++
                      )
                        DropdownMenuItem<int>(
                          value: index,
                          child: Text('Line ${index + 1}'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => endLine = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedLines.join('\n'),
                    maxLines: _maxLyricsShareRangeLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _LyricsShareRange(
                    startLine: startLine,
                    endLine: endLine,
                  ),
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text('Copy selected lines'),
              ),
            ],
          );
        },
      );
    },
  );
}

int _lyricsShareRangeEndLimit(int startLine, int lineCount) {
  return (startLine + _maxLyricsShareRangeLines - 1)
      .clamp(startLine, lineCount - 1)
      .toInt();
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
    details.add(
      'Imported sidecar lyrics for ${result.sidecarLyricsCount} track(s).',
    );
  }
  if (result.embeddedLyricsCount > 0) {
    details.add(
      'Imported embedded lyrics for ${result.embeddedLyricsCount} track(s).',
    );
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

enum _CustomCatalogAction { edit, remove }

enum _YouTubeDataAction { configure, remove }

class _SourcesTab extends StatefulWidget {
  const _SourcesTab({
    this.archiveProvider,
    this.providerSearchProviders,
  });

  final InternetArchiveProvider? archiveProvider;
  final List<MusicSourceProvider>? providerSearchProviders;

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
  List<ProviderSearchError> _providerSearchLoadMoreErrors =
      <ProviderSearchError>[];
  List<ProviderSearchSuggestion> _providerSearchSuggestions =
      <ProviderSearchSuggestion>[];
  Map<String, String> _providerSearchContinuations = <String, String>{};
  Map<String, String> _providerSearchFailedContinuations = <String, String>{};
  List<Track> _radioTracks = <Track>[];
  List<RadioBrowserStation> _radioStations = <RadioBrowserStation>[];
  int _radioNextOffset = 0;
  int _radioRequestSerial = 0;
  bool _radioHasMore = false;
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
  bool _providerSearchLoadingMore = false;
  bool _providerSearchSuggestionsLoading = false;
  bool _providerSearchLocalOnly = false;
  int _providerSearchRequestSerial = 0;
  int _providerSearchSuggestionRequestSerial = 0;
  Timer? _providerSearchSuggestionDebounce;
  String _providerSearchQuery = '';
  String? _providerSearchMessage;
  bool _radioLoading = false;
  bool _radioLoadingMore = false;
  String? _radioError;
  String? _radioLoadMoreError;

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
    _providerSearchSuggestionDebounce?.cancel();
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
    final customCatalogs = context.watch<CustomCatalogStore?>();
    final youtubeData = context.watch<YouTubeDataSettingsStore?>();
    final youtubeProviders = youtubeData?.musicProviders ??
        const <MusicSourceProvider>[];
    final youtubeProvider = youtubeProviders.isEmpty
        ? null
        : youtubeProviders.first;
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
          'Official APIs',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        _ProviderCard(
          title: 'YouTube Data API',
          status: youtubeData?.isConfigured == true ? 'Enabled' : 'Optional',
          description: youtubeData?.isConfigured == true
              ? 'Searches official video metadata only. Playback and offline media are unavailable.'
              : 'Configure a user-owned Google Cloud API key for official video metadata search only.',
          icon: Icons.ondemand_video_outlined,
          capabilities: youtubeProvider?.capabilities ??
              const <MusicSourceCapability>{
                MusicSourceCapability.metadataSearch,
                MusicSourceCapability.artwork,
              },
          disclosure: youtubeProvider?.disclosure ??
              const ProviderPrivacyDisclosure(
                networkDomains: <String>[
                  'www.googleapis.com',
                  'i.ytimg.com',
                ],
              ),
          actions: PopupMenuButton<_YouTubeDataAction>(
            tooltip: 'Manage YouTube Data API',
            onSelected: (action) {
              switch (action) {
                case _YouTubeDataAction.configure:
                  unawaited(_configureYouTubeData(context));
                  break;
                case _YouTubeDataAction.remove:
                  unawaited(_removeYouTubeData(context));
                  break;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_YouTubeDataAction>>[
              PopupMenuItem<_YouTubeDataAction>(
                value: _YouTubeDataAction.configure,
                enabled: youtubeData?.loaded == true && !offlineModeEnabled,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(
                    youtubeData?.isConfigured == true
                        ? 'Replace API key'
                        : 'Configure API key',
                  ),
                ),
              ),
              PopupMenuItem<_YouTubeDataAction>(
                value: _YouTubeDataAction.remove,
                enabled: youtubeData?.isConfigured == true,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Remove API key'),
                ),
              ),
            ],
          ),
        ),
        if (youtubeData?.loaded != true) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (youtubeData?.loadError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('YouTube Data API unavailable'),
            subtitle: Text(youtubeData!.loadError!),
          ),
        ],
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
        const SizedBox(height: 16),
        Text(
          'Custom JSON catalogs',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            OutlinedButton.icon(
              key: const Key('add-custom-catalog'),
              onPressed: customCatalogs?.loaded == true && !offlineModeEnabled
                  ? () => unawaited(_editCustomCatalog(context))
                  : null,
              icon: const Icon(Icons.add_link_outlined),
              label: const Text('Add JSON catalog'),
            ),
          ],
        ),
        if (customCatalogs == null || !customCatalogs.loaded) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ]
        else if (customCatalogs.loadError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.extension_off_outlined),
            title: const Text('Custom catalogs unavailable'),
            subtitle: Text(customCatalogs.loadError!),
          ),
        ]
        else if (customCatalogs.definitions.isEmpty)
          const ListTile(
            leading: Icon(Icons.data_object_outlined),
            title: Text('No custom JSON catalogs configured'),
            subtitle: Text(
              'Add a declared HTTPS catalog with its media hosts to search legal direct streams.',
            ),
          )
        else
          for (final definition in customCatalogs.definitions)
            _ProviderCard(
              title: definition.name,
              status: 'Enabled',
              description: definition.description.isEmpty
                  ? 'JSON catalog at ${definition.catalogUri.host}'
                  : definition.description,
              icon: Icons.data_object_outlined,
              capabilities: CustomCatalogProvider(definition).capabilities,
              disclosure: CustomCatalogProvider(definition).disclosure,
              actions: PopupMenuButton<_CustomCatalogAction>(
                tooltip: 'Manage ${definition.name}',
                onSelected: (action) {
                  switch (action) {
                    case _CustomCatalogAction.edit:
                      unawaited(
                        _editCustomCatalog(context, definition: definition),
                      );
                      break;
                    case _CustomCatalogAction.remove:
                      unawaited(_removeCustomCatalog(context, definition));
                      break;
                  }
                },
                itemBuilder: (_) => <PopupMenuEntry<_CustomCatalogAction>>[
                  const PopupMenuItem<_CustomCatalogAction>(
                    value: _CustomCatalogAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit catalog'),
                    ),
                  ),
                  const PopupMenuItem<_CustomCatalogAction>(
                    value: _CustomCatalogAction.remove,
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
                onChanged: _scheduleProviderSearchSuggestions,
                onSubmitted: (_) => _submitProviderSearch(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Search library and providers',
              onPressed: _providerSearchLoading
                  ? null
                  : _submitProviderSearch,
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        if (_providerSearchSuggestionsLoading) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(
            key: ValueKey<String>('provider-search-suggestions-progress'),
          ),
        ],
        if (_providerSearchSuggestions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final suggestion in _providerSearchSuggestions)
                ActionChip(
                  key: ValueKey<String>(
                    'provider-search-suggestion-${suggestion.providerId}-'
                    '${suggestion.suggestion.value}',
                  ),
                  avatar: Icon(
                    _providerSearchSuggestionIcon(suggestion.suggestion.kind),
                  ),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      suggestion.suggestion.value,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  tooltip: '${suggestion.providerName} '
                      '${suggestion.suggestion.kind.label}: '
                      '${suggestion.suggestion.value}',
                  onPressed: () => _selectProviderSearchSuggestion(suggestion),
                ),
            ],
          ),
        ],
        if (_providerSearchLoading) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(
            key: ValueKey<String>('provider-search-progress'),
          ),
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
              key: ValueKey<String>(
                'provider-search-result-${result.providerId}-${result.track.id}',
              ),
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
        if (_providerSearchLoadingMore) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(
            key: ValueKey<String>('provider-search-load-more-progress'),
          ),
        ],
        for (final error in _providerSearchLoadMoreErrors) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            key: ValueKey<String>(
              'provider-search-load-more-error-${error.providerId}',
            ),
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text('Could not load more from ${error.providerName}'),
            subtitle: Text(error.message),
          ),
        ],
        if (!_providerSearchLoadingMore &&
            _providerSearchLoadMoreErrors.isNotEmpty &&
            _providerSearchFailedContinuations.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              key: const ValueKey<String>(
                'provider-search-load-more-retry',
              ),
              onPressed: offlineModeEnabled && !_providerSearchLocalOnly
                  ? null
                  : () => unawaited(
                        _continueProviderCatalogSearch(
                          continuations:
                              _providerSearchFailedContinuations,
                        ),
                      ),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry failed providers'),
            ),
          ),
        ] else if (!_providerSearchLoadingMore &&
            _providerSearchLoadMoreErrors.isEmpty &&
            _providerSearchContinuations.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              key: const ValueKey<String>('provider-search-load-more'),
              onPressed: offlineModeEnabled && !_providerSearchLocalOnly
                  ? null
                  : () => unawaited(_continueProviderCatalogSearch()),
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more provider results'),
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
              onPressed: _radioLoading || _radioLoadingMore || offlineModeEnabled
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
        ] else if (_radioStations.isEmpty && !_radioLoading) ...<Widget>[
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
          for (final station in _radioStations)
            ListTile(
              leading: const Icon(Icons.radio_outlined),
              title: Text(station.name),
              subtitle: Text(_radioStationSummary(station)),
              onTap: () => _openRadioStation(context, station),
              trailing: const Icon(Icons.chevron_right),
            ),
        ],
        if (_radioLoadingMore) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_radioLoadMoreError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Could not load more stations'),
            subtitle: Text(_radioLoadMoreError!),
            trailing: IconButton(
              tooltip: 'Retry loading stations',
              onPressed: _radioLoadingMore || offlineModeEnabled
                  ? null
                  : _loadMoreRadioStations,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
        if (_radioStations.isNotEmpty && _radioHasMore) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _radioLoading || _radioLoadingMore || offlineModeEnabled
                  ? null
                  : _loadMoreRadioStations,
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more stations'),
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

  Future<void> _configureYouTubeData(BuildContext context) async {
    final keyController = TextEditingController();
    String? validationError;
    try {
      final apiKey = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Configure YouTube Data API'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'This source searches official video metadata only. It does not play, download, or cache YouTube audiovisual content and does not sign in to a YouTube account.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('youtube-data-api-key'),
                      controller: keyController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) {
                        final value = keyController.text.trim();
                        if (value.isEmpty) {
                          setDialogState(
                            () => validationError =
                                'Enter a Google Cloud API key.',
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Google Cloud API key',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Use an app-restricted key from your own Google Cloud project. YouTube Terms of Service: https://www.youtube.com/t/terms',
                    ),
                    if (validationError != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
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
                  final value = keyController.text.trim();
                  if (value.isEmpty) {
                    setDialogState(
                      () => validationError = 'Enter a Google Cloud API key.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || apiKey == null) {
        return;
      }
      final store = context.read<YouTubeDataSettingsStore?>();
      if (store == null) {
        return;
      }
      await store.saveApiKey(apiKey);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube Data API metadata search enabled.')),
      );
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
    } finally {
      keyController.dispose();
    }
  }

  Future<void> _removeYouTubeData(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove YouTube Data API key?'),
        content: const Text(
          'This disables YouTube Data API metadata search on this device. Saved metadata entries remain unchanged.',
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
    final store = context.read<YouTubeDataSettingsStore?>();
    if (store == null) {
      return;
    }
    await context
        .read<PlayerController>()
        .removeTracksFromSource('youtube-data-metadata');
    await store.removeApiKey();
    if (!context.mounted) {
      return;
    }
    _providerSearchRequestSerial += 1;
    setState(() {
      _providerSearchLoading = false;
      _providerSearchLoadingMore = false;
      _providerSearchResults.removeWhere(
        (result) => result.providerId == 'youtube-data-metadata',
      );
      _providerSearchErrors.removeWhere(
        (error) => error.providerId == 'youtube-data-metadata',
      );
      _providerSearchLoadMoreErrors.removeWhere(
        (error) => error.providerId == 'youtube-data-metadata',
      );
      _providerSearchContinuations.remove('youtube-data-metadata');
      _providerSearchFailedContinuations.remove('youtube-data-metadata');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('YouTube Data API key removed.')),
    );
  }

  Future<void> _editCustomCatalog(
    BuildContext context, {
    CustomCatalogDefinition? definition,
  }) async {
    final nameController = TextEditingController(text: definition?.name ?? '');
    final catalogUrlController = TextEditingController(
      text: definition?.catalogUri.toString() ?? '',
    );
    final domainsController = TextEditingController(
      text: definition?.mediaDomains.join(', ') ?? '',
    );
    final descriptionController = TextEditingController(
      text: definition?.description ?? '',
    );
    var allowInsecureHttp = definition?.allowInsecureHttp ?? false;
    String? validationError;
    try {
      final saved = await showDialog<CustomCatalogDefinition>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(
              definition == null ? 'Add JSON catalog' : 'Edit JSON catalog',
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      key: const Key('custom-catalog-name'),
                      controller: nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Catalog name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('custom-catalog-url'),
                      controller: catalogUrlController,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'JSON catalog URL',
                        hintText: 'https://catalog.example/music.json',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('custom-catalog-domains'),
                      controller: domainsController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Additional media domains',
                        hintText: 'cdn.example, audio.example',
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'The catalog host is always declared. Audio and artwork URLs must use this host or one listed above.',
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: allowInsecureHttp,
                      onChanged: (value) => setDialogState(
                        () => allowInsecureHttp = value ?? false,
                      ),
                      title: const Text('Allow insecure HTTP'),
                      subtitle: const Text(
                        'Only enable this for a trusted local network catalog.',
                      ),
                    ),
                    TextField(
                      key: const Key('custom-catalog-description'),
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                    if (validationError != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        validationError!,
                        style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error,
                        ),
                      ),
                    ],
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
                  try {
                    final savedDefinition = CustomCatalogDefinition.create(
                      id: definition?.id,
                      name: nameController.text,
                      catalogUrl: catalogUrlController.text,
                      mediaDomains: domainsController.text.split(
                        RegExp(r'[,\s]+'),
                      ),
                      allowInsecureHttp: allowInsecureHttp,
                      description: descriptionController.text,
                    );
                    Navigator.of(dialogContext).pop(savedDefinition);
                  } on FormatException catch (error) {
                    setDialogState(() => validationError = error.message);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || saved == null) {
        return;
      }
      final store = context.read<CustomCatalogStore?>();
      if (store == null) {
        return;
      }
      await store.save(saved);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${definition == null ? 'Added' : 'Updated'} ${saved.name}.',
          ),
        ),
      );
    } on StateError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    } finally {
      nameController.dispose();
      catalogUrlController.dispose();
      domainsController.dispose();
      descriptionController.dispose();
    }
  }

  Future<void> _removeCustomCatalog(
    BuildContext context,
    CustomCatalogDefinition definition,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${definition.name}?'),
        content: const Text(
          'This removes the catalog configuration from this device. Saved library entries remain unchanged.',
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
    final store = context.read<CustomCatalogStore?>();
    if (store == null) {
      return;
    }
    await context.read<PlayerController>().removeTracksFromSource(
      definition.providerId,
    );
    await store.remove(definition.id);
    if (!context.mounted) {
      return;
    }
    _providerSearchRequestSerial += 1;
    setState(() {
      _providerSearchLoading = false;
      _providerSearchLoadingMore = false;
      _providerSearchResults.removeWhere(
        (result) => result.providerId == definition.providerId,
      );
      _providerSearchErrors.removeWhere(
        (error) => error.providerId == definition.providerId,
      );
      _providerSearchLoadMoreErrors.removeWhere(
        (error) => error.providerId == definition.providerId,
      );
      _providerSearchContinuations.remove(definition.providerId);
      _providerSearchFailedContinuations.remove(definition.providerId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${definition.name}.')),
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
    _providerSearchRequestSerial += 1;
    setState(() {
      _providerSearchLoading = false;
      _providerSearchLoadingMore = false;
      _providerSearchResults.removeWhere(
        (result) => result.providerId == account.providerId,
      );
      _providerSearchErrors.removeWhere(
        (error) => error.providerId == account.providerId,
      );
      _providerSearchLoadMoreErrors.removeWhere(
        (error) => error.providerId == account.providerId,
      );
      _providerSearchContinuations.remove(account.providerId);
      _providerSearchFailedContinuations.remove(account.providerId);
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
    _providerSearchRequestSerial += 1;
    setState(() {
      _providerSearchLoading = false;
      _providerSearchLoadingMore = false;
      _providerSearchResults.removeWhere(
        (result) => result.providerId == account.providerId,
      );
      _providerSearchErrors.removeWhere(
        (error) => error.providerId == account.providerId,
      );
      _providerSearchLoadMoreErrors.removeWhere(
        (error) => error.providerId == account.providerId,
      );
      _providerSearchContinuations.remove(account.providerId);
      _providerSearchFailedContinuations.remove(account.providerId);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Rotated credential for ${account.name}.')),
    );
  }

  List<MusicSourceProvider> _providerSearchSources({bool localOnly = false}) {
    final override = widget.providerSearchProviders;
    if (override != null) {
      if (!localOnly) {
        return List<MusicSourceProvider>.unmodifiable(override);
      }
      return override
          .where(
            (provider) => provider.id == LocalLibraryProvider.providerId,
          )
          .toList(growable: false);
    }

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
      ...?context.read<YouTubeDataSettingsStore?>()?.musicProviders,
      ...context.read<SelfHostedProviderStore>().musicProviders,
      ...?context.read<CustomCatalogStore?>()?.musicProviders,
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
    final requestSerial = ++_providerSearchRequestSerial;
    if (query.isEmpty) {
      setState(() {
        _providerSearchQuery = '';
        _providerSearchResults = <ProviderSearchResult>[];
        _providerSearchErrors = <ProviderSearchError>[];
        _providerSearchLoadMoreErrors = <ProviderSearchError>[];
        _providerSearchContinuations = <String, String>{};
        _providerSearchFailedContinuations = <String, String>{};
        _providerSearchLoading = false;
        _providerSearchLoadingMore = false;
        _providerSearchSuggestionsLoading = false;
        _providerSearchSuggestions = <ProviderSearchSuggestion>[];
        _providerSearchMessage = 'Enter a search term.';
      });
      return;
    }

    final localOnly = context.read<LibraryStore>().offlineModeEnabled;
    setState(() {
      _providerSearchQuery = query;
      _providerSearchLocalOnly = localOnly;
      _providerSearchLoading = true;
      _providerSearchLoadingMore = false;
      _providerSearchSuggestionsLoading = false;
      _providerSearchSuggestions = <ProviderSearchSuggestion>[];
      _providerSearchMessage = null;
      _providerSearchErrors = <ProviderSearchError>[];
      _providerSearchLoadMoreErrors = <ProviderSearchError>[];
      _providerSearchResults = <ProviderSearchResult>[];
      _providerSearchContinuations = <String, String>{};
      _providerSearchFailedContinuations = <String, String>{};
    });

    try {
      final response = await _providerSearchCoordinatorFor(
        localOnly: localOnly,
      ).search(query);
      if (!mounted || requestSerial != _providerSearchRequestSerial) {
        return;
      }

      setState(() {
        _providerSearchResults = response.results;
        _providerSearchErrors = response.errors;
        _providerSearchContinuations = Map<String, String>.of(
          response.continuations,
        );
        _providerSearchLoading = false;
        _providerSearchMessage = _providerSearchCompletionMessage(
          hasResults: response.results.isNotEmpty,
          hasMore: response.hasMore,
          localOnly: localOnly,
        );
      });
    } catch (error) {
      if (!mounted || requestSerial != _providerSearchRequestSerial) {
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

  void _scheduleProviderSearchSuggestions(String value) {
    _providerSearchSuggestionDebounce?.cancel();
    final requestSerial = ++_providerSearchSuggestionRequestSerial;
    final query = value.trim();
    if (query.length < 2 || context.read<LibraryStore>().offlineModeEnabled) {
      setState(() {
        _providerSearchSuggestionsLoading = false;
        _providerSearchSuggestions = <ProviderSearchSuggestion>[];
      });
      return;
    }
    setState(() {
      _providerSearchSuggestionsLoading = true;
      _providerSearchSuggestions = <ProviderSearchSuggestion>[];
    });
    _providerSearchSuggestionDebounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(
        _loadProviderSearchSuggestions(query, requestSerial),
      ),
    );
  }

  Future<void> _loadProviderSearchSuggestions(
    String query,
    int requestSerial,
  ) async {
    if (!mounted || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final response = await _providerSearchCoordinator.suggest(query);
    if (!mounted || requestSerial != _providerSearchSuggestionRequestSerial) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      setState(() {
        _providerSearchSuggestionsLoading = false;
        _providerSearchSuggestions = <ProviderSearchSuggestion>[];
      });
      return;
    }
    setState(() {
      _providerSearchSuggestionsLoading = false;
      _providerSearchSuggestions = response.suggestions;
    });
  }

  void _selectProviderSearchSuggestion(ProviderSearchSuggestion suggestion) {
    _providerSearchController
      ..text = suggestion.suggestion.value
      ..selection = TextSelection.collapsed(
        offset: suggestion.suggestion.value.length,
      );
    _submitProviderSearch();
  }

  void _submitProviderSearch() {
    _providerSearchSuggestionDebounce?.cancel();
    _providerSearchSuggestionRequestSerial += 1;
    _searchProviderCatalogs();
  }

  IconData _providerSearchSuggestionIcon(
    MusicSourceSearchSuggestionKind kind,
  ) {
    switch (kind) {
      case MusicSourceSearchSuggestionKind.track:
        return Icons.music_note_outlined;
      case MusicSourceSearchSuggestionKind.artist:
        return Icons.person_outline;
      case MusicSourceSearchSuggestionKind.album:
        return Icons.album_outlined;
    }
  }

  Future<void> _continueProviderCatalogSearch({
    Map<String, String>? continuations,
  }) async {
    if (_providerSearchLoading || _providerSearchLoadingMore) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled &&
        !_providerSearchLocalOnly) {
      return;
    }
    final requested = Map<String, String>.of(
      continuations ?? _providerSearchContinuations,
    );
    final query = _providerSearchQuery;
    if (query.isEmpty || requested.isEmpty) {
      return;
    }

    final requestSerial = _providerSearchRequestSerial;
    setState(() {
      _providerSearchLoadingMore = true;
      _providerSearchLoadMoreErrors = <ProviderSearchError>[];
      _providerSearchFailedContinuations = <String, String>{};
    });

    try {
      final response = await _providerSearchCoordinatorFor(
        localOnly: _providerSearchLocalOnly,
      ).continueSearch(query, requested);
      if (!mounted || requestSerial != _providerSearchRequestSerial) {
        return;
      }

      final updatedContinuations = Map<String, String>.of(
        _providerSearchContinuations,
      );
      for (final providerId in response.successfulProviderIds) {
        updatedContinuations.remove(providerId);
      }
      updatedContinuations.addAll(response.continuations);
      final failedContinuations = <String, String>{};
      for (final error in response.errors) {
        final cursor = requested[error.providerId];
        if (cursor != null) {
          failedContinuations[error.providerId] = cursor;
        }
      }

      setState(() {
        _providerSearchResults = mergeProviderSearchResults(
          _providerSearchResults,
          response.results,
        );
        _providerSearchContinuations = updatedContinuations;
        _providerSearchFailedContinuations = failedContinuations;
        _providerSearchLoadMoreErrors = response.errors;
        _providerSearchLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestSerial != _providerSearchRequestSerial) {
        return;
      }
      setState(() {
        _providerSearchFailedContinuations = requested;
        _providerSearchLoadMoreErrors = <ProviderSearchError>[
          ProviderSearchError(
            providerId: 'provider-search',
            providerName: 'Provider search',
            message: error.toString(),
          ),
        ];
        _providerSearchLoadingMore = false;
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
    required bool hasMore,
    required bool localOnly,
  }) {
    if (hasMore) {
      return localOnly
          ? 'Offline mode: showing local library results only.'
          : null;
    }
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

    final report = await PodcastSubscriptionRefreshWorker()
        .refreshSubscriptions(library, subscriptions: subscriptions);

    if (!context.mounted) {
      return;
    }
    final selectedSubscription = _selectedPodcastSubscriptionId == null
        ? null
        : library.podcastSubscriptionById(_selectedPodcastSubscriptionId!);
    setState(() {
      _podcastLoading = false;
      if (selectedSubscription != null) {
        _podcastEpisodeTracks = selectedSubscription.episodes;
      }
      _podcastError = report.failedCount == 0
          ? null
          : '${report.failedCount} podcast feed(s) could not be refreshed.';
    });
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          report.failedCount == 0
              ? 'Refreshed ${report.refreshedCount} podcast feed(s).'
              : 'Refreshed ${report.refreshedCount} feed(s); ${report.failedCount} failed.',
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
    if (_radioLoading || _radioLoadingMore) {
      return;
    }

    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _radioRequestSerial += 1;
        _radioTracks = <Track>[];
        _radioStations = <RadioBrowserStation>[];
        _radioNextOffset = 0;
        _radioHasMore = false;
        _radioLoading = false;
        _radioLoadingMore = false;
        _radioError = 'Offline mode is on.';
        _radioLoadMoreError = null;
      });
      return;
    }

    final requestSerial = ++_radioRequestSerial;
    setState(() {
      _radioLoading = true;
      _radioError = null;
      _radioLoadMoreError = null;
      _radioHasMore = false;
    });

    try {
      final page = await _radioProvider.searchStationPage(
        _radioSearchController.text,
        filters: _radioFilters(),
      );
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioTracks = page.tracks;
        _radioStations = page.stations;
        _radioNextOffset = page.nextOffset;
        _radioHasMore = page.hasMore;
        _radioLoading = false;
      });
    } catch (error) {
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioTracks = <Track>[];
        _radioStations = <RadioBrowserStation>[];
        _radioNextOffset = 0;
        _radioHasMore = false;
        _radioLoading = false;
        _radioError = error.toString();
      });
    }
  }

  Future<void> _loadMoreRadioStations() async {
    if (_radioLoading || _radioLoadingMore || !_radioHasMore) {
      return;
    }

    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() => _radioLoadMoreError = 'Offline mode is on.');
      return;
    }

    final requestSerial = _radioRequestSerial;
    final offset = _radioNextOffset;
    final query = _radioSearchController.text;
    final filters = _radioFilters();
    setState(() {
      _radioLoadingMore = true;
      _radioLoadMoreError = null;
    });

    try {
      final page = await _radioProvider.searchStationPage(
        query,
        filters: filters,
        offset: offset,
      );
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioStations = _mergeRadioStations(_radioStations, page.stations);
        _radioTracks = _mergeRadioTracks(_radioTracks, page.tracks);
        _radioNextOffset = page.nextOffset;
        _radioHasMore = page.hasMore;
        _radioLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || requestSerial != _radioRequestSerial) {
        return;
      }

      setState(() {
        _radioLoadingMore = false;
        _radioLoadMoreError = error.toString();
      });
    }
  }

  List<RadioBrowserStation> _mergeRadioStations(
    List<RadioBrowserStation> current,
    List<RadioBrowserStation> incoming,
  ) {
    final keys = current
        .map((station) => '${station.stationUuid}|${station.streamUri}')
        .toSet();
    return <RadioBrowserStation>[
      ...current,
      ...incoming.where(
        (station) => keys.add('${station.stationUuid}|${station.streamUri}'),
      ),
    ];
  }

  List<Track> _mergeRadioTracks(List<Track> current, List<Track> incoming) {
    final ids = current.map((track) => track.id).toSet();
    return <Track>[...current, ...incoming.where((track) => ids.add(track.id))];
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

  String _radioStationSummary(RadioBrowserStation station) {
    final parts = <String>[
      if (station.countryCode.isNotEmpty) station.countryCode,
      if (station.language.isNotEmpty) station.language,
      if (station.codec.isNotEmpty) station.codec,
      if (station.bitrateKbps > 0) '${station.bitrateKbps} kbps',
    ];
    return parts.isEmpty ? 'Station details' : parts.join(' / ');
  }

  Future<void> _openRadioStation(
    BuildContext context,
    RadioBrowserStation station,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RadioBrowserStationScreen(
          station: station,
          provider: _radioProvider,
          onPlay: (track) => _playRadioStation(context, track),
          onSave: (track) => _saveRadioStation(context, track),
        ),
      ),
    );
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

class _DuplicateResolverSheet extends StatefulWidget {
  const _DuplicateResolverSheet();

  @override
  State<_DuplicateResolverSheet> createState() => _DuplicateResolverSheetState();
}

class _DuplicateResolverSheetState extends State<_DuplicateResolverSheet> {
  final Set<String> _selectedGroupKeys = <String>{};
  final Map<String, String> _keepTrackIdByGroupKey = <String, String>{};

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final groups = library.duplicateTrackGroups();
    final selectedGroups = groups
        .where((group) => _selectedGroupKeys.contains(group.key))
        .toList(growable: false);

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
                subtitle: Text(
                  selectedGroups.isEmpty
                      ? '${groups.length} duplicate group(s)'
                      : '${selectedGroups.length} group(s) selected',
                ),
                trailing: selectedGroups.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Merge selected groups',
                        icon: const Icon(Icons.merge_type_outlined),
                        onPressed: () => unawaited(
                          _mergeSelectedGroups(
                            context,
                            library,
                            selectedGroups,
                          ),
                        ),
                      ),
              ),
              const Divider(height: 1),
              if (library.canUndoDuplicateResolution)
                ListTile(
                  leading: const Icon(Icons.undo_outlined),
                  title: const Text('Undo last merge'),
                  subtitle: const Text(
                    'Restore the tracks and library state from the last duplicate merge.',
                  ),
                  onTap: () => unawaited(
                    _undoLastDuplicateResolution(context, library),
                  ),
                ),
              if (groups.isEmpty)
                const ListTile(
                  leading: Icon(Icons.check_circle_outline),
                  title: Text('No duplicate groups found'),
                )
              else
                for (final group in groups) ...<Widget>[
                  RadioGroup<String>(
                    groupValue: _keepTrackIdFor(group),
                    onChanged: (trackId) {
                      if (trackId == null) {
                        return;
                      }
                      _selectKeeper(
                        context,
                        group,
                        group.tracks.firstWhere(
                          (track) => track.id == trackId,
                        ),
                        groups,
                      );
                    },
                    child: Column(
                      children: <Widget>[
                        CheckboxListTile(
                          value: _selectedGroupKeys.contains(group.key),
                          onChanged: (selected) => _toggleGroupSelection(
                            context,
                            group,
                            groups,
                            selected ?? false,
                          ),
                          secondary: const Icon(Icons.merge_type_outlined),
                          title: Text(_duplicateMatchLabel(group.type)),
                          subtitle: Text(
                            '${group.tracks.length} matching tracks',
                          ),
                        ),
                        for (final track in group.tracks)
                          RadioListTile<String>(
                            dense: true,
                            value: track.id,
                            title: Text(track.title),
                            subtitle: Text(
                              _duplicateTrackSubtitle(track),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
                ],
            ],
          );
        },
      ),
    );
  }

  String _keepTrackIdFor(DuplicateTrackGroup group) {
    final selected = _keepTrackIdByGroupKey[group.key];
    if (selected != null && group.tracks.any((track) => track.id == selected)) {
      return selected;
    }
    return group.tracks.first.id;
  }

  void _toggleGroupSelection(
    BuildContext context,
    DuplicateTrackGroup group,
    List<DuplicateTrackGroup> groups,
    bool selected,
  ) {
    if (!selected) {
      setState(() => _selectedGroupKeys.remove(group.key));
      return;
    }

    final selectedGroups = groups.where(
      (candidate) => _selectedGroupKeys.contains(candidate.key),
    );
    final overlaps = selectedGroups.any(
      (candidate) => candidate.tracks.any(
        (candidateTrack) => group.tracks.any(
          (groupTrack) => groupTrack.id == candidateTrack.id,
        ),
      ),
    );
    if (overlaps) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review overlapping duplicate groups one at a time.'),
        ),
      );
      return;
    }

    setState(() {
      _selectedGroupKeys.add(group.key);
      _keepTrackIdByGroupKey.putIfAbsent(
        group.key,
        () => group.tracks.first.id,
      );
    });
  }

  void _selectKeeper(
    BuildContext context,
    DuplicateTrackGroup group,
    Track track,
    List<DuplicateTrackGroup> groups,
  ) {
    if (!_selectedGroupKeys.contains(group.key)) {
      _toggleGroupSelection(context, group, groups, true);
    }
    if (!_selectedGroupKeys.contains(group.key)) {
      return;
    }
    setState(() => _keepTrackIdByGroupKey[group.key] = track.id);
  }

  Future<void> _mergeSelectedGroups(
    BuildContext context,
    LibraryStore library,
    List<DuplicateTrackGroup> groups,
  ) async {
    final resolutions = groups
        .map(
          (group) {
            final keepTrackId = _keepTrackIdFor(group);
            return DuplicateTrackResolution(
              keepTrackId: keepTrackId,
              duplicateTrackIds: group.tracks
                  .where((track) => track.id != keepTrackId)
                  .map((track) => track.id),
            );
          },
        )
        .toList(growable: false);
    final removed = await library.resolveDuplicateTrackBatch(resolutions);
    if (!context.mounted) {
      return;
    }

    setState(() {
      for (final group in groups) {
        _selectedGroupKeys.remove(group.key);
        _keepTrackIdByGroupKey.remove(group.key);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Merged $removed duplicate(s) from ${groups.length} group(s).'),
      ),
    );
  }

  Future<void> _undoLastDuplicateResolution(
    BuildContext context,
    LibraryStore library,
  ) async {
    final restored = await library.undoLastDuplicateResolution();
    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? 'Restored the last duplicate merge.'
              : 'The last duplicate merge can no longer be undone.',
        ),
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
      entry.status == OfflineCacheEntryStatus.failed ||
      entry.status == OfflineCacheEntryStatus.processing;
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
            color: usesSystemAccent(accentColor)
                ? Theme.of(context).colorScheme.primary
                : seedColorForAccent(accentColor),
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

String _languagePreferenceLabel(
  AppLocalizations localizations,
  AppLanguagePreference preference,
) {
  switch (preference) {
    case AppLanguagePreference.system:
      return localizations.languageSystem;
    case AppLanguagePreference.english:
      return localizations.languageEnglish;
    case AppLanguagePreference.turkish:
      return localizations.languageTurkish;
    case AppLanguagePreference.arabic:
      return localizations.languageArabic;
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    this.onRestartOnboarding,
    this.onClearLyricsSearchCache,
    required this.lyricsSearchCacheLifetime,
    this.onLyricsSearchCacheLifetimeChanged,
  });

  final VoidCallback? onRestartOnboarding;
  final Future<void> Function()? onClearLyricsSearchCache;
  final Duration lyricsSearchCacheLifetime;
  final ValueChanged<Duration>? onLyricsSearchCacheLifetimeChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final player = context.watch<PlayerController>();
    final library = context.watch<LibraryStore>();
    // HomeScreen is also used directly by focused widget tests and embedders.
    // The app shell supplies this shared log, while those narrow surfaces can
    // remain independent of diagnostics capture.
    final diagnostics = context.watch<LocalDiagnosticLog?>();
    final folderWatcher = context.watch<LocalFolderWatchStore?>();
    final lyricsTranslation =
        context.watch<LyricsTranslationSettingsStore?>();
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
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          SwitchListTile(
            secondary: const Icon(Icons.minimize_outlined),
            title: const Text('Minimize to tray on close'),
            subtitle: const Text(
              'Keep playback running in the system tray until you choose Quit.',
            ),
            value: library.desktopMinimizeToTray,
            onChanged: (enabled) =>
                unawaited(library.setDesktopMinimizeToTray(enabled)),
          ),
        if (!kIsWeb && supportsDesktopTray(defaultTargetPlatform))
          ListTile(
            key: const Key('desktop-density-preference'),
            leading: const Icon(Icons.density_medium_outlined),
            title: const Text('Desktop density'),
            subtitle: const Text(
              'Choose how much space desktop controls and lists use.',
            ),
            trailing: DropdownButton<DesktopDensityPreference>(
              value: library.desktopDensityPreference,
              items: DesktopDensityPreference.values
                  .map(
                    (preference) => DropdownMenuItem<DesktopDensityPreference>(
                      value: preference,
                      child: Text(preference.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (preference) {
                if (preference != null) {
                  unawaited(library.setDesktopDensityPreference(preference));
                }
              },
            ),
          ),
        if (player.supportsPitch)
          ListTile(
            key: const Key('playback-pitch-setting'),
            title: const Text('Playback pitch'),
            subtitle: const Text(
              'Shifts pitch independently from playback speed on this device.',
            ),
            trailing: DropdownButton<double>(
              value: player.defaultPlaybackPitch,
              items: <DropdownMenuItem<double>>[
                for (final pitch in PlayerController.supportedPlaybackPitches)
                  DropdownMenuItem<double>(
                    value: pitch,
                    child: Text(
                      pitch == pitch.roundToDouble()
                          ? '${pitch.toStringAsFixed(0)}x'
                          : '${pitch}x',
                    ),
                  ),
              ],
              onChanged: (pitch) {
                if (pitch != null) {
                  unawaited(player.setPlaybackPitch(pitch));
                }
              },
            ),
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
        if (player.supportsSkipSilence)
          SwitchListTile(
            key: const Key('skip-silence-setting'),
            secondary: const Icon(Icons.graphic_eq_outlined),
            title: const Text('Skip silence'),
            subtitle: const Text(
              'Shortens quiet passages during playback on this device.',
            ),
            value: player.skipSilenceEnabled,
            onChanged: (enabled) =>
                unawaited(player.setSkipSilenceEnabled(enabled)),
          ),
        SwitchListTile(
          key: const Key('skip-failed-tracks-setting'),
          secondary: const Icon(Icons.skip_next_outlined),
          title: const Text('Skip failed tracks'),
          subtitle: const Text(
            'Advances through the queue when the current track cannot play.',
          ),
          value: player.skipFailedTracksEnabled,
          onChanged: (enabled) =>
              unawaited(player.setSkipFailedTracksEnabled(enabled)),
        ),
        if (lyricsTranslation != null)
          ListTile(
            key: const Key('lyrics-translation-settings'),
            leading: const Icon(Icons.translate_outlined),
            title: const Text('Lyrics translation'),
            subtitle: Text(
              lyricsTranslation.isConfigured
                  ? 'Self-hosted service: ${lyricsTranslation.endpoint!.host} to ${lyricsTranslation.targetLanguage}.'
                  : 'Configure a self-hosted LibreTranslate-compatible service.',
            ),
            onTap: () => unawaited(_configureLyricsTranslation(context)),
            trailing: lyricsTranslation.isConfigured
                ? IconButton(
                    tooltip: 'Remove lyrics translation service',
                    onPressed: () =>
                        unawaited(_removeLyricsTranslation(context)),
                    icon: const Icon(Icons.delete_outline),
                  )
                : const Icon(Icons.chevron_right),
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
        if (player.supportsCrossfade)
          ListTile(
            leading: const Icon(Icons.swap_calls_outlined),
            title: const Text('Crossfade'),
            subtitle: const Text(
              'Blends consecutive tracks when shuffle is off and duration is known.',
            ),
            trailing: DropdownButton<Duration>(
              value: player.crossfadeDuration,
              items: <DropdownMenuItem<Duration>>[
                for (final duration in PlayerController.supportedCrossfadeDurations)
                  DropdownMenuItem<Duration>(
                    value: duration,
                    child: Text(
                      duration == Duration.zero
                          ? 'Off'
                          : '${duration.inSeconds}s',
                    ),
                  ),
              ],
              onChanged: player.isSleepFadeActive
                  ? null
                  : (duration) {
                      if (duration != null) {
                        unawaited(player.setCrossfadeDuration(duration));
                      }
                    },
            ),
          ),
        if (player.supportsEqualizer ||
            player.supportsLoudnessEnhancer ||
            player.supportsVirtualizer)
          AudioEffectsSettingsTile(player: player),
        SwitchListTile(
          secondary: const Icon(Icons.graphic_eq_outlined),
          title: const Text('Loudness normalization'),
          subtitle: const Text('Use native ReplayGain tags when available.'),
          value: player.loudnessNormalizationEnabled,
          onChanged: player.isSleepFadeActive
              ? null
              : (enabled) =>
                    unawaited(player.setLoudnessNormalizationEnabled(enabled)),
        ),
        ListTile(
          leading: const Icon(Icons.album_outlined),
          title: const Text('ReplayGain source'),
          subtitle: const Text('Album gain keeps each album\'s dynamics.'),
          trailing: DropdownButton<ReplayGainMode>(
            value: player.replayGainMode,
            items: const <DropdownMenuItem<ReplayGainMode>>[
              DropdownMenuItem(
                value: ReplayGainMode.track,
                child: Text('Track'),
              ),
              DropdownMenuItem(
                value: ReplayGainMode.album,
                child: Text('Album'),
              ),
            ],
            onChanged:
                !player.loudnessNormalizationEnabled || player.isSleepFadeActive
                ? null
                : (mode) {
                    if (mode != null) {
                      unawaited(player.setReplayGainMode(mode));
                    }
                  },
          ),
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
        const Divider(),
        if (diagnostics != null)
          ListTile(
            key: const Key('local-diagnostic-log'),
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Local diagnostics'),
            subtitle: Text(
              diagnostics.entries.isEmpty
                  ? 'No reports. Nothing is sent from this device.'
                  : '${diagnostics.entries.length} local report(s). Nothing is sent automatically.',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: 'Export local diagnostics',
                  onPressed: diagnostics.entries.isEmpty
                      ? null
                      : () => unawaited(
                          _exportLocalDiagnostics(context, diagnostics),
                        ),
                  icon: const Icon(Icons.save_alt_outlined),
                ),
                IconButton(
                  tooltip: 'Clear local diagnostics',
                  onPressed: diagnostics.entries.isEmpty
                      ? null
                      : () => unawaited(
                          _clearLocalDiagnostics(context, diagnostics),
                        ),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(localizations.language),
          subtitle: Text(
            _languagePreferenceLabel(
              localizations,
              library.languagePreference,
            ),
          ),
          trailing: DropdownButton<AppLanguagePreference>(
            value: library.languagePreference,
            items: <DropdownMenuItem<AppLanguagePreference>>[
              for (final preference in AppLanguagePreference.values)
                DropdownMenuItem<AppLanguagePreference>(
                  value: preference,
                  child: Text(
                    _languagePreferenceLabel(localizations, preference),
                  ),
                ),
            ],
            onChanged: (preference) {
              if (preference != null) {
                unawaited(library.setLanguagePreference(preference));
              }
            },
          ),
        ),
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
          secondary: const Icon(Icons.favorite_outline),
          title: const Text('Use favorites in For you'),
          subtitle: const Text(
            'Let favorite tracks, artists, albums, and genres shape recommendations.',
          ),
          value: library.recommendationFavoriteSignalsEnabled,
          onChanged: (value) {
            unawaited(library.setRecommendationFavoriteSignalsEnabled(value));
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.history),
          title: const Text('Use listening history in For you'),
          subtitle: const Text(
            'Let recent plays, play counts, and unplayed status shape recommendations.',
          ),
          value: library.recommendationHistorySignalsEnabled,
          onChanged: (value) {
            unawaited(library.setRecommendationHistorySignalsEnabled(value));
          },
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
        if (!kIsWeb && supportsPlatformAudioRoutePicker(defaultTargetPlatform))
          ListTile(
            key: const Key('audio-output-picker'),
            leading: const Icon(Icons.speaker_group_outlined),
            title: const Text('Audio output'),
            subtitle: const Text(
              'Choose an available system playback route.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_showMobileAudioRoutePicker(context)),
          ),
        if (!kIsWeb && Platform.isAndroid)
          ListTile(
            key: const Key('android-pinned-shortcut'),
            leading: const Icon(Icons.push_pin_outlined),
            title: const Text('Pin playback shortcut'),
            trailing: PopupMenuButton<AndroidPinnedShortcut>(
              key: const Key('android-pinned-shortcut-menu'),
              tooltip: 'Choose a playback shortcut to pin',
              icon: const Icon(Icons.add),
              onSelected: (shortcut) => unawaited(
                _requestAndroidPinnedShortcut(context, shortcut),
              ),
              itemBuilder: (context) => <PopupMenuEntry<AndroidPinnedShortcut>>[
                for (final shortcut in AndroidPinnedShortcut.values)
                  PopupMenuItem<AndroidPinnedShortcut>(
                    value: shortcut,
                    child: Text(shortcut.label),
                  ),
              ],
            ),
          ),
        ListTile(
          leading: const Icon(Icons.lyrics_outlined),
          title: const Text('Cached lyrics searches'),
          subtitle: const Text(
            'Clear stored LRCLIB search results from this device.',
          ),
          trailing: IconButton(
            tooltip: 'Clear cached lyrics searches',
            onPressed: onClearLyricsSearchCache == null
                ? null
                : () => unawaited(onClearLyricsSearchCache!()),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Lyrics cache retention'),
          subtitle: const Text('How long cached searches remain available offline.'),
          trailing: DropdownButton<Duration>(
            value: lyricsSearchCacheLifetime,
            items: <DropdownMenuItem<Duration>>[
              for (final retention in supportedLyricsSearchCacheLifetimes)
                DropdownMenuItem<Duration>(
                  value: retention,
                  child: Text('${retention.inDays} day(s)'),
                ),
            ],
            onChanged: onLyricsSearchCacheLifetimeChanged == null
                ? null
                : (retention) {
                    if (retention != null) {
                      onLyricsSearchCacheLifetimeChanged!(retention);
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
                      : entry.status == OfflineCacheEntryStatus.processing
                          ? 'Pause active offline request'
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
        SwitchListTile.adaptive(
          secondary: const Icon(Icons.screenshot_monitor_outlined),
          title: const Text('Block screenshots'),
          subtitle: const Text('Prevent screenshots and screen recording on Android.'),
          value: library.screenshotProtectionEnabled,
          onChanged: library.loaded
              ? (enabled) => unawaited(
                  library.setScreenshotProtectionEnabled(enabled),
                )
              : null,
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
      final cancellationToken = OfflineCacheCancellationRegistry.instance
          .tokenFor(entry.id);
      final processingEntry = library.offlineCacheEntryById(entry.id) ?? entry;

      try {
        final resolvedTrack = await selfHosted.resolveTrack(
          processingEntry.track,
        );
        cancellationToken.throwIfCancelled();
        final materialization = await manager.materialize(
          processingEntry.copyWith(track: resolvedTrack),
          cancellationToken: cancellationToken,
        );
        if (library.offlineCacheEntryById(entry.id)?.status !=
            OfflineCacheEntryStatus.processing) {
          continue;
        }
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
      } on OfflineCacheCancelled {
        // The Options control has already persisted the paused state.
      } on Object catch (error) {
        if (library.offlineCacheEntryById(entry.id)?.status ==
            OfflineCacheEntryStatus.paused) {
          continue;
        }
        await library.markOfflineCacheEntryFailed(
          entry.id,
          reason: _offlineCacheErrorMessage(error),
        );
        failed += 1;
      } finally {
        OfflineCacheCancellationRegistry.instance.release(
          entry.id,
          cancellationToken,
        );
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
