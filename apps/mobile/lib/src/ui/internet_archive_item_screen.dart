import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/internet_archive_provider.dart';
import '../data/library_store.dart';
import '../domain/music_source_provider.dart';
import '../domain/track.dart';
import '../player/player_controller.dart';

class InternetArchiveItemScreen extends StatelessWidget {
  const InternetArchiveItemScreen({
    super.key,
    required this.item,
    required this.provider,
  });

  final InternetArchiveItem item;
  final InternetArchiveProvider provider;

  List<Track> get _tracks =>
      item.toTracks(sourceId: provider.id, baseUri: provider.baseUri);

  @override
  Widget build(BuildContext context) {
    final tracks = _tracks;
    final offlineModeEnabled = context.watch<LibraryStore>().offlineModeEnabled;

    return Scaffold(
      appBar: AppBar(title: const Text('Archive item')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
          if (item.creator.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(item.creator, style: Theme.of(context).textTheme.titleMedium),
          ],
          if (item.year.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(item.year),
          ],
          if (item.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(item.description),
          ],
          if (item.collections.isNotEmpty ||
              item.subjects.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ...item.collections.map(
                  (collection) => Chip(
                    avatar: const Icon(Icons.collections_bookmark_outlined),
                    label: Text(collection),
                  ),
                ),
                ...item.subjects.map(
                  (subject) => Chip(
                    avatar: const Icon(Icons.sell_outlined),
                    label: Text(subject),
                  ),
                ),
              ],
            ),
          ],
          if (item.licenseUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text('License: ${item.licenseUrl}'),
          ],
          const SizedBox(height: 20),
          Text(
            'Playable files',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (offlineModeEnabled)
            const ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Offline mode is on'),
              subtitle: Text(
                'Archive playback is unavailable until offline mode is turned off.',
              ),
            ),
          if (tracks.isEmpty)
            const ListTile(
              leading: Icon(Icons.audio_file_outlined),
              title: Text('No playable audio files'),
              subtitle: Text(
                'This archive item does not expose a supported audio file.',
              ),
            )
          else ...<Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: offlineModeEnabled
                      ? null
                      : () => _playAll(context, tracks),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play all'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _saveAll(context, tracks),
                  icon: const Icon(Icons.library_add_outlined),
                  label: const Text('Save all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final track in tracks)
              ListTile(
                leading: const Icon(Icons.audio_file_outlined),
                title: Text(track.title),
                subtitle: Text(_trackSubtitle(track)),
                onTap: offlineModeEnabled
                    ? null
                    : () => _playTrack(context, track, tracks),
                trailing: _trackActions(context, track),
              ),
          ],
        ],
      ),
    );
  }

  String _trackSubtitle(Track track) {
    final parts = <String>[track.artist, track.genre];
    if (track.duration > Duration.zero) {
      final minutes = track.duration.inMinutes;
      final seconds = track.duration.inSeconds
          .remainder(60)
          .toString()
          .padLeft(2, '0');
      parts.add('$minutes:$seconds');
    }
    return parts.join(' / ');
  }

  Future<void> _playAll(BuildContext context, List<Track> tracks) {
    return _playTrack(context, tracks.first, tracks);
  }

  Future<void> _playTrack(
    BuildContext context,
    Track track,
    List<Track> tracks,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<PlayerController>().playTrack(track, queue: tracks);
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not play ${track.title}.')),
      );
    }
  }

  Future<void> _saveAll(BuildContext context, List<Track> tracks) async {
    final messenger = ScaffoldMessenger.of(context);
    await context.read<LibraryStore>().addTracks(tracks);
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tracks.length == 1
              ? 'Saved ${tracks.single.title}.'
              : 'Saved ${tracks.length} archive tracks.',
        ),
      ),
    );
  }

  Widget _trackActions(BuildContext context, Track track) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PopupMenuButton<OfflineMediaAction>(
          tooltip: 'Queue offline media',
          icon: const Icon(Icons.download_for_offline_outlined),
          onSelected: (action) =>
              unawaited(_queueOffline(context, track, action)),
          itemBuilder: (_) => const <PopupMenuEntry<OfflineMediaAction>>[
            PopupMenuItem<OfflineMediaAction>(
              value: OfflineMediaAction.cache,
              child: ListTile(
                leading: Icon(Icons.offline_pin_outlined),
                title: Text('Queue cache'),
              ),
            ),
            PopupMenuItem<OfflineMediaAction>(
              value: OfflineMediaAction.download,
              child: ListTile(
                leading: Icon(Icons.download_outlined),
                title: Text('Queue download'),
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: 'Save archive track',
          onPressed: () => _saveAll(context, <Track>[track]),
          icon: const Icon(Icons.library_add_outlined),
        ),
      ],
    );
  }

  Future<void> _queueOffline(
    BuildContext context,
    Track track,
    OfflineMediaAction action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final decision = OfflineMediaPolicy(<MusicSourceProvider>[
      provider,
    ]).evaluate(track, action);
    if (!decision.isAllowed) {
      messenger.showSnackBar(SnackBar(content: Text(decision.reason)));
      return;
    }

    try {
      final entry = await context.read<LibraryStore>().queueOfflineCache(
        track,
        action,
        decision,
      );
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Queued ${entry.track.title} for ${entry.action.label.toLowerCase()}.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not queue ${track.title}: $error')),
      );
    }
  }
}
