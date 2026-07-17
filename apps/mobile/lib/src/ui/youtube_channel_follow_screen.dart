import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/youtube_channel_follow_store.dart';
import '../data/youtube_data_metadata_provider.dart';
import 'widgets/track_artwork.dart';

/// Public YouTube channel discovery with device-local follows.
///
/// The screen never reads or changes the user's YouTube subscriptions and does
/// not provide video playback, downloads, or a remote activity feed.
final class YouTubeChannelFollowScreen extends StatefulWidget {
  const YouTubeChannelFollowScreen({super.key, required this.provider});

  final YouTubeDataMetadataProvider provider;

  @override
  State<YouTubeChannelFollowScreen> createState() =>
      _YouTubeChannelFollowScreenState();
}

final class _YouTubeChannelFollowScreenState
    extends State<YouTubeChannelFollowScreen> {
  final _queryController = TextEditingController();
  List<YouTubeDataChannel> _channels = const <YouTubeDataChannel>[];
  String? _nextCursor;
  int? _total;
  bool _loading = false;
  String? _error;
  String? _query;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final follows = context.watch<YouTubeChannelFollowStore>();
    final offlineModeEnabled = library.offlineModeEnabled;
    final hasSearch = (_query ?? '').isNotEmpty;
    final hasMore = _nextCursor != null;
    return Scaffold(
      appBar: AppBar(title: const Text('YouTube channels')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            key: const Key('youtube-channel-search'),
            controller: _queryController,
            autocorrect: false,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Find public channels',
              suffixIcon: IconButton(
                tooltip: 'Search YouTube channels',
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: true)),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => unawaited(_load(reset: true)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Follows stay on this device. They are not YouTube account subscriptions and do not create a remote feed.',
          ),
          if (offlineModeEnabled && !hasSearch)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to search for public channels.'),
              ),
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
          else if (follows.follows.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Followed on this device',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            for (final channel in follows.follows)
              _ChannelTile(
                channel: channel,
                followed: true,
                onFollowChanged: (followed) =>
                    unawaited(
                      follows.setFollowed(_asChannel(channel), followed),
                    ),
              ),
          ],
          if (hasSearch) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Search results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_loading && _channels.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_error != null && _channels.isEmpty)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Could not load public channels'),
                subtitle: Text(_error!),
                trailing: IconButton(
                  tooltip: 'Retry YouTube channel search',
                  onPressed: _loading || offlineModeEnabled
                      ? null
                      : () => unawaited(_load(reset: true)),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            if (!_loading && _error == null && _channels.isEmpty)
              const ListTile(
                leading: Icon(Icons.person_search_outlined),
                title: Text('No public channels found'),
              ),
            for (final channel in _channels)
              _ChannelTile(
                channel: channel,
                followed: follows.isFollowed(channel.id),
                onFollowChanged: (followed) =>
                    unawaited(follows.setFollowed(channel, followed)),
              ),
            if (_loading && _channels.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null && _channels.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('Could not load more public channels'),
                subtitle: Text(_error!),
                trailing: IconButton(
                  tooltip: 'Retry YouTube channel page',
                  onPressed: _loading || offlineModeEnabled
                      ? null
                      : () => unawaited(_load(reset: false)),
                  icon: const Icon(Icons.refresh),
                ),
              ),
            if (_channels.isNotEmpty && hasMore)
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
            else if (_channels.isNotEmpty && _total != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'All loaded channel results are shown.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && _nextCursor == null)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      return;
    }
    final query = reset ? _queryController.text.trim() : _query;
    if (query == null || query.isEmpty) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _query = query;
        _channels = const <YouTubeDataChannel>[];
        _nextCursor = null;
        _total = null;
      }
    });
    try {
      final page = await widget.provider.searchChannelsPage(
        query,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _channels = reset
            ? page.channels
            : _mergeChannels(_channels, page.channels);
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

  List<YouTubeDataChannel> _mergeChannels(
    List<YouTubeDataChannel> current,
    List<YouTubeDataChannel> incoming,
  ) {
    final ids = current.map((channel) => channel.id).toSet();
    return <YouTubeDataChannel>[
      ...current,
      for (final channel in incoming)
        if (ids.add(channel.id)) channel,
    ];
  }

  String get _loadMoreLabel {
    final total = _total;
    if (total == null) {
      return 'Load more channels';
    }
    final remaining = total - _channels.length;
    return remaining > 0
        ? 'Load more channels ($remaining remaining)'
        : 'Load more channels';
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.followed,
    required this.onFollowChanged,
  });

  final YouTubeDataChannel channel;
  final bool followed;
  final ValueChanged<bool> onFollowChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: TrackArtwork(
        artworkUri: channel.thumbnailUri,
        fallbackIcon: Icons.account_circle_outlined,
      ),
      title: Text(channel.title),
      subtitle: channel.description == null || channel.description!.isEmpty
          ? Text(channel.id)
          : Text(
              channel.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      trailing: IconButton(
        tooltip: followed ? 'Unfollow channel' : 'Follow channel',
        onPressed: () => onFollowChanged(!followed),
        icon: Icon(followed ? Icons.bookmark : Icons.bookmark_add_outlined),
      ),
    );
  }
}

YouTubeDataChannel _asChannel(YouTubeChannelFollow follow) =>
    YouTubeDataChannel(
      id: follow.id,
      title: follow.title,
      description: follow.description,
      thumbnailUri: follow.thumbnailUri,
    );
