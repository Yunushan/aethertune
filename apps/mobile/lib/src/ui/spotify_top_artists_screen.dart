import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/spotify_metadata_provider.dart';
import 'widgets/track_artwork.dart';

final class SpotifyTopArtistsScreen extends StatefulWidget {
  const SpotifyTopArtistsScreen({super.key, required this.provider});

  final SpotifyMetadataProvider provider;

  @override
  State<SpotifyTopArtistsScreen> createState() => _SpotifyTopArtistsScreenState();
}

final class _SpotifyTopArtistsScreenState extends State<SpotifyTopArtistsScreen> {
  List<SpotifyTopArtist> _artists = const <SpotifyTopArtist>[];
  SpotifyTopTracksTimeRange _range = SpotifyTopTracksTimeRange.mediumTerm;
  bool _loading = false;
  String? _error;
  int _requestSerial = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Spotify top artists')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
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
          if (offline && _artists.isEmpty)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load your top Spotify artists.'),
            ),
          if (_loading && _artists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _artists.isEmpty)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Could not load top artists'),
              subtitle: Text(_error!),
              trailing: IconButton(
                tooltip: 'Retry top artists',
                onPressed: offline ? null : () => unawaited(_load()),
                icon: const Icon(Icons.refresh),
              ),
            ),
          if (!_loading && _error == null && _artists.isEmpty && !offline)
            const ListTile(
              leading: Icon(Icons.person_search_outlined),
              title: Text('No top artists found'),
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
        ],
      ),
    );
  }

  Future<void> _load() async {
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final request = ++_requestSerial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
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
    unawaited(_load());
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
