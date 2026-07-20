import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/library_sync_client.dart';
import '../../data/library_sync_store.dart';
import '../../data/listen_together_store.dart';
import '../../data/shared_playlist_store.dart';
import '../../domain/library_sync_account.dart';
import '../../domain/library_sync_profile.dart';
import '../../player/player_controller.dart';

enum _LibrarySyncConflictChoice { server, merge, local }

class LibrarySyncPanel extends StatelessWidget {
  const LibrarySyncPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<LibrarySyncStore>();
    final listenTogether = context.watch<ListenTogetherStore?>();
    final sharedPlaylists = context.watch<SharedPlaylistStore?>();
    final library = context.watch<LibraryStore>();
    final player = context.watch<PlayerController?>();
    final account = sync.account;
    final actionsEnabled =
        sync.loaded && !sync.busy && !library.offlineModeEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          key: const Key('library-sync-status'),
          leading: Icon(
            sync.isConfigured
                ? Icons.cloud_done_outlined
                : Icons.cloud_outlined,
          ),
          title: const Text('Cross-device library sync'),
          subtitle: Text(_statusText(sync)),
          trailing: IconButton(
            key: const Key('library-sync-configure'),
            tooltip: sync.isConfigured
                ? 'Edit sync server'
                : 'Configure sync server',
            onPressed: actionsEnabled
                ? () => _configure(context, account: account)
                : null,
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
        if (sync.busy)
          const LinearProgressIndicator(key: Key('library-sync-progress')),
        if (sync.isConfigured)
          ListTile(
            key: const Key('library-sync-profile'),
            dense: true,
            leading: _ProfileAvatar(profile: sync.profile),
            title: Text(
              sync.profile?.effectiveDisplayName ?? 'Server account',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              _profileStatusText(sync.profile),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (sync.profile?.editable == true)
                  IconButton(
                    key: const Key('library-sync-edit-profile'),
                    tooltip: 'Edit account identity',
                    onPressed: actionsEnabled
                        ? () => _editProfile(context, sync.profile!)
                        : null,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                IconButton(
                  key: const Key('library-sync-refresh-profile'),
                  tooltip: 'Refresh account identity',
                  onPressed: actionsEnabled
                      ? () => _refreshProfile(context)
                      : null,
                  icon: const Icon(Icons.refresh_outlined),
                ),
              ],
            ),
          ),
        if (sync.isConfigured && listenTogether != null)
          ListTile(
            key: const Key('listen-together-session'),
            leading: Icon(
              listenTogether.hosting
                  ? Icons.sensors_outlined
                  : listenTogether.joined
                  ? Icons.group_outlined
                  : Icons.group_add_outlined,
            ),
            title: Text(
              listenTogether.hosting
                  ? 'Hosting listen together'
                  : listenTogether.joined
                  ? 'Joined listen together'
                  : 'Listen together',
            ),
            subtitle: Text(
              _listenTogetherStatusText(context, listenTogether),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (!listenTogether.hosting && !listenTogether.joined)
                  IconButton(
                    key: const Key('listen-together-host'),
                    tooltip: 'Host listen together',
                    onPressed: actionsEnabled && player != null
                        ? () => _hostListenTogether(context)
                        : null,
                    icon: const Icon(Icons.sensors_outlined),
                  ),
                if (!listenTogether.hosting && !listenTogether.joined)
                  IconButton(
                    key: const Key('listen-together-join'),
                    tooltip: 'Join listen together',
                    onPressed: actionsEnabled && player != null
                        ? () => _joinListenTogether(context)
                        : null,
                    icon: const Icon(Icons.login_outlined),
                  ),
                if (!listenTogether.hosting && !listenTogether.joined)
                  IconButton(
                    key: const Key('listen-together-join-invite'),
                    tooltip: 'Join with invite code',
                    onPressed: actionsEnabled && player != null
                        ? () => _joinListenTogetherInvite(context)
                        : null,
                    icon: const Icon(Icons.vpn_key_outlined),
                  ),
                if (listenTogether.hosting)
                  IconButton(
                    key: const Key('listen-together-share-invite'),
                    tooltip: 'Create invite code',
                    onPressed: actionsEnabled
                        ? () => _shareListenTogetherInvite(context)
                        : null,
                    icon: const Icon(Icons.share_outlined),
                  ),
                if (listenTogether.hosting)
                  IconButton(
                    key: const Key('listen-together-end'),
                    tooltip: 'End listen together',
                    onPressed: actionsEnabled
                        ? () => _endListenTogether(context)
                        : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                if (listenTogether.joined && !listenTogether.hosting)
                  IconButton(
                    key: const Key('listen-together-refresh'),
                    tooltip: 'Refresh listen together',
                    onPressed: actionsEnabled && player != null && !listenTogether.busy
                        ? () => _refreshListenTogether(context)
                        : null,
                    icon: const Icon(Icons.refresh_outlined),
                  ),
                if (listenTogether.joined && !listenTogether.hosting)
                  IconButton(
                    key: const Key('listen-together-leave'),
                    tooltip: 'Leave listen together',
                    onPressed: listenTogether.busy
                        ? null
                        : () => context.read<ListenTogetherStore>().leave(),
                    icon: const Icon(Icons.logout_outlined),
                  ),
              ],
            ),
          ),
        if (sync.isConfigured && sharedPlaylists != null) ...<Widget>[
          ListTile(
            key: const Key('shared-playlists'),
            leading: const Icon(Icons.playlist_add_check_outlined),
            title: const Text('Private shared playlists'),
            subtitle: Text(
              sharedPlaylists.loaded
                  ? '${sharedPlaylists.bindings.length} linked playlist(s) · publish and refresh manually'
                  : 'Loading shared playlist links...',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  key: const Key('shared-playlists-host'),
                  tooltip: 'Share a playlist privately',
                  onPressed: actionsEnabled &&
                          !sharedPlaylists.busy &&
                          sharedPlaylists.loaded
                      ? () => _hostSharedPlaylist(context)
                      : null,
                  icon: const Icon(Icons.add_link_outlined),
                ),
                IconButton(
                  key: const Key('shared-playlists-join'),
                  tooltip: 'Join with invite code',
                  onPressed: actionsEnabled &&
                          !sharedPlaylists.busy &&
                          sharedPlaylists.loaded
                      ? () => _joinSharedPlaylistInvite(context)
                      : null,
                  icon: const Icon(Icons.vpn_key_outlined),
                ),
              ],
            ),
          ),
          if (sharedPlaylists.busy)
            const LinearProgressIndicator(key: Key('shared-playlists-progress')),
          for (final binding in sharedPlaylists.bindings)
            _SharedPlaylistBindingTile(binding: binding),
          if (sharedPlaylists.lastError != null && !sharedPlaylists.busy)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                sharedPlaylists.lastError!,
                key: const Key('shared-playlists-error'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        if (sync.isConfigured)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                IconButton.filledTonal(
                  key: const Key('library-sync-upload'),
                  tooltip: 'Upload library snapshot',
                  onPressed: actionsEnabled ? () => _upload(context) : null,
                  icon: const Icon(Icons.cloud_upload_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const Key('library-sync-download'),
                  tooltip: 'Download server snapshot',
                  onPressed: actionsEnabled ? () => _download(context) : null,
                  icon: const Icon(Icons.cloud_download_outlined),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('library-sync-delete-remote'),
                  tooltip: 'Delete server snapshot',
                  onPressed: actionsEnabled
                      ? () => _deleteRemoteSnapshot(context)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                ),
                const SizedBox(width: 8),
                IconButton(
                  key: const Key('library-sync-remove'),
                  tooltip: 'Remove sync server',
                  onPressed: sync.busy ? null : () => _remove(context),
                  icon: const Icon(Icons.link_off_outlined),
                ),
              ],
            ),
          ),
        if (sync.isConfigured)
          SwitchListTile.adaptive(
            key: const Key('library-sync-automatic-upload'),
            secondary: const Icon(Icons.sync_outlined),
            title: const Text('Automatic foreground uploads'),
            subtitle: const Text(
              'Upload every 15 minutes while the app is open. Server changes still require a manual choice.',
            ),
            value: sync.automaticUploadEnabled,
            onChanged: actionsEnabled
                ? (enabled) => _setAutomaticUpload(context, enabled)
                : null,
          ),
        if (sync.isConfigured)
          SwitchListTile.adaptive(
            key: const Key('library-sync-queue'),
            secondary: const Icon(Icons.queue_music_outlined),
            title: const Text('Sync active queue'),
            subtitle: const Text(
              'Sync library-backed queue order and current item. Media URLs, local files, and playback position stay on this device.',
            ),
            value: sync.queueSyncEnabled,
            onChanged: actionsEnabled && player != null
                ? (enabled) => _setQueueSync(context, enabled)
                : null,
          ),
        if (library.offlineModeEnabled)
          const ListTile(
            dense: true,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Library sync paused by offline mode'),
          ),
        if (sync.lastError != null && !sync.busy)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              sync.lastError!,
              key: const Key('library-sync-error'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  static String _statusText(LibrarySyncStore sync) {
    final account = sync.account;
    if (!sync.loaded) {
      return 'Loading secure sync settings...';
    }
    if (!sync.isConfigured || account == null) {
      return 'Not configured';
    }
    final revision = sync.remoteRevision == 0
        ? 'No server snapshot'
        : 'Server revision ${sync.remoteRevision}';
    final device = sync.remoteUpdatedByDevice;
    final remote = device == null ? revision : '$revision from $device';
    return '${account.baseUri.host} · $remote';
  }

  static String _profileStatusText(LibrarySyncProfile? profile) {
    if (profile == null) {
      return 'Account identity unavailable';
    }
    final device = profile.device;
    if (profile.managed && device != null) {
      return 'Account ${profile.id} · Device ${device.name}';
    }
    return 'Static account ${profile.id}';
  }

  static String _listenTogetherStatusText(
    BuildContext context,
    ListenTogetherStore listenTogether,
  ) {
    if (!listenTogether.hosting && !listenTogether.joined) {
      return 'Share the current library-backed queue';
    }

    final count = listenTogether.session?.trackIds.length ?? 0;
    final unavailable = listenTogether.unavailableTrackCount;
    final availability = unavailable == 0
        ? '$count shared library tracks'
        : '$count shared library tracks - $unavailable unavailable on this device';
    final updatedAt = listenTogether.updatedAt;
    if (updatedAt == null) {
      return '$availability - waiting for an update';
    }
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(updatedAt.toLocal()),
    );
    final device = listenTogether.updatedByDevice;
    return device == null || device.isEmpty
        ? '$availability - updated at $time'
        : '$availability - updated by $device at $time';
  }

  static Future<void> _refreshProfile(BuildContext context) async {
    try {
      final profile = await context.read<LibrarySyncStore>().refreshProfile(
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        _showSuccess(
          context,
          profile == null
              ? 'Server account identity is unavailable.'
              : 'Account identity refreshed.',
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, error);
      }
    }
  }

  static Future<void> _hostListenTogether(BuildContext context) async {
    try {
      await context.read<ListenTogetherStore>().host(
        context.read<LibraryStore>(),
        context.read<PlayerController>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Listen-together session started.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not start listen together: $error');
      }
    }
  }

  static Future<void> _joinListenTogether(BuildContext context) async {
    try {
      final restored = await context.read<ListenTogetherStore>().join(
        context.read<LibraryStore>(),
        context.read<PlayerController>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Joined shared playback with $restored tracks.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not join listen together: $error');
      }
    }
  }

  static Future<void> _endListenTogether(BuildContext context) async {
    try {
      await context.read<ListenTogetherStore>().endHostedSession();
      if (context.mounted) {
        _showSuccess(context, 'Listen-together session ended.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not end listen together: $error');
      }
    }
  }

  static Future<void> _refreshListenTogether(BuildContext context) async {
    try {
      final listenTogether = context.read<ListenTogetherStore>();
      final restored = await listenTogether.refreshJoined(
        context.read<LibraryStore>(),
        context.read<PlayerController>(),
      );
      if (!context.mounted) {
        return;
      }
      if (!listenTogether.joined) {
        _showSuccess(context, 'Listen-together session ended.');
      } else if (restored == 0) {
        _showSuccess(context, 'Shared playback is up to date.');
      } else {
        _showSuccess(context, 'Refreshed shared playback with $restored tracks.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not refresh listen together: $error');
      }
    }
  }

  static Future<void> _shareListenTogetherInvite(BuildContext context) async {
    try {
      final code = await context.read<ListenTogetherStore>().createInvite();
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Listen-together invite code'),
          content: SelectableText(code),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not create invite code: $error');
      }
    }
  }

  static Future<void> _joinListenTogetherInvite(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join listen together'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(labelText: 'Invite code'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !context.mounted) {
      return;
    }
    try {
      final restored = await context.read<ListenTogetherStore>().joinInvite(
        code,
        context.read<LibraryStore>(),
        context.read<PlayerController>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Joined shared playback with $restored tracks.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not join invite: $error');
      }
    }
  }

  static Future<void> _hostSharedPlaylist(BuildContext context) async {
    final library = context.read<LibraryStore>();
    if (library.playlists.isEmpty) {
      _showError(context, 'Create a local playlist before sharing it.');
      return;
    }
    final playlistId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share a playlist privately'),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: library.playlists
                .map(
                  (playlist) => ListTile(
                    title: Text(playlist.name),
                    subtitle: Text('${playlist.trackCount} track(s)'),
                    onTap: () => Navigator.of(dialogContext).pop(playlist.id),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (playlistId == null || !context.mounted) {
      return;
    }
    final playlist = library.playlistById(playlistId);
    if (playlist == null) {
      _showError(context, 'That local playlist is no longer available.');
      return;
    }
    try {
      await context.read<SharedPlaylistStore>().host(library, playlist);
      if (context.mounted) {
        _showSuccess(context, 'Private shared playlist created.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not share playlist: $error');
      }
    }
  }

  static Future<void> _joinSharedPlaylistInvite(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join private shared playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(labelText: 'Invite code'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !context.mounted) {
      return;
    }
    try {
      await context.read<SharedPlaylistStore>().joinInvite(
        code,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Private shared playlist added.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not join shared playlist: $error');
      }
    }
  }

  static Future<void> _refreshSharedPlaylist(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    try {
      await context.read<SharedPlaylistStore>().refresh(
        binding,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Shared playlist refreshed.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not refresh shared playlist: $error');
      }
    }
  }

  static Future<void> _publishSharedPlaylist(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    try {
      await context.read<SharedPlaylistStore>().publish(
        binding,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Shared playlist published.');
      }
    } on SharedPlaylistConflictException catch (_) {
      if (context.mounted) {
        _showError(context, 'A collaborator updated it first. Refresh or merge local changes.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not publish shared playlist: $error');
      }
    }
  }

  static Future<void> _mergeSharedPlaylist(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    final preferLocalName = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Merge local changes'),
        content: const Text(
          'The current server order stays first. Local track occurrences not already present on the server are appended. Choose which playlist name to keep.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep server name'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Keep local name'),
          ),
        ],
      ),
    );
    if (preferLocalName == null || !context.mounted) {
      return;
    }
    try {
      await context.read<SharedPlaylistStore>().mergeAndPublish(
        binding,
        context.read<LibraryStore>(),
        preferLocalName: preferLocalName,
      );
      if (context.mounted) {
        _showSuccess(context, 'Local and server playlist changes merged.');
      }
    } on SharedPlaylistConflictException catch (_) {
      if (context.mounted) {
        _showError(context, 'A collaborator updated it again. Refresh and retry the merge.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not merge shared playlist: $error');
      }
    }
  }

  static Future<void> _showSharedPlaylistHistory(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    try {
      final revisions = await context.read<SharedPlaylistStore>().history(
        binding,
        context.read<LibraryStore>(),
      );
      if (!context.mounted) {
        return;
      }
      final selected = await showDialog<SharedPlaylistRevision>(
        context: context,
        builder: (dialogContext) {
          final localizations = MaterialLocalizations.of(dialogContext);
          return AlertDialog(
            title: const Text('Playlist revision history'),
            content: SizedBox(
              width: 480,
              height: revisions.isEmpty ? null : 360,
              child: revisions.isEmpty
                  ? const Text('No archived revisions are available yet.')
                  : ListView(
                      children: revisions
                          .map(
                            (revision) {
                              final timestamp =
                                  '${localizations.formatMediumDate(revision.updatedAt.toLocal())} '
                                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(revision.updatedAt.toLocal()))}';
                              return ListTile(
                                leading: const Icon(Icons.history_outlined),
                                title: Text(
                                  'Revision ${revision.revision} · ${revision.name}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${revision.trackIds.length} track(s) · ${revision.updatedByDevice} · $timestamp',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing:
                                    binding.canEdit &&
                                        revision.revision < binding.revision
                                    ? const Icon(Icons.restore_outlined)
                                    : null,
                                onTap:
                                    binding.canEdit &&
                                        revision.revision < binding.revision
                                    ? () => Navigator.of(
                                      dialogContext,
                                    ).pop(revision)
                                    : null,
                              );
                            },
                          )
                          .toList(growable: false),
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
      if (selected != null && binding.canEdit && context.mounted) {
        await _restoreSharedPlaylistRevision(context, binding, selected);
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not load playlist history: $error');
      }
    }
  }

  static Future<void> _restoreSharedPlaylistRevision(
    BuildContext context,
    SharedPlaylistBinding binding,
    SharedPlaylistRevision revision,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Restore revision ${revision.revision}?'),
        content: Text(
          'This replaces the current shared playlist with "${revision.name}" and creates a new revision.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await context.read<SharedPlaylistStore>().restoreRevision(
        binding,
        revision,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Shared playlist revision restored.');
      }
    } on SharedPlaylistConflictException catch (_) {
      if (context.mounted) {
        _showError(context, 'A collaborator updated it first. Refresh before restoring.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not restore playlist revision: $error');
      }
    }
  }

  static Future<void> _createSharedPlaylistInvite(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    final role = await showDialog<SharedPlaylistAccessRole>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create private invite'),
        content: const Text('Choose what the person can do with this playlist.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SharedPlaylistAccessRole.viewer),
            child: const Text('Viewer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(SharedPlaylistAccessRole.editor),
            child: const Text('Editor'),
          ),
        ],
      ),
    );
    if (role == null || !context.mounted) {
      return;
    }
    try {
      final invitation = await context.read<SharedPlaylistStore>().createInvite(
        binding,
        role,
      );
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          final localizations = MaterialLocalizations.of(dialogContext);
          return AlertDialog(
            title: Text('${invitation.role.name} invite code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SelectableText(invitation.code),
                const SizedBox(height: 12),
                Text(
                  'Expires ${localizations.formatMediumDate(invitation.expiresAt.toLocal())}',
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not create invite code: $error');
      }
    }
  }

  static Future<void> _manageSharedPlaylistCollaborators(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    if (binding.collaborators.isEmpty) {
      _showError(context, 'There are no collaborators to manage.');
      return;
    }
    final collaboratorId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Manage collaborators'),
        content: SizedBox(
          width: 440,
          child: ListView(
            shrinkWrap: true,
            children: binding.collaborators.entries
                .map(
                  (entry) => ListTile(
                    leading: Icon(
                      entry.value == SharedPlaylistAccessRole.editor
                          ? Icons.edit_note_outlined
                          : Icons.visibility_outlined,
                    ),
                    title: Text(entry.key),
                    subtitle: Text('${entry.value.name} access'),
                    trailing: const Icon(Icons.person_remove_outlined),
                    onTap: () => Navigator.of(dialogContext).pop(entry.key),
                  ),
                )
                .toList(growable: false),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (collaboratorId == null || !context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revoke collaborator access?'),
        content: Text(
          '$collaboratorId will no longer be able to refresh or publish this private playlist.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await context.read<SharedPlaylistStore>().revokeCollaborator(
        binding,
        collaboratorId,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Collaborator access revoked.');
      }
    } on SharedPlaylistConflictException catch (_) {
      if (context.mounted) {
        _showError(context, 'A collaborator updated it first. Refresh before revoking access.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not revoke collaborator access: $error');
      }
    }
  }

  static Future<void> _rotateSharedPlaylistInvites(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invalidate unused invite codes?'),
        content: const Text(
          'Anyone who has not joined yet will need a newly created invite code.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Invalidate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      final invalidated = await context
          .read<SharedPlaylistStore>()
          .invalidateUnusedInvites(binding, context.read<LibraryStore>());
      if (context.mounted) {
        _showSuccess(context, 'Invalidated $invalidated unused invite code(s).');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not invalidate invite codes: $error');
      }
    }
  }

  static Future<void> _unlinkSharedPlaylist(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unlink shared playlist?'),
        content: const Text(
          'The local playlist stays on this device. Other collaborators keep their links.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await context.read<SharedPlaylistStore>().unlink(binding);
      if (context.mounted) {
        _showSuccess(context, 'Shared playlist unlinked from this device.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not unlink shared playlist: $error');
      }
    }
  }

  static Future<void> _deleteSharedPlaylist(
    BuildContext context,
    SharedPlaylistBinding binding,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete shared playlist?'),
        content: const Text(
          'This deletes the private server copy for every collaborator. The local playlist stays on this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await context.read<SharedPlaylistStore>().deleteHosted(
        binding,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Shared server playlist deleted.');
      }
    } on SharedPlaylistConflictException catch (_) {
      if (context.mounted) {
        _showError(context, 'A collaborator updated it first. Refresh before deleting.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, 'Could not delete shared playlist: $error');
      }
    }
  }

  static Future<void> _editProfile(
    BuildContext context,
    LibrarySyncProfile profile,
  ) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _LibrarySyncProfileDialog(profile: profile),
    );
    if (context.mounted && updated == true) {
      _showSuccess(context, 'Account identity updated.');
    }
  }

  static Future<void> _configure(
    BuildContext context, {
    LibrarySyncAccount? account,
  }) async {
    final configured = await showDialog<bool>(
      context: context,
      builder: (_) => _LibrarySyncConfigurationDialog(account: account),
    );
    if (!context.mounted || configured != true) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sync server configured.')));
  }

  static Future<void> _upload(BuildContext context) async {
    final sync = context.read<LibrarySyncStore>();
    final library = context.read<LibraryStore>();
    final player = context.read<PlayerController?>();
    try {
      final result = await sync.push(library, player: player);
      if (context.mounted) {
        _showSuccess(context, 'Uploaded library revision ${result.revision}.');
      }
    } on LibrarySyncConflictException catch (conflict) {
      if (!context.mounted) {
        return;
      }
      final choice = await _showConflictDialog(context, conflict);
      if (!context.mounted || choice == null) {
        return;
      }
      try {
        if (choice == _LibrarySyncConflictChoice.server) {
          final result = await sync.pull(library, player: player);
          if (context.mounted) {
            _showSuccess(
              context,
              'Downloaded server revision ${result.revision}.',
            );
          }
        } else if (choice == _LibrarySyncConflictChoice.merge) {
          final result = await sync.mergeAndPush(library, player: player);
          if (context.mounted) {
            _showSuccess(
              context,
              'Merged and uploaded library revision ${result.revision}.',
            );
          }
        } else {
          final result = await sync.push(
            library,
            baseRevision: conflict.currentRevision,
            player: player,
          );
          if (context.mounted) {
            _showSuccess(
              context,
              'Replaced server with revision ${result.revision}.',
            );
          }
        }
      } on Object catch (error) {
        if (context.mounted) {
          _showError(context, error);
        }
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, error);
      }
    }
  }

  static Future<void> _download(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Use server library?'),
        content: const Text(
          'Items absent from the server snapshot will be removed from this device. Matching local files and device cache settings are preserved.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('library-sync-confirm-download'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Use server copy'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    try {
      final result = await context.read<LibrarySyncStore>().pull(
        context.read<LibraryStore>(),
        player: context.read<PlayerController?>(),
      );
      if (context.mounted) {
        _showSuccess(context, 'Downloaded server revision ${result.revision}.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, error);
      }
    }
  }

  static Future<void> _setAutomaticUpload(
    BuildContext context,
    bool enabled,
  ) async {
    try {
      await context.read<LibrarySyncStore>().setAutomaticUploadEnabled(enabled);
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, error);
      }
    }
  }

  static Future<void> _setQueueSync(
    BuildContext context,
    bool enabled,
  ) async {
    try {
      await context.read<LibrarySyncStore>().setQueueSyncEnabled(enabled);
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, error);
      }
    }
  }

  static Future<void> _deleteRemoteSnapshot(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete server snapshot?'),
        content: const Text(
          'This removes the stored server library but keeps this device unchanged. The server records the reset as a new revision, and automatic uploads will be turned off.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const Key('library-sync-confirm-delete-remote'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete server copy'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    try {
      final result = await context
          .read<LibrarySyncStore>()
          .deleteRemoteSnapshot(context.read<LibraryStore>());
      if (context.mounted) {
        _showSuccess(
          context,
          'Deleted server snapshot at revision ${result.revision}.',
        );
      }
    } on LibrarySyncConflictException catch (conflict) {
      if (context.mounted) {
        _showError(
          context,
          'The server changed at revision ${conflict.currentRevision}. Refresh before deleting it.',
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, error);
      }
    }
  }

  static Future<_LibrarySyncConflictChoice?> _showConflictDialog(
    BuildContext context,
    LibrarySyncConflictException conflict,
  ) {
    final source = conflict.updatedByDevice == null
        ? 'another device'
        : conflict.updatedByDevice!;
    return showDialog<_LibrarySyncConflictChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Library changed on server'),
        content: Text(
          'Revision ${conflict.currentRevision} was uploaded by $source. Merge keeps independent items from both devices, combines playlist memberships, and keeps this device when the same metadata record conflicts.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          OutlinedButton.icon(
            key: const Key('library-sync-use-server'),
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_LibrarySyncConflictChoice.server),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Use server copy'),
          ),
          OutlinedButton.icon(
            key: const Key('library-sync-merge'),
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_LibrarySyncConflictChoice.merge),
            icon: const Icon(Icons.merge_type),
            label: const Text('Merge both'),
          ),
          FilledButton.icon(
            key: const Key('library-sync-use-local'),
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(_LibrarySyncConflictChoice.local),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text('Use this device'),
          ),
        ],
      ),
    );
  }

  static Future<void> _remove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove sync server?'),
        content: const Text(
          'The server snapshot is not deleted. This device removes its server settings and secure token.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('library-sync-confirm-remove'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) {
      return;
    }
    try {
      await context.read<LibrarySyncStore>().remove();
      if (context.mounted) {
        _showSuccess(context, 'Removed sync server from this device.');
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showError(context, error);
      }
    }
  }

  static void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class _SharedPlaylistBindingTile extends StatelessWidget {
  const _SharedPlaylistBindingTile({required this.binding});

  final SharedPlaylistBinding binding;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final playlist = library.playlistById(binding.localPlaylistId);
    final title = playlist?.name ?? 'Missing local playlist';
    final subtitle = '${binding.role.name} · revision ${binding.revision}';
    return ListTile(
      dense: true,
      leading: Icon(
        binding.isOwner
            ? Icons.admin_panel_settings_outlined
            : binding.canEdit
            ? Icons.edit_note_outlined
            : Icons.visibility_outlined,
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      trailing: PopupMenuButton<_SharedPlaylistAction>(
        tooltip: 'Shared playlist actions',
        onSelected: (action) {
          switch (action) {
            case _SharedPlaylistAction.refresh:
              LibrarySyncPanel._refreshSharedPlaylist(context, binding);
              break;
            case _SharedPlaylistAction.history:
              LibrarySyncPanel._showSharedPlaylistHistory(context, binding);
              break;
            case _SharedPlaylistAction.publish:
              LibrarySyncPanel._publishSharedPlaylist(context, binding);
              break;
            case _SharedPlaylistAction.merge:
              LibrarySyncPanel._mergeSharedPlaylist(context, binding);
              break;
            case _SharedPlaylistAction.invite:
              LibrarySyncPanel._createSharedPlaylistInvite(context, binding);
              break;
            case _SharedPlaylistAction.collaborators:
              LibrarySyncPanel._manageSharedPlaylistCollaborators(
                context,
                binding,
              );
              break;
            case _SharedPlaylistAction.rotateInvites:
              LibrarySyncPanel._rotateSharedPlaylistInvites(context, binding);
              break;
            case _SharedPlaylistAction.unlink:
              LibrarySyncPanel._unlinkSharedPlaylist(context, binding);
              break;
            case _SharedPlaylistAction.delete:
              LibrarySyncPanel._deleteSharedPlaylist(context, binding);
              break;
          }
        },
        itemBuilder: (menuContext) => <PopupMenuEntry<_SharedPlaylistAction>>[
          const PopupMenuItem(
            value: _SharedPlaylistAction.refresh,
            child: ListTile(
              leading: Icon(Icons.refresh_outlined),
              title: Text('Refresh from server'),
            ),
          ),
          const PopupMenuItem(
            value: _SharedPlaylistAction.history,
            child: ListTile(
              leading: Icon(Icons.history_outlined),
              title: Text('Revision history'),
            ),
          ),
          if (binding.canEdit)
            const PopupMenuItem(
              value: _SharedPlaylistAction.publish,
              child: ListTile(
                leading: Icon(Icons.publish_outlined),
                title: Text('Publish local changes'),
              ),
            ),
          if (binding.canEdit)
            const PopupMenuItem(
              value: _SharedPlaylistAction.merge,
              child: ListTile(
                leading: Icon(Icons.merge_type),
                title: Text('Merge local changes'),
              ),
            ),
          if (binding.isOwner)
            const PopupMenuItem(
              value: _SharedPlaylistAction.invite,
              child: ListTile(
                leading: Icon(Icons.person_add_alt_1_outlined),
                title: Text('Create invite code'),
              ),
            ),
          if (binding.isOwner)
            const PopupMenuItem(
              value: _SharedPlaylistAction.rotateInvites,
              child: ListTile(
                leading: Icon(Icons.restart_alt_outlined),
                title: Text('Invalidate unused invite codes'),
              ),
            ),
          if (binding.isOwner && binding.collaborators.isNotEmpty)
            const PopupMenuItem(
              value: _SharedPlaylistAction.collaborators,
              child: ListTile(
                leading: Icon(Icons.manage_accounts_outlined),
                title: Text('Manage collaborators'),
              ),
            ),
          const PopupMenuDivider(),
          if (binding.isOwner)
            const PopupMenuItem(
              value: _SharedPlaylistAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete server playlist'),
              ),
            ),
          const PopupMenuItem(
            value: _SharedPlaylistAction.unlink,
            child: ListTile(
              leading: Icon(Icons.link_off_outlined),
              title: Text('Unlink this device'),
            ),
          ),
        ],
      ),
    );
  }
}

enum _SharedPlaylistAction {
  refresh,
  history,
  publish,
  merge,
  invite,
  collaborators,
  rotateInvites,
  unlink,
  delete,
}

class _LibrarySyncProfileDialog extends StatefulWidget {
  const _LibrarySyncProfileDialog({required this.profile});

  final LibrarySyncProfile profile;

  @override
  State<_LibrarySyncProfileDialog> createState() =>
      _LibrarySyncProfileDialogState();
}

class _LibrarySyncProfileDialogState extends State<_LibrarySyncProfileDialog> {
  late final TextEditingController _displayNameController;
  late final TextEditingController _deviceNameController;
  late LibrarySyncProfileAvatarTone? _avatarTone;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(
      text: widget.profile.effectiveDisplayName,
    );
    _deviceNameController = TextEditingController(
      text: widget.profile.device?.name ?? '',
    );
    _avatarTone = widget.profile.avatarTone;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit account identity'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                key: const Key('library-sync-profile-display-name'),
                controller: _displayNameController,
                enabled: !_saving,
                autofocus: true,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Account display name',
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _error = null),
              ),
              TextField(
                key: const Key('library-sync-profile-device-name'),
                controller: _deviceNameController,
                enabled: !_saving,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Device name'),
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
              ),
              if (widget.profile.avatarToneSupported)
                DropdownButtonFormField<LibrarySyncProfileAvatarTone?>(
                  key: const Key('library-sync-profile-avatar-tone'),
                  value: _avatarTone,
                  decoration: const InputDecoration(labelText: 'Initials avatar'),
                  items: <DropdownMenuItem<LibrarySyncProfileAvatarTone?>>[
                    const DropdownMenuItem<LibrarySyncProfileAvatarTone?>(
                      value: null,
                      child: Text('No avatar'),
                    ),
                    ...LibrarySyncProfileAvatarTone.values.map(
                      (tone) => DropdownMenuItem<LibrarySyncProfileAvatarTone?>(
                        value: tone,
                        child: Text(_avatarToneLabel(tone)),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (tone) => setState(() {
                          _avatarTone = tone;
                          _error = null;
                        }),
                ),
              if (_error != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    key: const Key('library-sync-profile-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_saving) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  key: Key('library-sync-profile-progress'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('library-sync-save-profile'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<LibrarySyncStore>().updateProfile(
        context.read<LibraryStore>(),
        displayName: _displayNameController.text,
        deviceName: _deviceNameController.text,
        avatarTone: _avatarTone,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile});

  final LibrarySyncProfile? profile;

  @override
  Widget build(BuildContext context) {
    final profile = this.profile;
    final tone = profile?.avatarTone;
    if (profile == null || tone == null) {
      return Icon(
        profile?.managed == true
            ? Icons.manage_accounts_outlined
            : profile == null
            ? Icons.person_outline
            : Icons.key_outlined,
      );
    }
    final name = profile.effectiveDisplayName.trim();
    final initials = name.isEmpty
        ? '?'
        : name.split(RegExp(r'\s+')).take(2).map((part) => part[0]).join();
    return Semantics(
      label: 'Account avatar for ${profile.effectiveDisplayName}',
      child: CircleAvatar(
        backgroundColor: _avatarToneColor(context, tone),
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
        ),
      ),
    );
  }
}

Color _avatarToneColor(
  BuildContext context,
  LibrarySyncProfileAvatarTone tone,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    LibrarySyncProfileAvatarTone.azure => scheme.primary,
    LibrarySyncProfileAvatarTone.emerald => scheme.tertiary,
    LibrarySyncProfileAvatarTone.amber => scheme.secondary,
    LibrarySyncProfileAvatarTone.rose => scheme.error,
    LibrarySyncProfileAvatarTone.violet => scheme.primaryContainer,
    LibrarySyncProfileAvatarTone.slate => scheme.outline,
  };
}

String _avatarToneLabel(LibrarySyncProfileAvatarTone tone) => switch (tone) {
  LibrarySyncProfileAvatarTone.azure => 'Azure',
  LibrarySyncProfileAvatarTone.emerald => 'Emerald',
  LibrarySyncProfileAvatarTone.amber => 'Amber',
  LibrarySyncProfileAvatarTone.rose => 'Rose',
  LibrarySyncProfileAvatarTone.violet => 'Violet',
  LibrarySyncProfileAvatarTone.slate => 'Slate',
};

class _LibrarySyncConfigurationDialog extends StatefulWidget {
  const _LibrarySyncConfigurationDialog({this.account});

  final LibrarySyncAccount? account;

  @override
  State<_LibrarySyncConfigurationDialog> createState() =>
      _LibrarySyncConfigurationDialogState();
}

class _LibrarySyncConfigurationDialogState
    extends State<_LibrarySyncConfigurationDialog> {
  late final TextEditingController _urlController;
  late final TextEditingController _deviceController;
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _recoveryCodeController = TextEditingController();
  late bool _allowInsecureHttp;
  bool _obscureToken = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: widget.account?.baseUri.toString() ?? 'https://',
    );
    _deviceController = TextEditingController(
      text: widget.account?.deviceId ?? '',
    );
    _allowInsecureHttp = widget.account?.allowInsecureHttp ?? false;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _deviceController.dispose();
    _tokenController.dispose();
    _recoveryCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usesHttp = _urlController.text.trim().toLowerCase().startsWith(
      'http://',
    );
    return AlertDialog(
      title: const Text('Configure library sync'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                key: const Key('library-sync-url'),
                controller: _urlController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Server URL'),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _error = null),
              ),
              TextField(
                key: const Key('library-sync-device'),
                controller: _deviceController,
                enabled: !_saving,
                decoration: const InputDecoration(labelText: 'Device name'),
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() => _error = null),
              ),
              TextField(
                key: const Key('library-sync-token'),
                controller: _tokenController,
                enabled: !_saving,
                obscureText: _obscureToken,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Sync token',
                  suffixIcon: IconButton(
                    tooltip: _obscureToken ? 'Show token' : 'Hide token',
                    onPressed: _saving
                        ? null
                        : () => setState(() => _obscureToken = !_obscureToken),
                    icon: Icon(
                      _obscureToken ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
              ),
              TextField(
                key: const Key('library-sync-recovery-code'),
                controller: _recoveryCodeController,
                enabled: !_saving,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Recovery code (optional)',
                ),
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _save(),
              ),
              if (usesHttp)
                CheckboxListTile(
                  key: const Key('library-sync-insecure-http'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow insecure HTTP'),
                  subtitle: const Text(
                    'The sync token will be sent without TLS.',
                  ),
                  value: _allowInsecureHttp,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _allowInsecureHttp = value ?? false),
                ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    key: const Key('library-sync-config-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              if (_saving) ...<Widget>[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  key: Key('library-sync-config-progress'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('library-sync-test-save'),
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Test and save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final token = _tokenController.text.trim();
    final recoveryCode = _recoveryCodeController.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final account = createLibrarySyncAccount(
        baseUrl: _urlController.text,
        deviceId: _deviceController.text,
        allowInsecureHttp: _allowInsecureHttp,
      );
      final store = context.read<LibrarySyncStore>();
      if (recoveryCode.isNotEmpty) {
        await store.redeemRecoveryCodeAndSave(
          context.read<LibraryStore>(),
          account,
          recoveryCode,
        );
      } else {
        await store.testAndSave(
          context.read<LibraryStore>(),
          account,
          token,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      var message = error.toString();
      for (final secret in <String>[token, recoveryCode]) {
        if (secret.isNotEmpty) {
          message = message.replaceAll(secret, '[redacted]');
        }
      }
      setState(() {
        _saving = false;
        _error = token.isEmpty && recoveryCode.isEmpty
            ? error.toString()
            : message;
      });
    }
  }
}
