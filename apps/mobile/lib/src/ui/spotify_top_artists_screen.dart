import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/spotify_metadata_provider.dart';
import 'widgets/track_artwork.dart';

final class SpotifyTopArtistsScreen extends StatefulWidget {
  const SpotifyTopArtistsScreen({
    super.key,
    required this.provider,
    this.followedArtists = false,
  });

  final SpotifyMetadataProvider provider;
  final bool followedArtists;

  @override
  State<SpotifyTopArtistsScreen> createState() => _SpotifyTopArtistsScreenState();
}

final class _SpotifyTopArtistsScreenState extends State<SpotifyTopArtistsScreen> {
  List<SpotifyTopArtist> _artists = const <SpotifyTopArtist>[];
  SpotifyTopTracksTimeRange _range = SpotifyTopTracksTimeRange.mediumTerm;
  bool _loading = false;
  String? _error;
  int _requestSerial = 0;
  String? _nextAfter;
  int? _total;
  bool _hasMore = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!widget.followedArtists) ...<Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final range in SpotifyTopTracksTimeRange.values)
                  ChoiceChip(
                    label: Text(_rangeLabel(range)),
                    selected: _range == range,
                    onSelected: offline ? null : (_) => _selectRange(range),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (offline && _artists.isEmpty)
            ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: const Text('Offline mode is on'),
              subtitle: Text('Turn it off to load $_description.'),
            ),
          if (_loading && _artists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _artists.isEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text('Could not load $_description'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry $_description',
                onPressed: offline ? null : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!_loading && _error == null && _artists.isEmpty && !offline)
            ListTile(
              leading: const Icon(Icons.person_search_outlined),
              title: Text('No $_description found'),
            ),
          for (final artist in _artists)
            ListTile(
              leading: TrackArtwork(artworkUri: artist.artworkUri),
              title: Text(artist.name),
              trailing: IconButton(
                tooltip: library.isArtistFollowed(artist.name)
                    ? 'Unfollow local artist'
                    : 'Follow local artist',
                onPressed: () => unawaited(_setFollowed(artist, library)),
                icon: Icon(
                  library.isArtistFollowed(artist.name)
                      ? Icons.person_remove_outlined
                      : Icons.person_add_alt_1_outlined,
                ),
              ),
            ),
          if (_loading && _artists.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (widget.followedArtists && _artists.isNotEmpty && _hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading || offline
                    ? null
                    : () => unawaited(_load()),
                icon: const Icon(Icons.expand_more),
                label: Text(_loadMoreLabel),
              ),
            )
          else if (widget.followedArtists && _artists.isNotEmpty && _total != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'All $_total $_description loaded.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading ||
        context.read<LibraryStore>().offlineModeEnabled ||
        (widget.followedArtists && _loaded && !reset && !_hasMore)) {
      return;
    }
    final request = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
      if (reset && widget.followedArtists) {
        _artists = const <SpotifyTopArtist>[];
        _nextAfter = null;
        _total = null;
        _hasMore = false;
        _loaded = false;
      }
    });
    try {
      if (widget.followedArtists) {
        final page = await widget.provider.loadFollowedArtistsPage(
          after: reset ? null : _nextAfter,
        );
        if (!mounted || request != _requestSerial) return;
        setState(() {
          _artists = reset ? page.artists : _mergeArtists(_artists, page.artists);
          _nextAfter = page.nextAfter;
          _total = page.total;
          _hasMore = page.hasMore && page.artists.isNotEmpty;
          _loaded = true;
          _loading = false;
        });
        return;
      }
      final artists = await widget.provider.loadTopArtists(timeRange: _range);
      if (!mounted || request != _requestSerial) return;
      setState(() {
        _artists = artists;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || request != _requestSerial) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _selectRange(SpotifyTopTracksTimeRange range) {
    if (_range == range) return;
    _requestSerial += 1;
    setState(() {
      _range = range;
      _loading = false;
      _error = null;
    });
    unawaited(_load(reset: true));
  }

  List<SpotifyTopArtist> _mergeArtists(
    List<SpotifyTopArtist> current,
    List<SpotifyTopArtist> incoming,
  ) {
    final ids = current.map((artist) => artist.id).toSet();
    return <SpotifyTopArtist>[
      ...current,
      for (final artist in incoming)
        if (ids.add(artist.id)) artist,
    ];
  }

  String get _description =>
      widget.followedArtists ? 'followed artists' : 'top artists';
  String get _title =>
      widget.followedArtists ? 'Spotify followed artists' : 'Spotify top artists';
  String get _loadMoreLabel {
    final total = _total;
    if (total == null) return 'Load more $_description';
    final remaining = total - _artists.length;
    return remaining > 0
        ? 'Load more $_description ($remaining remaining)'
        : 'Load more $_description';
  }

  String _rangeLabel(SpotifyTopTracksTimeRange range) => switch (range) {
    SpotifyTopTracksTimeRange.shortTerm => '4 weeks',
    SpotifyTopTracksTimeRange.mediumTerm => '6 months',
    SpotifyTopTracksTimeRange.longTerm => '1 year',
  };

  Future<void> _setFollowed(
    SpotifyTopArtist artist,
    LibraryStore library,
  ) async {
    final followed = !library.isArtistFollowed(artist.name);
    await library.setArtistFollowed(artist.name, followed);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          followed
              ? '${artist.name} followed in your local library.'
              : '${artist.name} removed from local follows.',
        ),
      ),
    );
  }
}
