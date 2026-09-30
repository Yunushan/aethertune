part of 'home_screen.dart';

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
    final heatmapDays = library.listeningHeatmap(from: heatmapFrom, to: now);
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
              onPressed: () =>
                  _showStatsExportPicker(context, from: statsFrom, to: statsTo),
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
        ListTile(
          key: const Key('sponsorblock-categories-setting'),
          leading: const Icon(Icons.fast_forward_outlined),
          title: const Text('SponsorBlock categories'),
          subtitle: Text(library.sponsorBlockCategories.join(', ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              unawaited(_showSponsorBlockCategoryDialog(context, library)),
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
        LibraryStatsOverview(stats: stats),
        if (stats.playbackCount > 0) ...<Widget>[
          const SizedBox(height: 16),
          LibraryStatsCharts(stats: stats),
          const SizedBox(height: 16),
          LibraryStatsSection(
            title: 'Listening calendar',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16),
                child: ListeningHeatmap(days: heatmapDays),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListeningRecapSection(
            title: 'Monthly recaps',
            icon: Icons.calendar_month_outlined,
            recaps: monthlyRecaps,
            onShare: (recap) => _showListeningRecapPreview(context, recap),
          ),
          const SizedBox(height: 12),
          ListeningRecapSection(
            title: 'Yearly recaps',
            icon: Icons.event_note_outlined,
            recaps: yearlyRecaps,
            onShare: (recap) => _showListeningRecapPreview(context, recap),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          PlaybackHistoryEntrySection(
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
        Text('Recently played', style: Theme.of(context).textTheme.titleMedium),
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
                '${library.playCountForTrack(track.id, from: statsFrom, to: statsTo)} play(s)',
              ),
              trailing: Text(
                formatLibraryHistoryTime(
                  library.lastPlayedAt(track.id, from: statsFrom, to: statsTo),
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
                          itemBuilder: (_) =>
                              const <PopupMenuEntry<_SavedHistoryViewAction>>[
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
            child: SingleChildScrollView(child: SelectableText(document)),
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

Future<void> _showSponsorBlockCategoryDialog(
  BuildContext context,
  LibraryStore library,
) async {
  final selected = Set<String>.of(library.sponsorBlockCategories);
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('SponsorBlock categories'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final category in sponsorBlockCategories.toList()..sort())
                CheckboxListTile(
                  value: selected.contains(category),
                  title: Text(category),
                  onChanged: (enabled) => setDialogState(() {
                    if (enabled ?? false) {
                      selected.add(category);
                    } else if (selected.length > 1) {
                      selected.remove(category);
                    }
                  }),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await library.setSponsorBlockCategories(selected);
              if (context.mounted) Navigator.of(context).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
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

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.title, required this.message});

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
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
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
  await _tryPlayTrackWithResume(context, player, library, track, queue: queue);
}

Future<bool> _tryPlayTrackWithResume(
  BuildContext context,
  PlayerController player,
  LibraryStore library,
  Track track, {
  required List<Track> queue,
}) async {
  final initialPosition = isLongFormProgressTrack(track)
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
        onPressed: () =>
            unawaited(_saveTrackRadioPlaylist(context, library, seedTrack)),
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
      SnackBar(content: Text('No playable radio queue for ${group.label}.')),
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
      await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
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
  final cleared = await diagnostics.clear();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cleared
              ? 'Cleared local diagnostics.'
              : 'Could not clear saved diagnostics. Check device storage and retry.',
        ),
      ),
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
      : _albumMetadataLabel(tracks);
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
      artworkCrop: representative.artworkCrop,
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
        OutlinedButton.icon(
          onPressed: () => _saveCollectionShareCard(
            dialogContext,
            boundaryKey,
            kind: kind,
            fileToken: fileToken,
          ),
          icon: const Icon(Icons.save_alt_outlined),
          label: const Text('Save PNG'),
        ),
        FilledButton.icon(
          onPressed: () => _shareCollectionShareCard(
            dialogContext,
            boundaryKey,
            kind: kind,
            fileToken: fileToken,
          ),
          icon: const Icon(Icons.ios_share),
          label: const Text('Share'),
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
  final fileName =
      'aethertune-${_shareCardFileToken(kind)}-'
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
        SnackBar(content: Text('Could not save $kind share card: $error')),
      );
    }
  }
}

Future<void> _shareCollectionShareCard(
  BuildContext context,
  GlobalKey boundaryKey, {
  required String kind,
  required String fileToken,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final sharePositionOrigin = platformSharePositionOrigin(context);
  final fileName =
      'aethertune-${_shareCardFileToken(kind)}-'
      '${_shareCardFileToken(fileToken)}.png';
  try {
    final status = await const SharePlusImageShareService().share(
      PlatformImageShareRequest(
        bytes: await captureCollectionShareCardPng(boundaryKey),
        fileName: fileName,
        title: '${kind[0].toUpperCase()}${kind.substring(1)} - AetherTune',
        subject: 'AetherTune $kind share card',
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
              ? 'Shared $kind share card.'
              : 'Sharing is unavailable. Save the PNG instead.',
        ),
      ),
    );
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share $kind share card: $error')),
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
