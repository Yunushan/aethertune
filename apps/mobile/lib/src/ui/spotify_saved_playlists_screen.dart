import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/spotify_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// Browses user-authorized Spotify playlist metadata without Spotify playback.
final class SpotifySavedPlaylistsScreen extends StatefulWidget {
  const SpotifySavedPlaylistsScreen({super.key, required this.provider});

  final SpotifyMetadataProvider provider;

  @override
  State<SpotifySavedPlaylistsScreen> createState() =>
      _SpotifySavedPlaylistsScreenState();
}

final class _SpotifySavedPlaylistsScreenState
    extends State<SpotifySavedPlaylistsScreen> {
  List<SpotifySavedPlaylist> _playlists = const <SpotifySavedPlaylist>[];
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
      appBar: AppBar(title: const Text('Spotify playlists')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (offlineModeEnabled && _playlists.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load Spotify playlists.'),
            ),
          if (_loading && _playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _playlists.isEmpty)
            _SpotifyPlaylistErrorTile(
              title: 'Could not load playlists',
              error: _error!,
              tooltip: 'Retry playlists',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _playlists.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.queue_music_outlined),
              title: Text('No playlists found'),
            ),
          for (final playlist in _playlists)
            ListTile(
              leading: TrackArtwork(artworkUri: playlist.artworkUri),
              title: Text(playlist.title),
              subtitle: Text(_playlistSubtitle(playlist)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openPlaylist(playlist),
            ),
          if (_loading && _playlists.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null && _playlists.isNotEmpty)
            _SpotifyPlaylistErrorTile(
              title: 'Could not load more playlists',
              error: _error!,
              tooltip: 'Retry playlist page',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: false)),
            ),
          if (_playlists.isNotEmpty && _hasMore)
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
                'All $_total playlists loaded.',
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
        _playlists = const <SpotifySavedPlaylist>[];
        _nextOffset = 0;
        _total = null;
        _hasMore = false;
      }
    });
    try {
      final page = await widget.provider.loadSavedPlaylistsPage(offset: offset);
      if (!mounted) {
        return;
      }
      final playlists = reset
          ? page.playlists
          : _mergePlaylists(_playlists, page.playlists);
      setState(() {
        _playlists = playlists;
        _nextOffset = page.offset + page.playlists.length;
        _total = page.total;
        _hasMore = page.hasMore && page.playlists.isNotEmpty;
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

  void _openPlaylist(SpotifySavedPlaylist playlist) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifyPlaylistTracksScreen(
          provider: widget.provider,
          playlist: playlist,
        ),
      ),
    );
  }

  List<SpotifySavedPlaylist> _mergePlaylists(
    List<SpotifySavedPlaylist> current,
    List<SpotifySavedPlaylist> incoming,
  ) {
    final ids = current.map((playlist) => playlist.id).toSet();
    return <SpotifySavedPlaylist>[
      ...current,
      for (final playlist in incoming)
        if (ids.add(playlist.id)) playlist,
    ];
  }

  String get _loadMoreLabel {
    final total = _total;
    if (total == null) {
      return 'Load more playlists';
    }
    final remaining = total - _playlists.length;
    return remaining > 0
        ? 'Load more playlists ($remaining remaining)'
        : 'Load more playlists';
  }

  String _playlistSubtitle(SpotifySavedPlaylist playlist) {
    final count = playlist.totalTracks;
    return '${playlist.ownerName} - $count ${count == 1 ? 'track' : 'tracks'}';
  }
}

final class SpotifyPlaylistTracksScreen extends StatefulWidget {
  const SpotifyPlaylistTracksScreen({
    super.key,
    required this.provider,
    required this.playlist,
  });

  final SpotifyMetadataProvider provider;
  final SpotifySavedPlaylist playlist;

  @override
  State<SpotifyPlaylistTracksScreen> createState() =>
      _SpotifyPlaylistTracksScreenState();
}

final class _SpotifyPlaylistTracksScreenState
    extends State<SpotifyPlaylistTracksScreen> {
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
      appBar: AppBar(title: Text(widget.playlist.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (offlineModeEnabled && _tracks.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load this playlist.'),
            ),
          if (_loading && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _tracks.isEmpty)
            _SpotifyPlaylistErrorTile(
              title: 'Could not load playlist tracks',
              error: _error!,
              tooltip: 'Retry playlist tracks',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _tracks.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.music_note_outlined),
              title: Text('No playlist tracks found'),
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
            _SpotifyPlaylistErrorTile(
              title: 'Could not load more playlist tracks',
              error: _error!,
              tooltip: 'Retry playlist track page',
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
                'All $_total playlist tracks loaded.',
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
      final page = await widget.provider.loadPlaylistTracksPage(
        widget.playlist,
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
      return 'Load more playlist tracks';
    }
    final remaining = total - _tracks.length;
    return remaining > 0
        ? 'Load more playlist tracks ($remaining remaining)'
        : 'Load more playlist tracks';
  }
}

final class _SpotifyPlaylistErrorTile extends StatelessWidget {
  const _SpotifyPlaylistErrorTile({
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
