part of 'home_screen.dart';

mixin _SourcesPodcastSection on State<_SourcesTab> {
  ItunesPodcastDirectory get _podcastDirectory;
  bool _offlineModeBlocksSourceNetwork(BuildContext context);
  bool _offlineModeBlocksStream(BuildContext context, Track track);

  final _podcastFeedController = TextEditingController();
  final _podcastDirectoryQueryController = TextEditingController();
  List<Track> _podcastEpisodeTracks = <Track>[];
  List<PodcastDirectoryResult> _podcastDirectoryResults =
      <PodcastDirectoryResult>[];
  bool _podcastLoading = false;
  bool _podcastDirectoryLoading = false;
  bool _podcastDirectorySuggestionLoading = false;
  String? _podcastError;
  String? _podcastDirectoryError;
  String? _selectedPodcastSubscriptionId;
  int _podcastDirectoryRequestSerial = 0;
  Timer? _podcastDirectorySuggestionDebounce;

  void _disposePodcastSection() {
    _podcastDirectorySuggestionDebounce?.cancel();
    _podcastFeedController.dispose();
    _podcastDirectoryQueryController.dispose();
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
}
