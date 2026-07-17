import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/youtube_channel_follow_store.dart';
import '../data/youtube_data_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// An explicitly refreshed, metadata-only feed for locally followed channels.
///
/// A refresh issues one bounded official request for each followed public
/// channel. It is intentionally not a background subscription service.
final class YouTubeFollowedChannelFeedScreen extends StatefulWidget {
  const YouTubeFollowedChannelFeedScreen({
    super.key,
    required this.provider,
  });

  final YouTubeDataMetadataProvider provider;

  @override
  State<YouTubeFollowedChannelFeedScreen> createState() =>
      _YouTubeFollowedChannelFeedScreenState();
}

final class _YouTubeFollowedChannelFeedScreenState
    extends State<YouTubeFollowedChannelFeedScreen> {
  List<_FollowedChannelFeedItem> _items = const <_FollowedChannelFeedItem>[];
  bool _loading = false;
  bool _refreshed = false;
  int _failedChannels = 0;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final follows = context.watch<YouTubeChannelFollowStore>();
    final offlineModeEnabled = library.offlineModeEnabled;
    final canRefresh =
        follows.loaded && follows.follows.isNotEmpty && !_loading && !offlineModeEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('Followed YouTube channels')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Refresh manually to request recent public metadata from each channel you follow. This is not a YouTube account feed and does not enable playback or downloads.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: canRefresh ? () => unawaited(_refresh()) : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh followed channels'),
          ),
          if (!follows.loaded)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            )
          else if (follows.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Could not load followed channels'),
                subtitle: Text(follows.loadError!),
              ),
            )
          else if (follows.follows.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.person_search_outlined),
                title: Text('No public channels followed'),
              ),
            ),
          if (offlineModeEnabled && follows.follows.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to refresh followed channels.'),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_refreshed && !_loading && _items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.ondemand_video_outlined),
                title: Text('No recent public videos found'),
              ),
            ),
          if (_failedChannels > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text('$_failedChannels followed channel(s) could not refresh'),
                subtitle: const Text('Other public channel results are still shown.'),
              ),
            ),
          for (final item in _items)
            ListTile(
              leading: TrackArtwork(artworkUri: item.track.artworkUri),
              title: Text(item.track.title),
              subtitle: Text(item.subtitle),
              trailing: IconButton(
                tooltip: library.tracks.any((saved) => saved.id == item.track.id)
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
    if (_loading || context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final follows = context.read<YouTubeChannelFollowStore>();
    if (!follows.loaded || follows.follows.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _failedChannels = 0;
    });
    final responses = await Future.wait<_ChannelFeedResponse>(
      follows.follows.map((follow) async {
        try {
          final page = await widget.provider.loadChannelVideosPage(
            follow.id,
            limit: 5,
          );
          return _ChannelFeedResponse.success(
            channelTitle: follow.title,
            videos: page.videos,
          );
        } on Object {
          return const _ChannelFeedResponse.failure();
        }
      }),
    );
    if (!mounted) {
      return;
    }
    final seenTrackIds = <String>{};
    final items = <_FollowedChannelFeedItem>[
      for (final response in responses)
        if (response.videos != null)
          for (final video in response.videos!)
            if (seenTrackIds.add(video.track.id))
              _FollowedChannelFeedItem(
                track: video.track,
                channelTitle: response.channelTitle!,
                publishedAt: video.publishedAt,
              ),
    ]..sort(_compareFeedItems);
    setState(() {
      _items = List<_FollowedChannelFeedItem>.unmodifiable(items);
      _failedChannels = responses.where((response) => response.videos == null).length;
      _loading = false;
      _refreshed = true;
    });
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

final class _ChannelFeedResponse {
  const _ChannelFeedResponse.success({
    required this.channelTitle,
    required this.videos,
  });

  const _ChannelFeedResponse.failure()
    : channelTitle = null,
      videos = null;

  final String? channelTitle;
  final List<YouTubeDataChannelVideo>? videos;
}

final class _FollowedChannelFeedItem {
  const _FollowedChannelFeedItem({
    required this.track,
    required this.channelTitle,
    required this.publishedAt,
  });

  final Track track;
  final String channelTitle;
  final DateTime? publishedAt;

  String get subtitle {
    final date = publishedAt?.toIso8601String().split('T').first;
    return date == null ? channelTitle : '$channelTitle · $date';
  }
}

int _compareFeedItems(
  _FollowedChannelFeedItem first,
  _FollowedChannelFeedItem second,
) {
  final firstTime = first.publishedAt;
  final secondTime = second.publishedAt;
  if (firstTime == null && secondTime == null) {
    return first.track.title.toLowerCase().compareTo(second.track.title.toLowerCase());
  }
  if (firstTime == null) {
    return 1;
  }
  if (secondTime == null) {
    return -1;
  }
  final byTime = secondTime.compareTo(firstTime);
  return byTime != 0
      ? byTime
      : first.track.title.toLowerCase().compareTo(second.track.title.toLowerCase());
}
