import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/library_store.dart';
import '../../data/musicbrainz_artist_release_provider.dart';

typedef ArtistReleaseDetailsOpener = Future<bool> Function(Uri uri);

/// An explicitly refreshed, metadata-only release shelf for locally followed
/// artists. No request is sent when the shelf is first shown.
final class ArtistReleaseUpdatesShelf extends StatefulWidget {
  const ArtistReleaseUpdatesShelf({
    required this.provider,
    this.openDetails = _openMusicBrainzDetails,
    super.key,
  });

  final MusicBrainzArtistReleaseProvider provider;
  final ArtistReleaseDetailsOpener openDetails;

  @override
  State<ArtistReleaseUpdatesShelf> createState() =>
      _ArtistReleaseUpdatesShelfState();
}

final class _ArtistReleaseUpdatesShelfState
    extends State<ArtistReleaseUpdatesShelf> {
  MusicBrainzArtistReleaseFeed? _feed;
  bool _loading = false;
  int _requestSerial = 0;

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
