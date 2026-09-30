part of 'home_screen.dart';

class _HomeTab extends StatefulWidget {
  const _HomeTab({
    required this.onImport,
    required this.onImportFolder,
    required this.onAddToPlaylist,
    required this.onLyrics,
    this.internetArchiveProvider,
    this.radioBrowserProvider,
  });

  final VoidCallback onImport;
  final VoidCallback onImportFolder;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;
  final InternetArchiveProvider? internetArchiveProvider;
  final RadioBrowserProvider? radioBrowserProvider;

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  static const ProviderHomeFeedCoordinator _providerHomeCoordinator =
      ProviderHomeFeedCoordinator();

  late final InternetArchiveProvider _archiveProvider;
  late final RadioBrowserProvider _radioProvider;
  final AudiusProvider _audiusProvider = AudiusProvider();
  final MusicBrainzArtistReleaseProvider _artistReleaseProvider =
      MusicBrainzArtistReleaseProvider();
  LibraryChartRange _chartRange = LibraryChartRange.thirtyDays;
  FollowingFeedSource _followingFeedSource = FollowingFeedSource.all;
  ProviderHomeFeed? _providerHomeFeed;
  String? _providerHomeSignature;
  bool _providerHomeLoading = false;
  final Set<String> _providerHomeLoadingMoreSections = <String>{};
  final Set<String> _providerHomeLoadMoreFailures = <String>{};
  int _providerHomeRequest = 0;

  @override
  void initState() {
    super.initState();
    _archiveProvider =
        widget.internetArchiveProvider ?? InternetArchiveProvider();
    _radioProvider = widget.radioBrowserProvider ?? RadioBrowserProvider();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final providerStore = context.watch<SelfHostedProviderStore>();
    final signature = _providerHomeStoreSignature(providerStore);
    if (_providerHomeSignature != null && _providerHomeSignature != signature) {
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
    final youtubeData = context.watch<YouTubeDataSettingsStore?>();
    final youtubeFollows = context.watch<YouTubeChannelFollowStore?>();
    final youtubeFollowedFeed = context
        .watch<YouTubeFollowedChannelFeedStore?>();
    final jamendo = context.watch<JamendoSettingsStore?>();
    final spotify = context.watch<SpotifySettingsStore?>();
    final player = context.read<PlayerController>();

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final sections = library.homeFeedSections();
    final youtubeFollowingTracks =
        youtubeFollowedFeed?.items
            .map((item) => item.track)
            .toList(growable: false) ??
        const <Track>[];
    final followingTracks = library.followingFeedTracks(
      source: _followingFeedSource,
      youtubeTracks: youtubeFollowingTracks,
    );
    final charts = library.localCharts(range: _chartRange);
    final recommendationMatches = library.personalizedRecommendationMatches(
      limit: 6,
    );
    final recommendations = recommendationMatches
        .map((match) => match.track)
        .toList(growable: false);
    final recommendationReasons = <String, List<LibraryRecommendationReason>>{
      for (final match in recommendationMatches) match.track.id: match.reasons,
    };
    final moodMixes = library.localMoodMixes(limit: 5);
    final providerCatalogs = _providerHomeCatalogs(providerStore);
    YouTubeDataMetadataProvider? youtubeProvider;
    for (final provider
        in youtubeData?.musicProviders ?? const <MusicSourceProvider>[]) {
      if (provider is YouTubeDataMetadataProvider) {
        youtubeProvider = provider;
        break;
      }
    }
    SpotifyMetadataProvider? spotifyProvider;
    for (final provider
        in spotify?.musicProviders ?? const <MusicSourceProvider>[]) {
      if (provider is SpotifyMetadataProvider) {
        spotifyProvider = provider;
        break;
      }
    }
    JamendoProvider? jamendoProvider;
    for (final provider
        in jamendo?.musicProviders ?? const <MusicSourceProvider>[]) {
      if (provider is JamendoProvider) {
        jamendoProvider = provider;
        break;
      }
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Text('Home', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        _PopularRadioStationsShelf(provider: _radioProvider),
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
            onOpen: (provider, collection) =>
                unawaited(_openProviderHomeCollection(provider, collection)),
          ),
          const SizedBox(height: 12),
        ],
        if (youtubeProvider != null) ...<Widget>[
          _OfficialYouTubeMusicChartShelf(provider: youtubeProvider),
          const SizedBox(height: 12),
        ],
        if (youtubeProvider != null &&
            youtubeFollows?.loaded == true &&
            youtubeFollows!.follows.isNotEmpty) ...<Widget>[
          _FollowedYouTubeChannelShelf(provider: youtubeProvider),
          const SizedBox(height: 12),
        ],
        if (spotifyProvider != null) ...<Widget>[
          _SpotifySavedTracksShelf(provider: spotifyProvider),
          const SizedBox(height: 12),
        ],
        _PopularInternetArchiveShelf(provider: _archiveProvider),
        const SizedBox(height: 12),
        _AudiusTrendingShelf(provider: _audiusProvider),
        const SizedBox(height: 12),
        if (jamendoProvider != null) ...<Widget>[
          _JamendoPopularShelf(provider: jamendoProvider),
          const SizedBox(height: 12),
        ],
        if (library.followedArtists.isNotEmpty) ...<Widget>[
          ArtistReleaseUpdatesShelf(provider: _artistReleaseProvider),
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
          youtubeTracks: youtubeFollowingTracks,
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
              onStartRadio: () =>
                  unawaited(_startTrackRadio(context, player, library, track)),
              onSimilarTracks: () => unawaited(
                _showSimilarTracks(
                  context,
                  track,
                  onAddToPlaylist: widget.onAddToPlaylist,
                  onLyrics: widget.onLyrics,
                ),
              ),
              onShare: () =>
                  unawaited(_copyTrackShareText(context, library, track)),
              onFavorite: () => library.toggleFavorite(track.id),
              onAddToPlaylist: () => widget.onAddToPlaylist(track),
              onLyrics: () => widget.onLyrics(track),
              onEditMetadata: () =>
                  unawaited(_showTrackMetadataEditor(context, track)),
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
          onStartRadio: () =>
              unawaited(_startTrackRadio(context, player, library, track)),
          onSimilarTracks: () => unawaited(
            _showSimilarTracks(
              context,
              track,
              onAddToPlaylist: widget.onAddToPlaylist,
              onLyrics: widget.onLyrics,
            ),
          ),
          onShare: () =>
              unawaited(_copyTrackShareText(context, library, track)),
          onFavorite: () => library.toggleFavorite(track.id),
          onAddToPlaylist: () => widget.onAddToPlaylist(track),
          onLyrics: () => widget.onLyrics(track),
          onEditMetadata: () =>
              unawaited(_showTrackMetadataEditor(context, track)),
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
    required List<Track> youtubeTracks,
  }) {
    final hasFollowingContent = library
        .followingFeedTracks(youtubeTracks: youtubeTracks, limit: 1)
        .isNotEmpty;
    if (!hasFollowingContent) {
      return <Widget>[];
    }

    return <Widget>[
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.dynamic_feed_outlined),
        title: const Text('Following'),
        subtitle: const Text(
          'Newest updates from artists, podcasts, and public channels',
        ),
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
            onStartRadio: () =>
                unawaited(_startTrackRadio(context, player, library, track)),
            onSimilarTracks: () => unawaited(
              _showSimilarTracks(
                context,
                track,
                onAddToPlaylist: widget.onAddToPlaylist,
                onLyrics: widget.onLyrics,
              ),
            ),
            onShare: () =>
                unawaited(_copyTrackShareText(context, library, track)),
            onFavorite: () => library.toggleFavorite(track.id),
            onAddToPlaylist: () => widget.onAddToPlaylist(track),
            onLyrics: () => widget.onLyrics(track),
            onEditMetadata: () =>
                unawaited(_showTrackMetadataEditor(context, track)),
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
        signature !=
            _providerHomeStoreSignature(
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
        signature !=
            _providerHomeStoreSignature(
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

final class _OfficialYouTubeMusicChartShelf extends StatefulWidget {
  const _OfficialYouTubeMusicChartShelf({required this.provider});

  final YouTubeDataMetadataProvider provider;

  @override
  State<_OfficialYouTubeMusicChartShelf> createState() =>
      _OfficialYouTubeMusicChartShelfState();
}

final class _OfficialYouTubeMusicChartShelfState
    extends State<_OfficialYouTubeMusicChartShelf> {
  late final TextEditingController _regionController;
  List<Track> _tracks = const <Track>[];
  bool _loading = false;
  String? _error;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    _regionController = TextEditingController(
      text: context.read<YouTubeDataSettingsStore?>()?.preferredRegion ?? 'US',
    );
  }

  @override
  void dispose() {
    _regionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.leaderboard_outlined),
          title: const Text('Official YouTube music chart'),
          subtitle: const Text('Public Music-category video metadata'),
          trailing: IconButton(
            tooltip: 'Open YouTube music chart',
            onPressed: () => _openFullChart(context),
            icon: const Icon(Icons.open_in_new),
          ),
        ),
        Row(
          children: <Widget>[
            SizedBox(
              width: 96,
              child: TextField(
                controller: _regionController,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 2,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Region',
                  counterText: '',
                ),
                onSubmitted: (_) => unawaited(_load()),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('home-youtube-music-chart-refresh'),
              tooltip: 'Refresh YouTube music chart',
              onPressed: _loading || offline ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (offline && _tracks.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline mode'),
          ),
        if (_loading && _tracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_error != null && _tracks.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: const Text('Could not load the music chart'),
            subtitle: Text(_error!),
            trailing: IconButton(
              tooltip: 'Retry YouTube music chart',
              onPressed: _loading || offline ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        for (final track in _tracks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.music_video_outlined),
            title: Text(track.title),
            subtitle: Text(track.artist),
            onTap: () => _openFullChart(context),
            trailing: IconButton(
              tooltip: library.tracks.any((saved) => saved.id == track.id)
                  ? 'Saved to library'
                  : 'Save metadata to library',
              onPressed: () => unawaited(_saveTrack(context, track)),
              icon: Icon(
                library.tracks.any((saved) => saved.id == track.id)
                    ? Icons.bookmark
                    : Icons.bookmark_add_outlined,
              ),
            ),
          ),
        if (_loading && _tracks.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _load() async {
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final request = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await context.read<YouTubeDataSettingsStore?>()?.setPreferredRegion(
        _regionController.text,
      );
      final page = await widget.provider.loadPopularMusicPage(
        regionCode: _regionController.text,
        limit: 6,
      );
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _tracks = page.tracks;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _saveTrack(BuildContext context, Track track) async {
    await context.read<LibraryStore>().addTracks(<Track>[track]);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${track.title} metadata saved to your library.')),
    );
  }

  void _openFullChart(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubeMusicChartScreen(provider: widget.provider),
      ),
    );
  }
}

final class _FollowedYouTubeChannelShelf extends StatefulWidget {
  const _FollowedYouTubeChannelShelf({required this.provider});

  final YouTubeDataMetadataProvider provider;

  @override
  State<_FollowedYouTubeChannelShelf> createState() =>
      _FollowedYouTubeChannelShelfState();
}

final class _FollowedYouTubeChannelShelfState
    extends State<_FollowedYouTubeChannelShelf> {
  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final follows = context.watch<YouTubeChannelFollowStore?>();
    final feedStore = context.watch<YouTubeFollowedChannelFeedStore?>();
    final offline = library.offlineModeEnabled;
    final followCount = follows?.follows.length ?? 0;
    final items =
        feedStore?.items.take(6).toList(growable: false) ??
        const <YouTubeFollowedChannelFeedItem>[];
    final loading = feedStore?.refreshing ?? false;
    final failedChannelCount = feedStore?.lastFailedChannelCount ?? 0;
    final canRefresh =
        follows?.loaded == true && followCount > 0 && !loading && !offline;
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.video_library_outlined),
          title: const Text('Followed YouTube channels'),
          subtitle: Text('$followCount local public channel(s), metadata only'),
          trailing: IconButton(
            key: const Key('home-youtube-followed-channels-open'),
            tooltip: 'Open followed YouTube channels',
            onPressed: () => _openFullFeed(context),
            icon: const Icon(Icons.open_in_new),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton.filled(
            key: const Key('home-youtube-followed-channels-refresh'),
            tooltip: 'Refresh followed YouTube channels',
            onPressed: canRefresh ? () => unawaited(_refresh()) : null,
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (offline && items.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline mode'),
          ),
        if (loading && items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (failedChannelCount > 0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: Text('$failedChannelCount channel(s) unavailable'),
            subtitle: const Text('Other followed-channel metadata is shown.'),
          ),
        for (final item in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.ondemand_video_outlined),
            title: Text(item.track.title),
            subtitle: Text(item.subtitle),
            onTap: () => _openFullFeed(context),
            trailing: IconButton(
              tooltip: library.tracks.any((saved) => saved.id == item.track.id)
                  ? 'Saved to library'
                  : 'Save metadata to library',
              onPressed: () => unawaited(_saveTrack(context, item.track)),
              icon: Icon(
                library.tracks.any((saved) => saved.id == item.track.id)
                    ? Icons.bookmark
                    : Icons.bookmark_add_outlined,
              ),
            ),
          ),
        if (loading && items.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    final feedStore = context.read<YouTubeFollowedChannelFeedStore?>();
    if (feedStore == null ||
        feedStore.refreshing ||
        context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final follows = context.read<YouTubeChannelFollowStore?>();
    if (follows?.loaded != true || follows!.follows.isEmpty) {
      return;
    }
    await feedStore.refresh(
      widget.provider,
      follows.follows,
      limitPerChannel: 2,
      maxChannels: 6,
    );
  }

  Future<void> _saveTrack(BuildContext context, Track track) async {
    await context.read<LibraryStore>().addTracks(<Track>[track]);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${track.title} metadata saved to your library.')),
    );
  }

  void _openFullFeed(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            YouTubeFollowedChannelFeedScreen(provider: widget.provider),
      ),
    );
  }
}

enum _SpotifyHomeLibraryView { tracks, albums, playlists }

final class _SpotifySavedTracksShelf extends StatefulWidget {
  const _SpotifySavedTracksShelf({required this.provider});

  final SpotifyMetadataProvider provider;

  @override
  State<_SpotifySavedTracksShelf> createState() =>
      _SpotifySavedTracksShelfState();
}

final class _SpotifySavedTracksShelfState
    extends State<_SpotifySavedTracksShelf> {
  List<Track> _tracks = const <Track>[];
  List<SpotifySavedAlbum> _albums = const <SpotifySavedAlbum>[];
  List<SpotifySavedPlaylist> _playlists = const <SpotifySavedPlaylist>[];
  _SpotifyHomeLibraryView _view = _SpotifyHomeLibraryView.tracks;
  bool _loading = false;
  String? _error;
  int _requestSerial = 0;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    final hasItems = switch (_view) {
      _SpotifyHomeLibraryView.tracks => _tracks.isNotEmpty,
      _SpotifyHomeLibraryView.albums => _albums.isNotEmpty,
      _SpotifyHomeLibraryView.playlists => _playlists.isNotEmpty,
    };
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.library_music_outlined),
          title: const Text('Your Spotify library'),
          subtitle: Text(
            'Saved ${_spotifyHomeLibraryViewLabel(_view)} metadata from your connected account',
          ),
          trailing: IconButton(
            key: const Key('home-spotify-library-open'),
            tooltip:
                'Open Spotify saved ${_spotifyHomeLibraryViewLabel(_view)}',
            onPressed: () => _openSelectedView(context),
            icon: const Icon(Icons.open_in_new),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final view in _SpotifyHomeLibraryView.values)
              ChoiceChip(
                key: ValueKey<String>('home-spotify-${view.name}'),
                label: Text(_spotifyHomeLibraryViewLabel(view)),
                selected: _view == view,
                onSelected: (_) => _selectView(view),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton.filled(
            key: const Key('home-spotify-library-refresh'),
            tooltip:
                'Refresh Spotify saved ${_spotifyHomeLibraryViewLabel(_view)}',
            onPressed: _loading || offline ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (offline && !hasItems)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline mode'),
          ),
        if (_loading && !hasItems)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_error != null && !hasItems)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: Text(
              'Could not load saved Spotify ${_spotifyHomeLibraryViewLabel(_view)}',
            ),
            subtitle: Text(_error!),
            trailing: IconButton(
              tooltip:
                  'Retry Spotify saved ${_spotifyHomeLibraryViewLabel(_view)}',
              onPressed: _loading || offline ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        for (final track in _tracks)
          if (_view == _SpotifyHomeLibraryView.tracks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.music_note_outlined),
              title: Text(track.title),
              subtitle: Text(_spotifyTrackSubtitle(track)),
              onTap: () => _openSavedTracks(context),
              trailing: IconButton(
                tooltip: library.tracks.any((saved) => saved.id == track.id)
                    ? 'Saved to library'
                    : 'Save metadata to library',
                onPressed: () => unawaited(_saveTrack(context, track)),
                icon: Icon(
                  library.tracks.any((saved) => saved.id == track.id)
                      ? Icons.bookmark
                      : Icons.bookmark_add_outlined,
                ),
              ),
            ),
        for (final album in _albums)
          if (_view == _SpotifyHomeLibraryView.albums)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: TrackArtwork(artworkUri: album.artworkUri),
              title: Text(album.title),
              subtitle: Text(_spotifyAlbumSubtitle(album)),
              onTap: () => _openAlbum(context, album),
              trailing: const Icon(Icons.chevron_right),
            ),
        for (final playlist in _playlists)
          if (_view == _SpotifyHomeLibraryView.playlists)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: TrackArtwork(artworkUri: playlist.artworkUri),
              title: Text(playlist.title),
              subtitle: Text(_spotifyPlaylistSubtitle(playlist)),
              onTap: () => _openPlaylist(context, playlist),
              trailing: const Icon(Icons.chevron_right),
            ),
        if (_loading && hasItems)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _load() async {
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final view = _view;
    final request = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      switch (view) {
        case _SpotifyHomeLibraryView.tracks:
          final page = await widget.provider.loadSavedTracksPage(limit: 6);
          if (!mounted || request != _requestSerial) {
            return;
          }
          setState(() {
            _tracks = page.tracks;
            _loading = false;
          });
          return;
        case _SpotifyHomeLibraryView.albums:
          final page = await widget.provider.loadSavedAlbumsPage(limit: 6);
          if (!mounted || request != _requestSerial) {
            return;
          }
          setState(() {
            _albums = page.albums;
            _loading = false;
          });
          return;
        case _SpotifyHomeLibraryView.playlists:
          final page = await widget.provider.loadSavedPlaylistsPage(limit: 6);
          if (!mounted || request != _requestSerial) {
            return;
          }
          setState(() {
            _playlists = page.playlists;
            _loading = false;
          });
          return;
      }
    } on Object catch (error) {
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _saveTrack(BuildContext context, Track track) async {
    await context.read<LibraryStore>().addTracks(<Track>[track]);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${track.title} metadata saved to your library.')),
    );
  }

  void _selectView(_SpotifyHomeLibraryView view) {
    if (_view == view) {
      return;
    }
    _requestSerial += 1;
    setState(() {
      _view = view;
      _loading = false;
      _error = null;
    });
  }

  void _openSelectedView(BuildContext context) {
    switch (_view) {
      case _SpotifyHomeLibraryView.tracks:
        _openSavedTracks(context);
        return;
      case _SpotifyHomeLibraryView.albums:
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SpotifySavedAlbumsScreen(provider: widget.provider),
          ),
        );
        return;
      case _SpotifyHomeLibraryView.playlists:
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) =>
                SpotifySavedPlaylistsScreen(provider: widget.provider),
          ),
        );
        return;
    }
  }

  void _openSavedTracks(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifySavedTracksScreen(provider: widget.provider),
      ),
    );
  }

  void _openAlbum(BuildContext context, SpotifySavedAlbum album) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SpotifyAlbumTracksScreen(provider: widget.provider, album: album),
      ),
    );
  }

  void _openPlaylist(BuildContext context, SpotifySavedPlaylist playlist) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifyPlaylistTracksScreen(
          provider: widget.provider,
          playlist: playlist,
        ),
      ),
    );
  }
}

String _spotifyHomeLibraryViewLabel(_SpotifyHomeLibraryView view) {
  return switch (view) {
    _SpotifyHomeLibraryView.tracks => 'tracks',
    _SpotifyHomeLibraryView.albums => 'albums',
    _SpotifyHomeLibraryView.playlists => 'playlists',
  };
}

String _spotifyTrackSubtitle(Track track) {
  return <String>[
    track.artist,
    track.album,
  ].where((part) => part.trim().isNotEmpty).join(' - ');
}

String _spotifyAlbumSubtitle(SpotifySavedAlbum album) {
  final count = album.totalTracks;
  return '${album.artist} - $count ${count == 1 ? 'track' : 'tracks'}';
}

String _spotifyPlaylistSubtitle(SpotifySavedPlaylist playlist) {
  final count = playlist.totalTracks;
  return '${playlist.ownerName} - $count ${count == 1 ? 'track' : 'tracks'}';
}

final class _AudiusTrendingShelf extends StatefulWidget {
  const _AudiusTrendingShelf({required this.provider});

  final AudiusProvider provider;

  @override
  State<_AudiusTrendingShelf> createState() => _AudiusTrendingShelfState();
}

final class _AudiusTrendingShelfState extends State<_AudiusTrendingShelf> {
  List<Track> _tracks = const <Track>[];
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  int _requestSerial = 0;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.trending_up_outlined),
          title: const Text('Trending on Audius'),
          subtitle: const Text('Public tracks in Audius server-defined order'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                key: const Key('home-audius-browse'),
                tooltip: 'Browse Audius artists, albums, and playlists',
                onPressed: offline ? null : () => _browseCollections(context),
                icon: const Icon(Icons.explore_outlined),
              ),
              IconButton.filled(
                key: const Key('home-audius-trending-refresh'),
                tooltip: 'Refresh Audius trending tracks',
                onPressed: _loading || offline
                    ? null
                    : () => unawaited(_refresh()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_loading && !_loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_failed && !_loaded)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: const Text('Audius trending tracks are unavailable'),
            trailing: IconButton(
              tooltip: 'Retry Audius trending tracks',
              onPressed: _loading || offline
                  ? null
                  : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        for (final track in _tracks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.graphic_eq_outlined),
            title: Text(track.title),
            subtitle: Text(track.artist),
            onTap: offline ? null : () => unawaited(_playTrack(context, track)),
            trailing: IconButton(
              tooltip: library.tracks.any((saved) => saved.id == track.id)
                  ? 'Saved to library'
                  : 'Save track to library',
              onPressed: offline
                  ? null
                  : () => unawaited(_saveTrack(context, track)),
              icon: Icon(
                library.tracks.any((saved) => saved.id == track.id)
                    ? Icons.bookmark
                    : Icons.bookmark_add_outlined,
              ),
            ),
          ),
        if (_loading && _loaded)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final request = ++_requestSerial;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final tracks = await widget.provider.fetchTrending(limit: 6);
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _tracks = List<Track>.unmodifiable(tracks);
        _loading = false;
        _loaded = true;
      });
    } on Object {
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _browseCollections(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelfHostedBrowseScreen(
          provider: widget.provider,
          collectionKinds: const <MusicCatalogCollectionKind>[
            MusicCatalogCollectionKind.artist,
            MusicCatalogCollectionKind.album,
            MusicCatalogCollectionKind.playlist,
          ],
        ),
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, Track selected) async {
    if (context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final coordinator = ProviderSearchCoordinator(<MusicSourceProvider>[
      widget.provider,
    ]);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queue = await Future.wait<Track>(
        _tracks.map(coordinator.resolvePlayableTrack),
      );
      if (!context.mounted) {
        return;
      }
      final selectedTrack = queue.firstWhere(
        (track) => track.id == selected.id,
        orElse: () => selected,
      );
      if (!selectedTrack.isPlayable) {
        messenger.showSnackBar(
          SnackBar(content: Text('No playable stream for ${selected.title}.')),
        );
        return;
      }
      await context.read<PlayerController>().playTrack(
        selectedTrack,
        queue: queue.where((track) => track.isPlayable).toList(growable: false),
      );
    } on Object {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not play ${selected.title}.')),
        );
      }
    }
  }

  Future<void> _saveTrack(BuildContext context, Track track) async {
    final coordinator = ProviderSearchCoordinator(<MusicSourceProvider>[
      widget.provider,
    ]);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resolved = await coordinator.resolvePlayableTrack(track);
      if (!context.mounted) {
        return;
      }
      await context.read<LibraryStore>().addTracks(<Track>[resolved]);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('${resolved.title} saved to your library.')),
      );
    } on Object {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save ${track.title}.')),
        );
      }
    }
  }
}

final class _JamendoPopularShelf extends StatefulWidget {
  const _JamendoPopularShelf({required this.provider});

  final JamendoProvider provider;

  @override
  State<_JamendoPopularShelf> createState() => _JamendoPopularShelfState();
}

final class _JamendoPopularShelfState extends State<_JamendoPopularShelf> {
  List<Track> _tracks = const <Track>[];
  late final JamendoChartCache _chartCache;
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  int _requestSerial = 0;
  JamendoFeaturedGenre? _featuredGenre;
  String? _lyricsLanguageCode;

  @override
  void initState() {
    super.initState();
    _chartCache = SharedPreferencesJamendoChartCache();
    unawaited(_restoreCachedChart());
  }

  String get _chartCacheKey => jamendoChartCacheKey(
    genre: _featuredGenre?.apiValue,
    lyricsLanguageCode: _lyricsLanguageCode,
  );

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Popular on Jamendo'),
          subtitle: Text(
            <String>[
              _featuredGenre == null
                  ? 'Public tracks ranked by Jamendo popularity'
                  : 'Featured ${_featuredGenre!.label} tracks from Jamendo',
              if (_lyricsLanguageCode != null)
                'Lyrics: ${_lyricsLanguageCode!.toUpperCase()}',
            ].join(' / '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PopupMenuButton<String>(
                key: const Key('home-jamendo-genre-menu'),
                tooltip: 'Choose Jamendo featured genre',
                enabled: !_loading && !offline,
                onSelected: _selectFeaturedGenre,
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'all',
                    child: Text('All popular tracks'),
                  ),
                  for (final genre in JamendoFeaturedGenre.values)
                    PopupMenuItem<String>(
                      value: genre.apiValue,
                      child: Text(genre.label),
                    ),
                ],
                icon: const Icon(Icons.tune_outlined),
              ),
              IconButton(
                key: const Key('home-jamendo-language'),
                tooltip: 'Filter Jamendo tracks by lyrics language',
                onPressed: _loading || offline
                    ? null
                    : () => unawaited(_editLyricsLanguage()),
                icon: const Icon(Icons.language_outlined),
              ),
              IconButton.filled(
                key: const Key('home-jamendo-popular-refresh'),
                tooltip: 'Refresh popular Jamendo tracks',
                onPressed: _loading || offline
                    ? null
                    : () => unawaited(_refresh()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (_loading && !_loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_failed && !_loaded)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: const Text('Popular Jamendo tracks are unavailable'),
            trailing: IconButton(
              tooltip: 'Retry popular Jamendo tracks',
              onPressed: _loading || offline
                  ? null
                  : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        for (final track in _tracks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.graphic_eq_outlined),
            title: Text(track.title),
            subtitle: Text(track.artist),
            onTap: offline ? null : () => unawaited(_playTrack(context, track)),
            trailing: IconButton(
              tooltip: library.tracks.any((saved) => saved.id == track.id)
                  ? 'Saved to library'
                  : 'Save track to library',
              onPressed: offline
                  ? null
                  : () => unawaited(_saveTrack(context, track)),
              icon: Icon(
                library.tracks.any((saved) => saved.id == track.id)
                    ? Icons.bookmark
                    : Icons.bookmark_add_outlined,
              ),
            ),
          ),
        if (_loading && _loaded)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final request = ++_requestSerial;
    final cacheKey = _chartCacheKey;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final tracks = await widget.provider.fetchPopular(
        limit: 6,
        featuredGenre: _featuredGenre,
        lyricsLanguageCode: _lyricsLanguageCode,
      );
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _tracks = List<Track>.unmodifiable(tracks);
        _loading = false;
        _loaded = true;
      });
      unawaited(_storeCachedChart(cacheKey, tracks));
    } on Object {
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _selectFeaturedGenre(String selection) {
    final genre = selection == 'all'
        ? null
        : JamendoFeaturedGenre.values.firstWhere(
            (genre) => genre.apiValue == selection,
          );
    if (_featuredGenre == genre) {
      return;
    }
    _requestSerial += 1;
    setState(() {
      _featuredGenre = genre;
      _tracks = const <Track>[];
      _loaded = false;
      _failed = false;
    });
    unawaited(_restoreCachedChart());
  }

  Future<void> _editLyricsLanguage() async {
    var draft = _lyricsLanguageCode ?? '';
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lyrics language'),
        content: TextFormField(
          initialValue: draft,
          autofocus: true,
          maxLength: 2,
          textCapitalization: TextCapitalization.characters,
          onChanged: (value) => draft = value,
          decoration: const InputDecoration(
            labelText: 'Two-letter language code',
            hintText: 'EN',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(draft),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (!mounted || value == null) {
      return;
    }
    final normalized = value.trim().toLowerCase();
    if (normalized.isNotEmpty && !RegExp(r'^[a-z]{2}$').hasMatch(normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a two-letter language code.')),
      );
      return;
    }
    if (_lyricsLanguageCode == (normalized.isEmpty ? null : normalized)) {
      return;
    }
    _requestSerial += 1;
    setState(() {
      _lyricsLanguageCode = normalized.isEmpty ? null : normalized;
      _tracks = const <Track>[];
      _loaded = false;
      _failed = false;
    });
    unawaited(_restoreCachedChart());
  }

  Future<void> _restoreCachedChart() async {
    final request = _requestSerial;
    final cacheKey = _chartCacheKey;
    try {
      final cached = await _chartCache.read(cacheKey);
      if (!mounted ||
          request != _requestSerial ||
          cached == null ||
          cached.isExpired(DateTime.now())) {
        return;
      }
      setState(() {
        _tracks = cached.tracks;
        _loaded = true;
        _failed = false;
      });
    } on Object {
      // A corrupt local chart must never prevent the Home screen from loading.
    }
  }

  Future<void> _storeCachedChart(String key, List<Track> tracks) async {
    try {
      await _chartCache.write(key, tracks);
    } on Object {
      // The current public result remains usable when device storage is full.
    }
  }

  Future<void> _playTrack(BuildContext context, Track selected) async {
    if (context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final coordinator = ProviderSearchCoordinator(<MusicSourceProvider>[
      widget.provider,
    ]);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final queue = await Future.wait<Track>(
        _tracks.map(coordinator.resolvePlayableTrack),
      );
      if (!context.mounted) {
        return;
      }
      final selectedTrack = queue.firstWhere(
        (track) => track.id == selected.id,
        orElse: () => selected,
      );
      if (!selectedTrack.isPlayable) {
        messenger.showSnackBar(
          SnackBar(content: Text('No playable stream for ${selected.title}.')),
        );
        return;
      }
      await context.read<PlayerController>().playTrack(
        selectedTrack,
        queue: queue.where((track) => track.isPlayable).toList(growable: false),
      );
    } on Object {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not play ${selected.title}.')),
        );
      }
    }
  }

  Future<void> _saveTrack(BuildContext context, Track track) async {
    final coordinator = ProviderSearchCoordinator(<MusicSourceProvider>[
      widget.provider,
    ]);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final resolved = await coordinator.resolvePlayableTrack(track);
      if (!context.mounted) {
        return;
      }
      await context.read<LibraryStore>().addTracks(<Track>[resolved]);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('${resolved.title} saved to your library.')),
      );
    } on Object {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save ${track.title}.')),
        );
      }
    }
  }
}

final class _PopularRadioStationsShelf extends StatefulWidget {
  const _PopularRadioStationsShelf({required this.provider});

  final RadioBrowserProvider provider;

  @override
  State<_PopularRadioStationsShelf> createState() =>
      _PopularRadioStationsShelfState();
}

final class _PopularRadioStationsShelfState
    extends State<_PopularRadioStationsShelf> {
  List<RadioBrowserStation> _stations = const <RadioBrowserStation>[];
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  int _requestSerial = 0;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    final tracks = _stations
        .map((station) => station.toTrack(sourceId: widget.provider.id))
        .toList(growable: false);
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.radio_outlined),
          title: const Text('Popular radio stations'),
          subtitle: const Text(
            'Public stations ranked by Radio Browser clicks',
          ),
          trailing: IconButton.filled(
            key: const Key('home-popular-radio-refresh'),
            tooltip: 'Refresh popular radio stations',
            onPressed: _loading || offline ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (offline && !_loaded)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline mode'),
          ),
        if (_loading && !_loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_failed && !_loaded)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: const Text('Popular stations are unavailable'),
            trailing: IconButton(
              tooltip: 'Retry popular radio stations',
              onPressed: _loading || offline
                  ? null
                  : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        for (var index = 0; index < _stations.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.radio_outlined),
            title: Text(_stations[index].name),
            subtitle: Text(_radioStationSummary(_stations[index])),
            onTap: () => _openStation(context, _stations[index], tracks),
            trailing: IconButton(
              tooltip:
                  library.tracks.any((saved) => saved.id == tracks[index].id)
                  ? 'Saved to library'
                  : 'Save station to library',
              onPressed: () => unawaited(_saveTrack(context, tracks[index])),
              icon: Icon(
                library.tracks.any((saved) => saved.id == tracks[index].id)
                    ? Icons.bookmark
                    : Icons.bookmark_add_outlined,
              ),
            ),
          ),
        if (_loading && _loaded)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final request = ++_requestSerial;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.provider.searchStationPage('', pageSize: 6);
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _stations = List<RadioBrowserStation>.unmodifiable(page.stations);
        _loading = false;
        _loaded = true;
      });
    } on Object {
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _saveTrack(BuildContext context, Track track) async {
    await context.read<LibraryStore>().addTracks(<Track>[track]);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${track.title} saved to your library.')),
    );
  }

  Future<void> _openStation(
    BuildContext context,
    RadioBrowserStation station,
    List<Track> tracks,
  ) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RadioBrowserStationScreen(
          station: station,
          provider: widget.provider,
          onPlay: (track) => _playTrackWithResume(
            context,
            context.read<PlayerController>(),
            context.read<LibraryStore>(),
            track,
            queue: tracks,
          ),
          onSave: (track) => _saveTrack(context, track),
        ),
      ),
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

final class _PopularInternetArchiveShelf extends StatefulWidget {
  const _PopularInternetArchiveShelf({required this.provider});

  final InternetArchiveProvider provider;

  @override
  State<_PopularInternetArchiveShelf> createState() =>
      _PopularInternetArchiveShelfState();
}

final class _PopularInternetArchiveShelfState
    extends State<_PopularInternetArchiveShelf> {
  List<InternetArchiveItem> _items = const <InternetArchiveItem>[];
  bool _loading = false;
  bool _loaded = false;
  bool _failed = false;
  int _requestSerial = 0;

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<LibraryStore>().offlineModeEnabled;
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.library_music_outlined),
          title: const Text('Popular Archive audio'),
          subtitle: const Text(
            'Public audio ranked by Internet Archive downloads',
          ),
          trailing: IconButton.filled(
            key: const Key('home-popular-archive-refresh'),
            tooltip: 'Refresh popular Archive audio',
            onPressed: _loading || offline ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (offline && !_loaded)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline mode'),
          ),
        if (_loading && !_loaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (_failed && !_loaded)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: const Text('Popular Archive audio is unavailable'),
            trailing: IconButton(
              tooltip: 'Retry popular Archive audio',
              onPressed: _loading || offline
                  ? null
                  : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        for (final item in _items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.audio_file_outlined),
            title: Text(item.title.isEmpty ? item.identifier : item.title),
            subtitle: Text(_archiveHomeItemSubtitle(item)),
            onTap: () => _openItem(context, item),
          ),
        if (_loading && _loaded)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final request = ++_requestSerial;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await widget.provider.searchAudioPage(
        '',
        includeFacets: false,
        pageSize: 6,
      );
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _items = List<InternetArchiveItem>.unmodifiable(page.items);
        _loading = false;
        _loaded = true;
      });
    } on Object {
      if (!mounted || request != _requestSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _openItem(BuildContext context, InternetArchiveItem item) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveItemScreen(
          item: item,
          provider: widget.provider,
          onOpenCollection: (collection) =>
              _openCollection(context, collection),
        ),
      ),
    );
  }

  Future<void> _openCollection(BuildContext context, String collection) {
    final normalized = collection.trim();
    if (normalized.isEmpty) {
      return Future<void>.value();
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => InternetArchiveCollectionScreen(
          collection: normalized,
          provider: widget.provider,
        ),
      ),
    );
  }
}

String _archiveHomeItemSubtitle(InternetArchiveItem item) {
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
  )
  onOpen;

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
            title: Text('${feed!.errors.length} server section(s) unavailable'),
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
    final sectionLabel =
        section.titleOverride ??
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
            separatorBuilder: (_, _) => const SizedBox(width: 10),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    MusicCatalogDiscoveryKind.favorites => 'favorite albums',
    MusicCatalogDiscoveryKind.favoriteArtists => 'favorite artists',
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
    MusicCatalogDiscoveryKind.random => 'Random albums selected by this server',
    MusicCatalogDiscoveryKind.favorites =>
      'Favorite albums reported by this server',
    MusicCatalogDiscoveryKind.favoriteArtists =>
      'Favorite artists reported by this server',
  };
}

IconData _providerHomeDiscoveryIcon(MusicCatalogDiscoveryKind kind) {
  return switch (kind) {
    MusicCatalogDiscoveryKind.recentlyAdded => Icons.new_releases_outlined,
    MusicCatalogDiscoveryKind.frequentlyPlayed => Icons.trending_up,
    MusicCatalogDiscoveryKind.recentlyPlayed => Icons.history_outlined,
    MusicCatalogDiscoveryKind.random => Icons.shuffle,
    MusicCatalogDiscoveryKind.favorites => Icons.favorite_outline,
    MusicCatalogDiscoveryKind.favoriteArtists => Icons.people_alt_outlined,
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
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text('Local charts', style: Theme.of(context).textTheme.titleLarge),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<LibraryChartRange>(
                initialValue: selectedRange,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Range',
                  prefixIcon: Icon(Icons.bar_chart),
                ),
                items: <DropdownMenuItem<LibraryChartRange>>[
                  for (final range in LibraryChartRange.values)
                    DropdownMenuItem<LibraryChartRange>(
                      value: range,
                      child: Text(
                        _libraryChartRangeLabel(range),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
        LibraryStatsOverview(stats: stats),
        const SizedBox(height: 16),
        LibraryStatsCharts(stats: stats),
        const SizedBox(height: 16),
        LibraryStatsTrackSection(stats: stats),
        const SizedBox(height: 12),
        LibraryStatsGroupSection(
          title: 'Top artists',
          icon: Icons.person_outline,
          groups: stats.topArtists,
        ),
        const SizedBox(height: 12),
        LibraryStatsGroupSection(
          title: 'Top albums',
          icon: Icons.album_outlined,
          groups: stats.topAlbums,
        ),
        const SizedBox(height: 12),
        LibraryStatsGroupSection(
          title: 'Top genres',
          icon: Icons.category_outlined,
          groups: stats.topGenres,
        ),
        const SizedBox(height: 12),
        LibraryStatsGroupSection(
          title: 'Top sources',
          icon: Icons.source_outlined,
          groups: stats.topSources,
        ),
        const SizedBox(height: 12),
        LibraryStatsGroupSection(
          title: 'Top folders',
          icon: Icons.folder_outlined,
          groups: stats.topFolders,
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
            Text(message, textAlign: TextAlign.center),
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
    case LibraryHomeSectionType.audiobooks:
      return Icons.menu_book_outlined;
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
    case LibraryHomeSectionType.audiobooks:
      return 'Audiobooks';
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
    case LibraryHomeSectionType.audiobooks:
      return 'Imported M4B audiobooks, with resume progress';
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
    FollowingFeedSource.youtube => 'YouTube',
  };
}

String _followingFeedTrackDetail(Track track) {
  if (track.sourceId == 'youtube-data-metadata') {
    return 'Followed public channel metadata';
  }
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
