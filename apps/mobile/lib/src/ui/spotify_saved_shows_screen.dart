import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/spotify_metadata_provider.dart';
import 'spotify_saved_tracks_screen.dart';
import 'widgets/track_artwork.dart';

/// Browses saved Spotify show metadata and their public episode metadata.
final class SpotifySavedShowsScreen extends StatefulWidget {
  const SpotifySavedShowsScreen({
    super.key,
    required this.provider,
  });

  final SpotifyMetadataProvider provider;

  @override
  State<SpotifySavedShowsScreen> createState() =>
      _SpotifySavedShowsScreenState();
}

final class _SpotifySavedShowsScreenState
    extends State<SpotifySavedShowsScreen> {
  List<SpotifySavedShow> _shows = const <SpotifySavedShow>[];
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
      appBar: AppBar(title: const Text('Spotify saved shows')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (offlineModeEnabled && _shows.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load saved Spotify shows.'),
            ),
          if (_loading && _shows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _shows.isEmpty)
            _SpotifyShowsErrorTile(
              title: 'Could not load saved shows',
              error: _error!,
              tooltip: 'Retry saved shows',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _shows.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.podcasts_outlined),
              title: Text('No saved shows found'),
            ),
          for (final show in _shows)
            ListTile(
              leading: TrackArtwork(artworkUri: show.artworkUri),
              title: Text(show.title),
              subtitle: Text(_subtitle(show)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openShow(show),
            ),
          if (_loading && _shows.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null && _shows.isNotEmpty)
            _SpotifyShowsErrorTile(
              title: 'Could not load more saved shows',
              error: _error!,
              tooltip: 'Retry saved shows page',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: false)),
            ),
          if (_shows.isNotEmpty && _hasMore)
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
          else if (_shows.isNotEmpty && _total != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'All $_total saved shows loaded.',
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
        _shows = const <SpotifySavedShow>[];
        _nextOffset = 0;
        _total = null;
        _hasMore = false;
      }
    });
    try {
      final page = await widget.provider.loadSavedShowsPage(offset: offset);
      if (!mounted) {
        return;
      }
      final shows = reset ? page.shows : _mergeShows(_shows, page.shows);
      setState(() {
        _shows = shows;
        _nextOffset = page.offset + page.shows.length;
        _total = page.total;
        _hasMore = page.hasMore && page.shows.isNotEmpty;
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

  void _openShow(SpotifySavedShow show) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotifySavedTracksScreen(
          provider: widget.provider,
          show: show,
        ),
      ),
    );
  }

  List<SpotifySavedShow> _mergeShows(
    List<SpotifySavedShow> current,
    List<SpotifySavedShow> incoming,
  ) {
    final ids = current.map((show) => show.id).toSet();
    return <SpotifySavedShow>[
      ...current,
      for (final show in incoming)
        if (ids.add(show.id)) show,
    ];
  }

  String get _loadMoreLabel {
    final total = _total;
    if (total == null) {
      return 'Load more saved shows';
    }
    final remaining = total - _shows.length;
    return remaining > 0
        ? 'Load more saved shows ($remaining remaining)'
        : 'Load more saved shows';
  }

  String _subtitle(SpotifySavedShow show) {
    final count = show.totalEpisodes;
    return '${show.publisher} - $count ${count == 1 ? 'episode' : 'episodes'}';
  }
}

final class _SpotifyShowsErrorTile extends StatelessWidget {
  const _SpotifyShowsErrorTile({
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
