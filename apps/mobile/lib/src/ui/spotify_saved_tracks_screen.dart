import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/spotify_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// Browses an authorized Spotify library without exposing Spotify playback.
final class SpotifySavedTracksScreen extends StatefulWidget {
  const SpotifySavedTracksScreen({
    super.key,
    required this.provider,
    this.topTracks = false,
  });

  final SpotifyMetadataProvider provider;
  final bool topTracks;

  @override
  State<SpotifySavedTracksScreen> createState() =>
      _SpotifySavedTracksScreenState();
}

final class _SpotifySavedTracksScreenState
    extends State<SpotifySavedTracksScreen> {
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
      appBar: AppBar(
        title: Text(widget.topTracks ? 'Spotify top tracks' : 'Spotify saved tracks'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (offlineModeEnabled && _tracks.isEmpty)
            ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Offline mode is on'),
              subtitle: Text(
                widget.topTracks
                    ? 'Turn it off to load your top Spotify tracks.'
                    : 'Turn it off to load saved Spotify tracks.',
              ),
            ),
          if (_loading && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _tracks.isEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(
                widget.topTracks
                    ? 'Could not load top tracks'
                    : 'Could not load saved tracks',
              ),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: widget.topTracks ? 'Retry top tracks' : 'Retry saved tracks',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!_loading && _error == null && _tracks.isEmpty && !offlineModeEnabled)
            ListTile(
              leading: const Icon(Icons.library_music_outlined),
              title: Text(
                widget.topTracks ? 'No top tracks found' : 'No saved tracks found',
              ),
            ),
          for (final track in _tracks)
            ListTile(
              leading: TrackArtwork(artworkUri: track.artworkUri),
              title: Text(track.title),
              subtitle: Text(_subtitle(track)),
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
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(
                widget.topTracks
                    ? 'Could not load more top tracks'
                    : 'Could not load more saved tracks',
              ),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: widget.topTracks
                    ? 'Retry top tracks page'
                    : 'Retry saved track page',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.refresh),
              ),
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
                'All $_total saved tracks loaded.',
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
    final requestedOffset = reset ? 0 : _nextOffset;
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
      final page = widget.topTracks
          ? await widget.provider.loadTopTracksPage(offset: requestedOffset)
          : await widget.provider.loadSavedTracksPage(offset: requestedOffset);
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
      return widget.topTracks ? 'Load more top tracks' : 'Load more saved tracks';
    }
    final remaining = total - _tracks.length;
    return remaining > 0
        ? widget.topTracks
            ? 'Load more top tracks ($remaining remaining)'
            : 'Load more saved tracks ($remaining remaining)'
        : widget.topTracks
            ? 'Load more top tracks'
            : 'Load more saved tracks';
  }

  String _subtitle(Track track) {
    final parts = <String>[track.artist, track.album]
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);
    return parts.join(' - ');
  }
}
