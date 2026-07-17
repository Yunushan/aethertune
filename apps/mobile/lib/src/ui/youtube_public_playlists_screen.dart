import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/youtube_data_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// Public YouTube playlist discovery through the official Data API.
final class YouTubePublicPlaylistsScreen extends StatefulWidget {
  const YouTubePublicPlaylistsScreen({super.key, required this.provider});

  final YouTubeDataMetadataProvider provider;

  @override
  State<YouTubePublicPlaylistsScreen> createState() =>
      _YouTubePublicPlaylistsScreenState();
}

final class _YouTubePublicPlaylistsScreenState
    extends State<YouTubePublicPlaylistsScreen> {
  final _queryController = TextEditingController();
  List<YouTubeDataPlaylist> _playlists = const <YouTubeDataPlaylist>[];
  String? _nextCursor;
  int? _total;
  bool _loading = false;
  String? _error;
  String? _query;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offlineModeEnabled = context.watch<LibraryStore>().offlineModeEnabled;
    final hasSearch = (_query ?? '').isNotEmpty;
    final hasMore = _nextCursor != null;
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube public playlists')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('youtube-playlist-search'),
            controller: _queryController,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Find public playlists',
              suffixIcon: IconButton(
                tooltip: 'Search YouTube playlists',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => unawaited(_load(reset: true)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Public playlist metadata only. A playlist cannot grant playback, downloads, or account access.',
          ),
          if (offlineModeEnabled && !hasSearch)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to search public playlists.'),
              ),
            ),
          if (hasSearch) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Search results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_loading && _playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null && _playlists.isEmpty)
              _YouTubePlaylistErrorTile(
                title: 'Could not load public playlists',
                error: _error!,
                tooltip: 'Retry YouTube playlist search',
                enabled: !_loading && !offlineModeEnabled,
                onRetry: () => unawaited(_load(reset: true)),
              ),
            if (!_loading && _error == null && _playlists.isEmpty)
              const ListTile(
                leading: Icon(Icons.queue_music_outlined),
                title: Text('No public playlists found'),
              ),
            for (final playlist in _playlists)
              ListTile(
                leading: TrackArtwork(
                  artworkUri: playlist.thumbnailUri,
                  fallbackIcon: Icons.queue_music_outlined,
                ),
                title: Text(playlist.title),
                subtitle: Text(
                  playlist.channelTitle ?? playlist.description ?? playlist.id,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPlaylist(context, playlist),
              ),
            if (_loading && _playlists.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null && _playlists.isNotEmpty)
              _YouTubePlaylistErrorTile(
                title: 'Could not load more public playlists',
                error: _error!,
                tooltip: 'Retry YouTube playlist page',
                enabled: !_loading && !offlineModeEnabled,
                onRetry: () => unawaited(_load(reset: false)),
              ),
            if (_playlists.isNotEmpty && hasMore)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _loading || offlineModeEnabled
                      ? null
                      : () => unawaited(_load(reset: false)),
                  icon: const Icon(Icons.expand_more),
                  label: Text(_loadMoreLabel),
                ),
              )
            else if (_playlists.isNotEmpty && _total != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'All loaded public playlists are shown.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && _nextCursor == null)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final query = reset ? _queryController.text.trim() : _query;
    if (query == null || query.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _query = query;
        _playlists = const <YouTubeDataPlaylist>[];
        _nextCursor = null;
        _total = null;
      }
    });
    try {
      final page = await widget.provider.searchPlaylistsPage(
        query,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _playlists = reset
            ? page.playlists
            : _mergePlaylists(_playlists, page.playlists);
        _nextCursor = page.nextPageToken;
        _total = page.totalResults;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  List<YouTubeDataPlaylist> _mergePlaylists(
    List<YouTubeDataPlaylist> current,
    List<YouTubeDataPlaylist> incoming,
  ) {
    final ids = current.map((playlist) => playlist.id).toSet();
    return <YouTubeDataPlaylist>[
      ...current,
      for (final playlist in incoming)
        if (ids.add(playlist.id)) playlist,
    ];
  }

  void _openPlaylist(BuildContext context, YouTubeDataPlaylist playlist) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubePublicPlaylistItemsScreen(
          provider: widget.provider,
          playlist: playlist,
        ),
      ),
    );
  }

  String get _loadMoreLabel {
    final total = _total;
    if (total == null) {
      return 'Load more public playlists';
    }
    final remaining = total - _playlists.length;
    return remaining > 0
        ? 'Load more public playlists ($remaining remaining)'
        : 'Load more public playlists';
  }
}

/// Paged metadata for the public items of one discovered playlist.
final class YouTubePublicPlaylistItemsScreen extends StatefulWidget {
  const YouTubePublicPlaylistItemsScreen({
    super.key,
    required this.provider,
    required this.playlist,
  });

  final YouTubeDataMetadataProvider provider;
  final YouTubeDataPlaylist playlist;

  @override
  State<YouTubePublicPlaylistItemsScreen> createState() =>
      _YouTubePublicPlaylistItemsScreenState();
}

final class _YouTubePublicPlaylistItemsScreenState
    extends State<YouTubePublicPlaylistItemsScreen> {
  List<Track> _tracks = const <Track>[];
  String? _nextCursor;
  int? _total;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offlineModeEnabled = library.offlineModeEnabled;
    final hasMore = _nextCursor != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Save loaded metadata as local playlist',
            onPressed: _tracks.isEmpty || _loading
                ? null
                : () => unawaited(_saveLoadedTracksAsPlaylist()),
            icon: const Icon(Icons.playlist_add_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Public item metadata only. Saving entries does not enable playback or downloads.',
          ),
          if (offlineModeEnabled && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to load public playlist items.'),
              ),
            ),
          if (_loading && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _tracks.isEmpty)
            _YouTubePlaylistErrorTile(
              title: 'Could not load public playlist items',
              error: _error!,
              tooltip: 'Retry public playlist items',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _tracks.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.music_note_outlined),
              title: Text('No public playlist items found'),
            ),
          for (final track in _tracks)
            ListTile(
              leading: TrackArtwork(artworkUri: track.artworkUri),
              title: Text(track.title),
              subtitle: Text(track.artist),
              trailing: IconButton(
                tooltip: library.tracks.any((saved) => saved.id == track.id)
                    ? 'Saved to library'
                    : 'Save metadata to library',
                onPressed: () => unawaited(_saveTrack(track)),
                icon: Icon(
                  library.tracks.any((saved) => saved.id == track.id)
                      ? Icons.bookmark
                      : Icons.bookmark_add_outlined,
                ),
              ),
            ),
          if (_loading && _tracks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null && _tracks.isNotEmpty)
            _YouTubePlaylistErrorTile(
              title: 'Could not load more public playlist items',
              error: _error!,
              tooltip: 'Retry public playlist item page',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: false)),
            ),
          if (_tracks.isNotEmpty && hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.expand_more),
                label: Text(_loadMoreLabel),
              ),
            )
          else if (_tracks.isNotEmpty && _total != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'All loaded public playlist items are shown.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && _nextCursor == null)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      setState(() {
        _error = 'Offline mode is on.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _tracks = const <Track>[];
        _nextCursor = null;
        _total = null;
      }
    });
    try {
      final page = await widget.provider.loadPlaylistItemsPage(
        widget.playlist.id,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _tracks = reset ? page.tracks : <Track>[..._tracks, ...page.tracks];
        _nextCursor = page.nextPageToken;
        _total = page.totalResults;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _saveTrack(Track track) async {
    await context.read<LibraryStore>().addTracks(<Track>[track]);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${track.title} metadata saved to your library.')),
    );
  }

  Future<void> _saveLoadedTracksAsPlaylist() async {
    if (_tracks.isEmpty) {
      return;
    }
    final library = context.read<LibraryStore>();
    await library.addTracks(_tracks);
    final playlist = await library.createPlaylist(
      widget.playlist.title,
      trackIds: _tracks.map((track) => track.id).toList(growable: false),
    );
    final orderedPlaylist = await library.replacePlaylistTracks(
      playlist.id,
      _tracks.map((track) => track.id),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved ${orderedPlaylist?.trackIds.length ?? playlist.trackIds.length} '
          'loaded items as ${playlist.name}.',
        ),
      ),
    );
  }

  String get _loadMoreLabel {
    final total = _total;
    if (total == null) {
      return 'Load more public playlist items';
    }
    final remaining = total - _tracks.length;
    return remaining > 0
        ? 'Load more public playlist items ($remaining remaining)'
        : 'Load more public playlist items';
  }
}

final class _YouTubePlaylistErrorTile extends StatelessWidget {
  const _YouTubePlaylistErrorTile({
    required this.title,
    required this.error,
    required this.tooltip,
    required this.enabled,
    required this.onRetry,
  });

  final String title;
  final String error;
  final String tooltip;
  final bool enabled;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.error_outline),
      title: Text(title),
      subtitle: Text(error),
      trailing: IconButton(
        tooltip: tooltip,
        onPressed: enabled ? onRetry : null,
        icon: const Icon(Icons.refresh),
      ),
    );
  }
}
