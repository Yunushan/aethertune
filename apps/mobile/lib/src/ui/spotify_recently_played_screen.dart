import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/spotify_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// Browses authorized Spotify play history without exposing Spotify playback.
final class SpotifyRecentlyPlayedScreen extends StatefulWidget {
  const SpotifyRecentlyPlayedScreen({super.key, required this.provider});

  final SpotifyMetadataProvider provider;

  @override
  State<SpotifyRecentlyPlayedScreen> createState() =>
      _SpotifyRecentlyPlayedScreenState();
}

final class _SpotifyRecentlyPlayedScreenState
    extends State<SpotifyRecentlyPlayedScreen> {
  List<SpotifyRecentlyPlayedItem> _items =
      const <SpotifyRecentlyPlayedItem>[];
  String? _nextBefore;
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
      appBar: AppBar(title: const Text('Spotify recently played')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (offlineModeEnabled && _items.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load recently played Spotify tracks.'),
            ),
          if (_loading && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _items.isEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load recently played tracks'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry recently played tracks',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!_loading && _error == null && _items.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.history_outlined),
              title: Text('No recently played tracks found'),
            ),
          for (final item in _items)
            ListTile(
              leading: TrackArtwork(artworkUri: item.track.artworkUri),
              title: Text(item.track.title),
              subtitle: Text(_subtitle(context, item)),
              trailing: IconButton(
                tooltip: library.tracks.any(
                  (saved) => saved.id == item.track.id,
                )
                    ? 'Saved to library'
                    : 'Save metadata to library',
                onPressed: () => unawaited(_saveTrack(item.track)),
                icon: Icon(
                  library.tracks.any((saved) => saved.id == item.track.id)
                      ? Icons.bookmark
                      : Icons.bookmark_add_outlined,
                ),
              ),
            ),
          if (_loading && _items.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null && _items.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load more recently played tracks'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry recently played page',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (_items.isNotEmpty && _hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load older tracks'),
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
    final before = reset ? null : _nextBefore;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items = const <SpotifyRecentlyPlayedItem>[];
        _nextBefore = null;
        _hasMore = false;
      }
    });
    try {
      final page = await widget.provider.loadRecentlyPlayedPage(before: before);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = reset ? page.items : _mergeItems(_items, page.items);
        _nextBefore = page.nextBefore;
        _hasMore = page.hasMore && page.items.isNotEmpty;
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

  List<SpotifyRecentlyPlayedItem> _mergeItems(
    List<SpotifyRecentlyPlayedItem> current,
    List<SpotifyRecentlyPlayedItem> incoming,
  ) {
    final identities = current.map(_identity).toSet();
    return <SpotifyRecentlyPlayedItem>[
      ...current,
      for (final item in incoming)
        if (identities.add(_identity(item))) item,
    ];
  }

  String _identity(SpotifyRecentlyPlayedItem item) =>
      '${item.track.id}|${item.playedAt.microsecondsSinceEpoch}';

  String _subtitle(BuildContext context, SpotifyRecentlyPlayedItem item) {
    final date = item.playedAt.toLocal();
    final dateLabel = MaterialLocalizations.of(context).formatMediumDate(date);
    final timeLabel = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(date));
    return '${item.track.artist} - ${item.track.album} - Played $dateLabel, $timeLabel';
  }
}
