import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/youtube_account_following_feed.dart';
import '../data/youtube_account_provider.dart';
import '../data/youtube_followed_channel_feed.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// An ephemeral, explicitly refreshed feed for account subscription metadata.
final class YouTubeAccountFollowingFeedScreen extends StatefulWidget {
  const YouTubeAccountFollowingFeedScreen({super.key, required this.provider});

  final YouTubeAccountProvider provider;

  @override
  State<YouTubeAccountFollowingFeedScreen> createState() =>
      _YouTubeAccountFollowingFeedScreenState();
}

final class _YouTubeAccountFollowingFeedScreenState
    extends State<YouTubeAccountFollowingFeedScreen> {
  List<YouTubeFollowedChannelFeedItem> _items =
      const <YouTubeFollowedChannelFeedItem>[];
  bool _refreshing = false;
  int? _failedChannelCount;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offlineModeEnabled = library.offlineModeEnabled;
    final canRefresh = !_refreshing && !offlineModeEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Account subscription feed')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Refresh manually to read recent metadata from up to 12 connected-account subscriptions. Results stay on this screen, do not change subscriptions, and never enable playback or downloads.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canRefresh ? () => unawaited(_refresh()) : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh account subscriptions'),
          ),
          if (offlineModeEnabled)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to refresh account subscriptions.'),
              ),
            ),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Could not refresh account subscriptions'),
                subtitle: Text(_error!),
              ),
            ),
          if (_failedChannelCount != null && _failedChannelCount! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(
                  '$_failedChannelCount subscription channel(s) could not refresh',
                ),
                subtitle: const Text(
                  'Other account subscription results are still shown.',
                ),
              ),
            ),
          if (_failedChannelCount != null &&
              !_refreshing &&
              _error == null &&
              _items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.ondemand_video_outlined),
                title: Text('No recent account subscription videos found'),
              ),
            ),
          for (final item in _items)
            ListTile(
              leading: TrackArtwork(artworkUri: item.track.artworkUri),
              title: Text(item.track.title),
              subtitle: Text(item.subtitle),
              trailing: IconButton(
                tooltip:
                    library.tracks.any((saved) => saved.id == item.track.id)
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
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    if (_refreshing || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    setState(() {
      _refreshing = true;
      _error = null;
      _failedChannelCount = null;
    });
    try {
      final feed = await loadYouTubeAccountFollowingFeed(widget.provider);
      if (!mounted) {
        return;
      }
      setState(() {
        _items = feed.items;
        _failedChannelCount = feed.failedChannelCount;
        _refreshing = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _refreshing = false;
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
}
