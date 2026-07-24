import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/library_store.dart';
import '../data/youtube_account_provider.dart';
import '../data/youtube_data_metadata_provider.dart';
import '../domain/track.dart';
import 'widgets/track_artwork.dart';

/// Read-only playlists and subscriptions from a connected YouTube account.
final class YouTubeAccountLibraryScreen extends StatelessWidget {
  const YouTubeAccountLibraryScreen({super.key, required this.provider});

  final YouTubeAccountProvider provider;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('YouTube account library'),
          bottom: const TabBar(
            tabs: <Tab>[
              Tab(icon: Icon(Icons.queue_music_outlined), text: 'Playlists'),
              Tab(icon: Icon(Icons.subscriptions_outlined), text: 'Subscriptions'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _YouTubeAccountPlaylistsTab(provider: provider),
            _YouTubeAccountSubscriptionsTab(provider: provider),
          ],
        ),
      ),
    );
  }
}

final class _YouTubeAccountPlaylistsTab extends StatefulWidget {
  const _YouTubeAccountPlaylistsTab({required this.provider});

  final YouTubeAccountProvider provider;

  @override
  State<_YouTubeAccountPlaylistsTab> createState() =>
      _YouTubeAccountPlaylistsTabState();
}

final class _YouTubeAccountPlaylistsTabState
    extends State<_YouTubeAccountPlaylistsTab> {
  List<YouTubeDataPlaylist> _playlists = const <YouTubeDataPlaylist>[];
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
    final offlineModeEnabled = context.watch<LibraryStore>().offlineModeEnabled;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Read-only account metadata from the official YouTube Data API. This does not enable YouTube audio playback, downloads, or account changes.',
        ),
        if (offlineModeEnabled && _playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load account playlists.'),
            ),
          ),
        if (_loading && _playlists.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null && _playlists.isEmpty)
          _YouTubeAccountErrorTile(
            title: 'Could not load account playlists',
            error: _error!,
            tooltip: 'Retry account playlists',
            enabled: !_loading && !offlineModeEnabled,
            onRetry: () => unawaited(_load(reset: true)),
          ),
        if (!_loading &&
            _error == null &&
            _playlists.isEmpty &&
            !offlineModeEnabled)
          const ListTile(
            leading: Icon(Icons.queue_music_outlined),
            title: Text('No account playlists found'),
          ),
        for (final playlist in _playlists)
          ListTile(
            leading: TrackArtwork(
              artworkUri: playlist.thumbnailUri,
              fallbackIcon: Icons.queue_music_outlined,
            ),
            title: Text(playlist.title),
            subtitle: Text(
              playlist.channelTitle ?? playlist.description ?? playlist.id,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPlaylist(context, playlist),
          ),
        if (_loading && _playlists.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_error != null && _playlists.isNotEmpty)
          _YouTubeAccountErrorTile(
            title: 'Could not load more account playlists',
            error: _error!,
            tooltip: 'Retry account playlist page',
            enabled: !_loading && !offlineModeEnabled,
            onRetry: () => unawaited(_load(reset: false)),
          ),
        if (_playlists.isNotEmpty && _nextCursor != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading || offlineModeEnabled
                  ? null
                  : () => unawaited(_load(reset: false)),
              icon: const Icon(Icons.expand_more),
              label: Text(_loadMoreLabel),
            ),
          ),
      ],
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && _nextCursor == null)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      setState(() => _error = 'Offline mode is on.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _playlists = const <YouTubeDataPlaylist>[];
        _nextCursor = null;
        _total = null;
      }
    });
    try {
      final page = await widget.provider.loadMyPlaylistsPage(
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _playlists = reset
            ? page.playlists
            : _mergePlaylists(_playlists, page.playlists);
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

  void _openPlaylist(BuildContext context, YouTubeDataPlaylist playlist) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubeAccountPlaylistItemsScreen(
          provider: widget.provider,
          playlist: playlist,
        ),
      ),
    );
  }

  String get _loadMoreLabel {
    final remaining = (_total ?? _playlists.length) - _playlists.length;
    return remaining > 0
        ? 'Load more account playlists ($remaining remaining)'
        : 'Load more account playlists';
  }
}

final class _YouTubeAccountSubscriptionsTab extends StatefulWidget {
  const _YouTubeAccountSubscriptionsTab({required this.provider});

  final YouTubeAccountProvider provider;

  @override
  State<_YouTubeAccountSubscriptionsTab> createState() =>
      _YouTubeAccountSubscriptionsTabState();
}

final class _YouTubeAccountSubscriptionsTabState
    extends State<_YouTubeAccountSubscriptionsTab> {
  List<YouTubeDataChannel> _channels = const <YouTubeDataChannel>[];
  String? _nextCursor;
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'Subscriptions are shown as read-only channel metadata. AetherTune does not alter subscriptions.',
        ),
        if (offlineModeEnabled && _channels.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text('Turn it off to load subscriptions.'),
            ),
          ),
        if (_loading && _channels.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_error != null && _channels.isEmpty)
          _YouTubeAccountErrorTile(
            title: 'Could not load subscriptions',
            error: _error!,
            tooltip: 'Retry subscriptions',
            enabled: !_loading && !offlineModeEnabled,
            onRetry: () => unawaited(_load(reset: true)),
          ),
        if (!_loading &&
            _error == null &&
            _channels.isEmpty &&
            !offlineModeEnabled)
          const ListTile(
            leading: Icon(Icons.subscriptions_outlined),
            title: Text('No subscriptions found'),
          ),
        for (final channel in _channels)
          ListTile(
            leading: TrackArtwork(
              artworkUri: channel.thumbnailUri,
              fallbackIcon: Icons.subscriptions_outlined,
            ),
            title: Text(channel.title),
            subtitle: channel.description == null
                ? null
                : Text(
                    channel.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openChannel(context, channel),
          ),
        if (_loading && _channels.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_error != null && _channels.isNotEmpty)
          _YouTubeAccountErrorTile(
            title: 'Could not load more subscriptions',
            error: _error!,
            tooltip: 'Retry subscription page',
            enabled: !_loading && !offlineModeEnabled,
            onRetry: () => unawaited(_load(reset: false)),
          ),
        if (_channels.isNotEmpty && _nextCursor != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading || offlineModeEnabled
                  ? null
                  : () => unawaited(_load(reset: false)),
              icon: const Icon(Icons.expand_more),
              label: const Text('Load more subscriptions'),
            ),
          ),
      ],
    );
  }

  Future<void> _load({required bool reset}) async {
    if (_loading || (!reset && _nextCursor == null)) {
      return;
    }
    if (context.read<LibraryStore>().offlineModeEnabled) {
      setState(() => _error = 'Offline mode is on.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _channels = const <YouTubeDataChannel>[];
        _nextCursor = null;
      }
    });
    try {
      final page = await widget.provider.loadMySubscriptionsPage(
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _channels = reset ? page.channels : _mergeChannels(_channels, page.channels);
        _nextCursor = page.nextPageToken;
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

  void _openChannel(BuildContext context, YouTubeDataChannel channel) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => YouTubeAccountChannelVideosScreen(
          provider: widget.provider,
          channel: channel,
        ),
      ),
    );
  }
}

/// Bounded recent metadata from one subscription channel.
final class YouTubeAccountChannelVideosScreen extends StatefulWidget {
  const YouTubeAccountChannelVideosScreen({
    super.key,
    required this.provider,
    required this.channel,
  });

  final YouTubeAccountProvider provider;
  final YouTubeDataChannel channel;

  @override
  State<YouTubeAccountChannelVideosScreen> createState() =>
      _YouTubeAccountChannelVideosScreenState();
}

final class _YouTubeAccountChannelVideosScreenState
    extends State<YouTubeAccountChannelVideosScreen> {
  List<YouTubeDataChannelVideo> _videos = const <YouTubeDataChannelVideo>[];
  String? _nextCursor;
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
      appBar: AppBar(title: Text(widget.channel.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Recent subscription-channel metadata is read-only. Saving an entry does not enable YouTube playback or downloads.',
          ),
          if (offlineModeEnabled && _videos.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to load channel metadata.'),
              ),
            ),
          if (_loading && _videos.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _videos.isEmpty)
            _YouTubeAccountErrorTile(
              title: 'Could not load subscription channel metadata',
              error: _error!,
              tooltip: 'Retry subscription channel metadata',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _videos.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.video_library_outlined),
              title: Text('No channel videos found'),
            ),
          for (final video in _videos)
            ListTile(
              leading: TrackArtwork(artworkUri: video.track.artworkUri),
              title: Text(video.track.title),
              subtitle: Text(video.track.artist),
              trailing: IconButton(
                tooltip: library.tracks.any(
                  (saved) => saved.id == video.track.id,
                )
                    ? 'Saved to library'
                    : 'Save metadata to library',
                onPressed: () => unawaited(_saveTrack(video.track)),
                icon: Icon(
                  library.tracks.any((saved) => saved.id == video.track.id)
                      ? Icons.bookmark
                      : Icons.bookmark_add_outlined,
                ),
              ),
            ),
          if (_loading && _videos.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null && _videos.isNotEmpty)
            _YouTubeAccountErrorTile(
              title: 'Could not load more subscription channel metadata',
              error: _error!,
              tooltip: 'Retry subscription channel page',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: false)),
            ),
          if (_videos.isNotEmpty && _nextCursor != null)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more channel videos'),
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
      setState(() => _error = 'Offline mode is on.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _videos = const <YouTubeDataChannelVideo>[];
        _nextCursor = null;
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
        _videos = reset ? page.videos : _mergeChannelVideos(_videos, page.videos);
        _nextCursor = page.nextPageToken;
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
}

/// Paged read-only metadata for one playlist owned by the connected account.
final class YouTubeAccountPlaylistItemsScreen extends StatefulWidget {
  const YouTubeAccountPlaylistItemsScreen({
    super.key,
    required this.provider,
    required this.playlist,
  });

  final YouTubeAccountProvider provider;
  final YouTubeDataPlaylist playlist;

  @override
  State<YouTubeAccountPlaylistItemsScreen> createState() =>
      _YouTubeAccountPlaylistItemsScreenState();
}

final class _YouTubeAccountPlaylistItemsScreenState
    extends State<YouTubeAccountPlaylistItemsScreen> {
  List<Track> _tracks = const <Track>[];
  String? _nextCursor;
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
        title: Text(widget.playlist.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Save loaded metadata as local playlist',
            onPressed: _tracks.isEmpty || _loading
                ? null
                : () => unawaited(_saveLoadedTracksAsPlaylist()),
            icon: const Icon(Icons.playlist_add_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'Read-only playlist metadata only. Saving entries does not enable YouTube playback or downloads.',
          ),
          if (offlineModeEnabled && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: ListTile(
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Offline mode is on'),
                subtitle: Text('Turn it off to load account playlist items.'),
              ),
            ),
          if (_loading && _tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null && _tracks.isEmpty)
            _YouTubeAccountErrorTile(
              title: 'Could not load account playlist items',
              error: _error!,
              tooltip: 'Retry account playlist items',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: true)),
            ),
          if (!_loading && _error == null && _tracks.isEmpty && !offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.music_note_outlined),
              title: Text('No account playlist items found'),
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
            _YouTubeAccountErrorTile(
              title: 'Could not load more account playlist items',
              error: _error!,
              tooltip: 'Retry account playlist item page',
              enabled: !_loading && !offlineModeEnabled,
              onRetry: () => unawaited(_load(reset: false)),
            ),
          if (_tracks.isNotEmpty && _nextCursor != null)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading || offlineModeEnabled
                    ? null
                    : () => unawaited(_load(reset: false)),
                icon: const Icon(Icons.expand_more),
                label: const Text('Load more account playlist items'),
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
      setState(() => _error = 'Offline mode is on.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _tracks = const <Track>[];
        _nextCursor = null;
      }
    });
    try {
      final page = await widget.provider.loadPlaylistItemsPage(
        widget.playlist.id,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _tracks = reset ? page.tracks : _mergeTracks(_tracks, page.tracks);
        _nextCursor = page.nextPageToken;
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

  Future<void> _saveLoadedTracksAsPlaylist() async {
    if (_tracks.isEmpty) {
      return;
    }
    final library = context.read<LibraryStore>();
    await library.addTracks(_tracks);
    final playlist = await library.createPlaylist(
      widget.playlist.title,
      trackIds: _tracks.map((track) => track.id).toList(growable: false),
    );
    final orderedPlaylist = await library.replacePlaylistTracks(
      playlist.id,
      _tracks.map((track) => track.id),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved ${orderedPlaylist?.trackIds.length ?? playlist.trackIds.length} loaded items as ${playlist.name}.',
        ),
      ),
    );
  }
}

List<YouTubeDataPlaylist> _mergePlaylists(
  List<YouTubeDataPlaylist> current,
  List<YouTubeDataPlaylist> incoming,
) {
  final ids = current.map((playlist) => playlist.id).toSet();
  return <YouTubeDataPlaylist>[
    ...current,
    for (final playlist in incoming)
      if (ids.add(playlist.id)) playlist,
  ];
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

List<Track> _mergeTracks(List<Track> current, List<Track> incoming) {
  final ids = current.map((track) => track.id).toSet();
  return <Track>[
    ...current,
    for (final track in incoming)
      if (ids.add(track.id)) track,
  ];
}

List<YouTubeDataChannelVideo> _mergeChannelVideos(
  List<YouTubeDataChannelVideo> current,
  List<YouTubeDataChannelVideo> incoming,
) {
  final ids = current.map((video) => video.track.id).toSet();
  return <YouTubeDataChannelVideo>[
    ...current,
    for (final video in incoming)
      if (ids.add(video.track.id)) video,
  ];
}

final class _YouTubeAccountErrorTile extends StatelessWidget {
  const _YouTubeAccountErrorTile({
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
