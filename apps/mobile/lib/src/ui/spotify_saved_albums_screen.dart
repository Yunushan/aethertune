import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/spotify_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// Browses saved Spotify album metadata without exposing Spotify playback.
final class SpotifySavedAlbumsScreen extends StatefulWidget {
  const SpotifySavedAlbumsScreen({
    super.key,
    required this.provider,
    this.newReleases = false,
  });

  final SpotifyMetadataProvider provider;
  final bool newReleases;

  @override
  State<SpotifySavedAlbumsScreen> createState() =>
      _SpotifySavedAlbumsScreenState();
}

final class _SpotifySavedAlbumsScreenState
    extends State<SpotifySavedAlbumsScreen> {
  List<SpotifySavedAlbum> _albums = const <SpotifySavedAlbum>[];
  int _nextOffset = 0;
  int? _total;
  bool _hasMore = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final offlineModeEnabled = context.watch<LibraryStore>().offlineModeEnabled;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (offlineModeEnabled && _albums.isEmpty)
            ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Offline mode is on'),
              subtitle: Text('Turn it off to load $_collection.'),
            ),
          if (_loading && _albums.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _albums.isEmpty)
            _ErrorTile(
              title: 'Could not load $_collection',
              error: _error!,
              tooltip: 'Retry $_collection',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _albums.isEmpty && !offlineModeEnabled)
            ListTile(
              leading: const Icon(Icons.album_outlined),
              title: Text('No $_collection found'),
            ),
          for (final album in _albums)
            ListTile(
              leading: TrackArtwork(artworkUri: album.artworkUri),
              title: Text(album.title),
              subtitle: Text(_albumSubtitle(album)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openAlbum(album),
            ),
          if (_loading && _albums.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null && _albums.isNotEmpty)
            _ErrorTile(
              title: 'Could not load more $_collection',
              error: _error!,
              tooltip: 'Retry $_collection page',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: false)),
            ),
          if (_albums.isNotEmpty && _hasMore)
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
          else if (_albums.isNotEmpty && _total != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'All $_total $_collection loaded.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && !_hasMore)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      setState(() {
        _loading = false;
        _error = 'Offline mode is on.';
      });
      return;
    }
    final offset = reset ? 0 : _nextOffset;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _albums = const <SpotifySavedAlbum>[];
        _nextOffset = 0;
        _total = null;
        _hasMore = false;
      }
    });
    try {
      final page = widget.newReleases
          ? await widget.provider.loadNewReleasesPage(offset: offset)
          : await widget.provider.loadSavedAlbumsPage(offset: offset);
      if (!mounted) {
        return;
      }
      final albums = reset ? page.albums : _mergeAlbums(_albums, page.albums);
      setState(() {
        _albums = albums;
        _nextOffset = page.offset + page.albums.length;
        _total = page.total;
        _hasMore = page.hasMore && page.albums.isNotEmpty;
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

  void _openAlbum(SpotifySavedAlbum album) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifyAlbumTracksScreen(
          provider: widget.provider,
          album: album,
        ),
      ),
    );
  }

  List<SpotifySavedAlbum> _mergeAlbums(
    List<SpotifySavedAlbum> current,
    List<SpotifySavedAlbum> incoming,
  ) {
    final ids = current.map((album) => album.id).toSet();
    return <SpotifySavedAlbum>[
      ...current,
      for (final album in incoming)
        if (ids.add(album.id)) album,
    ];
  }

  String get _loadMoreLabel {
    final total = _total;
    if (total == null) {
      return 'Load more $_collection';
    }
    final remaining = total - _albums.length;
    return remaining > 0
        ? 'Load more $_collection ($remaining remaining)'
        : 'Load more $_collection';
  }

  String get _collection => widget.newReleases ? 'new releases' : 'saved albums';
  String get _title => widget.newReleases ? 'Spotify new releases' : 'Spotify saved albums';

  String _albumSubtitle(SpotifySavedAlbum album) {
    final count = album.totalTracks;
    return '${album.artist} - $count ${count == 1 ? 'track' : 'tracks'}';
  }
}

final class SpotifyAlbumTracksScreen extends StatefulWidget {
  const SpotifyAlbumTracksScreen({
    super.key,
    required this.provider,
    required this.album,
  });

  final SpotifyMetadataProvider provider;
  final SpotifySavedAlbum album;

  @override
  State<SpotifyAlbumTracksScreen> createState() =>
      _SpotifyAlbumTracksScreenState();
}

final class _SpotifyAlbumTracksScreenState
    extends State<SpotifyAlbumTracksScreen> {
  List<Track> _tracks = const <Track>[];
  int _nextOffset = 0;
  int? _total;
  bool _hasMore = false;
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (offlineModeEnabled && _tracks.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load this album.'),
            ),
          if (_loading && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _tracks.isEmpty)
            _ErrorTile(
              title: 'Could not load album tracks',
              error: _error!,
              tooltip: 'Retry album tracks',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _tracks.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.music_note_outlined),
              title: Text('No album tracks found'),
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
            _ErrorTile(
              title: 'Could not load more album tracks',
              error: _error!,
              tooltip: 'Retry album track page',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: false)),
            ),
          if (_tracks.isNotEmpty && _hasMore)
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
                'All $_total album tracks loaded.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && !_hasMore)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      setState(() {
        _loading = false;
        _error = 'Offline mode is on.';
      });
      return;
    }
    final offset = reset ? 0 : _nextOffset;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _tracks = const <Track>[];
        _nextOffset = 0;
        _total = null;
        _hasMore = false;
      }
    });
    try {
      final page = await widget.provider.loadAlbumTracksPage(
        widget.album,
        offset: offset,
      );
      if (!mounted) {
        return;
      }
      final tracks = reset ? page.tracks : _mergeTracks(_tracks, page.tracks);
      setState(() {
        _tracks = tracks;
        _nextOffset = page.offset + page.tracks.length;
        _total = page.total;
        _hasMore = page.hasMore && page.tracks.isNotEmpty;
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

  List<Track> _mergeTracks(List<Track> current, List<Track> incoming) {
    final ids = current.map((track) => track.id).toSet();
    return <Track>[
      ...current,
      for (final track in incoming)
        if (ids.add(track.id)) track,
    ];
  }

  String get _loadMoreLabel {
    final total = _total;
    if (total == null) {
      return 'Load more album tracks';
    }
    final remaining = total - _tracks.length;
    return remaining > 0
        ? 'Load more album tracks ($remaining remaining)'
        : 'Load more album tracks';
  }
}

final class _ErrorTile extends StatelessWidget {
  const _ErrorTile({
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
