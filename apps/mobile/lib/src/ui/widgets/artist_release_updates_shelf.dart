import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/library_store.dart';
import '../../data/musicbrainz_artist_release_provider.dart';
import 'desktop_background_work_policy.dart';

typedef ArtistReleaseDetailsOpener = Future<bool> Function(Uri uri);

/// A metadata-only release shelf for locally followed artists.
///
/// No request is sent when the shelf is first shown. On desktop only, an
/// explicitly enabled tray preference can refresh the shelf at most daily
/// while the resident process remains hidden or minimized.
final class ArtistReleaseUpdatesShelf extends StatefulWidget {
  ArtistReleaseUpdatesShelf({
    required this.provider,
    this.openDetails = _openMusicBrainzDetails,
    TargetPlatform? platform,
    super.key,
  }) : platform = platform ?? defaultTargetPlatform;

  final MusicBrainzArtistReleaseProvider provider;
  final ArtistReleaseDetailsOpener openDetails;
  final TargetPlatform platform;

  @override
  State<ArtistReleaseUpdatesShelf> createState() =>
      _ArtistReleaseUpdatesShelfState();
}

final class _ArtistReleaseUpdatesShelfState
    extends State<ArtistReleaseUpdatesShelf> with WidgetsBindingObserver {
  static const _automaticRefreshInterval = Duration(days: 1);
  static const _automaticRefreshCheckInterval = Duration(minutes: 15);

  MusicBrainzArtistReleaseFeed? _feed;
  bool _loading = false;
  int _requestSerial = 0;
  Timer? _automaticRefreshTimer;
  AppLifecycleState? _lifecycleState;
  DateTime? _lastAutomaticRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _automaticRefreshTimer = Timer.periodic(
      _automaticRefreshCheckInterval,
      (_) => _refreshAutomaticallyIfDue(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _automaticRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _refreshAutomaticallyIfDue();
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final offline = library.offlineModeEnabled;
    final feed = _feed;
    return Column(
      children: <Widget>[
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.new_releases_outlined),
          title: const Text('Recent releases from artists you follow'),
          subtitle: const Text(
            'Refresh sends up to four followed artist names to musicbrainz.org',
          ),
          trailing: IconButton.filled(
            key: const Key('home-artist-releases-refresh'),
            tooltip: 'Refresh artist release updates',
            onPressed: _loading || offline ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
        ),
        if (offline && feed == null)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Offline mode'),
          ),
        if (_loading && feed == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (feed?.hasCompleteFailure == true)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: const Text('Artist release updates are unavailable'),
            trailing: IconButton(
              tooltip: 'Retry artist release updates',
              onPressed: _loading || offline
                  ? null
                  : () => unawaited(_refresh()),
              icon: const Icon(Icons.refresh),
            ),
          ),
        if (feed != null && !feed.hasCompleteFailure && feed.releases.isEmpty)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_note_outlined),
            title: Text('No dated album, EP, or single updates found'),
          ),
        for (final release
            in feed?.releases ?? const <MusicBrainzArtistRelease>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.album_outlined),
            title: Text(release.title),
            subtitle: Text(
              '${release.artistName} - ${release.primaryType} - ${release.firstReleaseDate}',
            ),
            onTap: () => unawaited(_showReleaseDetails(release)),
          ),
        if (feed != null &&
            !feed.hasCompleteFailure &&
            feed.failedArtistCount > 0)
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('Some followed artists could not be refreshed'),
          ),
        if (_loading && feed != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Future<void> _refresh() async {
    final library = context.read<LibraryStore>();
    if (_loading || library.offlineModeEnabled) {
      return;
    }
    final request = ++_requestSerial;
    setState(() => _loading = true);
    final feed = await widget.provider.loadFollowedArtistReleases(
      artistNames: library.followedArtists,
    );
    if (!mounted || request != _requestSerial) {
      return;
    }
    setState(() {
      _feed = feed;
      _loading = false;
    });
  }

  void _refreshAutomaticallyIfDue() {
    final lifecycleState = _lifecycleState;
    if (!mounted ||
        lifecycleState == null ||
        !shouldKeepBackgroundWorkInDesktopProcess(
          platform: widget.platform,
          state: lifecycleState,
        )) {
      return;
    }
    final library = context.read<LibraryStore>();
    if (!library.desktopArtistReleaseRefreshEnabled ||
        library.offlineModeEnabled ||
        _loading ||
        library.followedArtists.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final lastRefresh = _lastAutomaticRefreshAt;
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _automaticRefreshInterval) {
      return;
    }
    _lastAutomaticRefreshAt = now;
    unawaited(_refresh());
  }

  Future<void> _showReleaseDetails(MusicBrainzArtistRelease release) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                release.title,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(release.artistName),
              Text('${release.primaryType} - ${release.firstReleaseDate}'),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () =>
                      unawaited(_openDetails(sheetContext, release)),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open MusicBrainz'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetails(
    BuildContext sheetContext,
    MusicBrainzArtistRelease release,
  ) async {
    final opened = await widget.openDetails(release.detailsUri);
    if (!sheetContext.mounted) {
      return;
    }
    if (opened) {
      Navigator.of(sheetContext).pop();
      return;
    }
    ScaffoldMessenger.of(sheetContext).showSnackBar(
      const SnackBar(content: Text('Could not open MusicBrainz.')),
    );
  }
}

Future<bool> _openMusicBrainzDetails(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
