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
part 'home_screen_settings.dart';

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
    final timestampStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colorScheme.primary);

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
          separatorBuilder: (_, _) => const Divider(height: 1),
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
    required this.library,
    required this.player,
    required this.translator,
    required this.translationTargetLanguage,
    required this.onEdit,
    required this.onShare,
    required this.onShareRange,
    required this.onAdjustTiming,
    required this.onSearch,
  });

  final Track track;
  final LibraryStore library;
  final PlayerController player;
  final LyricsTranslator? translator;
  final String translationTargetLanguage;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback onAdjustTiming;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final currentLyrics = library.lyricsForTrack(track.id);
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
            onSearch: onSearch,
            onTranslate: _translationAction(context, currentLyrics.plainText),
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
          onAdjustTiming: onAdjustTiming,
          onSearch: onSearch,
          onTranslate: _translationAction(
            context,
            syncedLines.map((line) => line.text).join('\n'),
          ),
        );
      },
    );
  }

  VoidCallback? _translationAction(BuildContext context, String lyricsText) {
    final currentTranslator = translator;
    if (currentTranslator == null || lyricsText.trim().isEmpty) {
      return null;
    }
    return () => unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!context.mounted) {
        return;
      }
      await _showLyricsTranslation(
        context,
        translator: currentTranslator,
        lyrics: lyricsText,
        targetLanguage: translationTargetLanguage,
      );
    }());
  }
}

class _EmptyNowPlayingLyrics extends StatelessWidget {
  const _EmptyNowPlayingLyrics({required this.track, required this.onEdit});

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
              'Add plain lyrics or import LRC, SRT, WebVTT, or TTML timed lyrics.',
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
    required this.onSearch,
    this.onTranslate,
  });

  final Track track;
  final String lyrics;
  final String? sourceLabel;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback onSearch;
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
                onSearch: onSearch,
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
    required this.onAdjustTiming,
    required this.onSearch,
    this.onTranslate,
  });

  final Track track;
  final List<SyncedLyricLine> lines;
  final String? sourceLabel;
  final PlayerController player;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback onAdjustTiming;
  final VoidCallback onSearch;
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
                separatorBuilder: (_, _) => const Divider(height: 1),
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
                      onAdjustTiming: widget.onAdjustTiming,
                      onSearch: widget.onSearch,
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

      final targetOffset = (activeIndex * _estimatedLineExtent)
          .clamp(0.0, controller.position.maxScrollExtent)
          .toDouble();
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
    this.onAdjustTiming,
    this.onSearch,
    this.onTranslate,
  });

  final Track track;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onShareRange;
  final VoidCallback? onAdjustTiming;
  final VoidCallback? onSearch;
  final VoidCallback? onTranslate;

  @override
  Widget build(BuildContext context) {
    final hasOverflowActions =
        onShare != null ||
        onShareRange != null ||
        onAdjustTiming != null ||
        onTranslate != null;

    return ListTile(
      leading: const Icon(Icons.subtitles_outlined),
      title: Text(track.title),
      subtitle: Text('${track.artist} · $subtitle'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onSearch != null)
            IconButton(
              tooltip: 'Find in lyrics',
              onPressed: onSearch,
              icon: const Icon(Icons.manage_search_outlined),
            ),
          if (hasOverflowActions)
            PopupMenuButton<_NowPlayingLyricsMenuAction>(
              tooltip: 'Lyrics actions',
              onSelected: _selectOverflowAction,
              itemBuilder: (context) =>
                  <PopupMenuEntry<_NowPlayingLyricsMenuAction>>[
                    if (onShare != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.share,
                        child: Text('Copy share text'),
                      ),
                    if (onShareRange != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.shareRange,
                        child: Text('Share selected lines'),
                      ),
                    if (onTranslate != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.translate,
                        child: Text('Translate lyrics'),
                      ),
                    if (onAdjustTiming != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.adjustTiming,
                        child: Text('Adjust lyric timing'),
                      ),
                  ],
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

  void _selectOverflowAction(_NowPlayingLyricsMenuAction action) {
    switch (action) {
      case _NowPlayingLyricsMenuAction.share:
        onShare?.call();
      case _NowPlayingLyricsMenuAction.shareRange:
        onShareRange?.call();
      case _NowPlayingLyricsMenuAction.translate:
        onTranslate?.call();
      case _NowPlayingLyricsMenuAction.adjustTiming:
        onAdjustTiming?.call();
    }
  }
}

Future<void> _configureLyricsSearchEndpoint(BuildContext context) async {
  final store = context.read<LyricsSearchEndpointSettingsStore?>();
  if (store == null) {
    return;
  }
  final controller = TextEditingController(
    text: store.endpoint?.toString() ?? '',
  );
  String? validationError;
  try {
    final endpoint = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Configure lyrics search'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'AetherTune sends track title, artist, album, and any search terms only to the HTTPS LRCLIB-compatible service you choose. This endpoint receives no credentials and results remain stored on this device.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('lyrics-search-endpoint'),
                  controller: controller,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Service URL',
                    hintText: 'https://lyrics.example',
                  ),
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(value),
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
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(
                    () => validationError = 'Enter an HTTPS service URL.',
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
    if (!context.mounted || endpoint == null) {
      return;
    }
    // Let the route dispose before its setting notification rebuilds Options.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!context.mounted) {
      return;
    }
    await store.save(endpoint);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lyrics search service configured.')),
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
        const SnackBar(content: Text('Could not save lyrics search settings.')),
      );
    }
  } finally {
    controller.dispose();
  }
}

Future<void> _removeLyricsSearchEndpoint(BuildContext context) async {
  final store = context.read<LyricsSearchEndpointSettingsStore?>();
  if (store == null || !store.isConfigured) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Use public LRCLIB again?'),
      content: const Text(
        'This removes the custom lyrics search endpoint from this device. Saved lyrics and cached searches remain unchanged.',
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
        const SnackBar(content: Text('Using public LRCLIB for lyrics search.')),
      );
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove lyrics search settings.'),
        ),
      );
    }
  }
}

enum _NowPlayingLyricsMenuAction { share, shareRange, translate, adjustTiming }

String _lyricsSubtitle(String base, String? sourceLabel) {
  final source = sourceLabel?.trim() ?? '';
  return source.isEmpty ? base : '$base - $source';
}

String _formatLyricsTimingOffset(Duration offset) {
  final milliseconds = offset.inMilliseconds;
  final sign = milliseconds < 0 ? '-' : '+';
  final absoluteMilliseconds = milliseconds.abs();
  final seconds = absoluteMilliseconds ~/ 1000;
  final tenths = (absoluteMilliseconds % 1000) ~/ 100;
  return '$sign$seconds.$tenths s';
}

class _LyricsSearchEntry {
  const _LyricsSearchEntry({
    required this.lineNumber,
    required this.text,
    this.timestamp,
  });

  final int lineNumber;
  final String text;
  final Duration? timestamp;
}

Future<void> _showLyricsSearch(
  BuildContext context, {
  required Track track,
  required TrackLyrics? lyrics,
  required PlayerController player,
}) async {
  final currentLyrics = lyrics;
  if (currentLyrics == null || currentLyrics.isEmpty) {
    return;
  }

  final syncedLines = currentLyrics.syncedLines;
  final entries = syncedLines.isNotEmpty
      ? <_LyricsSearchEntry>[
          for (var index = 0; index < syncedLines.length; index += 1)
            _LyricsSearchEntry(
              lineNumber: index + 1,
              text: syncedLines[index].text,
              timestamp: syncedLines[index].timestamp,
            ),
        ]
      : <_LyricsSearchEntry>[
          for (final entry
              in currentLyrics.plainText
                  .split(RegExp(r'\r?\n'))
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList(growable: false)
                  .indexed)
            _LyricsSearchEntry(lineNumber: entry.$1 + 1, text: entry.$2),
        ];
  if (entries.isEmpty) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (_) =>
        _LyricsSearchDialog(track: track, entries: entries, player: player),
  );
}

class _LyricsSearchDialog extends StatefulWidget {
  const _LyricsSearchDialog({
    required this.track,
    required this.entries,
    required this.player,
  });

  final Track track;
  final List<_LyricsSearchEntry> entries;
  final PlayerController player;

  @override
  State<_LyricsSearchDialog> createState() => _LyricsSearchDialogState();
}

class _LyricsSearchDialogState extends State<_LyricsSearchDialog> {
  final _controller = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchingIndices = findLyricLineMatchIndices(
      widget.entries.map((entry) => entry.text).toList(growable: false),
      _query,
    );

    return AlertDialog(
      title: Text('Find in ${widget.track.title}'),
      content: SizedBox(
        width: 460,
        height: 360,
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              controller: _controller,
              key: const Key('lyrics-find-input'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Find lyrics',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _query.trim().isEmpty
                  ? const SizedBox.shrink()
                  : matchingIndices.isEmpty
                  ? const Center(child: Text('No matching lines'))
                  : ListView.separated(
                      itemCount: matchingIndices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = widget.entries[matchingIndices[index]];
                        return ListTile(
                          key: Key('lyric-search-result-${entry.lineNumber}'),
                          dense: true,
                          title: Text(
                            entry.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.timestamp == null
                                ? 'Line ${entry.lineNumber}'
                                : formatSyncedLyricTimestamp(entry.timestamp!),
                          ),
                          onTap: () async {
                            if (entry.timestamp != null) {
                              await widget.player.seek(entry.timestamp!);
                            }
                            if (!mounted) {
                              return;
                            }
                            Navigator.of(this.context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

Future<void> _showLyricsTimingAdjustment(
  BuildContext context,
  LibraryStore library,
  Track track,
) async {
  if (library.lyricsForTrack(track.id)?.hasSyncedLines != true) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final offset =
              library.lyricsForTrack(track.id)?.timingOffset ?? Duration.zero;

          Future<void> adjust(Duration change) async {
            await library.setLyricsTimingOffset(track.id, offset + change);
            if (dialogContext.mounted) {
              setDialogState(() {});
            }
          }

          Future<void> reset() async {
            await library.setLyricsTimingOffset(track.id, Duration.zero);
            if (dialogContext.mounted) {
              setDialogState(() {});
            }
          }

          return AlertDialog(
            title: const Text('Adjust lyric timing'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_formatLyricsTimingOffset(offset)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Move lyrics 0.5 seconds earlier',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: -500))),
                      icon: const Icon(Icons.fast_rewind_outlined),
                    ),
                    IconButton(
                      tooltip: 'Move lyrics 0.1 seconds earlier',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: -100))),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Move lyrics 0.1 seconds later',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: 100))),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Move lyrics 0.5 seconds later',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: 500))),
                      icon: const Icon(Icons.fast_forward_outlined),
                    ),
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: offset == Duration.zero
                    ? null
                    : () => unawaited(reset()),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showLyricsTranslation(
  BuildContext context, {
  required LyricsTranslator translator,
  required String lyrics,
  required String targetLanguage,
}) async {
  final localizations = AppLocalizations.of(context)!;
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      duration: Duration(days: 1),
      content: Text(localizations.translatingLyrics),
    ),
  );

  try {
    final translated = await translator.translate(
      lyrics,
      targetLanguage: targetLanguage,
    );
    messenger.hideCurrentSnackBar();
    if (!navigator.mounted) {
      return;
    }
    await showDialog<void>(
      context: navigator.context,
      builder: (_) => _TranslatedLyricsDialog(
        lyrics: translated,
        targetLanguage: targetLanguage,
      ),
    );
  } on Object catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(localizations.couldNotTranslateLyrics('$error'))),
    );
  }
}

class _TranslatedLyricsDialog extends StatelessWidget {
  const _TranslatedLyricsDialog({
    required this.lyrics,
    required this.targetLanguage,
  });

  final String lyrics;
  final String targetLanguage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return AlertDialog(
      title: Text(localizations.translatedLyrics),
      content: SizedBox(
        width: 560,
        height: height,
        child: ListView(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.translate_outlined),
              title: Text(
                localizations.translatedLyricsForLanguage(targetLanguage),
              ),
              trailing: IconButton(
                tooltip: localizations.copyTranslatedLyrics,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: lyrics));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.translatedLyricsCopied),
                      ),
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
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
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
    final currentIndex = current == null
        ? -1
        : queue.indexWhere((track) => track.id == current.id);
    final hasUpcomingTracks =
        currentIndex >= 0 && currentIndex < queue.length - 1;

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Queues'),
            subtitle: Text(
              '${savedQueues.length} saved · ${player.activeQueueName} active',
            ),
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
                    PopupMenuItem(
                      value: _SavedQueueAction.clearUpcoming,
                      enabled: hasUpcomingTracks,
                      child: const ListTile(
                        leading: Icon(Icons.playlist_remove),
                        title: Text('Clear upcoming tracks'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _SavedQueueAction.clear,
                      enabled: queue.isNotEmpty,
                      child: const ListTile(
                        leading: Icon(Icons.delete_sweep_outlined),
                        title: Text('Clear queue'),
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
                  : () => unawaited(player.switchSavedQueue(savedQueue.id)),
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
              subtitle: Text(
                'Play tracks from Library, Playlists, or History.',
              ),
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
      if (player.persistenceError != null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Use a unique queue name (up to 80 characters).'),
        ),
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
        if (context.mounted && !renamed && player.persistenceError == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Use a unique queue name (up to 80 characters).'),
            ),
          );
        }
        return;
      case _SavedQueueAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete queue?'),
            content: Text(
              'Delete ${player.activeQueueName} and its saved tracks?',
            ),
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
        return;
      case _SavedQueueAction.clearUpcoming:
      case _SavedQueueAction.clear:
        final upcomingOnly = action == _SavedQueueAction.clearUpcoming;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              upcomingOnly ? 'Clear upcoming tracks?' : 'Clear queue?',
            ),
            content: Text(
              upcomingOnly
                  ? 'The current track will keep playing.'
                  : 'This stops playback and removes every track from ${player.activeQueueName}.',
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
        if (upcomingOnly) {
          await player.clearUpcomingTracks();
        } else {
          await player.clearActiveQueue();
        }
        return;
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
      leading: Icon(isCurrent ? Icons.graphic_eq : Icons.music_note_outlined),
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

enum _SavedQueueAction { rename, delete, clearUpcoming, clear }

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
    required this.onBatchLyrics,
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
  final ValueChanged<List<Track>> onBatchLyrics;

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
              IconButton(
                tooltip: 'Saved library views',
                onPressed: () => _showSavedLibraryViews(context),
                icon: const Icon(Icons.bookmark_outline),
              ),
              IconButton(
                tooltip: 'Find missing lyrics in these results',
                onPressed: tracks.isEmpty ? null : () => onBatchLyrics(tracks),
                icon: const Icon(Icons.lyrics_outlined),
              ),
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
              separatorBuilder: (_, _) => const Divider(height: 1),
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
            ),
          ),
      ],
    );
  }

  Future<void> _showSavedLibraryViews(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer<LibraryStore>(
          builder: (context, library, _) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.68,
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.bookmark_add_outlined),
                      title: const Text('Save current library view'),
                      subtitle: Text(
                        _savedLibraryViewDescription(
                          query: query,
                          favoritesOnly: favoritesOnly,
                          offlineOnly: offlineOnly,
                          sortMode: sortMode,
                        ),
                      ),
                      onTap: () => unawaited(_createSavedLibraryView(context)),
                    ),
                    const Divider(height: 1),
                    if (library.savedLibraryViews.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'Save a search, favorites, local-files filter, and sort order to return to it quickly.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: library.savedLibraryViews.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final view = library.savedLibraryViews[index];
                            return ListTile(
                              leading: const Icon(Icons.bookmark),
                              title: Text(view.name),
                              subtitle: Text(
                                _savedLibraryViewDescription(
                                  query: view.query,
                                  favoritesOnly: view.favoritesOnly,
                                  offlineOnly: view.offlineOnly,
                                  sortMode: view.sortMode,
                                ),
                              ),
                              trailing:
                                  PopupMenuButton<_SavedLibraryViewAction>(
                                    tooltip: 'Edit saved library view',
                                    onSelected: (action) async {
                                      switch (action) {
                                        case _SavedLibraryViewAction.update:
                                          await library.updateSavedLibraryView(
                                            view.id,
                                            name: view.name,
                                            query: query,
                                            favoritesOnly: favoritesOnly,
                                            offlineOnly: offlineOnly,
                                            sortMode: sortMode,
                                          );
                                          break;
                                        case _SavedLibraryViewAction.rename:
                                          Navigator.of(sheetContext).pop();
                                          await _renameSavedLibraryView(
                                            context,
                                            view,
                                          );
                                          break;
                                        case _SavedLibraryViewAction.delete:
                                          await library.deleteSavedLibraryView(
                                            view.id,
                                          );
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) =>
                                        const <
                                          PopupMenuEntry<
                                            _SavedLibraryViewAction
                                          >
                                        >[
                                          PopupMenuItem<
                                            _SavedLibraryViewAction
                                          >(
                                            value:
                                                _SavedLibraryViewAction.update,
                                            child: Text('Update from current'),
                                          ),
                                          PopupMenuItem<
                                            _SavedLibraryViewAction
                                          >(
                                            value:
                                                _SavedLibraryViewAction.rename,
                                            child: Text('Rename'),
                                          ),
                                          PopupMenuItem<
                                            _SavedLibraryViewAction
                                          >(
                                            value:
                                                _SavedLibraryViewAction.delete,
                                            child: Text('Delete'),
                                          ),
                                        ],
                                  ),
                              onTap: () {
                                searchController
                                  ..text = view.query
                                  ..selection = TextSelection.collapsed(
                                    offset: view.query.length,
                                  );
                                onQueryChanged(view.query);
                                onFavoritesOnlyChanged(view.favoritesOnly);
                                onOfflineOnlyChanged(view.offlineOnly);
                                onSortModeChanged(view.sortMode);
                                Navigator.of(sheetContext).pop();
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _createSavedLibraryView(BuildContext context) async {
    final name = await _showSavedLibraryViewNameDialog(
      context,
      title: 'Save library view',
    );
    if (name == null || !context.mounted) {
      return;
    }
    await context.read<LibraryStore>().createSavedLibraryView(
      name: name,
      query: query,
      favoritesOnly: favoritesOnly,
      offlineOnly: offlineOnly,
      sortMode: sortMode,
    );
  }

  Future<void> _renameSavedLibraryView(
    BuildContext context,
    SavedLibraryView view,
  ) async {
    final name = await _showSavedLibraryViewNameDialog(
      context,
      title: 'Rename library view',
      initialName: view.name,
    );
    if (name == null || !context.mounted) {
      return;
    }
    await context.read<LibraryStore>().updateSavedLibraryView(
      view.id,
      name: name,
      query: view.query,
      favoritesOnly: view.favoritesOnly,
      offlineOnly: view.offlineOnly,
      sortMode: view.sortMode,
    );
  }
}

Future<String?> _showSavedLibraryViewNameDialog(
  BuildContext context, {
  required String title,
  String initialName = '',
}) async {
  final controller = TextEditingController(text: initialName);
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => _TextEditingControllerOwner(
      controllers: <TextEditingController>[controller],
      child: AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (name == null || name.isEmpty) {
    return null;
  }
  return name;
}

enum _SavedLibraryViewAction { update, rename, delete }

String _savedLibraryViewDescription({
  required String query,
  required bool favoritesOnly,
  required bool offlineOnly,
  required LibrarySortMode sortMode,
}) {
  final labels = <String>[_librarySortLabel(sortMode)];
  if (query.trim().isNotEmpty) {
    labels.add('"${query.trim()}"');
  }
  if (favoritesOnly) {
    labels.add('Favorites');
  }
  if (offlineOnly) {
    labels.add('Local files');
  }
  return labels.join(' · ');
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
            separatorBuilder: (_, _) => const Divider(height: 1),
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
                            : () => unawaited(_saveMoodMix(context, library)),
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

  Future<void> _saveMoodMix(BuildContext context, LibraryStore library) async {
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
            separatorBuilder: (_, _) => const Divider(height: 1),
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
        : _albumMetadataLabel(tracks);
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
                    _copyBrowseGroupShareText(context, library, type, group),
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
                separatorBuilder: (_, _) => const SizedBox(width: 12),
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
      onPlay: () =>
          _playTrackWithResume(context, player, library, track, queue: tracks),
      onStartRadio: () =>
          unawaited(_startTrackRadio(context, player, library, track)),
      onSimilarTracks: () => unawaited(
        _showSimilarTracks(
          context,
          track,
          onAddToPlaylist: onAddToPlaylist,
          onLyrics: onLyrics,
        ),
      ),
      onShare: () => unawaited(_copyTrackShareText(context, library, track)),
      onFavorite: () => library.toggleFavorite(track.id),
      onAddToPlaylist: () => onAddToPlaylist(track),
      onLyrics: () => onLyrics(track),
      onEditMetadata: () => unawaited(_showTrackMetadataEditor(context, track)),
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
          artworkCrop: track?.artworkCrop ?? ArtworkCrop.centered,
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
              artworkCrop: track?.artworkCrop ?? ArtworkCrop.centered,
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
            separatorBuilder: (_, _) => const Divider(height: 1),
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
