import 'package:flutter/material.dart';

import '../../data/musicbrainz_metadata_provider.dart';
import '../../domain/track.dart';

Future<MusicBrainzMetadataCandidate?> showMusicBrainzMetadataSearchSheet(
  BuildContext context, {
  required Track track,
  required MusicBrainzMetadataProvider provider,
  required bool offlineModeEnabled,
}) {
  return showModalBottomSheet<MusicBrainzMetadataCandidate>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => MusicBrainzMetadataSearchSheet(
      track: track,
      provider: provider,
      offlineModeEnabled: offlineModeEnabled,
    ),
  );
}

class MusicBrainzMetadataSearchSheet extends StatefulWidget {
  const MusicBrainzMetadataSearchSheet({
    required this.track,
    required this.provider,
    required this.offlineModeEnabled,
    super.key,
  });

  final Track track;
  final MusicBrainzMetadataProvider provider;
  final bool offlineModeEnabled;

  @override
  State<MusicBrainzMetadataSearchSheet> createState() =>
      _MusicBrainzMetadataSearchSheetState();
}

class _MusicBrainzMetadataSearchSheetState
    extends State<MusicBrainzMetadataSearchSheet> {
  List<MusicBrainzMetadataCandidate> _results =
      const <MusicBrainzMetadataCandidate>[];
  Object? _error;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.manage_search_outlined),
              title: const Text('Find metadata'),
              trailing: IconButton(
                tooltip: 'Close metadata search',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                widget.offlineModeEnabled
                    ? 'Offline mode is on. No MusicBrainz request can be made.'
                    : 'Searches musicbrainz.org with this track\'s title, artist, and album. Audio files and library paths are never sent. Review a result before it fills the editor.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('musicbrainz-metadata-search'),
                  onPressed: widget.offlineModeEnabled || _loading
                      ? null
                      : _search,
                  icon: const Icon(Icons.search),
                  label: const Text('Search MusicBrainz'),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _buildResults(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          key: Key('musicbrainz-metadata-loading'),
        ),
      );
    }
    if (_error != null) {
      return _MetadataSearchMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Metadata search failed',
        message: 'Try again when your connection is available.',
        actionLabel: 'Retry',
        onAction: _search,
      );
    }
    if (_results.isEmpty) {
      return _MetadataSearchMessage(
        icon: Icons.manage_search_outlined,
        title: 'Ready to search',
        message: 'Search only when the displayed metadata describes this track.',
        actionLabel: 'Search MusicBrainz',
        onAction: widget.offlineModeEnabled ? null : _search,
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = _results[index];
        return ListTile(
          key: Key('musicbrainz-metadata-result-${result.recordingId}'),
          leading: const Icon(Icons.library_music_outlined),
          title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            _subtitle(result),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pop(result),
        );
      },
    );
  }

  Future<void> _search() async {
    if (widget.offlineModeEnabled) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await widget.provider.search(
        title: widget.track.title,
        artist: widget.track.artist,
        album: widget.track.album,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _results = results;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }
}

class _MetadataSearchMessage extends StatelessWidget {
  const _MetadataSearchMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

String _subtitle(MusicBrainzMetadataCandidate result) {
  return <String>[
    result.artist,
    result.album,
    if (result.genre.isNotEmpty) result.genre,
    if (result.duration > Duration.zero) _formatDuration(result.duration),
    if (result.score > 0) 'Match ${result.score}',
  ].join(' - ');
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
