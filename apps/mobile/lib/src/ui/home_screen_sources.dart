part of 'home_screen.dart';

enum _SelfHostedAccountAction { browse, edit, rotateCredential, remove }

enum _CustomCatalogAction { edit, remove }

enum _YouTubeDataAction { musicChart, channels, playlists, configure, remove }

enum _YouTubeAccountAction { library, configure, remove }

enum _JamendoAction { browseCollections, configure, remove }

enum _AudiusAction { browseCollections }

enum _ItunesAction { browseAlbums, chooseStorefront }

enum _SpotifyAction {
  savedTracks,
  savedEpisodes,
  savedShows,
  savedAlbums,
  playlists,
  recentlyPlayed,
  topTracks,
  topArtists,
  followedArtists,
  newReleases,
  configure,
  remove,
}

class _SourcesTab extends StatefulWidget {
  const _SourcesTab({
    this.archiveProvider,
    this.podcastDirectory,
    this.podcastProviderFactory,
    this.providerSearchProviders,
  });

  final InternetArchiveProvider? archiveProvider;
  final ItunesPodcastDirectory? podcastDirectory;
  final PodcastRssProvider Function(Uri feedUri)? podcastProviderFactory;
  final List<MusicSourceProvider>? providerSearchProviders;

  @override
  State<_SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<_SourcesTab> {
  final _provider = const DemoSourceProvider();
  late final InternetArchiveProvider _archiveProvider;
  final AudiusProvider _audiusProvider = AudiusProvider();
  late final ItunesPodcastDirectory _podcastDirectory;
  final _providerSearchController = TextEditingController();
  final _archiveSearchController = TextEditingController();
  final _archiveCollectionController = TextEditingController();
  final _archiveSubjectController = TextEditingController();
  final _archiveCreatorController = TextEditingController();
  final _archiveYearController = TextEditingController();
  final _podcastFeedController = TextEditingController();
  final _podcastDirectoryQueryController = TextEditingController();
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
  List<PodcastDirectoryResult> _podcastDirectoryResults =
      <PodcastDirectoryResult>[];
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
  bool _podcastDirectoryLoading = false;
  bool _podcastDirectorySuggestionLoading = false;
  String? _podcastError;
  String? _podcastDirectoryError;
  String? _selectedPodcastSubscriptionId;
  bool _providerSearchLoading = false;
  bool _providerSearchLoadingMore = false;
  bool _providerSearchSuggestionsLoading = false;
  bool _providerSearchLocalOnly = false;
  String? _providerSearchSourceFilterId;
  int _providerSearchRequestSerial = 0;
  int _providerSearchSuggestionRequestSerial = 0;
  Timer? _providerSearchSuggestionDebounce;
  int _podcastDirectoryRequestSerial = 0;
  Timer? _podcastDirectorySuggestionDebounce;
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
    _podcastDirectory = widget.podcastDirectory ?? ItunesPodcastDirectory();
    _provider.search('').then((tracks) {
      if (mounted) {
        setState(() => _demoTracks = tracks);
      }
    });
  }

  @override
  void dispose() {
    _providerSearchSuggestionDebounce?.cancel();
    _podcastDirectorySuggestionDebounce?.cancel();
    _providerSearchController.dispose();
    _archiveSearchController.dispose();
    _archiveCollectionController.dispose();
    _archiveSubjectController.dispose();
    _archiveCreatorController.dispose();
    _archiveYearController.dispose();
    _podcastFeedController.dispose();
    _podcastDirectoryQueryController.dispose();
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
    final podcastChapterHosts = context.watch<PodcastChapterHostPolicy?>();
    final selfHosted = context.watch<SelfHostedProviderStore>();
    final customCatalogs = context.watch<CustomCatalogStore?>();
    final librarySync = context.watch<LibrarySyncStore?>();
    final youtubeData = context.watch<YouTubeDataSettingsStore?>();
    final youtubeAccount = context.watch<YouTubeAccountSettingsStore?>();
    final YouTubeAccountProvider? youtubeAccountProvider =
        youtubeAccount?.accountProvider;
    final jamendo = context.watch<JamendoSettingsStore?>();
    final itunes = context.watch<ItunesMetadataSettingsStore?>();
    final itunesProvider = itunes?.provider ?? _itunesMetadataProvider;
    final itunesStatus =
        'Enabled - ${itunes?.storefront ?? itunesProvider.country.toUpperCase()}';
    final youtubeProviders =
        youtubeData?.musicProviders ?? const <MusicSourceProvider>[];
    YouTubeDataMetadataProvider? youtubeProvider;
    for (final candidate in youtubeProviders) {
      if (candidate is YouTubeDataMetadataProvider) {
        youtubeProvider = candidate;
        break;
      }
    }
    JamendoProvider? jamendoProvider;
    for (final candidate
        in jamendo?.musicProviders ?? const <MusicSourceProvider>[]) {
      if (candidate is JamendoProvider) {
        jamendoProvider = candidate;
        break;
      }
    }
    final spotify = context.watch<SpotifySettingsStore?>();
    final spotifyProviders =
        spotify?.musicProviders ?? const <MusicSourceProvider>[];
    SpotifyMetadataProvider? spotifyProvider;
    for (final candidate in spotifyProviders) {
      if (candidate is SpotifyMetadataProvider) {
        spotifyProvider = candidate;
        break;
      }
    }
    final podcastSubscriptions = library.podcastSubscriptions;
    final offlineModeEnabled = library.offlineModeEnabled;
    final selfHostedActionsEnabled =
        selfHosted.loaded &&
        selfHosted.loadError == null &&
        !offlineModeEnabled;
    final providerSearchSources = _providerSearchSourceFacets();
    final selectedProviderSearchSourceId =
        providerSearchSources.containsKey(_providerSearchSourceFilterId)
        ? _providerSearchSourceFilterId
        : null;
    final visibleProviderSearchResults = _providerSearchResults
        .where(
          (result) =>
              selectedProviderSearchSourceId == null ||
              result.providerId == selectedProviderSearchSourceId,
        )
        .toList(growable: false);
    final visibleProviderSearchErrors = _providerSearchErrors
        .where(
          (error) =>
              selectedProviderSearchSourceId == null ||
              error.providerId == selectedProviderSearchSourceId,
        )
        .toList(growable: false);
    final visibleProviderSearchLoadMoreErrors = _providerSearchLoadMoreErrors
        .where(
          (error) =>
              selectedProviderSearchSourceId == null ||
              error.providerId == selectedProviderSearchSourceId,
        )
        .toList(growable: false);
    final visibleProviderSearchContinuations = _filterProviderContinuations(
      _providerSearchContinuations,
      selectedProviderSearchSourceId,
    );
    final visibleProviderSearchFailedContinuations =
        _filterProviderContinuations(
          _providerSearchFailedContinuations,
          selectedProviderSearchSourceId,
        );

    return ListView(
      key: const Key('sources-scroll-view'),
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
          description:
              'Import and play files selected through the native picker.',
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
          description:
              'Parse legal RSS feeds with audio enclosures into playable episode tracks.',
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
        _ProviderCard(
          title: _audiusProvider.name,
          status: 'Enabled',
          description: _audiusProvider.description,
          icon: Icons.graphic_eq_outlined,
          capabilities: _audiusProvider.capabilities,
          disclosure: _audiusProvider.disclosure,
          actions: PopupMenuButton<_AudiusAction>(
            tooltip: 'Browse Audius',
            onSelected: (action) {
              if (action == _AudiusAction.browseCollections) {
                _openAudiusCollections(context);
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_AudiusAction>>[
              PopupMenuItem<_AudiusAction>(
                value: _AudiusAction.browseCollections,
                enabled: !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.explore_outlined),
                  title: Text('Browse public artists, albums, and playlists'),
                ),
              ),
            ],
          ),
        ),
        _ProviderCard(
          title: _musicBrainzMetadataProvider.name,
          status: 'Enabled',
          description: _musicBrainzMetadataProvider.description,
          icon: Icons.library_music_outlined,
          capabilities: _musicBrainzMetadataProvider.capabilities,
          disclosure: _musicBrainzMetadataProvider.disclosure,
        ),
        const SizedBox(height: 16),
        Text('Official APIs', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _ProviderCard(
          title: 'YouTube Data API',
          status: youtubeData?.isConfigured == true ? 'Enabled' : 'Optional',
          description: youtubeData?.isConfigured == true
              ? 'Searches and browses official music video metadata. Playback and offline media are unavailable.'
              : 'Configure a user-owned Google Cloud API key for official video metadata search only.',
          icon: Icons.ondemand_video_outlined,
          capabilities:
              youtubeProvider?.capabilities ??
              const <MusicSourceCapability>{
                MusicSourceCapability.metadataSearch,
                MusicSourceCapability.artwork,
              },
          disclosure:
              youtubeProvider?.disclosure ??
              const ProviderPrivacyDisclosure(
                networkDomains: <String>['www.googleapis.com', 'i.ytimg.com'],
              ),
          actions: PopupMenuButton<_YouTubeDataAction>(
            tooltip: 'Manage YouTube Data API',
            onSelected: (action) {
              switch (action) {
                case _YouTubeDataAction.musicChart:
                  if (youtubeProvider != null) {
                    _openYouTubeMusicChart(context, youtubeProvider);
                  }
                  break;
                case _YouTubeDataAction.channels:
                  if (youtubeProvider != null) {
                    _openYouTubeChannels(context, youtubeProvider);
                  }
                  break;
                case _YouTubeDataAction.playlists:
                  if (youtubeProvider != null) {
                    _openYouTubePublicPlaylists(context, youtubeProvider);
                  }
                  break;
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
                value: _YouTubeDataAction.musicChart,
                enabled: youtubeProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.trending_up_outlined),
                  title: Text('Music chart'),
                ),
              ),
              PopupMenuItem<_YouTubeDataAction>(
                value: _YouTubeDataAction.channels,
                enabled: youtubeProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_search_outlined),
                  title: Text('Public channels'),
                ),
              ),
              PopupMenuItem<_YouTubeDataAction>(
                value: _YouTubeDataAction.playlists,
                enabled: youtubeProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.queue_music_outlined),
                  title: Text('Public playlists'),
                ),
              ),
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
        const SizedBox(height: 8),
        _ProviderCard(
          title: 'Jamendo API',
          status: jamendo?.isConfigured == true ? 'Enabled' : 'Optional',
          description: jamendo?.isConfigured == true
              ? 'Official Jamendo music search and direct stream playback. Offline media stays unavailable.'
              : 'Configure your Jamendo developer client ID for official music search and streaming.',
          icon: Icons.music_note_outlined,
          capabilities:
              jamendoProvider?.capabilities ??
              const <MusicSourceCapability>{
                MusicSourceCapability.metadataSearch,
                MusicSourceCapability.streamResolution,
                MusicSourceCapability.directPlayback,
                MusicSourceCapability.artwork,
              },
          disclosure:
              jamendoProvider?.disclosure ??
              const ProviderPrivacyDisclosure(
                networkDomains: <String>[
                  'api.jamendo.com',
                  'usercontent.jamendo.com',
                  '*.storage.jamendo.com',
                ],
              ),
          actions: PopupMenuButton<_JamendoAction>(
            tooltip: 'Manage Jamendo API',
            onSelected: (action) {
              switch (action) {
                case _JamendoAction.browseCollections:
                  if (jamendoProvider != null) {
                    _openJamendoCollections(context, jamendoProvider);
                  }
                  break;
                case _JamendoAction.configure:
                  unawaited(_configureJamendo(context));
                  break;
                case _JamendoAction.remove:
                  unawaited(_removeJamendo(context));
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_JamendoAction>>[
              PopupMenuItem<_JamendoAction>(
                value: _JamendoAction.browseCollections,
                enabled: jamendoProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.explore_outlined),
                  title: Text('Browse artists and albums'),
                ),
              ),
              PopupMenuItem<_JamendoAction>(
                value: _JamendoAction.configure,
                enabled: jamendo?.loaded == true && !offlineModeEnabled,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(
                    jamendo?.isConfigured == true
                        ? 'Replace client ID'
                        : 'Configure client ID',
                  ),
                ),
              ),
              PopupMenuItem<_JamendoAction>(
                value: _JamendoAction.remove,
                enabled: jamendo?.isConfigured == true,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Remove client ID'),
                ),
              ),
            ],
          ),
        ),
        if (jamendo?.loaded != true) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (jamendo?.loadError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Jamendo API unavailable'),
            subtitle: Text(jamendo!.loadError!),
          ),
        ],
        const SizedBox(height: 8),
        _ProviderCard(
          title: 'YouTube account library',
          status:
              youtubeAccount?.isConfigured == true &&
                  youtubeAccount?.desktopOAuthSupported == true
              ? 'Enabled'
              : youtubeAccount?.desktopOAuthSupported == true
              ? 'Optional'
              : 'Desktop only',
          description: youtubeAccount?.desktopOAuthSupported == true
              ? youtubeAccount?.isConfigured == true
                    ? 'Browses your own playlists and subscriptions through read-only official API access. Playback and offline media are unavailable.'
                    : 'Connect a user-owned Google OAuth desktop client to browse your own playlist and subscription metadata.'
              : 'Google loopback OAuth is available only in the desktop app. Mobile does not offer this sign-in path.',
          icon: Icons.account_circle_outlined,
          capabilities: const <MusicSourceCapability>{
            MusicSourceCapability.metadataSearch,
            MusicSourceCapability.artwork,
            MusicSourceCapability.authentication,
            MusicSourceCapability.subscriptions,
          },
          disclosure: const ProviderPrivacyDisclosure(
            networkDomains: <String>[
              'accounts.google.com',
              'oauth2.googleapis.com',
              'www.googleapis.com',
              'i.ytimg.com',
            ],
            requiresUserCredentials: true,
          ),
          actions: PopupMenuButton<_YouTubeAccountAction>(
            tooltip: 'Manage YouTube account library',
            onSelected: (action) {
              switch (action) {
                case _YouTubeAccountAction.library:
                  if (youtubeAccountProvider != null) {
                    _openYouTubeAccountLibrary(context, youtubeAccountProvider);
                  }
                  break;
                case _YouTubeAccountAction.configure:
                  unawaited(_configureYouTubeAccount(context));
                  break;
                case _YouTubeAccountAction.remove:
                  unawaited(_removeYouTubeAccount(context));
                  break;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_YouTubeAccountAction>>[
              PopupMenuItem<_YouTubeAccountAction>(
                value: _YouTubeAccountAction.library,
                enabled: youtubeAccountProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.video_library_outlined),
                  title: Text('My playlists and subscriptions'),
                ),
              ),
              PopupMenuItem<_YouTubeAccountAction>(
                value: _YouTubeAccountAction.configure,
                enabled:
                    youtubeAccount?.loaded == true &&
                    youtubeAccount?.desktopOAuthSupported == true &&
                    !offlineModeEnabled,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login_outlined),
                  title: Text(
                    youtubeAccount?.isConfigured == true
                        ? 'Replace account connection'
                        : 'Connect account',
                  ),
                ),
              ),
              PopupMenuItem<_YouTubeAccountAction>(
                value: _YouTubeAccountAction.remove,
                enabled: youtubeAccount?.isConfigured == true,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout_outlined),
                  title: Text('Disconnect account'),
                ),
              ),
            ],
          ),
        ),
        if (youtubeAccount?.loaded != true) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (youtubeAccount?.loadError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('YouTube account library unavailable'),
            subtitle: Text(youtubeAccount!.loadError!),
          ),
        ],
        const SizedBox(height: 8),
        _ProviderCard(
          title: 'Spotify Web API',
          status: spotify?.isConfigured == true ? 'Enabled' : 'Optional',
          description: spotify?.isConfigured == true
              ? 'Searches and reads saved Spotify track metadata. Playback and offline media are unavailable.'
              : 'Connect your own Spotify developer app for official metadata access.',
          icon: Icons.library_music_outlined,
          capabilities:
              spotifyProvider?.capabilities ??
              const <MusicSourceCapability>{
                MusicSourceCapability.metadataSearch,
                MusicSourceCapability.artwork,
                MusicSourceCapability.authentication,
              },
          disclosure:
              spotifyProvider?.disclosure ??
              const ProviderPrivacyDisclosure(
                networkDomains: <String>[
                  'accounts.spotify.com',
                  'api.spotify.com',
                ],
                requiresUserCredentials: true,
              ),
          actions: PopupMenuButton<_SpotifyAction>(
            tooltip: 'Manage Spotify Web API',
            onSelected: (action) {
              switch (action) {
                case _SpotifyAction.savedTracks:
                  if (spotifyProvider != null) {
                    _openSpotifySavedTracks(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.savedEpisodes:
                  if (spotifyProvider != null) {
                    _openSpotifySavedEpisodes(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.savedShows:
                  if (spotifyProvider != null) {
                    _openSpotifySavedShows(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.savedAlbums:
                  if (spotifyProvider != null) {
                    _openSpotifySavedAlbums(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.playlists:
                  if (spotifyProvider != null) {
                    _openSpotifyPlaylists(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.recentlyPlayed:
                  if (spotifyProvider != null) {
                    _openSpotifyRecentlyPlayed(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.topTracks:
                  if (spotifyProvider != null) {
                    _openSpotifyTopTracks(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.topArtists:
                  if (spotifyProvider != null) {
                    _openSpotifyTopArtists(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.followedArtists:
                  if (spotifyProvider != null) {
                    _openSpotifyFollowedArtists(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.newReleases:
                  if (spotifyProvider != null) {
                    _openSpotifyNewReleases(context, spotifyProvider);
                  }
                  break;
                case _SpotifyAction.configure:
                  unawaited(_configureSpotify(context));
                  break;
                case _SpotifyAction.remove:
                  unawaited(_removeSpotify(context));
                  break;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_SpotifyAction>>[
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.savedTracks,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.library_music_outlined),
                  title: Text('Saved tracks'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.savedAlbums,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.album_outlined),
                  title: Text('Saved albums'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.playlists,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.queue_music_outlined),
                  title: Text('Playlists'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.recentlyPlayed,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.history_outlined),
                  title: Text('Recently played'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.topTracks,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.auto_graph_outlined),
                  title: Text('Top tracks'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.topArtists,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.people_alt_outlined),
                  title: Text('Top artists'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.savedEpisodes,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.podcasts_outlined),
                  title: Text('Saved episodes'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.savedShows,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.video_library_outlined),
                  title: Text('Saved shows'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.followedArtists,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_search_outlined),
                  title: Text('Followed artists'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.newReleases,
                enabled: spotifyProvider != null && !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.new_releases_outlined),
                  title: Text('New releases'),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.configure,
                enabled:
                    spotify?.loaded == true &&
                    !offlineModeEnabled &&
                    spotify?.connecting != true,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login_outlined),
                  title: Text(
                    spotify?.isConfigured == true
                        ? 'Reconnect Spotify'
                        : 'Connect Spotify',
                  ),
                ),
              ),
              PopupMenuItem<_SpotifyAction>(
                value: _SpotifyAction.remove,
                enabled: spotify?.isConfigured == true,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Disconnect Spotify'),
                ),
              ),
            ],
          ),
        ),
        if (spotify?.connecting == true) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          const Text('Waiting for Spotify authorization in your browser.'),
        ] else if (spotify?.loaded != true) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (spotify?.loadError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Spotify connection unavailable'),
            subtitle: Text(spotify!.loadError!),
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
            OutlinedButton.icon(
              onPressed:
                  selfHostedActionsEnabled && selfHosted.accounts.isNotEmpty
                  ? () => unawaited(
                      _exportSelfHostedAccountConfiguration(context),
                    )
                  : null,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Export servers'),
            ),
            OutlinedButton.icon(
              onPressed: selfHostedActionsEnabled
                  ? () => unawaited(
                      _showSelfHostedAccountConfigurationImport(context),
                    )
                  : null,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import servers'),
            ),
            OutlinedButton.icon(
              key: const Key('upload-self-hosted-accounts-to-sync'),
              onPressed:
                  selfHosted.loaded &&
                      librarySync?.isConfigured == true &&
                      !offlineModeEnabled
                  ? () => unawaited(
                      _uploadSelfHostedAccountConfigurationToSync(context),
                    )
                  : null,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload to sync server'),
            ),
            OutlinedButton.icon(
              key: const Key('import-self-hosted-accounts-from-sync'),
              onPressed:
                  selfHosted.loaded &&
                      librarySync?.isConfigured == true &&
                      !offlineModeEnabled
                  ? () => unawaited(
                      _importSelfHostedAccountConfigurationFromSync(context),
                    )
                  : null,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Import from sync server'),
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
              onTap:
                  selfHostedActionsEnabled &&
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
                        unawaited(_browseSelfHostedAccount(context, account));
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
                    enabled:
                        selfHostedActionsEnabled &&
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
                    enabled:
                        selfHostedActionsEnabled &&
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
            OutlinedButton.icon(
              key: const Key('export-custom-catalogs'),
              onPressed:
                  customCatalogs?.loaded == true &&
                      customCatalogs!.definitions.isNotEmpty
                  ? () => unawaited(_exportCustomCatalogConfiguration(context))
                  : null,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Export catalogs'),
            ),
            OutlinedButton.icon(
              key: const Key('import-custom-catalogs'),
              onPressed: customCatalogs?.loaded == true && !offlineModeEnabled
                  ? () => unawaited(
                      _importCustomCatalogConfigurationFile(context),
                    )
                  : null,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Import catalogs'),
            ),
            OutlinedButton.icon(
              key: const Key('upload-custom-catalogs-to-sync'),
              onPressed:
                  customCatalogs?.loaded == true &&
                      librarySync?.isConfigured == true &&
                      !offlineModeEnabled
                  ? () => unawaited(
                      _uploadCustomCatalogConfigurationToSync(context),
                    )
                  : null,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload to sync server'),
            ),
            OutlinedButton.icon(
              key: const Key('import-custom-catalogs-from-sync'),
              onPressed:
                  customCatalogs?.loaded == true &&
                      librarySync?.isConfigured == true &&
                      !offlineModeEnabled
                  ? () => unawaited(
                      _importCustomCatalogConfigurationFromSync(context),
                    )
                  : null,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Import from sync server'),
            ),
          ],
        ),
        if (customCatalogs == null || !customCatalogs.loaded) ...<Widget>[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ] else if (customCatalogs.loadError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.extension_off_outlined),
            title: const Text('Custom catalogs unavailable'),
            subtitle: Text(customCatalogs.loadError!),
          ),
        ] else if (customCatalogs.definitions.isEmpty)
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
          description:
              'No DRM bypass, scraping, or paid-service cloning is included.',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: 16),
        Text('Provider search', style: Theme.of(context).textTheme.titleMedium),
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
              onPressed: _providerSearchLoading ? null : _submitProviderSearch,
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
                  tooltip:
                      '${suggestion.providerName} '
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
        if (providerSearchSources.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Semantics(
            label: 'Filter provider search results by source',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  key: const ValueKey<String>('provider-search-source-all'),
                  label: const Text('All sources'),
                  selected: selectedProviderSearchSourceId == null,
                  onSelected: (_) {
                    setState(() => _providerSearchSourceFilterId = null);
                  },
                ),
                for (final source in providerSearchSources.entries)
                  ChoiceChip(
                    key: ValueKey<String>(
                      'provider-search-source-${source.key}',
                    ),
                    label: Text(source.value),
                    selected: source.key == selectedProviderSearchSourceId,
                    onSelected: (selected) {
                      setState(
                        () => _providerSearchSourceFilterId = selected
                            ? source.key
                            : null,
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
        for (final error in visibleProviderSearchErrors) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text('${error.providerName} failed'),
            subtitle: Text(error.message),
          ),
        ],
        if (visibleProviderSearchResults.isEmpty &&
            !_providerSearchLoading &&
            _providerSearchMessage == null &&
            visibleProviderSearchErrors.isEmpty) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.public),
            title: Text(
              selectedProviderSearchSourceId == null
                  ? 'No search results loaded'
                  : 'No results from ${providerSearchSources[selectedProviderSearchSourceId]}',
            ),
            subtitle: Text(
              selectedProviderSearchSourceId == null
                  ? 'Search Local Library, Demo Provider, Radio Browser, and Internet Archive.'
                  : 'Choose All sources to see retained results from every provider.',
            ),
          ),
        ],
        if (visibleProviderSearchResults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          for (final result in visibleProviderSearchResults)
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
                    onPressed: () =>
                        _saveProviderSearchTrack(context, result.track),
                    icon: const Icon(Icons.library_add_outlined),
                  ),
                  _offlineQueueMenu(
                    context: context,
                    track: result.track,
                    decisionFor: (action) => _providerSearchCoordinator
                        .offlineDecision(result.track, action),
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
        for (final error in visibleProviderSearchLoadMoreErrors) ...<Widget>[
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
            visibleProviderSearchLoadMoreErrors.isNotEmpty &&
            visibleProviderSearchFailedContinuations.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              key: const ValueKey<String>('provider-search-load-more-retry'),
              onPressed: offlineModeEnabled && !_providerSearchLocalOnly
                  ? null
                  : () => unawaited(
                      _continueProviderCatalogSearch(
                        continuations: visibleProviderSearchFailedContinuations,
                      ),
                    ),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry failed providers'),
            ),
          ),
        ] else if (!_providerSearchLoadingMore &&
            visibleProviderSearchLoadMoreErrors.isEmpty &&
            visibleProviderSearchContinuations.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: OutlinedButton.icon(
              key: const ValueKey<String>('provider-search-load-more'),
              onPressed: offlineModeEnabled && !_providerSearchLocalOnly
                  ? null
                  : () => unawaited(
                      _continueProviderCatalogSearch(
                        continuations: visibleProviderSearchContinuations,
                      ),
                    ),
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more provider results'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text('Video', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ListTile(
          key: const Key('video-player-open'),
          leading: const Icon(Icons.video_file_outlined),
          title: const Text('Open video'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                key: const Key('video-player-open-local'),
                tooltip: 'Open local video',
                onPressed: () => unawaited(_openLocalVideo(context)),
                icon: const Icon(Icons.folder_open_outlined),
              ),
              IconButton(
                key: const Key('video-player-open-url'),
                tooltip: 'Open HTTPS video',
                onPressed: offlineModeEnabled
                    ? null
                    : () => unawaited(_openVideoUrl(context)),
                icon: const Icon(Icons.link),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Podcast RSS feeds',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('podcast-directory-query'),
          controller: _podcastDirectoryQueryController,
          enabled: !offlineModeEnabled,
          decoration: InputDecoration(
            labelText: 'Find podcasts',
            helperText: 'Searches the public Apple podcast directory.',
            prefixIcon: const Icon(Icons.manage_search_outlined),
            suffixIcon: IconButton(
              key: const Key('podcast-directory-search'),
              tooltip: 'Search podcast directory',
              onPressed: offlineModeEnabled || _podcastDirectoryLoading
                  ? null
                  : () => _searchPodcastDirectory(context),
              icon: _podcastDirectoryLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
            ),
          ),
          textInputAction: TextInputAction.search,
          onSubmitted: offlineModeEnabled || _podcastDirectoryLoading
              ? null
              : (_) => _searchPodcastDirectory(context),
          onChanged: _schedulePodcastDirectorySuggestions,
        ),
        if (_podcastDirectoryError != null) ...<Widget>[
          const SizedBox(height: 8),
          ListTile(
            key: const Key('podcast-directory-error'),
            leading: const Icon(Icons.error_outline),
            title: const Text('Podcast directory search failed'),
            subtitle: Text(_podcastDirectoryError!),
          ),
        ],
        if (_podcastDirectoryResults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            'Podcast directory results',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final result in _podcastDirectoryResults)
            ListTile(
              key: ValueKey<String>(
                'podcast-directory-result-${result.feedUri}',
              ),
              leading: const Icon(Icons.podcasts_outlined),
              title: Text(result.title),
              subtitle: Text(
                <String>[
                  result.author,
                  result.genre,
                ].where((value) => value.isNotEmpty).join(' · '),
              ),
              trailing: TextButton(
                key: ValueKey<String>(
                  'podcast-directory-subscribe-${result.feedUri}',
                ),
                onPressed: _podcastLoading || offlineModeEnabled
                    ? null
                    : () => _subscribeToPodcastDirectoryResult(context, result),
                child: const Text('Subscribe'),
              ),
            ),
        ],
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
                onSubmitted: offlineModeEnabled
                    ? null
                    : (_) => _addPodcastFeed(context),
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
              onPressed:
                  _podcastLoading ||
                      offlineModeEnabled ||
                      podcastSubscriptions.isEmpty
                  ? null
                  : () => _refreshAllPodcastFeeds(context),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh all'),
            ),
            if (podcastChapterHosts != null)
              OutlinedButton.icon(
                onPressed: podcastChapterHosts.loaded
                    ? () => _showPodcastChapterHostManager(context)
                    : null,
                icon: const Icon(Icons.policy_outlined),
                label: const Text('Chapter hosts'),
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
                      decisionFor: (action) =>
                          _podcastOfflineDecision(context, track, action),
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
                onSubmitted: offlineModeEnabled
                    ? null
                    : (_) => _searchRadioStations(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Search stations',
              onPressed:
                  _radioLoading || _radioLoadingMore || offlineModeEnabled
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
              onPressed:
                  _radioLoading || _radioLoadingMore || offlineModeEnabled
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
        ] else if (_archiveItems.isNotEmpty &&
            _archiveTotalResults != null) ...<Widget>[
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
        const SizedBox(height: 16),
        _ProviderCard(
          title: itunesProvider.name,
          status: itunesStatus,
          description: itunesProvider.description,
          icon: Icons.storefront_outlined,
          capabilities: itunesProvider.capabilities,
          disclosure: itunesProvider.disclosure,
          actions: PopupMenuButton<_ItunesAction>(
            tooltip: 'Manage iTunes Store metadata',
            onSelected: (action) {
              switch (action) {
                case _ItunesAction.browseAlbums:
                  _openItunesAlbums(context, itunesProvider);
                  break;
                case _ItunesAction.chooseStorefront:
                  unawaited(_configureItunesStorefront(context));
                  break;
              }
            },
            itemBuilder: (_) => <PopupMenuEntry<_ItunesAction>>[
              PopupMenuItem<_ItunesAction>(
                value: _ItunesAction.browseAlbums,
                enabled: !offlineModeEnabled,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.album_outlined),
                  title: Text('Browse public albums'),
                ),
              ),
              const PopupMenuItem<_ItunesAction>(
                value: _ItunesAction.chooseStorefront,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.public_outlined),
                  title: Text('Choose storefront'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _browseSelfHostedAccount(
    BuildContext context,
    SelfHostedProviderAccount account,
  ) async {
    final provider = context.read<SelfHostedProviderStore>().catalogProviderFor(
      account.id,
    );
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

  void _openJamendoCollections(BuildContext context, JamendoProvider provider) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelfHostedBrowseScreen(
          provider: provider,
          collectionKinds: const <MusicCatalogCollectionKind>[
            MusicCatalogCollectionKind.artist,
            MusicCatalogCollectionKind.album,
            MusicCatalogCollectionKind.playlist,
          ],
        ),
      ),
    );
  }

  void _openItunesAlbums(
    BuildContext context,
    ItunesMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelfHostedBrowseScreen(
          provider: provider,
          collectionKinds: const <MusicCatalogCollectionKind>[
            MusicCatalogCollectionKind.album,
          ],
        ),
      ),
    );
  }

  Future<void> _configureItunesStorefront(BuildContext context) async {
    final store = context.read<ItunesMetadataSettingsStore?>();
    if (store == null) {
      return;
    }
    final controller = TextEditingController(text: store.storefront);
    try {
      final storefront = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Choose iTunes Store storefront'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Use a two-letter ISO country code. This changes only '
                  'future public metadata searches; no account or media '
                  'access is used.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('itunes-storefront'),
                  controller: controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Storefront',
                    counterText: '',
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(value),
                ),
              ],
            ),
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
      if (!context.mounted || storefront == null) {
        return;
      }
      final previousStorefront = store.storefront;
      await store.setStorefront(storefront);
      if (!context.mounted || store.storefront == previousStorefront) {
        return;
      }
      _providerSearchRequestSerial += 1;
      _providerSearchSuggestionRequestSerial += 1;
      setState(() {
        _providerSearchLoading = false;
        _providerSearchLoadingMore = false;
        _providerSearchSuggestionsLoading = false;
        _providerSearchResults.removeWhere(
          (result) => result.providerId == 'itunes-metadata',
        );
        _providerSearchErrors.removeWhere(
          (error) => error.providerId == 'itunes-metadata',
        );
        _providerSearchLoadMoreErrors.removeWhere(
          (error) => error.providerId == 'itunes-metadata',
        );
        _providerSearchSuggestions.removeWhere(
          (suggestion) => suggestion.providerId == 'itunes-metadata',
        );
        _providerSearchContinuations.remove('itunes-metadata');
        _providerSearchFailedContinuations.remove('itunes-metadata');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'iTunes Store metadata searches now use ${store.storefront}.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _configureJamendo(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final clientId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Configure Jamendo API'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Use a client ID from your own Jamendo developer application. Jamendo searches and streams returned public tracks; AetherTune does not cache or download them.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('jamendo-client-id'),
                  controller: controller,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Jamendo client ID',
                  ),
                ),
              ],
            ),
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
      if (!context.mounted || clientId == null) {
        return;
      }
      final store = context.read<JamendoSettingsStore?>();
      if (store == null) {
        return;
      }
      await store.saveClientId(clientId);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jamendo music search enabled.')),
      );
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _removeJamendo(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Jamendo client ID?'),
        content: const Text(
          'This disables Jamendo search and streaming on this device. Saved entries remain unchanged.',
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
    final store = context.read<JamendoSettingsStore?>();
    if (store == null) {
      return;
    }
    await context.read<PlayerController>().removeTracksFromSource('jamendo');
    await store.removeClientId();
    if (!context.mounted) {
      return;
    }
    _providerSearchRequestSerial += 1;
    setState(() {
      _providerSearchLoading = false;
      _providerSearchLoadingMore = false;
      _providerSearchResults.removeWhere(
        (result) => result.providerId == 'jamendo',
      );
      _providerSearchErrors.removeWhere(
        (error) => error.providerId == 'jamendo',
      );
      _providerSearchLoadMoreErrors.removeWhere(
        (error) => error.providerId == 'jamendo',
      );
      _providerSearchContinuations.remove('jamendo');
      _providerSearchFailedContinuations.remove('jamendo');
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Jamendo client ID removed.')));
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
                      'This source searches and browses official music video metadata only. It does not play, download, or cache YouTube audiovisual content and does not sign in to a YouTube account.',
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
        const SnackBar(
          content: Text('YouTube Data API metadata search enabled.'),
        ),
      );
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      keyController.dispose();
    }
  }

  void _openYouTubeMusicChart(
    BuildContext context,
    YouTubeDataMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubeMusicChartScreen(provider: provider),
      ),
    );
  }

  void _openAudiusCollections(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelfHostedBrowseScreen(
          provider: _audiusProvider,
          collectionKinds: const <MusicCatalogCollectionKind>[
            MusicCatalogCollectionKind.artist,
            MusicCatalogCollectionKind.album,
            MusicCatalogCollectionKind.playlist,
          ],
        ),
      ),
    );
  }

  void _openYouTubeChannels(
    BuildContext context,
    YouTubeDataMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubeChannelFollowScreen(provider: provider),
      ),
    );
  }

  void _openYouTubePublicPlaylists(
    BuildContext context,
    YouTubeDataMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubePublicPlaylistsScreen(provider: provider),
      ),
    );
  }

  void _openYouTubeAccountLibrary(
    BuildContext context,
    YouTubeAccountProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubeAccountLibraryScreen(provider: provider),
      ),
    );
  }

  Future<void> _configureYouTubeAccount(BuildContext context) async {
    final clientIdController = TextEditingController();
    String? validationError;
    try {
      final clientId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Connect YouTube account library'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'AetherTune uses Google Authorization Code with PKCE and a temporary loopback callback. Create your own Google OAuth desktop client and add http://127.0.0.1 as an authorized redirect URI without a port.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'The connection reads playlist, playlist-item, and subscription metadata only. It does not play, download, cache, upload, or change YouTube content.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('youtube-account-client-id'),
                      controller: clientIdController,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Google OAuth desktop client ID',
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isEmpty) {
                          setDialogState(
                            () => validationError =
                                'Enter a Google OAuth desktop client ID.',
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
                  final value = clientIdController.text.trim();
                  if (value.isEmpty) {
                    setDialogState(
                      () => validationError =
                          'Enter a Google OAuth desktop client ID.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Authorize'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || clientId == null) {
        return;
      }
      final store = context.read<YouTubeAccountSettingsStore?>();
      if (store == null) {
        return;
      }
      await store.connect(clientId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('YouTube account library enabled.')),
        );
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on StateError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      clientIdController.dispose();
    }
  }

  Future<void> _removeYouTubeAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect YouTube account library?'),
        content: const Text(
          'This removes the YouTube access and refresh tokens from this device. Saved metadata entries remain unchanged.',
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
    final store = context.read<YouTubeAccountSettingsStore?>();
    if (store == null) {
      return;
    }
    await store.remove();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('YouTube account library disconnected.')),
      );
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
    await context.read<PlayerController>().removeTracksFromSource(
      'youtube-data-metadata',
    );
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

  Future<void> _configureSpotify(BuildContext context) async {
    final clientIdController = TextEditingController();
    String? validationError;
    try {
      final clientId = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Connect Spotify Web API'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'AetherTune uses Spotify Authorization Code with PKCE. Create your own Spotify developer app, then add http://127.0.0.1 as an allowed redirect URI without a port. AetherTune opens the authorization page and uses a temporary local callback port.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Spotify searches and reads saved-track metadata and artwork only. It does not play, download, cache, or copy Spotify audio.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('spotify-client-id'),
                      controller: clientIdController,
                      enableSuggestions: false,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Spotify developer client ID',
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isEmpty) {
                          setDialogState(
                            () => validationError =
                                'Enter a Spotify developer client ID.',
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
                  final value = clientIdController.text.trim();
                  if (value.isEmpty) {
                    setDialogState(
                      () => validationError =
                          'Enter a Spotify developer client ID.',
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop(value);
                },
                child: const Text('Authorize'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || clientId == null) {
        return;
      }
      final store = context.read<SpotifySettingsStore?>();
      if (store == null) {
        return;
      }
      await store.connect(clientId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Spotify metadata search enabled.')),
        );
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on StateError catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      clientIdController.dispose();
    }
  }

  void _openSpotifySavedTracks(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifySavedTracksScreen(provider: provider),
      ),
    );
  }

  void _openSpotifySavedEpisodes(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SpotifySavedTracksScreen(provider: provider, savedEpisodes: true),
      ),
    );
  }

  void _openSpotifySavedShows(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifySavedShowsScreen(provider: provider),
      ),
    );
  }

  void _openSpotifySavedAlbums(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifySavedAlbumsScreen(provider: provider),
      ),
    );
  }

  void _openSpotifyPlaylists(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifySavedPlaylistsScreen(provider: provider),
      ),
    );
  }

  void _openSpotifyTopTracks(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SpotifySavedTracksScreen(provider: provider, topTracks: true),
      ),
    );
  }

  void _openSpotifyTopArtists(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifyTopArtistsScreen(provider: provider),
      ),
    );
  }

  void _openSpotifyFollowedArtists(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SpotifyTopArtistsScreen(provider: provider, followedArtists: true),
      ),
    );
  }

  void _openSpotifyNewReleases(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SpotifySavedAlbumsScreen(provider: provider, newReleases: true),
      ),
    );
  }

  void _openSpotifyRecentlyPlayed(
    BuildContext context,
    SpotifyMetadataProvider provider,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifyRecentlyPlayedScreen(provider: provider),
      ),
    );
  }

  Future<void> _removeSpotify(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect Spotify?'),
        content: const Text(
          'This removes the Spotify access and refresh tokens from this device. Saved metadata entries remain unchanged.',
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
    final store = context.read<SpotifySettingsStore?>();
    if (store == null) {
      return;
    }
    await context.read<PlayerController>().removeTracksFromSource(
      'spotify-metadata',
    );
    await store.remove();
    if (!context.mounted) {
      return;
    }
    _providerSearchRequestSerial += 1;
    setState(() {
      _providerSearchLoading = false;
      _providerSearchLoadingMore = false;
      _providerSearchResults.removeWhere(
        (result) => result.providerId == 'spotify-metadata',
      );
      _providerSearchErrors.removeWhere(
        (error) => error.providerId == 'spotify-metadata',
      );
      _providerSearchLoadMoreErrors.removeWhere(
        (error) => error.providerId == 'spotify-metadata',
      );
      _providerSearchContinuations.remove('spotify-metadata');
      _providerSearchFailedContinuations.remove('spotify-metadata');
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Spotify disconnected.')));
  }

  Future<void> _exportCustomCatalogConfiguration(BuildContext context) async {
    final export = context.read<CustomCatalogStore>().exportConfiguration();
    final messenger = ScaffoldMessenger.of(context);
    const fileName = 'aethertune-custom-catalogs.json';
    try {
      final bytes = Uint8List.fromList(utf8.encode(export.json));
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Export custom catalogs',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
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
      final skipped = export.skippedInsecureCatalogCount;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${export.exportedCatalogCount} '
            '${export.exportedCatalogCount == 1 ? 'catalog' : 'catalogs'}'
            '${skipped == 0 ? '.' : '; skipped $skipped HTTP catalog${skipped == 1 ? '' : 's'}.'}',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export catalogs: $error')),
      );
    }
  }

  Future<void> _uploadCustomCatalogConfigurationToSync(
    BuildContext context,
  ) async {
    final catalogs = context.read<CustomCatalogStore>();
    final export = catalogs.exportConfiguration();
    final document = jsonDecode(export.json);
    if (document is! Map) {
      throw const FormatException('Custom catalog configuration is invalid.');
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context
          .read<LibrarySyncStore>()
          .updateProviderConfiguration(
            context.read<LibraryStore>(),
            (remoteSnapshot) => _providerConfigurationWithSection(
              remoteSnapshot,
              section: 'customCatalogs',
              document: Map<String, Object?>.from(document),
            ),
          );
      if (!context.mounted) {
        return;
      }
      final skipped = export.skippedInsecureCatalogCount;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Uploaded ${export.exportedCatalogCount} secure '
            '${export.exportedCatalogCount == 1 ? 'catalog' : 'catalogs'} '
            'at provider revision ${result.revision}'
            '${skipped == 0 ? '.' : '; skipped $skipped HTTP catalog${skipped == 1 ? '' : 's'}.'}',
          ),
        ),
      );
    } on LibrarySyncConflictException {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Provider settings changed remotely. Import them before uploading again.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not upload catalogs: $error')),
      );
    }
  }

  Future<void> _importCustomCatalogConfigurationFromSync(
    BuildContext context,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final remote = await context
          .read<LibrarySyncStore>()
          .fetchProviderConfiguration(context.read<LibraryStore>());
      final snapshot = remote.snapshot;
      if (snapshot == null) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No provider configuration is stored on this sync server.',
              ),
            ),
          );
        }
        return;
      }
      _validateProviderConfigurationRoot(snapshot);
      final customCatalogs = snapshot['customCatalogs'];
      if (customCatalogs is! Map) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No custom catalogs are stored on this sync server.'),
          ),
        );
        return;
      }
      if (!context.mounted) {
        return;
      }
      final result = await context
          .read<CustomCatalogStore>()
          .importConfiguration(jsonEncode(customCatalogs));
      if (!context.mounted) {
        return;
      }
      final parts = <String>[
        '${result.importedCatalogCount} imported',
        if (result.skippedExistingCatalogCount > 0)
          '${result.skippedExistingCatalogCount} already configured',
        if (result.skippedInsecureCatalogCount > 0)
          '${result.skippedInsecureCatalogCount} HTTP catalog${result.skippedInsecureCatalogCount == 1 ? '' : 's'} skipped',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Provider configuration revision ${remote.revision}: ${parts.join(', ')}.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not import synced catalogs: $error')),
      );
    }
  }

  Map<String, Object?> _providerConfigurationWithSection(
    Map<String, Object?>? remoteSnapshot, {
    required String section,
    required Map<String, Object?> document,
  }) {
    final root = Map<String, Object?>.from(
      remoteSnapshot ??
          const <String, Object?>{
            'format': 'aethertune.provider_configurations',
            'version': 1,
          },
    );
    if (remoteSnapshot != null) {
      _validateProviderConfigurationRoot(root);
    }
    return <String, Object?>{...root, section: document};
  }

  void _validateProviderConfigurationRoot(Map<String, Object?> snapshot) {
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

  Future<void> _uploadSelfHostedAccountConfigurationToSync(
    BuildContext context,
  ) async {
    final accounts = context.read<SelfHostedProviderStore>();
    final export = accounts.exportAccountConfiguration();
    final document = jsonDecode(export.json);
    if (document is! Map) {
      throw const FormatException(
        'Self-hosted account configuration is invalid.',
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context
          .read<LibrarySyncStore>()
          .updateProviderConfiguration(
            context.read<LibraryStore>(),
            (remoteSnapshot) => _providerConfigurationWithSection(
              remoteSnapshot,
              section: 'selfHostedAccounts',
              document: Map<String, Object?>.from(document),
            ),
          );
      if (!context.mounted) {
        return;
      }
      final skipped = export.skippedInsecureAccountCount;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Uploaded ${export.exportedAccountCount} secure '
            '${export.exportedAccountCount == 1 ? 'server' : 'servers'} '
            'at provider revision ${result.revision}'
            '${skipped == 0 ? '.' : '; skipped $skipped HTTP server${skipped == 1 ? '' : 's'}.'}',
          ),
        ),
      );
    } on LibrarySyncConflictException {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Provider settings changed remotely. Import them before uploading again.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not upload servers: $error')),
      );
    }
  }

  Future<void> _importSelfHostedAccountConfigurationFromSync(
    BuildContext context,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final remote = await context
          .read<LibrarySyncStore>()
          .fetchProviderConfiguration(context.read<LibraryStore>());
      final snapshot = remote.snapshot;
      if (snapshot == null) {
        if (context.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No provider configuration is stored on this sync server.',
              ),
            ),
          );
        }
        return;
      }
      _validateProviderConfigurationRoot(snapshot);
      final selfHostedAccounts = snapshot['selfHostedAccounts'];
      if (selfHostedAccounts is! Map) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No self-hosted servers are stored on this sync server.',
            ),
          ),
        );
        return;
      }
      if (!context.mounted) {
        return;
      }
      final result = await context
          .read<SelfHostedProviderStore>()
          .importAccountConfiguration(jsonEncode(selfHostedAccounts));
      if (!context.mounted) {
        return;
      }
      final parts = <String>[
        '${result.importedAccountCount} imported',
        if (result.skippedExistingAccountCount > 0)
          '${result.skippedExistingAccountCount} already configured',
        if (result.skippedInsecureAccountCount > 0)
          '${result.skippedInsecureAccountCount} HTTP server${result.skippedInsecureAccountCount == 1 ? '' : 's'} skipped',
      ];
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Provider configuration revision ${remote.revision}: ${parts.join(', ')}. Credentials remain local.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not import synced servers: $error')),
      );
    }
  }

  Future<void> _importCustomCatalogConfigurationFile(
    BuildContext context,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );
      if (files.isEmpty) {
        return;
      }
      final document = utf8.decode(await readPickedFileBytes(files.first));
      if (!context.mounted) {
        return;
      }
      final imported = await context
          .read<CustomCatalogStore>()
          .importConfiguration(document);
      if (!context.mounted) {
        return;
      }
      final parts = <String>[
        '${imported.importedCatalogCount} imported',
        if (imported.skippedExistingCatalogCount > 0)
          '${imported.skippedExistingCatalogCount} already configured',
        if (imported.skippedInsecureCatalogCount > 0)
          '${imported.skippedInsecureCatalogCount} HTTP catalog${imported.skippedInsecureCatalogCount == 1 ? '' : 's'} skipped',
      ];
      messenger.showSnackBar(
        SnackBar(content: Text('Catalog configuration: ${parts.join(', ')}.')),
      );
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not import catalogs: $error')),
      );
    }
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
                      decoration: const InputDecoration(
                        labelText: 'Catalog name',
                      ),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
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
    final player = context.read<PlayerController>();
    try {
      await store.remove(definition.id);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove the catalog.')),
        );
      }
      return;
    }
    var queueCleanupFailed = false;
    try {
      await player.removeTracksFromSource(definition.providerId);
    } on Object {
      queueCleanupFailed = true;
    }
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
      SnackBar(
        content: Text(
          queueCleanupFailed
              ? 'Removed ${definition.name}, but its playback queue could not be updated.'
              : 'Removed ${definition.name}.',
        ),
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

  Future<void> _exportSelfHostedAccountConfiguration(
    BuildContext context,
  ) async {
    final export = context
        .read<SelfHostedProviderStore>()
        .exportAccountConfiguration();
    final messenger = ScaffoldMessenger.of(context);
    const fileName = 'aethertune-self-hosted-accounts.json';

    try {
      final bytes = Uint8List.fromList(utf8.encode(export.json));
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Export self-hosted servers',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
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
      final skipped = export.skippedInsecureAccountCount;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${export.exportedAccountCount} server '
            '${export.exportedAccountCount == 1 ? 'configuration' : 'configurations'}'
            '${skipped == 0 ? '.' : '; skipped $skipped HTTP server${skipped == 1 ? '' : 's'}.'}',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not export servers: $error')),
      );
    }
  }

  Future<void> _showSelfHostedAccountConfigurationImport(
    BuildContext context,
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
                title: const Text('Choose server configuration'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importSelfHostedAccountConfigurationFile(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_outlined),
                title: const Text('Paste server configuration'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final document =
                      await _promptForSelfHostedAccountConfiguration(context);
                  if (!context.mounted || document == null) {
                    return;
                  }
                  await _importSelfHostedAccountConfiguration(
                    context,
                    document,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importSelfHostedAccountConfigurationFile(
    BuildContext context,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );
      if (files.isEmpty) {
        return;
      }
      final document = utf8.decode(await readPickedFileBytes(files.first));
      if (!context.mounted) {
        return;
      }
      await _importSelfHostedAccountConfiguration(context, document);
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read server configuration: $error')),
      );
    }
  }

  Future<void> _importSelfHostedAccountConfiguration(
    BuildContext context,
    String document,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await context
          .read<SelfHostedProviderStore>()
          .importAccountConfiguration(document);
      if (!context.mounted) {
        return;
      }
      final parts = <String>[
        '${result.importedAccountCount} imported',
        if (result.skippedExistingAccountCount > 0)
          '${result.skippedExistingAccountCount} already configured',
        if (result.skippedInsecureAccountCount > 0)
          '${result.skippedInsecureAccountCount} HTTP server${result.skippedInsecureAccountCount == 1 ? '' : 's'} skipped',
      ];
      messenger.showSnackBar(
        SnackBar(content: Text('Server configuration: ${parts.join(', ')}.')),
      );
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not import servers: $error')),
      );
    }
  }

  Future<String?> _promptForSelfHostedAccountConfiguration(
    BuildContext context,
  ) async {
    final controller = TextEditingController();
    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Import self-hosted servers'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                autofocus: true,
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Server configuration JSON',
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
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Removed ${account.name}.')));
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
          .where((provider) => provider.id == LocalLibraryProvider.providerId)
          .toList(growable: false);
    }

    final library = context.read<LibraryStore>();
    final localLibraryProvider = LocalLibraryProvider(
      searchTracks: (query) => library.search(query),
    );
    if (localOnly) {
      return <MusicSourceProvider>[localLibraryProvider];
    }
    final itunes = context.read<ItunesMetadataSettingsStore?>();

    return <MusicSourceProvider>[
      localLibraryProvider,
      _provider,
      _radioProvider,
      _archiveProvider,
      _audiusProvider,
      _musicBrainzMetadataProvider,
      ...(itunes?.musicProviders ??
          <MusicSourceProvider>[_itunesMetadataProvider]),
      ...?context.read<YouTubeDataSettingsStore?>()?.musicProviders,
      ...?context.read<JamendoSettingsStore?>()?.musicProviders,
      ...?context.read<SpotifySettingsStore?>()?.musicProviders,
      ...context.read<SelfHostedProviderStore>().musicProviders,
      ...?context.read<CustomCatalogStore?>()?.musicProviders,
    ];
  }

  Map<String, String> _providerSearchSourceFacets() {
    final sources = <String, String>{};
    void add(String providerId, String providerName) {
      if (providerId.trim().isNotEmpty && providerName.trim().isNotEmpty) {
        sources.putIfAbsent(providerId, () => providerName);
      }
    }

    for (final result in _providerSearchResults) {
      add(result.providerId, result.providerName);
    }
    for (final error in _providerSearchErrors) {
      add(error.providerId, error.providerName);
    }
    for (final error in _providerSearchLoadMoreErrors) {
      add(error.providerId, error.providerName);
    }
    final ordered = sources.entries.toList(growable: false)
      ..sort(
        (left, right) =>
            left.value.toLowerCase().compareTo(right.value.toLowerCase()),
      );
    return Map<String, String>.unmodifiable(<String, String>{
      for (final source in ordered) source.key: source.value,
    });
  }

  Map<String, String> _filterProviderContinuations(
    Map<String, String> continuations,
    String? providerId,
  ) {
    if (providerId == null) {
      return continuations;
    }
    final cursor = continuations[providerId];
    return cursor == null
        ? const <String, String>{}
        : <String, String>{providerId: cursor};
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
        unawaited(_queueOfflineTrack(context, track, decisionFor(action)));
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

    final subscription = context.read<LibraryStore>().podcastSubscriptionById(
      subscriptionId,
    );
    final feedUri = Uri.tryParse(subscription?.feedUrl ?? '');
    if (feedUri == null) {
      return OfflineMediaPolicyDecision(
        action: action,
        isAllowed: false,
        reason: 'No valid podcast feed is selected for this episode.',
      );
    }

    final provider = PodcastRssProvider(feedUri: feedUri, id: track.sourceId);
    return OfflineMediaPolicy(<MusicSourceProvider>[
      provider,
    ]).evaluate(track, action);
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
        _providerSearchSourceFilterId = null;
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
      _providerSearchSourceFilterId = null;
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
      () => unawaited(_loadProviderSearchSuggestions(query, requestSerial)),
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

  IconData _providerSearchSuggestionIcon(MusicSourceSearchSuggestionKind kind) {
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
      final playableTrack = await _providerSearchCoordinator
          .resolvePlayableTrack(track);
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
      final savedTrack = await _providerSearchCoordinator.resolvePlayableTrack(
        track,
      );
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

  Future<void> _openLocalVideo(BuildContext context) async {
    final file = await pickSingleFile(type: FileType.video);
    if (!context.mounted || file == null) {
      return;
    }

    final source = localVideoUri(file.path ?? '');
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that video file.')),
      );
      return;
    }
    _pushVideo(context, source, title: file.name);
  }

  Future<void> _openVideoUrl(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final rawUrl = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Open HTTPS video'),
          content: SizedBox(
            width: 480,
            child: TextField(
              autofocus: true,
              controller: controller,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Video URL'),
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Open'),
            ),
          ],
        ),
      );
      if (!context.mounted || rawUrl == null) {
        return;
      }

      final source = parseLegalVideoUrl(rawUrl);
      if (source == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a complete HTTPS video URL.')),
        );
        return;
      }
      _pushVideo(context, source, title: 'Direct video');
    } finally {
      controller.dispose();
    }
  }

  void _pushVideo(BuildContext context, Uri source, {required String title}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlaybackScreen(source: source, title: title),
      ),
    );
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

  Future<void> _searchPodcastDirectory(BuildContext context) async {
    final library = context.read<LibraryStore>();
    _podcastDirectorySuggestionDebounce?.cancel();
    final requestSerial = ++_podcastDirectoryRequestSerial;
    if (_offlineModeBlocksSourceNetwork(context)) {
      setState(() {
        _podcastDirectoryResults = <PodcastDirectoryResult>[];
        _podcastDirectoryError = 'Offline mode is on.';
      });
      return;
    }
    final query = _podcastDirectoryQueryController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _podcastDirectoryResults = <PodcastDirectoryResult>[];
        _podcastDirectoryError = 'Enter a podcast name or topic.';
      });
      return;
    }
    setState(() {
      _podcastDirectoryLoading = true;
      _podcastDirectorySuggestionLoading = false;
      _podcastDirectoryError = null;
    });
    try {
      final results = await _podcastDirectory.search(query);
      if (!mounted || requestSerial != _podcastDirectoryRequestSerial) {
        return;
      }
      if (library.offlineModeEnabled) {
        setState(() {
          _podcastDirectoryResults = <PodcastDirectoryResult>[];
          _podcastDirectoryLoading = false;
          _podcastDirectoryError = 'Offline mode is on.';
        });
        return;
      }
      setState(() {
        _podcastDirectoryResults = results;
        _podcastDirectoryLoading = false;
      });
    } on Object {
      if (!mounted || requestSerial != _podcastDirectoryRequestSerial) {
        return;
      }
      setState(() {
        _podcastDirectoryResults = <PodcastDirectoryResult>[];
        _podcastDirectoryLoading = false;
        _podcastDirectoryError = 'Try again after checking your connection.';
      });
    }
  }

  void _schedulePodcastDirectorySuggestions(String rawQuery) {
    _podcastDirectorySuggestionDebounce?.cancel();
    if (_podcastDirectoryLoading) {
      return;
    }
    final query = rawQuery.trim();
    final requestSerial = ++_podcastDirectoryRequestSerial;
    if (query.length < 2) {
      if (_podcastDirectorySuggestionLoading ||
          _podcastDirectoryResults.isNotEmpty ||
          _podcastDirectoryError != null) {
        setState(() {
          _podcastDirectorySuggestionLoading = false;
          _podcastDirectoryResults = <PodcastDirectoryResult>[];
          _podcastDirectoryError = null;
        });
      }
      return;
    }
    if (_offlineModeBlocksSourceNetwork(context)) {
      return;
    }
    setState(() {
      _podcastDirectorySuggestionLoading = true;
      _podcastDirectoryError = null;
    });
    _podcastDirectorySuggestionDebounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_loadPodcastDirectorySuggestions(query, requestSerial)),
    );
  }

  Future<void> _loadPodcastDirectorySuggestions(
    String query,
    int requestSerial,
  ) async {
    try {
      final results = await _podcastDirectory.search(query, limit: 6);
      if (!mounted || requestSerial != _podcastDirectoryRequestSerial) {
        return;
      }
      final library = context.read<LibraryStore>();
      if (library.offlineModeEnabled) {
        setState(() {
          _podcastDirectorySuggestionLoading = false;
          _podcastDirectoryResults = <PodcastDirectoryResult>[];
        });
        return;
      }
      setState(() {
        _podcastDirectorySuggestionLoading = false;
        _podcastDirectoryResults = results;
      });
    } on Object {
      if (!mounted || requestSerial != _podcastDirectoryRequestSerial) {
        return;
      }
      setState(() {
        _podcastDirectorySuggestionLoading = false;
        _podcastDirectoryResults = <PodcastDirectoryResult>[];
      });
    }
  }

  Future<void> _subscribeToPodcastDirectoryResult(
    BuildContext context,
    PodcastDirectoryResult result,
  ) async {
    _podcastFeedController.text = result.feedUri.toString();
    await _loadAndSavePodcastFeed(context, result.feedUri);
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
            child: SingleChildScrollView(child: SelectableText(opml)),
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
                decoration: const InputDecoration(labelText: 'OPML'),
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
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
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
    final chapterHosts = context.read<PodcastChapterHostPolicy?>();
    final messenger = ScaffoldMessenger.of(context);
    final provider =
        widget.podcastProviderFactory?.call(feedUri) ??
        PodcastRssProvider(
          feedUri: feedUri,
          isExternalChapterUriApproved: chapterHosts?.allows,
        );

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

      final unapprovedChapterHosts = feed.unapprovedExternalChapterHosts;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            unapprovedChapterHosts.isEmpty
                ? 'Loaded ${feed.title}.'
                : 'Chapters from ${unapprovedChapterHosts.first} need approval.',
          ),
          action: unapprovedChapterHosts.isEmpty
              ? null
              : SnackBarAction(
                  label: 'Review',
                  onPressed: () {
                    unawaited(
                      _showPodcastChapterHostManager(
                        context,
                        initialHost: unapprovedChapterHosts.first,
                        subscriptionId: refreshed.id,
                      ),
                    );
                  },
                ),
        ),
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

    final report = await PodcastSubscriptionRefreshWorker(
      isExternalChapterUriApproved: context
          .read<PodcastChapterHostPolicy?>()
          ?.allows,
    ).refreshSubscriptions(library, subscriptions: subscriptions);

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

  Future<void> _showPodcastChapterHostManager(
    BuildContext context, {
    String? initialHost,
    String? subscriptionId,
  }) async {
    final policy = context.read<PodcastChapterHostPolicy?>();
    if (policy == null) {
      return;
    }
    final controller = TextEditingController(text: initialHost ?? '');
    String? errorMessage;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              final approvalHistory = subscriptionId == null
                  ? const <PodcastChapterHostApproval>[]
                  : policy.approvalHistoryForSubscription(subscriptionId);
              return AlertDialog(
                title: const Text('External chapter hosts'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        controller: controller,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'HTTPS hostname',
                          hintText: 'chapters.example.com',
                        ),
                        onChanged: (_) {
                          if (errorMessage != null) {
                            setDialogState(() => errorMessage = null);
                          }
                        },
                      ),
                      if (errorMessage != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: TextStyle(
                            color: Theme.of(dialogContext).colorScheme.error,
                          ),
                        ),
                      ],
                      if (approvalHistory.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Approval history for this feed',
                            style: Theme.of(dialogContext).textTheme.labelLarge,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView(
                          shrinkWrap: true,
                          children: <Widget>[
                            for (final entry in approvalHistory)
                              ListTile(
                                key: Key(
                                  'podcast-chapter-host-history-${entry.host}',
                                ),
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.history_outlined),
                                title: Text(entry.host),
                                subtitle: Text(
                                  policy.approvedHosts.contains(entry.host)
                                      ? 'Approved for this feed'
                                      : 'Previously approved; currently revoked',
                                ),
                              ),
                            for (final host in policy.approvedHosts)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.verified_user_outlined,
                                ),
                                title: Text(host),
                                trailing: IconButton(
                                  tooltip: 'Revoke $host',
                                  onPressed: () async {
                                    await policy.revokeHost(host);
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              ),
                          ],
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
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        if (subscriptionId == null) {
                          await policy.approveHost(controller.text);
                        } else {
                          await policy.approveHostForSubscription(
                            subscriptionId,
                            controller.text,
                          );
                        }
                        controller.clear();
                        setDialogState(() => errorMessage = null);
                      } on FormatException catch (error) {
                        setDialogState(() => errorMessage = error.message);
                      } on Exception catch (error) {
                        setDialogState(() => errorMessage = error.toString());
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Approve'),
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Removed ${subscription.title}.')));
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

  String _podcastEpisodeSubtitle(Track track, PlaybackProgressEntry? progress) {
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

    messenger.showSnackBar(SnackBar(content: Text('Saved ${track.title}.')));
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

    final requestSerial = reset
        ? ++_archiveRequestSerial
        : _archiveRequestSerial;
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
    final playableFileCount = item.files
        .where((file) => file.isPlayableAudio)
        .length;
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
          onOpenCollection: (collection) =>
              _openArchiveCollection(context, collection),
        ),
      ),
    );
  }

  Future<void> _openArchiveCollection(BuildContext context, String collection) {
    final normalized = collection.trim();
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveCollectionScreen(
          collection: normalized,
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

    messenger.showSnackBar(SnackBar(content: Text('Saved ${track.title}.')));
  }
}
