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
import '../data/android_audio_library_access.dart';
import '../data/android_system_downloads_exporter.dart';
import '../data/audius_provider.dart';
import '../data/file_picker_adapter.dart';
import '../data/flac_vorbis_comment_writer.dart';
import '../data/internet_archive_provider.dart';
import '../data/itunes_metadata_provider.dart';
import '../data/itunes_metadata_settings_store.dart';
import '../data/jamendo_chart_cache.dart';
import '../data/jamendo_settings_store.dart';
import '../data/jamendo_provider.dart';
import '../data/itunes_podcast_directory.dart';
import '../data/jellyfin_provider.dart';
import '../data/library_store.dart';
import '../data/library_sync_client.dart';
import '../data/library_sync_store.dart';
import '../data/listenbrainz_scrobbling_store.dart';
import '../data/local_diagnostic_log.dart';
import '../data/local_folder_watch_store.dart';
import '../data/local_library_provider.dart';
import '../data/local_media_uri.dart';
import '../data/local_folder_scanner.dart';
import '../data/lrclib_lyrics_provider.dart';
import '../data/lyrics_batch_matcher.dart';
import '../data/lyrics_search_endpoint_settings_store.dart';
import '../data/lyrics_translation_settings_store.dart';
import '../data/m4a_metadata_writer.dart';
import '../data/musicbrainz_metadata_provider.dart';
import '../data/musicbrainz_artist_release_provider.dart';
import '../data/mp3_id3v1_tag_writer.dart';
import '../data/ogg_vorbis_comment_writer.dart';
import '../data/offline_cache_manager.dart';
import '../data/offline_cache_pressure_enforcer.dart';
import '../data/podcast_rss_provider.dart';
import '../data/podcast_chapter_host_policy.dart';
import '../data/podcast_subscription_refresh_worker.dart';
import '../data/playlist_artwork_file_store.dart';
import '../data/radio_browser_provider.dart';
import '../data/self_hosted_provider_store.dart';
import '../data/saf_tree_scanner.dart';
import '../data/shared_smart_playlist_store.dart';
import '../data/sponsorblock_segment_provider.dart';
import '../data/spotify_metadata_provider.dart';
import '../data/spotify_settings_store.dart';
import '../data/subsonic_provider.dart';
import '../data/track_artwork_file_store.dart';
import '../data/wav_riff_info_writer.dart';
import '../data/youtube_channel_follow_store.dart';
import '../data/youtube_followed_channel_feed.dart';
import '../data/youtube_followed_channel_feed_store.dart';
import '../data/youtube_account_settings_store.dart';
import '../data/youtube_account_provider.dart';
import '../data/youtube_data_settings_store.dart';
import '../data/youtube_data_metadata_provider.dart';
import '../domain/backup_file_document.dart';
import '../domain/artwork_crop.dart';
import '../domain/custom_catalog_definition.dart';
import '../domain/desktop_tray_action.dart';
import '../domain/lyrics_document.dart';
import '../domain/legal_video_source.dart';
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
import '../domain/track_chapter.dart';
import '../domain/track_lyrics.dart';
import '../player/offline_playback_policy.dart';
import '../player/android_pinned_shortcut_bridge.dart';
import '../player/player_controller.dart';
import 'library_stats_charts.dart';
import 'library_stats_sections.dart';
import 'now_playing_screen.dart';
import 'offline_cache_maintenance_dialog.dart';
import 'desktop_audio_output_settings.dart';
import 'desktop_navigation_shortcuts.dart';
import 'internet_archive_item_screen.dart';
import 'internet_archive_collection_screen.dart';
import 'platform_audio_route_picker.dart';
import 'platform_image_share.dart';
import 'platform_text_share.dart';
import 'radio_browser_station_screen.dart';
import 'responsive_layout.dart';
import 'self_hosted_browse_screen.dart';
import 'video_playback_screen.dart';
import 'spotify_saved_tracks_screen.dart';
import 'spotify_saved_albums_screen.dart';
import 'spotify_saved_playlists_screen.dart';
import 'spotify_saved_shows_screen.dart';
import 'spotify_recently_played_screen.dart';
import 'spotify_top_artists_screen.dart';
import 'youtube_music_chart_screen.dart';
import 'youtube_channel_follow_screen.dart';
import 'youtube_followed_channel_feed_screen.dart';
import 'youtube_account_library_screen.dart';
import 'youtube_public_playlists_screen.dart';
import 'theme_colors.dart';
import 'widgets/listening_recap_card.dart';
import 'widgets/musicbrainz_metadata_search_sheet.dart';
import 'widgets/artist_release_updates_shelf.dart';
import 'widgets/artwork_crop_editor.dart';
import 'widgets/audio_effects_settings.dart';
import 'widgets/collection_share_card.dart';
import 'widgets/listening_heatmap.dart';
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

part 'home_screen_home_tab.dart';
part 'home_screen_playlists.dart';
part 'home_screen_sources.dart';
part 'home_screen_history.dart';
part 'home_screen_library.dart';
part 'home_screen_settings.dart';
part 'home_screen_lyrics.dart';
part 'home_screen_queue.dart';

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

Future<void> _configureListenBrainz(BuildContext context) async {
  final store = context.read<ListenBrainzScrobblingStore?>();
  if (store == null) {
    return;
  }
  final tokenController = TextEditingController();
  String? validationError;
  try {
    final token = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Connect ListenBrainz'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'AetherTune sends the artist, track title, optional album, duration, and playback-start time to api.listenbrainz.org only after you have listened to at least half a track or four minutes, whichever comes first. Your token stays in this device\'s credential vault and is never included in backups.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('listenbrainz-token'),
                      controller: tokenController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'ListenBrainz user token',
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isEmpty) {
                          setDialogState(
                            () => validationError =
                                'Enter a ListenBrainz user token.',
                          );
                          return;
                        }
                        Navigator.of(dialogContext).pop(value);
                      },
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
                  final value = tokenController.text.trim();
                  if (value.isEmpty) {
                    setDialogState(
                      () =>
                          validationError = 'Enter a ListenBrainz user token.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Connect'),
              ),
            ],
          );
        },
      ),
    );
    if (!context.mounted || token == null) {
      return;
    }
    await store.configure(token);
    if (!context.mounted) {
      return;
    }
    final account = store.userName;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          account == null
              ? 'ListenBrainz scrobbling enabled.'
              : 'ListenBrainz scrobbling enabled for $account.',
        ),
      ),
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not connect ListenBrainz. Check the user token.',
          ),
        ),
      );
    }
  } finally {
    tokenController.dispose();
  }
}

Future<void> _removeListenBrainz(BuildContext context) async {
  final store = context.read<ListenBrainzScrobblingStore?>();
  if (store == null || !store.isConfigured) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Disconnect ListenBrainz?'),
      content: const Text(
        'This removes the ListenBrainz user token from this device and stops future submissions. Existing ListenBrainz listens and local history stay unchanged.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Disconnect'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) {
    return;
  }
  try {
    await store.remove();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ListenBrainz disconnected.')),
      );
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            store.isConfigured
                ? 'Could not disconnect ListenBrainz.'
                : 'ListenBrainz disconnected, but local retry data could not be removed.',
          ),
        ),
      );
    }
  }
}

Future<void> _showDesktopAudioOutputSettings(BuildContext context) async {
  final opened = await openDesktopAudioOutputSettings();
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Windows Sound settings could not be opened.'),
      ),
    );
  }
}

Future<void> _retryListenBrainzPending(BuildContext context) async {
  final store = context.read<ListenBrainzScrobblingStore?>();
  if (store == null || !store.isConfigured || store.pendingListenCount == 0) {
    return;
  }
  final submitted = await store.retryPendingListens();
  if (!context.mounted) {
    return;
  }
  final remaining = store.pendingListenCount;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        remaining == 0
            ? 'Submitted $submitted pending ListenBrainz listen${submitted == 1 ? '' : 's'}.'
            : 'Submitted $submitted listen${submitted == 1 ? '' : 's'}; $remaining still pending.',
      ),
    ),
  );
}

Future<void> _setListenBrainzBackgroundRetry(
  BuildContext context,
  bool enabled,
) async {
  final store = context.read<ListenBrainzScrobblingStore?>();
  if (store == null || !store.isConfigured) {
    return;
  }
  try {
    await store.setBackgroundRetryEnabled(enabled);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Pending ListenBrainz listens can retry in Android and iOS background passes.'
              : 'Background ListenBrainz retries disabled.',
        ),
      ),
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update ListenBrainz background retries.'),
        ),
      );
    }
  }
}

Future<void> _importListenBrainzHistory(BuildContext context) async {
  final store = context.read<ListenBrainzScrobblingStore?>();
  final library = context.read<LibraryStore>();
  if (store == null || !store.isConfigured) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Import ListenBrainz history?'),
      content: const Text(
        'AetherTune will request your 100 most recent ListenBrainz listens using the token stored in this device\'s credential vault. It reads each title, artist, optional album, and timestamp, then adds only exact, unambiguous matches for tracks already in this library. Unmatched and duplicate listens are skipped.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) {
    return;
  }

  try {
    final remoteEntries = await store.fetchListenHistory();
    final result = await library.importPlaybackHistory(
      remoteEntries.map(
        (entry) => PlaybackHistoryImportEntry(
          title: entry.title,
          artist: entry.artist,
          album: entry.album,
          playedAt: entry.listenedAt,
        ),
      ),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.imported == 0
              ? 'No new matching ListenBrainz listens were imported.'
              : 'Imported ${result.imported} ListenBrainz listen${result.imported == 1 ? '' : 's'} from ${result.matched} match${result.matched == 1 ? '' : 'es'}.',
        ),
      ),
    );
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not import ListenBrainz history.')),
      );
    }
  }
}

Future<void> _configureLyricsTranslation(BuildContext context) async {
  final store = context.read<LyricsTranslationSettingsStore?>();
  if (store == null) {
    return;
  }
  final localizations = AppLocalizations.of(context)!;
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
                    decoration: InputDecoration(
                      labelText: localizations.targetLanguage,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save lyrics translation settings.'),
        ),
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
  try {
    await store.remove();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lyrics translation service removed.')),
      );
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove lyrics translation settings.'),
        ),
      );
    }
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
final _musicBrainzMetadataProvider = MusicBrainzMetadataProvider();
final _itunesMetadataProvider = ItunesMetadataProvider();
const _platformTextShareService = SharePlusTextShareService();

List<NavigationDestination> _navigationBarDestinations(
  AppLocalizations localizations,
) {
  return _aetherTuneNavigationDestinations
      .map((destination) {
        return NavigationDestination(
          icon: Icon(destination.icon),
          selectedIcon: Icon(destination.selectedIcon),
          label: destination.label(localizations),
        );
      })
      .toList(growable: false);
}

List<NavigationRailDestination> _navigationRailDestinations(
  AppLocalizations localizations,
) {
  return _aetherTuneNavigationDestinations
      .map((destination) {
        return NavigationRailDestination(
          icon: Icon(destination.icon),
          selectedIcon: Icon(destination.selectedIcon),
          label: Text(destination.label(localizations)),
        );
      })
      .toList(growable: false);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.initialTab = 0,
    this.initialImportAudio = false,
    this.onRestartOnboarding,
    this.internetArchiveProvider,
    this.radioBrowserProvider,
    this.podcastDirectory,
    this.podcastProviderFactory,
    this.providerSearchProviders,
  }) : assert(
         initialTab >= 0 && initialTab < _aetherTuneNavigationDestinationCount,
       );

  final int initialTab;
  final bool initialImportAudio;
  final VoidCallback? onRestartOnboarding;
  final InternetArchiveProvider? internetArchiveProvider;
  final RadioBrowserProvider? radioBrowserProvider;
  final ItunesPodcastDirectory? podcastDirectory;
  final PodcastRssProvider Function(Uri feedUri)? podcastProviderFactory;
  final List<MusicSourceProvider>? providerSearchProviders;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  late final RadioBrowserProvider _radioClickProvider;
  final _lyricsCacheSettings = LyricsSearchCacheSettingsStore();
  late int _tabIndex;
  bool _favoritesOnly = false;
  bool _offlineLibraryOnly = false;
  String _query = '';
  LibrarySortMode _librarySortMode = LibrarySortMode.recentlyAdded;
  PlayerController? _historyPlayer;
  LibraryStore? _historyLibrary;
  ListenBrainzScrobblingStore? _historyListenBrainz;
  StreamSubscription<Duration>? _progressSub;
  String? _lastProgressTrackId;
  String? _listenBrainzTrackId;
  DateTime? _listenBrainzStartedAt;
  Duration _lastRecordedProgressPosition = Duration.zero;
  int _lastRecordedPlaybackSerial = 0;
  double? _desktopQueuePaneDragWidth;
  Duration _lyricsSearchCacheLifetime = defaultLyricsSearchCacheLifetime;
  bool _isRefreshingLocalMetadata = false;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTab;
    _radioClickProvider = widget.radioBrowserProvider ?? RadioBrowserProvider();
    unawaited(_loadLyricsSearchCacheLifetime());
    if (widget.initialImportAudio) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_importAudio(context));
        }
      });
    }
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
    _historyListenBrainz = context.read<ListenBrainzScrobblingStore?>();
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
    _listenBrainzTrackId = track.id;
    _listenBrainzStartedAt = DateTime.now();
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
    if (player == null || library == null || track == null) {
      return;
    }

    final startedAt = _listenBrainzTrackId == track.id
        ? _listenBrainzStartedAt
        : null;
    final scrobbling = _historyListenBrainz;
    if (!library.pauseListeningHistory &&
        !library.offlineModeEnabled &&
        scrobbling != null &&
        startedAt != null) {
      unawaited(
        scrobbling.submitIfEligible(
          track: track,
          startedAt: startedAt,
          position: position,
        ),
      );
    }

    if (!isLongFormProgressTrack(track)) {
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
      await _lyricsProviderFor(context).clearCachedSearchResults();
    } on Object {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not clear cached lyrics searches.'),
        ),
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
    setState(() => _lyricsSearchCacheLifetime = retention);
  }

  LrcLibLyricsProvider _lyricsProviderFor(BuildContext context) {
    final endpoint = context
        .read<LyricsSearchEndpointSettingsStore?>()
        ?.endpoint;
    return LrcLibLyricsProvider(
      baseUri: endpoint,
      cacheLifetime: _lyricsSearchCacheLifetime,
    );
  }

  Future<void> _uploadLyricsSearchEndpointToSync(BuildContext context) async {
    final endpointSettings = context.read<LyricsSearchEndpointSettingsStore>();
    if (!endpointSettings.isConfigured) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final document = endpointSettings.exportConfiguration();
      final remote = await context
          .read<LibrarySyncStore>()
          .updateProviderConfiguration(
            context.read<LibraryStore>(),
            (remoteSnapshot) =>
                _lyricsSearchProviderSnapshot(remoteSnapshot, document),
          );
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Lyrics search service uploaded at provider revision ${remote.revision}.',
          ),
        ),
      );
    } on LibrarySyncConflictException {
      if (context.mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Provider settings changed remotely. Import them before uploading again.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not upload lyrics search service: $error'),
          ),
        );
      }
    }
  }

  Future<void> _importLyricsSearchEndpointFromSync(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final remote = await context
          .read<LibrarySyncStore>()
          .fetchProviderConfiguration(context.read<LibraryStore>());
      if (!context.mounted) {
        return;
      }
      final snapshot = remote.snapshot;
      if (snapshot == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No provider configuration is stored on this sync server.',
            ),
          ),
        );
        return;
      }
      _validateLyricsSearchProviderSnapshot(snapshot);
      final document = snapshot['lyricsSearchEndpoint'];
      if (document is! Map) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No lyrics search service is stored on this sync server.',
            ),
          ),
        );
        return;
      }
      await context
          .read<LyricsSearchEndpointSettingsStore>()
          .importConfiguration(Map<String, Object?>.from(document));
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Lyrics search service imported from provider revision ${remote.revision}.',
          ),
        ),
      );
    } on Object catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Could not import lyrics search service: $error'),
          ),
        );
      }
    }
  }

  Map<String, Object?> _lyricsSearchProviderSnapshot(
    Map<String, Object?>? remoteSnapshot,
    Map<String, Object?> document,
  ) {
    final root = Map<String, Object?>.from(
      remoteSnapshot ??
          const <String, Object?>{
            'format': 'aethertune.provider_configurations',
            'version': 1,
          },
    );
    if (remoteSnapshot != null) {
      _validateLyricsSearchProviderSnapshot(root);
    }
    return <String, Object?>{...root, 'lyricsSearchEndpoint': document};
  }

  void _validateLyricsSearchProviderSnapshot(Map<String, Object?> snapshot) {
    const allowedKeys = <String>{
      'format',
      'version',
      'customCatalogs',
      'selfHostedAccounts',
      'lyricsSearchEndpoint',
    };
    if (snapshot.keys.any((key) => !allowedKeys.contains(key)) ||
        snapshot['format'] != 'aethertune.provider_configurations' ||
        snapshot['version'] != 1 ||
        (snapshot['customCatalogs'] == null &&
            snapshot['selfHostedAccounts'] == null &&
            snapshot['lyricsSearchEndpoint'] == null)) {
      throw const FormatException('Remote provider configuration is invalid.');
    }
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
    final sleepTimerActive = context.select<PlayerController, bool>(
      (player) =>
          player.sleepTimerRemaining != null || player.stopAtEndOfTrackEnabled,
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
                onAddToPlaylist: (track) => _showAddToPlaylist(context, track),
                onLyrics: (track) => _showLyricsEditor(context, track),
                internetArchiveProvider: widget.internetArchiveProvider,
                radioBrowserProvider: widget.radioBrowserProvider,
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
                onAddToPlaylist: (track) => _showAddToPlaylist(context, track),
                onLyrics: (track) => _showLyricsEditor(context, track),
                onBatchLyrics: (tracks) =>
                    unawaited(_matchMissingLyrics(context, tracks)),
              ),
              _PlaylistsTab(
                onAddToPlaylist: (track) => _showAddToPlaylist(context, track),
                onLyrics: (track) => _showLyricsEditor(context, track),
              ),
              const _HistoryTab(),
              _SourcesTab(
                archiveProvider: widget.internetArchiveProvider,
                podcastDirectory: widget.podcastDirectory,
                podcastProviderFactory: widget.podcastProviderFactory,
                providerSearchProviders: widget.providerSearchProviders,
              ),
              _SettingsTab(
                onRestartOnboarding: widget.onRestartOnboarding,
                isRefreshingLocalMetadata: _isRefreshingLocalMetadata,
                onRefreshLocalMetadata: _refreshLocalLibraryMetadata,
                onClearLyricsSearchCache: () =>
                    _clearLyricsSearchCache(context),
                onUploadLyricsSearchEndpointToSync: () =>
                    _uploadLyricsSearchEndpointToSync(context),
                onImportLyricsSearchEndpointFromSync: () =>
                    _importLyricsSearchEndpointFromSync(context),
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
            tooltip: sleepTimerActive
                ? localizations.sleepTimerActive
                : localizations.sleepTimer,
            onPressed: () => _showSleepTimer(context),
            icon: Icon(sleepTimerActive ? Icons.timer : Icons.bedtime_outlined),
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
                        ? 'Search cached ${_lyricsProviderFor(context).name} results'
                        : 'Search ${_lyricsProviderFor(context).name}',
                    child: TextButton.icon(
                      onPressed: () async {
                        final selected = await showLyricsSearchSheet(
                          dialogContext,
                          track: track,
                          provider: _lyricsProviderFor(context),
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
                      onPressed: () => Navigator.of(
                        dialogContext,
                      ).pop(const _LyricsEditorResult(plainText: '')),
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
    final file = await pickSingleFile(
      allowedExtensions: supportedLyricsDocumentExtensions,
      dialogTitle: 'Import lyrics file',
      type: FileType.custom,
    );

    if (!context.mounted || file == null) {
      return null;
    }

    if (!isSupportedLyricsDocumentName(file.name)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Choose a .txt, .lrc, or .ttml lyrics file.'),
        ),
      );
      return null;
    }

    try {
      final bytes = await readPickedFileBytes(file);
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

  Future<void> _createPlaylist(BuildContext context, {Track? seedTrack}) async {
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
    final translationSettings = context.read<LyricsTranslationSettingsStore?>();
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
          library: library,
          player: player,
          translator: translationSettings?.translator,
          translationTargetLanguage:
              translationSettings?.targetLanguage ?? 'en',
          onEdit: () {
            Navigator.of(sheetContext).pop();
            unawaited(_showLyricsEditor(context, track));
          },
          onShare: () =>
              unawaited(_copyLyricsShareText(context, library, track)),
          onShareRange: () => unawaited(
            _copyLyricsSelectedRangeShareText(context, library, track),
          ),
          onAdjustTiming: () =>
              unawaited(_showLyricsTimingAdjustment(context, library, track)),
          onSearch: () => unawaited(
            _showLyricsSearch(
              context,
              track: track,
              lyrics: library.lyricsForTrack(track.id),
              player: player,
            ),
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
              decoration: const InputDecoration(labelText: 'Playlist name'),
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
    final scanningSelectedAudio = AppLocalizations.of(
      context,
    )!.scanningSelectedAudio;

    final files = await FilePicker.pickFiles(type: FileType.audio);

    if (files.isEmpty) {
      return;
    }

    final filePaths = files
        .map((file) => file.path)
        .whereType<String>()
        .toList(growable: false);
    if (filePaths.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No readable audio files selected.')),
      );
      return;
    }

    final progress = _showLocalImportProgress(messenger, scanningSelectedAudio);
    try {
      final scanResult = await scanLocalFilesInBackground(
        filePaths,
        importedAt: DateTime.now(),
        onProgress: progress.update,
      );
      await _addScannedTracksToLibrary(library, scanResult);

      if (!context.mounted) {
        progress.dismiss();
        return;
      }
      progress.dismiss();
      messenger.showSnackBar(
        SnackBar(content: Text(_selectedFilesImportSummary(scanResult))),
      );
    } on Object catch (error) {
      progress.dismiss();
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_folderImportErrorMessage(error))),
      );
    }
  }

  Future<void> _importAudioFolder(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    final folderPath = Platform.isAndroid
        ? await _selectAndroidAudioTree(context)
        : await FilePicker.getDirectoryPath(dialogTitle: 'Import audio folder');
    if (!context.mounted || folderPath == null) {
      return;
    }

    final progress = _showLocalImportProgress(
      messenger,
      AppLocalizations.of(context)!.scanningAudioFolder,
    );
    try {
      final scanResult = await scanLocalFolderWithSafSupportInBackground(
        folderPath,
        importedAt: DateTime.now(),
        onProgress: progress.update,
      );
      await _addScannedTracksToLibrary(library, scanResult);
      await library.watchLocalFolder(folderPath);

      if (!context.mounted) {
        progress.dismiss();
        return;
      }

      progress.dismiss();
      messenger.showSnackBar(
        SnackBar(content: Text(_folderImportSummary(scanResult))),
      );
    } on Object catch (error) {
      progress.dismiss();
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text(_folderImportErrorMessage(error))),
      );
    }
  }

  Future<void> _matchMissingLyrics(
    BuildContext context,
    List<Track> tracks,
  ) async {
    final library = context.read<LibraryStore>();
    if (library.offlineModeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Turn off Offline mode before searching for lyrics.'),
        ),
      );
      return;
    }
    final candidates = tracks
        .where(
          (track) =>
              library.lyricsForTrack(track.id) == null &&
              track.title.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No missing lyrics in these results.')),
      );
      return;
    }

    final provider = _lyricsProviderFor(context);
    final disclosure = provider.disclosure;
    final searchCount = candidates.length > LyricsBatchMatcher.maxTracksPerBatch
        ? LyricsBatchMatcher.maxTracksPerBatch
        : candidates.length;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Find missing lyrics?'),
        content: Text(
          'AetherTune will search ${provider.name} for up to '
          '$searchCount tracks. It sends ${disclosure.dataSent.join(', ')} '
          'to ${disclosure.networkSummary}. Only one exact title and artist '
          'match with a compatible duration is saved. Existing lyrics, '
          'ambiguous matches, and instrumental results stay untouched.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    if (!context.mounted || approved != true) {
      return;
    }

    final report = await LyricsBatchMatcher(provider).match(candidates);
    var applied = 0;
    var skippedExisting = 0;
    for (final outcome in report.matches) {
      final result = outcome.result!;
      if (library.lyricsForTrack(outcome.track.id) != null) {
        skippedExisting += 1;
        continue;
      }
      await library.setLyricsIfAbsent(
        outcome.track.id,
        result.preferredLyrics!,
        sourceId: result.providerId,
        sourceName: result.providerName,
        sourceExternalId: result.externalId,
        sourceUri: result.sourceUri,
      );
      applied += 1;
    }
    if (!context.mounted) {
      return;
    }
    final summary = <String>[
      'Added lyrics to $applied ${applied == 1 ? 'track' : 'tracks'}',
      if (report.unmatchedCount > 0) '${report.unmatchedCount} unmatched',
      if (report.failedCount > 0) '${report.failedCount} failed',
      if (skippedExisting > 0) '$skippedExisting kept existing',
      if (report.wasLimited)
        'first ${LyricsBatchMatcher.maxTracksPerBatch} searched',
    ].join('; ');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(summary)));
  }

  Future<String?> _selectAndroidAudioTree(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose an audio folder'),
        content: const Text(
          'Android will open its folder picker. AetherTune keeps read access only to the folder you choose, so it can refresh your audio files and matching lyric or chapter sidecars later. Individual-file imports remain separate.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Choose folder'),
          ),
        ],
      ),
    );
    if (!context.mounted || approved != true) {
      return null;
    }
    final treeUri = await AndroidAudioLibraryAccess.selectPersistedAudioTree();
    if (!context.mounted || treeUri != null) {
      return treeUri;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Android folder access was not selected. You can still import individual files instead.',
        ),
      ),
    );
    return null;
  }

  Future<void> _refreshLocalLibraryMetadata() async {
    if (_isRefreshingLocalMetadata) {
      return;
    }

    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final localFilePaths = library.tracks
        .where(
          (track) =>
              track.sourceId == 'local' &&
              track.localPath != null &&
              track.localPath!.isNotEmpty,
        )
        .map((track) => track.localPath!)
        .where((localPath) => !isContentMediaUri(localPath))
        .toList(growable: false);
    final safRoots = library.watchedLocalFolderPaths
        .where(isContentMediaUri)
        .toList(growable: false);
    if (localFilePaths.isEmpty && safRoots.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No local audio files are available to refresh.'),
        ),
      );
      return;
    }

    setState(() => _isRefreshingLocalMetadata = true);
    final progress = _showLocalImportProgress(
      messenger,
      'Refreshing local audio metadata...',
    );
    try {
      final scanResults = <LocalFolderScanResult>[];
      if (localFilePaths.isNotEmpty) {
        scanResults.add(
          await scanLocalFilesInBackground(
            localFilePaths,
            importedAt: DateTime.now(),
            onProgress: progress.update,
          ),
        );
      }
      for (final safRoot in safRoots) {
        scanResults.add(
          await scanLocalFolderWithSafSupportInBackground(
            safRoot,
            importedAt: DateTime.now(),
            onProgress: progress.update,
          ),
        );
      }
      final scanResult = _mergeLocalFolderScanResults(scanResults);
      await library.reconcileLocalTracks(
        scanResult.tracks,
        sidecarLyricsByTrackId: scanResult.sidecarLyricsByTrackId,
        embeddedLyricsByTrackId: scanResult.embeddedLyricsByTrackId,
        sidecarChaptersByTrackId: scanResult.sidecarChaptersByTrackId,
      );

      if (!mounted) {
        progress.dismiss();
        return;
      }
      progress.dismiss();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            scanResult.tracks.isEmpty
                ? 'No readable local audio files were refreshed.'
                : 'Refreshed metadata for ${scanResult.tracks.length} local audio file(s).',
          ),
        ),
      );
    } on Object catch (error) {
      progress.dismiss();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_folderImportErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _isRefreshingLocalMetadata = false);
      }
    }
  }

  Future<void> _showSleepTimer(BuildContext context) async {
    final player = context.read<PlayerController>();
    final localizations = AppLocalizations.of(context)!;
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
            final remaining = player.sleepTimerRemaining;
            final stopAtEndOfTrack = player.stopAtEndOfTrackEnabled;
            final hasActiveTimer = remaining != null || stopAtEndOfTrack;
            return SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  if (stopAtEndOfTrack)
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(localizations.sleepTimerActive),
                      subtitle: Text(localizations.sleepTimerStopsAtEnd),
                    )
                  else if (remaining != null)
                    ListTile(
                      leading: const Icon(Icons.timer_outlined),
                      title: Text(localizations.sleepTimerActive),
                      subtitle: Text(
                        localizations.sleepTimerStopsIn(
                          formatSleepTimerRemaining(
                            remaining,
                            lessThanOneMinute:
                                localizations.sleepTimerLessThanOneMinute,
                            minutesLabel: localizations.sleepTimerMinutes,
                            hoursLabel: localizations.sleepTimerHours,
                          ),
                        ),
                      ),
                    ),
                  if (hasActiveTimer) const Divider(height: 1),
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
                    enabled: hasActiveTimer,
                    onTap: hasActiveTimer
                        ? () {
                            player.cancelSleepTimer();
                            Navigator.of(sheetContext).pop();
                          }
                        : null,
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
                    errorText =
                        'Enter a whole number from '
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
                    helperText:
                        '$minCustomSleepTimerMinutes to '
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
    required this.albumArtist,
    required this.year,
    required this.trackNumber,
    required this.genre,
  });

  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int? year;
  final int? trackNumber;
  final String genre;
}

Future<void> _showTrackMetadataEditor(BuildContext context, Track track) async {
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
    albumArtist: draft.albumArtist,
    clearAlbumArtist: draft.albumArtist.trim().isEmpty,
    year: draft.year,
    clearYear: draft.year == null,
    trackNumber: draft.trackNumber,
    clearTrackNumber: draft.trackNumber == null,
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
            albumArtist: updated.albumArtist,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        } else if (_isLocalFlac(updated)) {
          await const FlacVorbisCommentWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        } else if (_isLocalM4aM4bM4rOrAlac(updated)) {
          await const M4aMetadataWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist ?? '',
            year: updated.year ?? 0,
            trackNumber: updated.trackNumber ?? 0,
            genre: updated.genre,
          );
        } else if (_isLocalOggOrOpus(updated)) {
          await const OggVorbisCommentWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        } else {
          await const WavRiffInfoWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Saved app metadata, but could not update embedded tags: $error',
              ),
            ),
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
  final library = context.read<LibraryStore>();
  final titleController = TextEditingController(text: track.title);
  final artistController = TextEditingController(text: track.artist);
  final albumController = TextEditingController(text: track.album);
  final albumArtistController = TextEditingController(
    text: track.albumArtist ?? '',
  );
  final yearController = TextEditingController(
    text: track.year?.toString() ?? '',
  );
  final trackNumberController = TextEditingController(
    text: track.trackNumber?.toString() ?? '',
  );
  final genreController = TextEditingController(text: track.genre);
  String? titleErrorText;
  String? yearErrorText;
  String? trackNumberErrorText;

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

              final yearText = yearController.text.trim();
              final year = yearText.isEmpty ? null : int.tryParse(yearText);
              final trackNumberText = trackNumberController.text.trim();
              final trackNumber = trackNumberText.isEmpty
                  ? null
                  : int.tryParse(trackNumberText);
              if ((yearText.isNotEmpty &&
                      (year == null || year < 1000 || year > 9999)) ||
                  (trackNumberText.isNotEmpty &&
                      (trackNumber == null || trackNumber <= 0))) {
                setDialogState(() {
                  yearErrorText =
                      yearText.isNotEmpty &&
                          (year == null || year < 1000 || year > 9999)
                      ? 'Use a four-digit year'
                      : null;
                  trackNumberErrorText =
                      trackNumberText.isNotEmpty &&
                          (trackNumber == null || trackNumber <= 0)
                      ? 'Use a positive whole number'
                      : null;
                });
                return;
              }

              Navigator.of(dialogContext).pop(
                _TrackMetadataDraft(
                  title: title,
                  artist: artistController.text,
                  album: albumController.text,
                  albumArtist: albumArtistController.text,
                  year: year,
                  trackNumber: trackNumber,
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
                        controller: albumArtistController,
                        decoration: const InputDecoration(
                          labelText: 'Album artist',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: yearController,
                        decoration: InputDecoration(
                          errorText: yearErrorText,
                          labelText: 'Release year',
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (yearErrorText != null) {
                            setDialogState(() {
                              yearErrorText = null;
                            });
                          }
                        },
                      ),
                      TextField(
                        controller: trackNumberController,
                        decoration: InputDecoration(
                          errorText: trackNumberErrorText,
                          labelText: 'Track number',
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (trackNumberErrorText != null) {
                            setDialogState(() {
                              trackNumberErrorText = null;
                            });
                          }
                        },
                      ),
                      TextField(
                        controller: genreController,
                        decoration: const InputDecoration(labelText: 'Genre'),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('track-metadata-find-musicbrainz'),
                          onPressed: library.offlineModeEnabled
                              ? null
                              : () async {
                                  final candidate =
                                      await showMusicBrainzMetadataSearchSheet(
                                        dialogContext,
                                        track: Track(
                                          id: track.id,
                                          title: titleController.text,
                                          artist: artistController.text,
                                          album: albumController.text,
                                          genre: genreController.text,
                                          duration: track.duration,
                                        ),
                                        provider: _musicBrainzMetadataProvider,
                                        offlineModeEnabled:
                                            library.offlineModeEnabled,
                                      );
                                  if (candidate == null ||
                                      !dialogContext.mounted) {
                                    return;
                                  }
                                  setDialogState(() {
                                    titleController.text = candidate.title;
                                    artistController.text = candidate.artist;
                                    albumController.text = candidate.album;
                                    if (candidate.genre.isNotEmpty) {
                                      genreController.text = candidate.genre;
                                    }
                                    titleErrorText = null;
                                  });
                                },
                          icon: const Icon(Icons.manage_search_outlined),
                          label: const Text('Find metadata'),
                        ),
                      ),
                      if (library.offlineModeEnabled)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Offline mode prevents metadata lookup.'),
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
                FilledButton(onPressed: submit, child: const Text('Save')),
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
    albumArtistController.dispose();
    yearController.dispose();
    trackNumberController.dispose();
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
            if (track.artworkUri != null)
              ListTile(
                leading: const Icon(Icons.crop_outlined),
                title: const Text('Crop and position'),
                subtitle: const Text('Pan and zoom the current artwork.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _editTrackArtworkCrop(context, track);
                },
              ),
            if (_isLocalM4aM4bM4rOrAlac(track))
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: const Text('Write cover to M4A/M4B/M4R/ALAC file'),
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
  final file = await pickSingleFile(
    type: FileType.image,
    dialogTitle: 'Choose track artwork',
  );
  if (!context.mounted || file == null) {
    return;
  }

  Uri? savedArtwork;
  try {
    savedArtwork = await _trackArtworkFileStore.save(
      await readPickedFileBytes(file),
    );
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
  final file = await pickSingleFile(
    type: FileType.image,
    dialogTitle: 'Choose M4A/M4B/M4R/ALAC cover artwork',
  );
  if (!context.mounted || file == null) {
    return;
  }

  final artwork = await readPickedFileBytes(file);
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
        SnackBar(
          content: Text(
            'Could not update embedded M4A/M4B/M4R/ALAC artwork: $error',
          ),
        ),
      );
    }
  }
}

Future<bool?> _confirmM4aArtworkWrite(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update M4A/M4B/M4R/ALAC embedded artwork?'),
      content: const Text(
        'This replaces the file cover with the selected PNG or JPEG. Other M4A/M4B/M4R/ALAC metadata is preserved. Standard front-loaded files repair validated chunk offsets; malformed or fragmented layouts are left unchanged.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Update M4A/M4B/M4R/ALAC'),
        ),
      ],
    ),
  );
}

Uri _m4aArtworkDataUri(List<int> artwork) {
  final mimeType =
      artwork.length >= 8 &&
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
  final initialValue =
      track.artworkIsUserManaged &&
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save artwork: $error')));
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

Future<void> _editTrackArtworkCrop(BuildContext context, Track track) async {
  final artworkUri = track.artworkUri;
  if (artworkUri == null) {
    return;
  }
  final crop = await showArtworkCropEditor(
    context,
    artworkUri: artworkUri,
    initialCrop: track.artworkCrop,
  );
  if (!context.mounted || crop == null) {
    return;
  }
  final updated = await context.read<LibraryStore>().updateTrackArtworkCrop(
    track.id,
    crop,
  );
  if (!context.mounted || updated == null) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Updated artwork crop for ${updated.title}.')),
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
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
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
            separatorBuilder: (_, _) => const Divider(height: 1),
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
                onShare: () =>
                    unawaited(_copyTrackShareText(context, library, track)),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
                onEditMetadata: () =>
                    unawaited(_showTrackMetadataEditor(context, track)),
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

String _recommendationReasonText(List<LibraryRecommendationReason> reasons) {
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
    case LibraryRecommendationReason.highlyRated:
      return 'a highly rated track';
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

String _albumMetadataLabel(List<Track> tracks) {
  final artistLabel = _albumArtistLabel(
    _collectionMetadataValues(
      tracks.map((track) => track.albumArtist ?? track.artist),
    ),
  );
  final years = _collectionMetadataValues(
    tracks.map((track) => track.year?.toString() ?? ''),
  );
  return years.isEmpty ? artistLabel : '$artistLabel · ${years.join(' / ')}';
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
    case LibrarySortMode.rating:
      return 'Rating';
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
    case LibrarySortMode.rating:
      return Icons.star_outline;
  }
}

String _playlistDocumentFormatLabel(PlaylistDocumentFormat format) {
  switch (format) {
    case PlaylistDocumentFormat.json:
      return 'JSON';
    case PlaylistDocumentFormat.m3u:
      return 'M3U';
    case PlaylistDocumentFormat.pls:
      return 'PLS';
    case PlaylistDocumentFormat.xspf:
      return 'XSPF';
    case PlaylistDocumentFormat.wpl:
      return 'WPL';
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
    case PlaylistDocumentFormat.pls:
      return 'PLS';
    case PlaylistDocumentFormat.xspf:
      return 'XSPF';
    case PlaylistDocumentFormat.wpl:
      return 'WPL';
    case PlaylistDocumentFormat.csv:
      return 'CSV';
  }
}

bool _canWriteEmbeddedMetadata(Track track) {
  return _isLocalMp3(track) ||
      _isLocalFlac(track) ||
      _isLocalM4aM4bM4rOrAlac(track) ||
      _isLocalOggOrOpus(track) ||
      _isLocalWav(track);
}

bool _isLocalMp3(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.mp3');
}

bool _isLocalFlac(Track track) {
  return (track.localPath?.trim() ?? '').toLowerCase().endsWith('.flac');
}

bool _isLocalM4aM4bM4rOrAlac(Track track) {
  final path = (track.localPath?.trim() ?? '').toLowerCase();
  return path.endsWith('.m4a') ||
      path.endsWith('.m4b') ||
      path.endsWith('.m4r') ||
      path.endsWith('.alac');
}

bool _isLocalOggOrOpus(Track track) {
  final path = (track.localPath?.trim() ?? '').toLowerCase();
  return path.endsWith('.ogg') ||
      path.endsWith('.oga') ||
      path.endsWith('.opus');
}

bool _isLocalWav(Track track) {
  final path = (track.localPath?.trim() ?? '').toLowerCase();
  return path.endsWith('.wav') || path.endsWith('.wave');
}

Future<bool?> _confirmEmbeddedTagWrite(BuildContext context, Track track) {
  final format = _isLocalMp3(track)
      ? 'MP3'
      : _isLocalFlac(track)
      ? 'FLAC'
      : _isLocalM4aM4bM4rOrAlac(track)
      ? 'M4A/M4B/M4R/ALAC'
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
            : format == 'M4A/M4B/M4R/ALAC'
            ? 'This writes title, artist, album, and genre to standard M4A/M4B/M4R/ALAC metadata atoms while preserving artwork and other metadata items. Standard front-loaded files repair validated chunk offsets; malformed or fragmented layouts are left unchanged.'
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
    case PlaylistDocumentFormat.pls:
      return 'pls';
    case PlaylistDocumentFormat.xspf:
      return 'xspf';
    case PlaylistDocumentFormat.wpl:
      return 'wpl';
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
    case PlaylistDocumentFormat.pls:
      return Icons.format_list_numbered;
    case PlaylistDocumentFormat.xspf:
      return Icons.code_outlined;
    case PlaylistDocumentFormat.wpl:
      return Icons.library_music_outlined;
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

String _customSmartPlaylistRuleFieldLabel(CustomSmartPlaylistRuleField field) {
  return switch (field) {
    CustomSmartPlaylistRuleField.searchText => 'Search text',
    CustomSmartPlaylistRuleField.sourceId => 'Exact source ID',
    CustomSmartPlaylistRuleField.artist => 'Exact artist',
    CustomSmartPlaylistRuleField.album => 'Exact album',
    CustomSmartPlaylistRuleField.genre => 'Exact genre',
    CustomSmartPlaylistRuleField.minimumDurationSeconds => 'Minimum duration',
    CustomSmartPlaylistRuleField.maximumDurationSeconds => 'Maximum duration',
    CustomSmartPlaylistRuleField.favoritesOnly => 'Favorites only',
    CustomSmartPlaylistRuleField.minimumRating => 'Minimum rating',
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

String _customSmartPlaylistSubtitle(CustomSmartPlaylist rule, int trackCount) {
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
      const SnackBar(
        content: Text('Add lyrics before sharing selected lines.'),
      ),
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
                  _LyricsShareRange(startLine: startLine, endLine: endLine),
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
  final localArtwork = _lyricsShareCardLocalArtwork(track);
  var includeArtwork = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Lyrics share card'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (localArtwork != null)
                SwitchListTile.adaptive(
                  key: const Key('lyrics-share-card-artwork-toggle'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.image_outlined),
                  title: const Text('Include local artwork'),
                  subtitle: const Text(
                    'Include this selected local image only in the PNG you save or share.',
                  ),
                  value: includeArtwork,
                  onChanged: (enabled) {
                    setDialogState(() => includeArtwork = enabled);
                  },
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: LyricsShareCard(
                    title: track.title,
                    artist: track.artist,
                    shareText: shareText,
                    backgroundImage: includeArtwork ? localArtwork : null,
                    artworkCrop: includeArtwork
                        ? track.artworkCrop
                        : ArtworkCrop.centered,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () => unawaited(
              _saveLyricsShareCard(dialogContext, boundaryKey, track),
            ),
            icon: const Icon(Icons.save_alt_outlined),
            label: const Text('Save PNG'),
          ),
          FilledButton.icon(
            onPressed: () => unawaited(
              _shareLyricsShareCard(dialogContext, boundaryKey, track),
            ),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share'),
          ),
        ],
      ),
    ),
  );
}

ImageProvider? _lyricsShareCardLocalArtwork(Track track) {
  return localLyricsShareCardBackgroundImageProvider(
    artworkIsUserManaged: track.artworkIsUserManaged,
    artworkUri: track.artworkUri,
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
    if (outputPath == null) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
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

Future<void> _shareLyricsShareCard(
  BuildContext context,
  GlobalKey boundaryKey,
  Track track,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final sharePositionOrigin = platformSharePositionOrigin(context);
  try {
    final status = await const SharePlusImageShareService().share(
      PlatformImageShareRequest(
        bytes: await captureLyricsShareCardPng(boundaryKey),
        fileName: 'aethertune-lyrics.png',
        title: '${track.title} lyrics - AetherTune',
        subject: 'AetherTune lyrics share card',
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
              ? 'Shared lyrics share card.'
              : 'Sharing is unavailable. Save the PNG instead.',
        ),
      ),
    );
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share lyrics share card: $error')),
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
    if (outputPath == null) {
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
    }
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${export.fileName}.')),
    );
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(unavailableMessage)));
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
      PlatformTextShareRequest(text: text, sharePositionOrigin: origin),
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
  if (result.sidecarChaptersCount > 0) {
    details.add(
      'Imported CUE chapters for ${result.sidecarChaptersCount} track(s).',
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

_LocalImportProgressHandle _showLocalImportProgress(
  ScaffoldMessengerState messenger,
  String message,
) {
  final progress = ValueNotifier<LocalFolderScanProgress>(
    const LocalFolderScanProgress(
      phase: LocalFolderScanPhase.discovering,
      completed: 0,
    ),
  );
  messenger.removeCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(days: 1),
      content: ValueListenableBuilder<LocalFolderScanProgress>(
        valueListenable: progress,
        builder: (context, value, child) {
          final total = value.total;
          final isDiscovering = value.phase == LocalFolderScanPhase.discovering;
          final label = isDiscovering
              ? '$message Finding audio files (${value.completed} found).'
              : '$message ${value.completed} of $total files.';
          final indicatorValue = isDiscovering || total == null || total == 0
              ? null
              : value.completed / total;
          return Row(
            children: <Widget>[
              SizedBox(
                width: 48,
                child: LinearProgressIndicator(value: indicatorValue),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
            ],
          );
        },
      ),
    ),
  );
  return _LocalImportProgressHandle(
    progress: progress,
    onDismiss: () => messenger.removeCurrentSnackBar(),
  );
}

final class _LocalImportProgressHandle {
  _LocalImportProgressHandle({required this.progress, required this.onDismiss});

  final ValueNotifier<LocalFolderScanProgress> progress;
  final VoidCallback onDismiss;
  var _dismissed = false;

  void update(LocalFolderScanProgress value) {
    if (!_dismissed) {
      progress.value = value;
    }
  }

  void dismiss() {
    if (_dismissed) {
      return;
    }
    _dismissed = true;
    onDismiss();
    progress.dispose();
  }
}

String _selectedFilesImportSummary(LocalFolderScanResult result) {
  if (result.tracks.isEmpty) {
    return 'No supported audio files were imported.';
  }

  final details = <String>['Imported ${result.tracks.length} audio file(s).'];
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
  if (result.sidecarChaptersCount > 0) {
    details.add(
      'Imported CUE chapters for ${result.sidecarChaptersCount} track(s).',
    );
  }
  if (result.ignoredFileCount > 0) {
    details.add(
      'Skipped ${result.ignoredFileCount} unavailable or non-audio file(s).',
    );
  }

  return details.join(' ');
}

Future<void> _addScannedTracksToLibrary(
  LibraryStore library,
  LocalFolderScanResult scanResult,
) async {
  if (scanResult.tracks.isEmpty) {
    return;
  }

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
  for (final entry in scanResult.sidecarChaptersByTrackId.entries) {
    await library.setTrackChaptersIfAbsent(entry.key, entry.value);
  }
}

LocalFolderScanResult _mergeLocalFolderScanResults(
  Iterable<LocalFolderScanResult> results,
) {
  final tracksById = <String, Track>{};
  final sidecarLyrics = <String, String>{};
  final embeddedLyrics = <String, String>{};
  final sidecarChapters = <String, List<TrackChapter>>{};
  var ignoredFileCount = 0;
  var inaccessibleDirectoryCount = 0;
  for (final result in results) {
    for (final track in result.tracks) {
      tracksById[track.id] = track;
    }
    sidecarLyrics.addAll(result.sidecarLyricsByTrackId);
    embeddedLyrics.addAll(result.embeddedLyricsByTrackId);
    sidecarChapters.addAll(result.sidecarChaptersByTrackId);
    ignoredFileCount += result.ignoredFileCount;
    inaccessibleDirectoryCount += result.inaccessibleDirectoryCount;
  }
  return LocalFolderScanResult(
    tracks: List.unmodifiable(tracksById.values),
    ignoredFileCount: ignoredFileCount,
    inaccessibleDirectoryCount: inaccessibleDirectoryCount,
    sidecarLyricsByTrackId: Map.unmodifiable(sidecarLyrics),
    embeddedLyricsByTrackId: Map.unmodifiable(embeddedLyrics),
    sidecarChaptersByTrackId: Map.unmodifiable(sidecarChapters),
  );
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
            Text(_emptyLibrarySubtitle, textAlign: TextAlign.center),
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
  State<_DuplicateResolverSheet> createState() =>
      _DuplicateResolverSheetState();
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
                  onTap: () =>
                      unawaited(_undoLastDuplicateResolution(context, library)),
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
                        group.tracks.firstWhere((track) => track.id == trackId),
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
        .map((group) {
          final keepTrackId = _keepTrackIdFor(group);
          return DuplicateTrackResolution(
            keepTrackId: keepTrackId,
            duplicateTrackIds: group.tracks
                .where((track) => track.id != keepTrackId)
                .map((track) => track.id),
          );
        })
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
        content: Text(
          'Merged $removed duplicate(s) from ${groups.length} group(s).',
        ),
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
    case DuplicateMatchType.audioFingerprint:
      return 'Same encoded audio payload';
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

String _offlineCacheProviderLimitLabel(LibraryStore library, String sourceId) {
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
