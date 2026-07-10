import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../domain/music_catalog_provider.dart';
import '../domain/music_source_provider.dart';
import '../domain/provider_search.dart';
import '../domain/track.dart';
import '../player/player_controller.dart';

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
    required this.kind,
    required this.request,
    required this.onRefresh,
    required this.onOpen,
    super.key,
  });

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
                return TextField(
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
                leading: Icon(_collectionIcon(collection.kind)),
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
                trailing: const Icon(Icons.chevron_right),
                onTap: () => widget.onOpen(collection),
              );
            },
          ),
        );
      },
    );
  }
}

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
          leading: Icon(_collectionIcon(collection.kind)),
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
        return ListTile(
          key: ValueKey<String>('catalog-track-${track.id}'),
          leading: const Icon(Icons.music_note),
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
            tooltip: 'Actions for ${track.title}',
            onSelected: (action) => _handleTrackAction(action, track, tracks),
            itemBuilder: (_) => const <PopupMenuEntry<_CatalogTrackAction>>[
              PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.play,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.play_arrow),
                  title: Text('Play'),
                ),
              ),
              PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.save,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.library_add_outlined),
                  title: Text('Save to library'),
                ),
              ),
              PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.cache,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.offline_pin_outlined),
                  title: Text('Queue offline cache'),
                ),
              ),
              PopupMenuItem<_CatalogTrackAction>(
                value: _CatalogTrackAction.download,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.download_outlined),
                  title: Text('Queue download'),
                ),
              ),
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

  void _handleTrackAction(
    _CatalogTrackAction action,
    Track track,
    List<Track> queue,
  ) {
    switch (action) {
      case _CatalogTrackAction.play:
        unawaited(_play(track, queue));
      case _CatalogTrackAction.save:
        unawaited(_save(track));
      case _CatalogTrackAction.cache:
        unawaited(_queueOffline(track, OfflineMediaAction.cache));
      case _CatalogTrackAction.download:
        unawaited(_queueOffline(track, OfflineMediaAction.download));
    }
  }
}

enum _CatalogTrackAction { play, save, cache, download }

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
