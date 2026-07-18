import 'package:flutter/material.dart';

import '../../domain/lyrics_provider.dart';
import '../../domain/track.dart';

Future<LyricsSearchResult?> showLyricsSearchSheet(
  BuildContext context, {
  required Track track,
  required LyricsProvider provider,
  bool offlineOnly = false,
}) {
  return showModalBottomSheet<LyricsSearchResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => LyricsSearchSheet(
      track: track,
      provider: provider,
      offlineOnly: offlineOnly,
    ),
  );
}

class LyricsSearchSheet extends StatefulWidget {
  const LyricsSearchSheet({
    required this.track,
    required this.provider,
    this.offlineOnly = false,
    super.key,
  });

  final Track track;
  final LyricsProvider provider;
  final bool offlineOnly;

  @override
  State<LyricsSearchSheet> createState() => _LyricsSearchSheetState();
}

class _LyricsSearchSheetState extends State<LyricsSearchSheet> {
  late final TextEditingController _queryController;
  List<LyricsSearchResult> _results = const <LyricsSearchResult>[];
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: <String>[
        widget.track.title.trim(),
        if (!_isUnknown(widget.track.artist, 'Unknown Artist'))
          widget.track.artist.trim(),
        if (!_isUnknown(widget.track.album, 'Unknown Album'))
          widget.track.album.trim(),
      ].where((value) => value.isNotEmpty).join(' '),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.subtitles_outlined),
              title: Text('Search ${widget.provider.name}'),
              trailing: IconButton(
                tooltip: 'Close lyrics search',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.offlineOnly
                      ? 'Offline mode: cached ${widget.provider.name} results only. No network request is made.'
                      : _privacySummary(widget.provider),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: TextField(
                key: const Key('lyrics-search-query'),
                controller: _queryController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  labelText: 'Track, artist, or album',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Search lyrics',
                    onPressed: _loading ? null : _search,
                    icon: const Icon(Icons.arrow_forward),
                  ),
                  border: const OutlineInputBorder(),
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
          key: Key('lyrics-search-loading'),
        ),
      );
    }
    if (_error != null) {
      return _LyricsSearchMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Lyrics search failed',
        message: _error.toString(),
        actionLabel: 'Retry',
        onAction: _search,
      );
    }
    if (_results.isEmpty) {
      return _LyricsSearchMessage(
        icon: Icons.search_off,
        title: 'No lyrics found',
        message: 'Try a shorter title or include the artist name.',
        actionLabel: 'Search again',
        onAction: _search,
      );
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final result = _results[index];
        return ListTile(
          key: Key('lyrics-result-${result.externalId}'),
          enabled: result.isSelectable,
          leading: Icon(_resultIcon(result)),
          title: Text(
            result.trackName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            _resultSubtitle(result),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: result.isSelectable
              ? const Icon(Icons.chevron_right)
              : const Text('Instrumental'),
          onTap: result.isSelectable
              ? () => Navigator.of(context).pop(result)
              : null,
        );
      },
    );
  }

  Future<void> _search() async {
    final keywords = _queryController.text.trim();
    if (keywords.isEmpty) {
      setState(() {
        _loading = false;
        _results = const <LyricsSearchResult>[];
        _error = 'Enter a track, artist, or album.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = LyricsSearchQuery(
          keywords: keywords,
          trackName: widget.track.title,
          artistName: widget.track.artist,
          albumName: widget.track.album,
          duration: widget.track.duration,
        );
      final results = widget.offlineOnly && widget.provider is OfflineLyricsProvider
          ? await (widget.provider as OfflineLyricsProvider).searchOffline(query)
          : await widget.provider.search(query);
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

class _LyricsSearchMessage extends StatelessWidget {
  const _LyricsSearchMessage({
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
  final VoidCallback onAction;

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

String _privacySummary(LyricsProvider provider) {
  final disclosure = provider.disclosure;
  final domain = disclosure.networkSummary;
  final sent = disclosure.dataSent.isEmpty
      ? 'No track metadata is declared as sent.'
      : 'Sends ${disclosure.dataSent.join(', ')}.';
  return '$domain. $sent A selected result is stored locally with attribution.';
}

String _resultSubtitle(LyricsSearchResult result) {
  final metadata = <String>[
    result.artistName,
    if (result.albumName.trim().isNotEmpty &&
        result.albumName != 'Unknown Album')
      result.albumName,
    if (result.duration > Duration.zero) _formatDuration(result.duration),
    if (result.hasSyncedLyrics)
      'Synced'
    else if (result.hasPlainLyrics)
      'Plain',
    '${result.providerName} #${result.externalId}',
  ];
  return metadata.join(' - ');
}

IconData _resultIcon(LyricsSearchResult result) {
  if (result.hasSyncedLyrics) {
    return Icons.sync;
  }
  if (result.hasPlainLyrics) {
    return Icons.notes;
  }
  return Icons.music_off_outlined;
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

bool _isUnknown(String value, String unknownValue) {
  final normalized = value.trim();
  return normalized.isEmpty ||
      normalized.toLowerCase() == unknownValue.toLowerCase();
}
