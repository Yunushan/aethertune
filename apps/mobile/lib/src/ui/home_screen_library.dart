part of 'home_screen.dart';

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
