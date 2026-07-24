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

const int _catalogPageSize = 100;
const List<MusicCatalogCollectionKind> _defaultCatalogCollectionKinds =
    <MusicCatalogCollectionKind>[
      MusicCatalogCollectionKind.artist,
      MusicCatalogCollectionKind.album,
      MusicCatalogCollectionKind.playlist,
    ];

class SelfHostedBrowseScreen extends StatefulWidget {
  const SelfHostedBrowseScreen({
    required this.provider,
    this.collectionKinds = _defaultCatalogCollectionKinds,
    super.key,
  }) : assert(collectionKinds.length > 0);

  final MusicCatalogProvider provider;
  final List<MusicCatalogCollectionKind> collectionKinds;

  @override
  State<SelfHostedBrowseScreen> createState() =>
      _SelfHostedBrowseScreenState();
}

class _SelfHostedBrowseScreenState extends State<SelfHostedBrowseScreen> {
  final Map<MusicCatalogCollectionKind, Future<MusicCatalogCollectionPage>>
      _requests =
      <MusicCatalogCollectionKind, Future<MusicCatalogCollectionPage>>{};
  bool _requestsStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final offline = context.watch<LibraryStore>().offlineModeEnabled;
    if (!offline && !_requestsStarted) {
      _requestsStarted = true;
      for (final kind in widget.collectionKinds) {
        _requests[kind] = _browseInitialPage(kind);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final offline = context.watch<LibraryStore>().offlineModeEnabled;
    return DefaultTabController(
      length: widget.collectionKinds.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.provider.name),
          bottom: TabBar(
            tabs: <Widget>[
              for (final kind in widget.collectionKinds)
                Tab(icon: Icon(_collectionIcon(kind)), text: _kindPlural(kind)),
            ],
          ),
        ),
        body: offline
            ? const _CatalogOfflineState()
            : TabBarView(
                children: <Widget>[
                  for (final kind in widget.collectionKinds)
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
    final request = _browseInitialPage(kind);
    setState(() {
      _requests[kind] = request;
    });
    try {
      await request;
    } on Object {
      // FutureBuilder renders the provider's redacted error and retry action.
    }
  }

  Future<MusicCatalogCollectionPage> _browseInitialPage(
    MusicCatalogCollectionKind kind,
  ) async {
    final provider = widget.provider;
    if (provider is MusicCatalogPagingProvider &&
        provider.pagedCollectionKinds.contains(kind)) {
      return provider.browseCollectionsPage(
        kind,
        limit: _catalogPageSize,
      );
    }
    final collections = await provider.browseCollections(kind);
    return MusicCatalogCollectionPage(
      collections: collections,
      nextOffset: collections.length,
      hasMore: false,
      totalCount: collections.length,
    );
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
  final Future<MusicCatalogCollectionPage> request;
  final Future<void> Function() onRefresh;
  final ValueChanged<MusicCatalogCollection> onOpen;

  @override
  State<_CatalogCollectionList> createState() =>
      _CatalogCollectionListState();
}

class _CatalogCollectionListState extends State<_CatalogCollectionList> {
  final TextEditingController _filterController = TextEditingController();
  final List<MusicCatalogCollection> _additionalCollections =
      <MusicCatalogCollection>[];
  String _query = '';
  bool _playlistMutationInProgress = false;
  bool _albumFavoriteMutationInProgress = false;
  final Map<String, bool> _remoteAlbumFavoriteOverrides = <String, bool>{};
  bool _artistFavoriteMutationInProgress = false;
  final Map<String, bool> _remoteArtistFavoriteOverrides = <String, bool>{};
  bool _loadingMore = false;
  Object? _loadMoreError;
  bool? _hasMoreOverride;
  int? _nextOffsetOverride;

  @override
  void didUpdateWidget(covariant _CatalogCollectionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.request, widget.request)) {
      _additionalCollections.clear();
      _loadingMore = false;
      _loadMoreError = null;
      _hasMoreOverride = null;
      _nextOffsetOverride = null;
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MusicCatalogCollectionPage>(
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
        final page = snapshot.data!;
        final collections = _mergeCatalogCollections(
          page.collections,
          _additionalCollections,
        );
        final hasMore = _hasMoreOverride ?? page.hasMore;
        final nextOffset = _nextOffsetOverride ?? page.nextOffset;
        final playlistMutator = widget.provider.capabilities.contains(
                  MusicSourceCapability.playlistMutation,
                ) &&
                widget.provider is MusicPlaylistMutationProvider
            ? widget.provider as MusicPlaylistMutationProvider
            : null;
        final canMutatePlaylists =
            widget.kind == MusicCatalogCollectionKind.playlist &&
                playlistMutator != null;
        final albumFavoriteMutator = widget.kind ==
                    MusicCatalogCollectionKind.album &&
                widget.provider.capabilities.contains(
                  MusicSourceCapability.albumFavoriteMutation,
                ) &&
                widget.provider is MusicAlbumFavoriteMutationProvider
            ? widget.provider as MusicAlbumFavoriteMutationProvider
            : null;
        final artistFavoriteMutator = widget.kind ==
                    MusicCatalogCollectionKind.artist &&
                widget.provider.capabilities.contains(
                  MusicSourceCapability.artistFavoriteMutation,
                ) &&
                widget.provider is MusicArtistFavoriteMutationProvider
            ? widget.provider as MusicArtistFavoriteMutationProvider
            : null;
        final library = context.watch<LibraryStore>();
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
        final showEmpty = visible.isEmpty;
        final contentCount = showEmpty ? 1 : visible.length;
        final showContinuation =
            hasMore || _loadingMore || _loadMoreError != null;
        final continuationIndex = contentCount + 1;

        return RefreshIndicator(
          onRefresh: widget.onRefresh,
          child: ListView.separated(
            key: PageStorageKey<String>('catalog-${widget.kind.name}'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: 1 + contentCount + (showContinuation ? 1 : 0),
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
              if (showContinuation && index == continuationIndex) {
                return _buildContinuation(
                  collections,
                  nextOffset: nextOffset,
                  hasMore: hasMore,
                );
              }
              if (showEmpty) {
                return _CatalogEmptyState(
                  label: normalizedQuery.isEmpty
                      ? 'No ${_kindPlural(widget.kind).toLowerCase()} found.'
                      : 'No ${_kindPlural(widget.kind).toLowerCase()} match this filter.',
                );
              }
              final collection = visible[index - 1];
              final isArtist =
                  collection.kind == MusicCatalogCollectionKind.artist;
              final isFollowed =
                  isArtist && library.isArtistFollowed(collection.title);
              final isRemoteAlbumFavorite =
                  _remoteAlbumFavoriteOverrides[collection.id] ??
                      collection.isFavorite;
              final isRemoteArtistFavorite =
                  _remoteArtistFavoriteOverrides[collection.id] ??
                      collection.isFavorite;
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
                trailing: isArtist
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            key: ValueKey<String>(
                              'catalog-follow-artist-${collection.id}',
                            ),
                            tooltip: isFollowed
                                ? 'Unfollow artist'
                                : 'Follow artist',
                            onPressed: () => unawaited(
                              library.setArtistFollowed(
                                collection.title,
                                !isFollowed,
                              ),
                            ),
                            icon: Icon(
                              isFollowed
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                            ),
                          ),
                          if (artistFavoriteMutator != null)
                            IconButton(
                              key: ValueKey<String>(
                                'catalog-favorite-artist-${collection.id}',
                              ),
                              tooltip: isRemoteArtistFavorite
                                  ? 'Remove server artist favorite'
                                  : 'Favorite artist on server',
                              onPressed: _artistFavoriteMutationInProgress
                                  ? null
                                  : () => unawaited(
                                        _setRemoteArtistFavorite(
                                          artistFavoriteMutator,
                                          collection,
                                          isRemoteArtistFavorite,
                                        ),
                                      ),
                              icon: Icon(
                                isRemoteArtistFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                              ),
                            ),
                        ],
                      )
                    : canMutatePlaylists
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
                    : albumFavoriteMutator != null
                    ? IconButton(
                        key: ValueKey<String>(
                          'catalog-favorite-album-${collection.id}',
                        ),
                        tooltip: isRemoteAlbumFavorite
                            ? 'Remove server album favorite'
                            : 'Favorite album on server',
                        onPressed: _albumFavoriteMutationInProgress
                            ? null
                            : () => unawaited(
                                  _setRemoteAlbumFavorite(
                                    albumFavoriteMutator,
                                    collection,
                                    isRemoteAlbumFavorite,
                                  ),
                                ),
                        icon: Icon(
                          isRemoteAlbumFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                        ),
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

  Widget _buildContinuation(
    List<MusicCatalogCollection> existingCollections, {
    required int nextOffset,
    required bool hasMore,
  }) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final error = _loadMoreError;
    if (error != null) {
      return ListTile(
        key: Key('catalog-load-more-error-${widget.kind.name}'),
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.warning_amber_outlined),
        title: Text('Could not load more ${_kindPlural(widget.kind).toLowerCase()}.'),
        subtitle: Text(error.toString()),
        trailing: TextButton.icon(
          key: Key('catalog-load-more-retry-${widget.kind.name}'),
          onPressed: () => unawaited(
            _loadMore(existingCollections, nextOffset: nextOffset),
          ),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      );
    }
    if (!hasMore) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.center,
      child: OutlinedButton.icon(
        key: Key('catalog-load-more-${widget.kind.name}'),
        onPressed: () => unawaited(
          _loadMore(existingCollections, nextOffset: nextOffset),
        ),
        icon: const Icon(Icons.expand_more),
        label: Text('Load more ${_kindPlural(widget.kind).toLowerCase()}'),
      ),
    );
  }

  Future<void> _loadMore(
    List<MusicCatalogCollection> existingCollections, {
    required int nextOffset,
  }) async {
    final provider = widget.provider;
    if (_loadingMore ||
        provider is! MusicCatalogPagingProvider ||
        !provider.pagedCollectionKinds.contains(widget.kind)) {
      return;
    }
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });
    final initialRequest = widget.request;
    try {
      final page = await provider.browseCollectionsPage(
        widget.kind,
        offset: nextOffset,
        limit: _catalogPageSize,
      );
      if (!mounted || !identical(initialRequest, widget.request)) {
        return;
      }
      final knownIds = existingCollections
          .map((collection) => collection.id)
          .toSet();
      final unique = page.collections
          .where((collection) => knownIds.add(collection.id))
          .toList(growable: false);
      final progressed = page.nextOffset > nextOffset;
      setState(() {
        _additionalCollections.addAll(unique);
        _nextOffsetOverride = progressed ? page.nextOffset : nextOffset;
        _hasMoreOverride =
            page.hasMore && progressed && page.collections.isNotEmpty;
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted || !identical(initialRequest, widget.request)) {
        return;
      }
      setState(() {
        _loadMoreError = error;
        _loadingMore = false;
      });
    }
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

  Future<void> _setRemoteAlbumFavorite(
    MusicAlbumFavoriteMutationProvider favoriteMutator,
    MusicCatalogCollection album,
    bool isFavorite,
  ) async {
    if (album.id.trim().isEmpty || _albumFavoriteMutationInProgress) {
      return;
    }
    final nextFavorite = !isFavorite;
    setState(() => _albumFavoriteMutationInProgress = true);
    try {
      await favoriteMutator.setAlbumFavorite(
        album.id,
        isFavorite: nextFavorite,
      );
      if (!mounted) {
        return;
      }
      setState(
        () => _remoteAlbumFavoriteOverrides[album.id] = nextFavorite,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextFavorite
                ? 'Added ${album.title} to server favorite albums.'
                : 'Removed ${album.title} from server favorite albums.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _albumFavoriteMutationInProgress = false);
      }
    }
  }

  Future<void> _setRemoteArtistFavorite(
    MusicArtistFavoriteMutationProvider favoriteMutator,
    MusicCatalogCollection artist,
    bool isFavorite,
  ) async {
    if (artist.id.trim().isEmpty || _artistFavoriteMutationInProgress) {
      return;
    }
    final nextFavorite = !isFavorite;
    setState(() => _artistFavoriteMutationInProgress = true);
    try {
      await favoriteMutator.setArtistFavorite(
        artist.id,
        isFavorite: nextFavorite,
      );
      if (!mounted) {
        return;
      }
      setState(
        () => _remoteArtistFavoriteOverrides[artist.id] = nextFavorite,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextFavorite
                ? 'Added ${artist.title} to server favorite artists.'
                : 'Removed ${artist.title} from server favorite artists.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _artistFavoriteMutationInProgress = false);
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
  Future<MusicCatalogDetail>? _request;
  bool _requestStarted = false;
  final TextEditingController _filterController = TextEditingController();
  String _query = '';
  bool _playlistMutationInProgress = false;
  bool _favoriteMutationInProgress = false;
  final Map<String, bool> _remoteFavoriteOverrides = <String, bool>{};
  bool _radioInProgress = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final offline = context.watch<LibraryStore>().offlineModeEnabled;
    if (!offline && !_requestStarted) {
      _requestStarted = true;
      _request = widget.provider.loadCollection(widget.collection);
    }
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
              future: _request!,
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
    final radioProvider = _radioProvider;
    final radioSeedKind = _radioSeedKind(widget.collection.kind);
    final canStartRadio = radioProvider != null &&
        radioSeedKind != null &&
        radioProvider.radioSeedKinds.contains(radioSeedKind) &&
        widget.collection.id.trim().isNotEmpty;
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
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (canStartRadio) ...<Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: _startRadioButton(
                    radioProvider,
                    radioSeedKind,
                    widget.collection.title,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _filterField('Filter albums'),
            ],
          );
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
    final radioProvider = _radioProvider;
    final collectionRadioSeedKind = _radioSeedKind(widget.collection.kind);
    final canStartCollectionRadio = radioProvider != null &&
        collectionRadioSeedKind != null &&
        radioProvider.radioSeedKinds.contains(collectionRadioSeedKind) &&
        widget.collection.id.trim().isNotEmpty;
    final canStartTrackRadio = radioProvider != null &&
        radioProvider.radioSeedKinds.contains(
          MusicCatalogRadioSeedKind.track,
        );
    final playlistMutator = widget.provider.capabilities.contains(
              MusicSourceCapability.playlistMutation,
            ) &&
            widget.provider is MusicPlaylistMutationProvider
        ? widget.provider as MusicPlaylistMutationProvider
        : null;
    final isMutablePlaylist =
        widget.collection.kind == MusicCatalogCollectionKind.playlist &&
            playlistMutator != null;
    final favoriteMutator = widget.provider.capabilities.contains(
              MusicSourceCapability.favoriteMutation,
            ) &&
            widget.provider is MusicTrackFavoriteMutationProvider
        ? widget.provider as MusicTrackFavoriteMutationProvider
        : null;
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
      separatorBuilder: (_, _) => const Divider(height: 1),
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
                  if (canStartCollectionRadio)
                    _startRadioButton(
                      radioProvider,
                      collectionRadioSeedKind,
                      widget.collection.title,
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
        final trackId = track.externalId?.trim() ?? '';
        final isRemoteFavorite =
            _remoteFavoriteOverrides[trackId] ?? track.isFavorite;
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
            enabled:
                !_playlistMutationInProgress && !_favoriteMutationInProgress,
            tooltip: 'Actions for ${track.title}',
            onSelected: (action) => _handleTrackAction(
              action,
              track,
              tracks,
              playlistIndex,
              playlistMutator,
              favoriteMutator,
              isRemoteFavorite,
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
              if (canStartTrackRadio &&
                  (track.externalId?.trim().isNotEmpty ?? false))
                const PopupMenuItem<_CatalogTrackAction>(
                  value: _CatalogTrackAction.startRadio,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.radio_outlined),
                    title: Text('Start radio'),
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
              if (favoriteMutator != null)
                PopupMenuItem<_CatalogTrackAction>(
                  value: _CatalogTrackAction.favoriteOnServer,
                  enabled: trackId.isNotEmpty,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      isRemoteFavorite
                          ? Icons.favorite_border
                          : Icons.favorite,
                    ),
                    title: Text(
                      isRemoteFavorite
                          ? 'Remove server favorite'
                          : 'Favorite on server',
                    ),
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

  MusicCatalogRadioProvider? get _radioProvider {
    final provider = widget.provider;
    if (!provider.capabilities.contains(
          MusicSourceCapability.recommendations,
        ) ||
        provider is! MusicCatalogRadioProvider) {
      return null;
    }
    return provider;
  }

  Widget _startRadioButton(
    MusicCatalogRadioProvider provider,
    MusicCatalogRadioSeedKind seedKind,
    String label,
  ) {
    return OutlinedButton.icon(
      key: ValueKey<String>('catalog-start-radio-${seedKind.name}'),
      onPressed: _radioInProgress
          ? null
          : () => unawaited(
                _startRadio(
                  provider,
                  MusicCatalogRadioSeed(
                    kind: seedKind,
                    id: widget.collection.id,
                  ),
                  label: label,
                ),
              ),
      icon: _radioInProgress
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.radio_outlined),
      label: const Text('Start radio'),
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

  Future<void> _startRadio(
    MusicCatalogRadioProvider provider,
    MusicCatalogRadioSeed seed, {
    required String label,
    Track? seedTrack,
  }) async {
    if (_radioInProgress ||
        !provider.radioSeedKinds.contains(seed.kind) ||
        seed.id.trim().isEmpty) {
      return;
    }
    final library = context.read<LibraryStore>();
    if (library.offlineModeEnabled) {
      _showMessage('Self-hosted radio is unavailable in offline mode.');
      return;
    }
    final player = context.read<PlayerController>();
    setState(() => _radioInProgress = true);
    try {
      final recommendations = _deduplicateRadioTracks(
        await provider.loadRadio(seed),
      );
      if (!mounted) {
        return;
      }
      if (library.offlineModeEnabled) {
        _showMessage('Self-hosted radio is unavailable in offline mode.');
        return;
      }
      final queue = _deduplicateRadioTracks(<Track>[
        ?seedTrack,
        ...recommendations,
      ]);
      if (recommendations.isEmpty ||
          (seedTrack != null && queue.length == 1)) {
        _showMessage('No radio tracks found for $label.');
        return;
      }
      await player.playTrack(queue.first, queue: queue);
      if (mounted) {
        _showMessage(
          'Started radio for $label with ${queue.length} track(s).',
        );
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _radioInProgress = false);
      }
    }
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

  Future<void> _setRemoteFavorite(
    MusicTrackFavoriteMutationProvider favoriteMutator,
    Track track,
    bool isFavorite,
  ) async {
    final trackId = track.externalId?.trim() ?? '';
    if (trackId.isEmpty || _favoriteMutationInProgress) {
      return;
    }
    final nextFavorite = !isFavorite;
    setState(() => _favoriteMutationInProgress = true);
    try {
      await favoriteMutator.setTrackFavorite(
        trackId,
        isFavorite: nextFavorite,
      );
      if (!mounted) {
        return;
      }
      setState(() => _remoteFavoriteOverrides[trackId] = nextFavorite);
      _showMessage(
        nextFavorite
            ? 'Added ${track.title} to server favorites.'
            : 'Removed ${track.title} from server favorites.',
      );
    } on Object catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _favoriteMutationInProgress = false);
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
    MusicTrackFavoriteMutationProvider? favoriteMutator,
    bool isRemoteFavorite,
  ) {
    switch (action) {
      case _CatalogTrackAction.play:
        unawaited(_play(track, queue));
      case _CatalogTrackAction.startRadio:
        final radioProvider = _radioProvider;
        final externalId = track.externalId?.trim() ?? '';
        if (radioProvider != null && externalId.isNotEmpty) {
          unawaited(
            _startRadio(
              radioProvider,
              MusicCatalogRadioSeed(
                kind: MusicCatalogRadioSeedKind.track,
                id: externalId,
              ),
              label: track.title,
              seedTrack: track,
            ),
          );
        }
      case _CatalogTrackAction.save:
        unawaited(_save(track));
      case _CatalogTrackAction.addToRemotePlaylist:
        if (playlistMutator != null) {
          unawaited(_addToRemotePlaylist(playlistMutator, track));
        }
      case _CatalogTrackAction.favoriteOnServer:
        if (favoriteMutator != null) {
          unawaited(
            _setRemoteFavorite(favoriteMutator, track, isRemoteFavorite),
          );
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
  startRadio,
  save,
  addToRemotePlaylist,
  favoriteOnServer,
  cache,
  download,
  moveUp,
  moveDown,
  removeFromRemotePlaylist,
}

MusicCatalogRadioSeedKind? _radioSeedKind(
  MusicCatalogCollectionKind kind,
) {
  return switch (kind) {
    MusicCatalogCollectionKind.artist => MusicCatalogRadioSeedKind.artist,
    MusicCatalogCollectionKind.album => MusicCatalogRadioSeedKind.album,
    MusicCatalogCollectionKind.playlist => null,
  };
}

List<Track> _deduplicateRadioTracks(Iterable<Track> tracks) {
  final seen = <String>{};
  final result = <Track>[];
  for (final track in tracks) {
    final externalId = track.externalId?.trim() ?? '';
    final identity = externalId.isEmpty
        ? '${track.sourceId}|${track.id}'
        : '${track.sourceId}|$externalId';
    if (seen.add(identity)) {
      result.add(track);
    }
  }
  return List<Track>.unmodifiable(result);
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

List<MusicCatalogCollection> _mergeCatalogCollections(
  Iterable<MusicCatalogCollection> first,
  Iterable<MusicCatalogCollection> second,
) {
  final merged = <MusicCatalogCollection>[];
  final ids = <String>{};
  for (final collection in <Iterable<MusicCatalogCollection>>[first, second]
      .expand((collections) => collections)) {
    final id = collection.id.trim();
    if (id.isEmpty || !ids.add('${collection.kind.name}|$id')) {
      continue;
    }
    merged.add(collection);
  }
  return List<MusicCatalogCollection>.unmodifiable(merged);
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
