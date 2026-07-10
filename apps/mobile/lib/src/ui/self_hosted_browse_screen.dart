import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/provider_search.dart';
import '../domain/track.dart';
import '../player/player_controller.dart';
import 'widgets/track_artwork.dart';

class SelfHostedBrowseScreen extends StatefulWidget {
  const SelfHostedBrowseScreen({
    required this.provider,
    super.key,
  });

  final MusicCatalogProvider provider;

  @override
  State<SelfHostedBrowseScreen> createState() =>
      _SelfHostedBrowseScreenState();
}

class _SelfHostedBrowseScreenState extends State<SelfHostedBrowseScreen> {
  final Map<MusicCatalogCollectionKind, Future<List<MusicCatalogCollection>>>
      _requests =
      <MusicCatalogCollectionKind, Future<List<MusicCatalogCollection>>>{};
  bool _requestsStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final offline = context.watch<LibraryStore>().offlineModeEnabled;
    if (!offline && !_requestsStarted) {
      _requestsStarted = true;
      for (final kind in MusicCatalogCollectionKind.values) {
        _requests[kind] = widget.provider.browseCollections(kind);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<LibraryStore>().offlineModeEnabled;
    return DefaultTabController(
      length: MusicCatalogCollectionKind.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.provider.name),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(icon: Icon(Icons.people_outline), text: 'Artists'),
              Tab(icon: Icon(Icons.album_outlined), text: 'Albums'),
              Tab(icon: Icon(Icons.queue_music_outlined), text: 'Playlists'),
            ],
          ),
        ),
        body: offline
            ? const _CatalogOfflineState()
            : TabBarView(
                children: <Widget>[
                  for (final kind in MusicCatalogCollectionKind.values)
                    _CatalogCollectionList(
                      key: ValueKey<MusicCatalogCollectionKind>(kind),
                      provider: widget.provider,
                      kind: kind,
                      request: _requests[kind]!,
                      onRefresh: () => _refresh(kind),
                      onOpen: _openCollection,
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _refresh(MusicCatalogCollectionKind kind) async {
    final request = widget.provider.browseCollections(kind);
    setState(() {
      _requests[kind] = request;
    });
    try {
      await request;
    } on Object {
      // FutureBuilder renders the provider's redacted error and retry action.
    }
  }

  Future<void> _openCollection(MusicCatalogCollection collection) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelfHostedCollectionScreen(
          provider: widget.provider,
          collection: collection,
        ),
      ),
    );
  }
}

class _CatalogCollectionList extends StatefulWidget {
  const _CatalogCollectionList({
    required this.provider,
    required this.kind,
    required this.request,
    required this.onRefresh,
    required this.onOpen,
    super.key,
  });

  final MusicCatalogProvider provider;
  final MusicCatalogCollectionKind kind;
  final Future<List<MusicCatalogCollection>> request;
  final Future<void> Function() onRefresh;
  final ValueChanged<MusicCatalogCollection> onOpen;

  @override
  State<_CatalogCollectionList> createState() =>
      _CatalogCollectionListState();
}

class _CatalogCollectionListState extends State<_CatalogCollectionList> {
  final TextEditingController _filterController = TextEditingController();
  String _query = '';
  bool _playlistMutationInProgress = false;

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MusicCatalogCollection>>(
      future: widget.request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _CatalogErrorState(
            error: snapshot.error!,
            onRetry: widget.onRefresh,
          );
        }
        final collections = snapshot.data ?? const <MusicCatalogCollection>[];
        final playlistMutator = widget.provider.capabilities.contains(
                  MusicSourceCapability.playlistMutation,
                ) &&
                widget.provider is MusicPlaylistMutationProvider
            ? widget.provider as MusicPlaylistMutationProvider
            : null;
        final canMutatePlaylists =
            widget.kind == MusicCatalogCollectionKind.playlist &&
                playlistMutator != null;
        final normalizedQuery = _query.trim().toLowerCase();
        final visible = normalizedQuery.isEmpty
            ? collections
            : collections
                .where(
                  (collection) =>
                      collection.title.toLowerCase().contains(normalizedQuery) ||
                      collection.subtitle
                          .toLowerCase()
                          .contains(normalizedQuery),
                )
                .toList(growable: false);

        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.separated(
            key: PageStorageKey<String>('catalog-${widget.kind.name}'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: visible.isEmpty ? 2 : visible.length + 1,
            separatorBuilder: (_, index) => index == 0
                ? const SizedBox(height: 12)
                : const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (canMutatePlaylists) ...<Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('catalog-create-playlist'),
                          onPressed: _playlistMutationInProgress
                              ? null
                              : () => _createPlaylist(playlistMutator),
                          icon: const Icon(Icons.playlist_add),
                          label: const Text('Create playlist'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      key: Key('catalog-filter-${widget.kind.name}'),
                      controller: _filterController,
                      decoration: InputDecoration(
                        labelText: 'Filter ${_kindPlural(widget.kind)}',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear filter',
                                onPressed: () {
                                  _filterController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ],
                );
              }
              if (index == 1 && visible.isEmpty) {
                return _CatalogEmptyState(
                  label: normalizedQuery.isEmpty
                      ? 'No ${_kindPlural(widget.kind).toLowerCase()} found.'
                      : 'No ${_kindPlural(widget.kind).toLowerCase()} match this filter.',
                );
              }
              final collection = visible[index - 1];
              return ListTile(
                key: ValueKey<String>(
                  'catalog-${collection.kind.name}-${collection.id}',
                ),
                leading: TrackArtwork(
                  artworkUri: null,
                  providerId: widget.provider.id,
                  providerArtworkId: collection.artworkId,
                  providerArtworkVersion: collection.artworkVersion,
                  loadProviderArtwork: collection.artworkId == null
                      ? null
                      : (maxWidth) => widget.provider.loadArtwork(
                            collection.artworkId!,
                            version: collection.artworkVersion,
                            maxWidth: maxWidth,
                          ),
                  fallbackIcon: _collectionIcon(collection.kind),
                  borderRadius: collection.kind ==
                          MusicCatalogCollectionKind.artist
                      ? 22
                      : 8,
                ),
                title: Text(
                  collection.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: collection.subtitle.isEmpty
                    ? null
                    : Text(
                        collection.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: canMutatePlaylists
                    ? PopupMenuButton<_CatalogPlaylistAction>(
                        key: ValueKey<String>(
                          'catalog-playlist-actions-${collection.id}',
                        ),
                        enabled: !_playlistMutationInProgress,
                        tooltip: 'Actions for ${collection.title}',
                        onSelected: (action) => _handlePlaylistAction(
                          action,
                          playlistMutator,
                          collection,
                        ),
                        itemBuilder: (_) => const <
                            PopupMenuEntry<_CatalogPlaylistAction>>[
                          PopupMenuItem<_CatalogPlaylistAction>(
                            value: _CatalogPlaylistAction.rename,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Rename'),
                            ),
                          ),
                          PopupMenuItem<_CatalogPlaylistAction>(
                            value: _CatalogPlaylistAction.delete,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete'),
                            ),
                          ),
                        ],
                      )
                    : const Icon(Icons.chevron_right),
                onTap: () => widget.onOpen(collection),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _createPlaylist(
    MusicPlaylistMutationProvider playlistMutator,
  ) async {
    final name = await _promptForRemotePlaylistName(
      context,
      title: 'Create remote playlist',
      actionLabel: 'Create',
    );
    if (name == null) {
      return;
    }
    await _runPlaylistMutation(
      () => playlistMutator.createPlaylist(name),
      'Created $name.',
    );
  }

  void _handlePlaylistAction(
    _CatalogPlaylistAction action,
    MusicPlaylistMutationProvider playlistMutator,
    MusicCatalogCollection playlist,
  ) {
    switch (action) {
      case _CatalogPlaylistAction.rename:
        unawaited(_renamePlaylist(playlistMutator, playlist));
      case _CatalogPlaylistAction.delete:
        unawaited(_deletePlaylist(playlistMutator, playlist));
    }
  }

  Future<void> _renamePlaylist(
    MusicPlaylistMutationProvider playlistMutator,
    MusicCatalogCollection playlist,
  ) async {
    final name = await _promptForRemotePlaylistName(
      context,
      title: 'Rename remote playlist',
      actionLabel: 'Rename',
      initialValue: playlist.title,
    );
    if (name == null || name == playlist.title) {
      return;
    }
    await _runPlaylistMutation(
      () => playlistMutator.renamePlaylist(playlist.id, name),
      'Renamed playlist to $name.',
    );
  }

  Future<void> _deletePlaylist(
    MusicPlaylistMutationProvider playlistMutator,
    MusicCatalogCollection playlist,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete remote playlist?'),
        content: Text(
          'Delete ${playlist.title} from ${widget.provider.name}?',
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
    if (confirmed != true) {
      return;
    }
    await _runPlaylistMutation(
      () => playlistMutator.deletePlaylist(playlist.id),
      'Deleted ${playlist.title}.',
    );
  }

  Future<void> _runPlaylistMutation(
    Future<void> Function() mutation,
    String successMessage,
  ) async {
    if (_playlistMutationInProgress) {
      return;
    }
    setState(() => _playlistMutationInProgress = true);
    try {
      await mutation();
      await widget.onRefresh();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _playlistMutationInProgress = false);
      }
    }
  }
}

enum _CatalogPlaylistAction { rename, delete }

class SelfHostedCollectionScreen extends StatefulWidget {
  const SelfHostedCollectionScreen({
    required this.provider,
    required this.collection,
    super.key,
  });

  final MusicCatalogProvider provider;
  final MusicCatalogCollection collection;

  @override
  State<SelfHostedCollectionScreen> createState() =>
      _SelfHostedCollectionScreenState();
}

class _SelfHostedCollectionScreenState
    extends State<SelfHostedCollectionScreen> {
  late Future<MusicCatalogDetail> _request;
  final TextEditingController _filterController = TextEditingController();
  String _query = '';
  bool _playlistMutationInProgress = false;

  @override
  void initState() {
    super.initState();
    _request = widget.provider.loadCollection(widget.collection);
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<LibraryStore>().offlineModeEnabled;
    return Scaffold(
      appBar: AppBar(title: Text(widget.collection.title)),
      body: offline
          ? const _CatalogOfflineState()
          : FutureBuilder<MusicCatalogDetail>(
              future: _request,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _CatalogErrorState(
                    error: snapshot.error!,
                    onRetry: _reload,
                  );
                }
                final detail = snapshot.data!;
                if (detail.collections.isNotEmpty) {
                  return _buildNestedCollections(detail.collections);
                }
                return _buildTracks(detail.tracks);
              },
            ),
    );
  }

  Widget _buildNestedCollections(List<MusicCatalogCollection> collections) {
    final normalizedQuery = _query.trim().toLowerCase();
    final visible = normalizedQuery.isEmpty
        ? collections
        : collections
            .where(
              (collection) =>
                  collection.title.toLowerCase().contains(normalizedQuery) ||
                  collection.subtitle.toLowerCase().contains(normalizedQuery),
            )
            .toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visible.isEmpty ? 2 : visible.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _filterField('Filter albums');
        }
        if (index == 1 && visible.isEmpty) {
          return const _CatalogEmptyState(label: 'No albums found.');
        }
        final collection = visible[index - 1];
        return ListTile(
          key: ValueKey<String>('catalog-detail-${collection.id}'),
          leading: TrackArtwork(
            artworkUri: null,
            providerId: widget.provider.id,
            providerArtworkId: collection.artworkId,
            providerArtworkVersion: collection.artworkVersion,
            loadProviderArtwork: collection.artworkId == null
                ? null
                : (maxWidth) => widget.provider.loadArtwork(
                      collection.artworkId!,
                      version: collection.artworkVersion,
                      maxWidth: maxWidth,
                    ),
            fallbackIcon: _collectionIcon(collection.kind),
          ),
          title: Text(collection.title),
          subtitle:
              collection.subtitle.isEmpty ? null : Text(collection.subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => SelfHostedCollectionScreen(
                provider: widget.provider,
                collection: collection,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTracks(List<Track> tracks) {
    final playlistMutator = widget.provider.capabilities.contains(
              MusicSourceCapability.playlistMutation,
            ) &&
            widget.provider is MusicPlaylistMutationProvider
        ? widget.provider as MusicPlaylistMutationProvider
        : null;
    final isMutablePlaylist =
        widget.collection.kind == MusicCatalogCollectionKind.playlist &&
            playlistMutator != null;
    final normalizedQuery = _query.trim().toLowerCase();
    final visible = normalizedQuery.isEmpty
        ? tracks
        : tracks
            .where(
              (track) => <String>[track.title, track.artist, track.album]
                  .any((value) => value.toLowerCase().contains(normalizedQuery)),
            )
            .toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: visible.isEmpty ? 2 : visible.length + 1,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    key: const Key('catalog-play-all'),
                    onPressed: tracks.isEmpty ? null : () => _play(tracks.first, tracks),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play all'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('catalog-save-all'),
                    onPressed: tracks.isEmpty ? null : () => _saveAll(tracks),
                    icon: const Icon(Icons.library_add_outlined),
                    label: const Text('Save all'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _filterField('Filter tracks'),
            ],
          );
        }
        if (index == 1 && visible.isEmpty) {
          return _CatalogEmptyState(
            label: normalizedQuery.isEmpty
                ? 'No tracks found.'
                : 'No tracks match this filter.',
          );
        }
        final track = visible[index - 1];
        final playlistIndex = tracks.indexWhere(
          (candidate) => candidate.id == track.id,
        );
        return ListTile(
          key: ValueKey<String>('catalog-track-${track.id}'),
          leading: TrackArtwork(
            artworkUri: track.artworkUri,
            providerId: track.sourceId,
            providerArtworkId: track.providerArtworkId,
            providerArtworkVersion: track.providerArtworkVersion,
            loadProviderArtwork: track.providerArtworkId == null
                ? null
                : (maxWidth) => widget.provider.loadArtwork(
                      track.providerArtworkId!,
                      version: track.providerArtworkVersion,
                      maxWidth: maxWidth,
                    ),
          ),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${track.artist} · ${track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _play(track, tracks),
          trailing: PopupMenuButton<_CatalogTrackAction>(
            key: ValueKey<String>('catalog-track-actions-${track.id}'),
            enabled: !_playlistMutationInProgress,
            tooltip: 'Actions for ${track.title}',
            onSelected: (action) => _handleTrackAction(
              action,
              track,
              tracks,
              playlistIndex,
              playlistMutator,
            ),
            itemBuilder: (_) => <PopupMenuEntry<_CatalogTrackAction>>[
              const PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.play,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.play_arrow),
                  title: Text('Play'),
                ),
              ),
              const PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.save,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.library_add_outlined),
                  title: Text('Save to library'),
                ),
              ),
              if (playlistMutator != null && !isMutablePlaylist)
                PopupMenuItem<_CatalogTrackAction>(
                  value: _CatalogTrackAction.addToRemotePlaylist,
                  enabled: track.externalId?.trim().isNotEmpty ?? false,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.playlist_add),
                    title: Text('Add to remote playlist'),
                  ),
                ),
              const PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.cache,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.offline_pin_outlined),
                  title: Text('Queue offline cache'),
                ),
              ),
              const PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.download,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_outlined),
                  title: Text('Queue download'),
                ),
              ),
              if (isMutablePlaylist) ...<PopupMenuEntry<_CatalogTrackAction>>[
                const PopupMenuDivider(),
                PopupMenuItem<_CatalogTrackAction>(
                  value: _CatalogTrackAction.moveUp,
                  enabled: playlistIndex > 0,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.arrow_upward),
                    title: Text('Move up'),
                  ),
                ),
                PopupMenuItem<_CatalogTrackAction>(
                  value: _CatalogTrackAction.moveDown,
                  enabled: playlistIndex >= 0 &&
                      playlistIndex < tracks.length - 1,
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.arrow_downward),
                    title: Text('Move down'),
                  ),
                ),
                const PopupMenuItem<_CatalogTrackAction>(
                  value: _CatalogTrackAction.removeFromRemotePlaylist,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.playlist_remove),
                    title: Text('Remove from playlist'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _filterField(String label) {
    return TextField(
      key: const Key('catalog-detail-filter'),
      controller: _filterController,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear filter',
                onPressed: () {
                  _filterController.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.clear),
              ),
      ),
      onChanged: (value) => setState(() => _query = value),
    );
  }

  Future<void> _reload() async {
    final request = widget.provider.loadCollection(widget.collection);
    setState(() {
      _request = request;
    });
    try {
      await request;
    } on Object {
      // FutureBuilder renders the provider's redacted error and retry action.
    }
  }

  Future<void> _play(Track track, List<Track> queue) async {
    await context.read<PlayerController>().playTrack(track, queue: queue);
  }

  Future<void> _saveAll(List<Track> tracks) async {
    await context.read<LibraryStore>().addTracks(tracks);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${tracks.length} track(s).')),
    );
  }

  Future<void> _save(Track track) async {
    await context.read<LibraryStore>().addTracks(<Track>[track]);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${track.title}.')),
    );
  }

  Future<void> _queueOffline(
    Track track,
    OfflineMediaAction action,
  ) async {
    final coordinator = ProviderSearchCoordinator(
      <MusicSourceProvider>[widget.provider],
    );
    final decision = coordinator.offlineDecision(track, action);
    if (!decision.isAllowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(decision.reason)),
      );
      return;
    }
    await context.read<LibraryStore>().queueOfflineCache(
          track,
          action,
          decision,
        );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Queued ${action.label.toLowerCase()} for ${track.title}.')),
    );
  }

  Future<void> _addToRemotePlaylist(
    MusicPlaylistMutationProvider playlistMutator,
    Track track,
  ) async {
    final trackId = track.externalId?.trim() ?? '';
    if (trackId.isEmpty || _playlistMutationInProgress) {
      return;
    }
    setState(() => _playlistMutationInProgress = true);
    try {
      final playlists = await widget.provider.browseCollections(
        MusicCatalogCollectionKind.playlist,
      );
      if (!mounted) {
        return;
      }
      final selection = playlists.isEmpty
          ? _newRemotePlaylistSelection
          : await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (sheetContext) => SafeArea(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: <Widget>[
                    const ListTile(
                      title: Text('Add to remote playlist'),
                    ),
                    ListTile(
                      key: const Key('remote-playlist-create-with-track'),
                      leading: const Icon(Icons.playlist_add),
                      title: const Text('New playlist'),
                      onTap: () => Navigator.of(sheetContext).pop(
                        _newRemotePlaylistSelection,
                      ),
                    ),
                    for (final playlist in playlists)
                      ListTile(
                        key: ValueKey<String>(
                          'remote-playlist-choice-${playlist.id}',
                        ),
                        leading: const Icon(Icons.queue_music_outlined),
                        title: Text(playlist.title),
                        subtitle: playlist.subtitle.isEmpty
                            ? null
                            : Text(playlist.subtitle),
                        onTap: () =>
                            Navigator.of(sheetContext).pop(playlist.id),
                      ),
                  ],
                ),
              ),
            );
      if (selection == null || !mounted) {
        return;
      }
      if (selection == _newRemotePlaylistSelection) {
        final name = await _promptForRemotePlaylistName(
          context,
          title: 'Create remote playlist',
          actionLabel: 'Create',
        );
        if (name == null) {
          return;
        }
        await playlistMutator.createPlaylist(
          name,
          trackIds: <String>[trackId],
        );
        if (mounted) {
          _showMessage('Created $name with ${track.title}.');
        }
        return;
      }
      await playlistMutator.addPlaylistTracks(
        selection,
        <String>[trackId],
      );
      if (!mounted) {
        return;
      }
      final target = playlists.where((item) => item.id == selection).first;
      _showMessage('Added ${track.title} to ${target.title}.');
    } on Object catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _playlistMutationInProgress = false);
      }
    }
  }

  Future<void> _moveRemotePlaylistTrack(
    MusicPlaylistMutationProvider playlistMutator,
    List<Track> tracks,
    int fromIndex,
    int toIndex,
  ) async {
    if (fromIndex < 0 ||
        fromIndex >= tracks.length ||
        toIndex < 0 ||
        toIndex >= tracks.length) {
      return;
    }
    final trackIds = _externalTrackIds(tracks);
    if (trackIds == null) {
      _showMessage('This playlist contains a track without a provider ID.');
      return;
    }
    final moved = trackIds.removeAt(fromIndex);
    trackIds.insert(toIndex, moved);
    await _runDetailPlaylistMutation(
      () => playlistMutator.replacePlaylistTracks(
        widget.collection.id,
        trackIds,
      ),
      'Updated playlist order.',
    );
  }

  Future<void> _removeRemotePlaylistTrack(
    MusicPlaylistMutationProvider playlistMutator,
    Track track,
    List<Track> tracks,
    int trackIndex,
  ) async {
    if (trackIndex < 0 || trackIndex >= tracks.length) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove from remote playlist?'),
        content: Text('Remove ${track.title} from ${widget.collection.title}?'),
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
    if (confirmed != true) {
      return;
    }
    final trackIds = _externalTrackIds(tracks);
    if (trackIds == null) {
      _showMessage('This playlist contains a track without a provider ID.');
      return;
    }
    trackIds.removeAt(trackIndex);
    await _runDetailPlaylistMutation(
      () => playlistMutator.replacePlaylistTracks(
        widget.collection.id,
        trackIds,
      ),
      'Removed ${track.title}.',
    );
  }

  Future<void> _runDetailPlaylistMutation(
    Future<void> Function() mutation,
    String successMessage,
  ) async {
    if (_playlistMutationInProgress) {
      return;
    }
    setState(() => _playlistMutationInProgress = true);
    try {
      await mutation();
      await _reload();
      if (mounted) {
        _showMessage(successMessage);
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _playlistMutationInProgress = false);
      }
    }
  }

  List<String>? _externalTrackIds(List<Track> tracks) {
    final trackIds = <String>[];
    for (final track in tracks) {
      final trackId = track.externalId?.trim() ?? '';
      if (trackId.isEmpty) {
        return null;
      }
      trackIds.add(trackId);
    }
    return trackIds;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _handleTrackAction(
    _CatalogTrackAction action,
    Track track,
    List<Track> queue,
    int playlistIndex,
    MusicPlaylistMutationProvider? playlistMutator,
  ) {
    switch (action) {
      case _CatalogTrackAction.play:
        unawaited(_play(track, queue));
      case _CatalogTrackAction.save:
        unawaited(_save(track));
      case _CatalogTrackAction.addToRemotePlaylist:
        if (playlistMutator != null) {
          unawaited(_addToRemotePlaylist(playlistMutator, track));
        }
      case _CatalogTrackAction.cache:
        unawaited(_queueOffline(track, OfflineMediaAction.cache));
      case _CatalogTrackAction.download:
        unawaited(_queueOffline(track, OfflineMediaAction.download));
      case _CatalogTrackAction.moveUp:
        if (playlistMutator != null) {
          unawaited(
            _moveRemotePlaylistTrack(
              playlistMutator,
              queue,
              playlistIndex,
              playlistIndex - 1,
            ),
          );
        }
      case _CatalogTrackAction.moveDown:
        if (playlistMutator != null) {
          unawaited(
            _moveRemotePlaylistTrack(
              playlistMutator,
              queue,
              playlistIndex,
              playlistIndex + 1,
            ),
          );
        }
      case _CatalogTrackAction.removeFromRemotePlaylist:
        if (playlistMutator != null) {
          unawaited(
            _removeRemotePlaylistTrack(
              playlistMutator,
              track,
              queue,
              playlistIndex,
            ),
          );
        }
    }
  }
}

enum _CatalogTrackAction {
  play,
  save,
  addToRemotePlaylist,
  cache,
  download,
  moveUp,
  moveDown,
  removeFromRemotePlaylist,
}

class _CatalogOfflineState extends StatelessWidget {
  const _CatalogOfflineState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_outlined, size: 48),
            SizedBox(height: 12),
            Text('Self-hosted browsing is unavailable in offline mode.'),
          ],
        ),
      ),
    );
  }
}

class _CatalogErrorState extends StatelessWidget {
  const _CatalogErrorState({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogEmptyState extends StatelessWidget {
  const _CatalogEmptyState({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: <Widget>[
          const Icon(Icons.library_music_outlined, size: 48),
          const SizedBox(height: 12),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

const _newRemotePlaylistSelection = '__aethertune_new_playlist__';

Future<String?> _promptForRemotePlaylistName(
  BuildContext context, {
  required String title,
  required String actionLabel,
  String initialValue = '',
}) {
  var value = initialValue.trim();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          key: const Key('remote-playlist-name'),
          initialValue: initialValue,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Playlist name'),
          onChanged: (nextValue) {
            setDialogState(() => value = nextValue.trim());
          },
          onFieldSubmitted: (_) {
            if (value.isNotEmpty) {
              Navigator.of(dialogContext).pop(value);
            }
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: value.isEmpty
                ? null
                : () => Navigator.of(dialogContext).pop(value),
            child: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

String _kindPlural(MusicCatalogCollectionKind kind) {
  switch (kind) {
    case MusicCatalogCollectionKind.artist:
      return 'Artists';
    case MusicCatalogCollectionKind.album:
      return 'Albums';
    case MusicCatalogCollectionKind.playlist:
      return 'Playlists';
  }
}

IconData _collectionIcon(MusicCatalogCollectionKind kind) {
  switch (kind) {
    case MusicCatalogCollectionKind.artist:
      return Icons.person_outline;
    case MusicCatalogCollectionKind.album:
      return Icons.album_outlined;
    case MusicCatalogCollectionKind.playlist:
      return Icons.queue_music_outlined;
  }
}
