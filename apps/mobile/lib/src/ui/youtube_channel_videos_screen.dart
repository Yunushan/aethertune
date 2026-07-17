import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/youtube_data_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// A public, date-ordered metadata shelf for a discovered YouTube channel.
///
/// It intentionally does not show a video player or resolve audiovisual media.
final class YouTubeChannelVideosScreen extends StatefulWidget {
  const YouTubeChannelVideosScreen({
    super.key,
    required this.provider,
    required this.channel,
  });

  final YouTubeDataMetadataProvider provider;
  final YouTubeDataChannel channel;

  @override
  State<YouTubeChannelVideosScreen> createState() =>
      _YouTubeChannelVideosScreenState();
}

final class _YouTubeChannelVideosScreenState
    extends State<YouTubeChannelVideosScreen> {
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
      appBar: AppBar(title: Text(widget.channel.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Recent public video metadata',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Metadata only. Saving an entry does not make it playable or download it.',
          ),
          if (offlineModeEnabled && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to load public channel videos.'),
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
              title: const Text('Could not load public channel videos'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry public channel videos',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!_loading && _error == null && _tracks.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.ondemand_video_outlined),
              title: Text('No public videos found'),
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
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load more public channel videos'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry public channel video page',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.refresh),
              ),
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
                'All loaded public channel videos are shown.',
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
      final page = await widget.provider.loadChannelVideosPage(
        widget.channel.id,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _tracks = reset ? page.tracks : _mergeTracks(_tracks, page.tracks);
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
      return 'Load more public channel videos';
    }
    final remaining = total - _tracks.length;
    return remaining > 0
        ? 'Load more public channel videos ($remaining remaining)'
        : 'Load more public channel videos';
  }
}
