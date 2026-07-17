import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/youtube_data_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// Official YouTube Music-category chart metadata. It never opens playback.
final class YouTubeMusicChartScreen extends StatefulWidget {
  const YouTubeMusicChartScreen({super.key, required this.provider});

  final YouTubeDataMetadataProvider provider;

  @override
  State<YouTubeMusicChartScreen> createState() =>
      _YouTubeMusicChartScreenState();
}

final class _YouTubeMusicChartScreenState
    extends State<YouTubeMusicChartScreen> {
  final _regionController = TextEditingController(text: 'US');
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
  void dispose() {
    _regionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offlineModeEnabled = library.offlineModeEnabled;
    final hasMore = _nextCursor != null;
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube music chart')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 104,
                child: TextField(
                  key: const Key('youtube-chart-region'),
                  controller: _regionController,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Region',
                    counterText: '',
                  ),
                  onSubmitted: (_) => unawaited(_load(reset: true)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh music chart',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (offlineModeEnabled && _tracks.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load the music chart.'),
            ),
          if (_loading && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _tracks.isEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load the music chart'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry music chart',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!_loading && _error == null && _tracks.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.ondemand_video_outlined),
              title: Text('No music chart videos found'),
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
              title: const Text('Could not load more chart results'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry music chart page',
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
                'All $_total chart results loaded.',
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
        _loading = false;
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
      final page = await widget.provider.loadPopularMusicPage(
        regionCode: _regionController.text,
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
      return 'Load more chart results';
    }
    final remaining = total - _tracks.length;
    return remaining > 0
        ? 'Load more chart results ($remaining remaining)'
        : 'Load more chart results';
  }
}
