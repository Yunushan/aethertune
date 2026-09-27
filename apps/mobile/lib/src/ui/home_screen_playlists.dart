part of 'home_screen.dart';

class _CustomSmartPlaylistDraft {
  const _CustomSmartPlaylistDraft({
    required this.name,
    required this.query,
    required this.sourceId,
    required this.artist,
    required this.album,
    required this.genre,
    required this.minimumDurationSeconds,
    required this.maximumDurationSeconds,
    required this.favoritesOnly,
    required this.minimumPlayCount,
    required this.minimumDaysSinceLastPlayed,
    required this.matchMode,
    required this.ruleGroups,
    required this.sortMode,
    required this.limit,
  });

  final String name;
  final String query;
  final String sourceId;
  final String artist;
  final String album;
  final String genre;
  final int minimumDurationSeconds;
  final int maximumDurationSeconds;
  final bool favoritesOnly;
  final int minimumPlayCount;
  final int minimumDaysSinceLastPlayed;
  final CustomSmartPlaylistMatchMode matchMode;
  final List<CustomSmartPlaylistRuleGroup> ruleGroups;
  final CustomSmartPlaylistSortMode sortMode;
  final int limit;
}

class _TextEditingControllerOwner extends StatefulWidget {
  const _TextEditingControllerOwner({
    required this.controllers,
    required this.child,
  });

  final List<TextEditingController> controllers;
  final Widget child;

  @override
  State<_TextEditingControllerOwner> createState() =>
      _TextEditingControllerOwnerState();
}

class _TextEditingControllerOwnerState
    extends State<_TextEditingControllerOwner> {
  @override
  void dispose() {
    for (final controller in widget.controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PlaylistsTab extends StatefulWidget {
  const _PlaylistsTab({required this.onAddToPlaylist, required this.onLyrics});

  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  State<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<_PlaylistsTab> {
  String? _folderFilter;

  ValueChanged<Track> get onAddToPlaylist => widget.onAddToPlaylist;
  ValueChanged<Track> get onLyrics => widget.onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final sharedSmartPlaylists = context.watch<SharedSmartPlaylistStore?>();

    if (!library.loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final smartPlaylists = library.smartPlaylists();
    final customSmartPlaylists = library.customSmartPlaylists;
    final folders = library.playlistFolders;
    final hasUnfiledPlaylists = library.playlists.any(
      (playlist) => playlist.folder.trim().isEmpty,
    );
    final activeFolder =
        _folderFilter != null &&
            _folderFilter != '' &&
            !folders.contains(_folderFilter)
        ? null
        : _folderFilter;
    final manualPlaylists = library.playlists
        .where((playlist) {
          if (activeFolder == null) {
            return true;
          }
          return playlist.folder.trim() == activeFolder;
        })
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Playlists',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Import playlist',
              onPressed: () => _showPlaylistImportFormatPicker(context),
              icon: const Icon(Icons.upload_file),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Create playlist',
              onPressed: () => _createPlaylist(context),
              icon: const Icon(Icons.playlist_add),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              key: const Key('smart-playlist-create'),
              tooltip: 'Create smart playlist',
              onPressed: () => _createCustomSmartPlaylist(context),
              icon: const Icon(Icons.filter_alt_outlined),
            ),
            if (sharedSmartPlaylists?.available ?? false) ...<Widget>[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const Key('shared-smart-playlist-join'),
                tooltip: 'Join private smart playlist',
                onPressed: (sharedSmartPlaylists?.busy ?? true)
                    ? null
                    : () => _joinSharedSmartPlaylist(context),
                icon: const Icon(Icons.vpn_key_outlined),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Built-in smart playlists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final smartPlaylist in smartPlaylists)
          _SmartPlaylistCard(
            smartPlaylist: smartPlaylist,
            onOpen: () => _showSmartPlaylist(context, smartPlaylist.type),
          ),
        const SizedBox(height: 16),
        Text(
          'Custom smart playlists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (customSmartPlaylists.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.filter_alt_outlined),
              title: const Text('No custom smart playlists'),
              trailing: IconButton(
                tooltip: 'Create smart playlist',
                onPressed: () => _createCustomSmartPlaylist(context),
                icon: const Icon(Icons.add),
              ),
            ),
          )
        else
          for (final rule in customSmartPlaylists)
            _CustomSmartPlaylistCard(
              rule: rule,
              tracks: library.tracksForCustomSmartPlaylist(rule.id),
              onOpen: () => _showCustomSmartPlaylist(context, rule.id),
              onEdit: () => _editCustomSmartPlaylist(context, rule),
              onArtwork: () => _editCustomSmartPlaylistArtwork(context, rule),
              onCopyImportLink: () => unawaited(
                _copyCustomSmartPlaylistImportLink(context, library, rule),
              ),
              onPrivateShare: sharedSmartPlaylists?.available ?? false
                  ? () => _shareCustomSmartPlaylist(context, rule)
                  : null,
              onRefreshPublicSubscription:
                  sharedSmartPlaylists?.publicSubscriptionForLocalSmartPlaylist(
                        rule.id,
                      ) !=
                      null
                  ? () => _refreshPublicSmartPlaylistSubscription(context, rule)
                  : null,
              onUnsubscribePublicSubscription:
                  sharedSmartPlaylists?.publicSubscriptionForLocalSmartPlaylist(
                        rule.id,
                      ) !=
                      null
                  ? () => _unsubscribeFromPublicSmartPlaylist(context, rule)
                  : null,
              onDuplicate: () =>
                  unawaited(_duplicateCustomSmartPlaylist(context, rule)),
              onDelete: () => _deleteCustomSmartPlaylist(context, rule),
            ),
        const SizedBox(height: 16),
        Text(
          'Manual playlists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (folders.isNotEmpty || hasUnfiledPlaylists) ...<Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              ChoiceChip(
                label: const Text('All'),
                selected: activeFolder == null,
                onSelected: (_) => setState(() => _folderFilter = null),
              ),
              if (hasUnfiledPlaylists)
                ChoiceChip(
                  label: const Text('Unfiled'),
                  selected: activeFolder == '',
                  onSelected: (_) => setState(() => _folderFilter = ''),
                ),
              for (final folder in folders)
                ChoiceChip(
                  label: Text(folder),
                  selected: activeFolder == folder,
                  onSelected: (_) => setState(() => _folderFilter = folder),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (library.playlists.isEmpty)
          _EmptyPlaylists(onCreate: () => _createPlaylist(context))
        else if (manualPlaylists.isEmpty)
          const ListTile(
            leading: Icon(Icons.folder_off_outlined),
            title: Text('No playlists in this folder'),
          )
        else
          for (final playlist in manualPlaylists)
            _PlaylistCard(
              playlist: playlist,
              tracks: library.tracksForPlaylist(playlist.id),
              onOpen: () => _showPlaylist(context, playlist.id),
              onExport: (format) =>
                  _showPlaylistExport(context, playlist, format),
              onShare: () =>
                  unawaited(_copyPlaylistShareText(context, library, playlist)),
              onCopyImportLink: () => unawaited(
                _copyPlaylistImportLink(context, library, playlist),
              ),
              onShareCard: () =>
                  unawaited(_showPlaylistShareCard(context, playlist)),
              onArtwork: () => _editPlaylistArtwork(context, playlist),
              onDuplicate: () =>
                  unawaited(_duplicatePlaylist(context, playlist)),
              onRename: () => _renamePlaylist(context, playlist),
              onMoveToFolder: () => _movePlaylistToFolder(context, playlist),
              onDelete: () => _deletePlaylist(context, playlist),
            ),
      ],
    );
  }

  Future<void> _showPlaylistImportFormatPicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              for (final format in PlaylistDocumentFormat.values)
                ListTile(
                  leading: Icon(_playlistDocumentFormatIcon(format)),
                  title: Text('Import ${_playlistDocumentFormatLabel(format)}'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _importPlaylist(context, format);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Paste AetherTune playlist link'),
                subtitle: const Text(
                  'Import a portable playlist shared from AetherTune.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importPlaylistLink(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.filter_alt_outlined),
                title: const Text('Paste AetherTune smart playlist link'),
                subtitle: const Text(
                  'Import portable smart-playlist rules from AetherTune.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importCustomSmartPlaylistLink(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.public_outlined),
                title: const Text('Paste public smart playlist link'),
                subtitle: const Text(
                  'Import checksum-verified rules from an HTTPS public link.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importPublicSharedSmartPlaylistLink(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Subscribe to public smart playlist'),
                subtitle: const Text(
                  'Store an HTTPS link securely for manual refreshes.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _subscribeToPublicSharedSmartPlaylist(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importPlaylist(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: Text(
                  'Choose ${_playlistDocumentFormatLabel(format)} file',
                ),
                subtitle: Text(
                  'Import a .${_playlistDocumentFormatFileExtension(format)} playlist file.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importPlaylistFile(context, format);
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_paste_outlined),
                title: Text(
                  'Paste ${_playlistDocumentFormatLabel(format)} content',
                ),
                subtitle: const Text('Import a copied playlist document.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _importPlaylistText(context, format);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _importPlaylistFile(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final extension = _playlistDocumentFormatFileExtension(format);
    final file = await pickSingleFile(
      allowedExtensions: <String>[extension],
      dialogTitle: 'Import ${_playlistDocumentFormatLabel(format)} playlist',
      type: FileType.custom,
    );
    if (!context.mounted || file == null) {
      return;
    }
    if (!file.name.toLowerCase().endsWith('.$extension')) {
      messenger.showSnackBar(
        SnackBar(content: Text('Choose a .$extension playlist file.')),
      );
      return;
    }

    try {
      final document = utf8.decode(
        await readPickedFileBytes(file),
        allowMalformed: false,
      );
      if (!context.mounted) {
        return;
      }
      await _importPlaylistDocument(context, format, document);
    } on FormatException {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Playlist files must be valid UTF-8 text.'),
        ),
      );
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not read playlist file: $error')),
      );
    }
  }

  Future<void> _importPlaylistText(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    final document = await _promptForPlaylistDocument(context, format);
    if (!context.mounted || document == null) {
      return;
    }
    await _importPlaylistDocument(context, format, document);
  }

  Future<void> _importPlaylistDocument(
    BuildContext context,
    PlaylistDocumentFormat format,
    String document,
  ) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    try {
      final playlist = await library.importPlaylistDocument(
        document,
        format: format,
      );

      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Imported ${playlist.name}.')),
      );
    } on FormatException catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _importPlaylistLink(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final link = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import AetherTune playlist link'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(labelText: 'Playlist link'),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (!context.mounted || link == null) {
        return;
      }
      final playlist = await context.read<LibraryStore>().importPlaylistLink(
        link,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported ${playlist.name}.')));
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _importCustomSmartPlaylistLink(BuildContext context) async {
    final controller = TextEditingController();
    try {
      final link = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import AetherTune smart playlist link'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(labelText: 'Smart playlist link'),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (!context.mounted || link == null) {
        return;
      }
      final playlist = await context
          .read<LibraryStore>()
          .importCustomSmartPlaylistLink(link);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported ${playlist.name}.')));
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _importPublicSharedSmartPlaylistLink(
    BuildContext context,
  ) async {
    final controller = TextEditingController();
    try {
      final link = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import public smart playlist'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(labelText: 'HTTPS public link'),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (!context.mounted || link == null || link.trim().isEmpty) {
        return;
      }
      final playlist = await context
          .read<SharedSmartPlaylistStore>()
          .importPublicLink(link, context.read<LibraryStore>());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported public smart playlist ${playlist.name}.'),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not import public smart playlist: $error'),
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _subscribeToPublicSharedSmartPlaylist(
    BuildContext context,
  ) async {
    final controller = TextEditingController();
    try {
      final link = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Subscribe to public smart playlist'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(labelText: 'HTTPS public link'),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Subscribe'),
            ),
          ],
        ),
      );
      if (!context.mounted || link == null || link.trim().isEmpty) {
        return;
      }
      final subscription = await context
          .read<SharedSmartPlaylistStore>()
          .subscribeToPublicLink(link, context.read<LibraryStore>());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Subscribed to public smart playlist ${subscription.remoteId}.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not subscribe to public smart playlist: $error',
            ),
          ),
        );
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _refreshPublicSmartPlaylistSubscription(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final store = context.read<SharedSmartPlaylistStore>();
    final subscription = store.publicSubscriptionForLocalSmartPlaylist(rule.id);
    if (subscription == null) {
      return;
    }
    try {
      await store.refreshPublicSubscription(
        subscription,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refreshed public smart playlist ${rule.name}.'),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not refresh public smart playlist: $error'),
          ),
        );
      }
    }
  }

  Future<void> _unsubscribeFromPublicSmartPlaylist(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final store = context.read<SharedSmartPlaylistStore>();
    final subscription = store.publicSubscriptionForLocalSmartPlaylist(rule.id);
    if (subscription == null) {
      return;
    }
    try {
      await store.unsubscribeFromPublicLink(subscription);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unsubscribed from ${rule.name}.')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not unsubscribe from public smart playlist: $error',
            ),
          ),
        );
      }
    }
  }

  Future<String?> _promptForPlaylistDocument(
    BuildContext context,
    PlaylistDocumentFormat format,
  ) async {
    final controller = TextEditingController();

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Import ${_playlistDocumentFormatLabel(format)}'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                autofocus: true,
                controller: controller,
                decoration: InputDecoration(
                  labelText:
                      '${_playlistDocumentFormatExtension(format)} content',
                ),
                keyboardType: TextInputType.multiline,
                minLines: 8,
                maxLines: 14,
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Import'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final name = await _promptForPlaylistName(context, title: 'New playlist');
    if (!context.mounted || name == null) {
      return;
    }

    final playlist = await library.createPlaylist(name);
    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Created ${playlist.name}.')),
    );
  }

  Future<void> _createCustomSmartPlaylist(BuildContext context) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);
    final draft = await _promptForCustomSmartPlaylistRule(
      context,
      title: 'New smart playlist',
    );
    if (!context.mounted || draft == null) {
      return;
    }

    final rule = await library.createCustomSmartPlaylist(
      name: draft.name,
      query: draft.query,
      sourceId: draft.sourceId,
      artist: draft.artist,
      album: draft.album,
      genre: draft.genre,
      minimumDurationSeconds: draft.minimumDurationSeconds,
      maximumDurationSeconds: draft.maximumDurationSeconds,
      favoritesOnly: draft.favoritesOnly,
      minimumPlayCount: draft.minimumPlayCount,
      minimumDaysSinceLastPlayed: draft.minimumDaysSinceLastPlayed,
      matchMode: draft.matchMode,
      ruleGroups: draft.ruleGroups,
      sortMode: draft.sortMode,
      limit: draft.limit,
    );
    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text('Created ${rule.name}.')));
  }

  Future<void> _editCustomSmartPlaylist(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final library = context.read<LibraryStore>();
    final draft = await _promptForCustomSmartPlaylistRule(
      context,
      title: 'Edit smart playlist',
      initialRule: rule,
    );
    if (!context.mounted || draft == null) {
      return;
    }

    await library.updateCustomSmartPlaylist(
      rule.id,
      name: draft.name,
      query: draft.query,
      sourceId: draft.sourceId,
      artist: draft.artist,
      album: draft.album,
      genre: draft.genre,
      minimumDurationSeconds: draft.minimumDurationSeconds,
      maximumDurationSeconds: draft.maximumDurationSeconds,
      favoritesOnly: draft.favoritesOnly,
      minimumPlayCount: draft.minimumPlayCount,
      minimumDaysSinceLastPlayed: draft.minimumDaysSinceLastPlayed,
      matchMode: draft.matchMode,
      ruleGroups: draft.ruleGroups,
      sortMode: draft.sortMode,
      limit: draft.limit,
    );
  }

  Future<void> _deleteCustomSmartPlaylist(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final library = context.read<LibraryStore>();
    final sharedSmartPlaylists = context.read<SharedSmartPlaylistStore?>();
    final messenger = ScaffoldMessenger.of(context);

    final publicSubscription = sharedSmartPlaylists
        ?.publicSubscriptionForLocalSmartPlaylist(rule.id);
    if (publicSubscription != null) {
      await sharedSmartPlaylists!.unsubscribeFromPublicLink(publicSubscription);
    }
    await library.deleteCustomSmartPlaylist(rule.id);
    await _playlistArtworkFileStore.delete(rule.artworkUri);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text('Deleted ${rule.name}.')));
  }

  Future<void> _duplicateCustomSmartPlaylist(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final duplicate = await context
        .read<LibraryStore>()
        .duplicateCustomSmartPlaylist(rule.id);
    if (!context.mounted || duplicate == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created ${duplicate.name}.')));
  }

  Future<void> _joinSharedSmartPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final invite = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join private smart playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Invite code'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            icon: const Icon(Icons.login_outlined),
            label: const Text('Join'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!context.mounted || invite == null || invite.trim().isEmpty) {
      return;
    }
    try {
      final binding = await context.read<SharedSmartPlaylistStore>().joinInvite(
        invite,
        context.read<LibraryStore>(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Joined shared smart playlist ${binding.remoteId}.'),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not join shared smart playlist: $error'),
          ),
        );
      }
    }
  }

  Future<void> _shareCustomSmartPlaylist(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final store = context.read<SharedSmartPlaylistStore>();
    final library = context.read<LibraryStore>();
    try {
      var binding = store.bindingForLocalSmartPlaylist(rule.id);
      binding ??= await store.host(library, rule);
      if (!context.mounted) {
        return;
      }
      if (!binding.isOwner) {
        if (binding.canEdit) {
          await store.publish(binding, library);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Published shared smart-playlist rules.'),
              ),
            );
          }
          return;
        }
        await store.refresh(binding, library);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Refreshed shared smart-playlist rules.'),
            ),
          );
        }
        return;
      }
      final shareMode = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Share smart playlist'),
          content: const Text(
            'Choose private collaboration or a public rule link.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('public'),
              child: const Text('Public link'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('revokePublic'),
              child: const Text('Revoke public link'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('viewer'),
              child: const Text('Viewer'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('editor'),
              child: const Text('Editor'),
            ),
          ],
        ),
      );
      if (!context.mounted || shareMode == null) {
        return;
      }
      if (shareMode == 'public') {
        final link = await store.createPublicLink(binding, library);
        if (!context.mounted) {
          return;
        }
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Public smart-playlist link'),
            content: SelectableText(link.uri.toString()),
            actions: <Widget>[
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        );
        return;
      }
      if (shareMode == 'revokePublic') {
        await store.revokePublicLink(binding, library);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Revoked public smart-playlist link.'),
            ),
          );
        }
        return;
      }
      final role = shareMode == 'editor'
          ? SharedPlaylistAccessRole.editor
          : SharedPlaylistAccessRole.viewer;
      final invite = await store.createInvite(binding, role);
      if (!context.mounted) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Private smart-playlist invite'),
          content: SelectableText(invite.code),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not share smart playlist: $error')),
        );
      }
    }
  }

  Future<void> _renamePlaylist(BuildContext context, Playlist playlist) async {
    final library = context.read<LibraryStore>();
    final name = await _promptForPlaylistName(
      context,
      title: 'Rename playlist',
      initialValue: playlist.name,
    );
    if (!context.mounted || name == null) {
      return;
    }

    await library.renamePlaylist(playlist.id, name);
  }

  Future<void> _movePlaylistToFolder(
    BuildContext context,
    Playlist playlist,
  ) async {
    final controller = TextEditingController(text: playlist.folder);
    try {
      final folder = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('Move ${playlist.name}'),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Folder',
                hintText: 'Leave empty for Unfiled',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Move'),
              ),
            ],
          );
        },
      );
      if (!context.mounted || folder == null) {
        return;
      }
      await context.read<LibraryStore>().updatePlaylistFolder(
        playlist.id,
        folder,
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _editPlaylistArtwork(
    BuildContext context,
    Playlist playlist,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose image file'),
                subtitle: const Text(
                  'Store a private PNG, JPEG, GIF, or WebP image.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _pickPlaylistArtworkFile(context, playlist);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Set image URL'),
                subtitle: const Text('Use an http or https image URL.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _setPlaylistArtworkUrl(context, playlist);
                },
              ),
              if (playlist.artworkUri != null)
                ListTile(
                  leading: const Icon(Icons.crop_outlined),
                  title: const Text('Crop and position'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _editPlaylistArtworkCrop(context, playlist);
                  },
                ),
              if (playlist.artworkUri != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Remove artwork'),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await _removePlaylistArtwork(context, playlist);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickPlaylistArtworkFile(
    BuildContext context,
    Playlist playlist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await pickSingleFile(
      type: FileType.image,
      dialogTitle: 'Choose playlist artwork',
    );
    if (!context.mounted || file == null) {
      return;
    }

    try {
      final artworkUri = await _playlistArtworkFileStore.save(
        await readPickedFileBytes(file),
      );
      if (!context.mounted) {
        return;
      }
      final updated = await context.read<LibraryStore>().updatePlaylistArtwork(
        playlist.id,
        artworkUri,
      );
      if (!context.mounted || updated == null) {
        return;
      }
      await _playlistArtworkFileStore.delete(playlist.artworkUri);
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Updated artwork for ${updated.name}.')),
      );
    } on FormatException catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Exception catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save artwork: $error')),
        );
      }
    }
  }

  Future<void> _setPlaylistArtworkUrl(
    BuildContext context,
    Playlist playlist,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final initialValue =
        playlist.artworkUri != null && _isNetworkImageUri(playlist.artworkUri!)
        ? playlist.artworkUri!.toString()
        : '';
    final value = await _promptForPlaylistArtwork(context, initialValue);
    if (!context.mounted || value == null) {
      return;
    }

    final normalized = value.trim();
    final artworkUri = Uri.tryParse(normalized);
    if (artworkUri == null || !_isNetworkImageUri(artworkUri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter an http or https image URL.')),
      );
      return;
    }

    final updated = await context.read<LibraryStore>().updatePlaylistArtwork(
      playlist.id,
      artworkUri,
    );
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(playlist.artworkUri);
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Updated artwork for ${updated.name}.')),
    );
  }

  Future<void> _removePlaylistArtwork(
    BuildContext context,
    Playlist playlist,
  ) async {
    final updated = await context.read<LibraryStore>().updatePlaylistArtwork(
      playlist.id,
      null,
    );
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(playlist.artworkUri);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed artwork for ${updated.name}.')),
    );
  }

  Future<void> _editPlaylistArtworkCrop(
    BuildContext context,
    Playlist playlist,
  ) async {
    final artworkUri = playlist.artworkUri;
    if (artworkUri == null) {
      return;
    }
    final crop = await showArtworkCropEditor(
      context,
      artworkUri: artworkUri,
      initialCrop: playlist.artworkCrop,
    );
    if (!context.mounted || crop == null) {
      return;
    }
    final updated = await context
        .read<LibraryStore>()
        .updatePlaylistArtworkCrop(playlist.id, crop);
    if (!context.mounted || updated == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated artwork crop for ${updated.name}.')),
    );
  }

  Future<void> _deletePlaylist(BuildContext context, Playlist playlist) async {
    final library = context.read<LibraryStore>();
    final messenger = ScaffoldMessenger.of(context);

    await library.deletePlaylist(playlist.id);
    await _playlistArtworkFileStore.delete(playlist.artworkUri);

    if (!context.mounted) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${playlist.name}.')),
    );
  }

  Future<void> _duplicatePlaylist(
    BuildContext context,
    Playlist playlist,
  ) async {
    final duplicate = await context.read<LibraryStore>().duplicatePlaylist(
      playlist.id,
    );
    if (!context.mounted || duplicate == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created ${duplicate.name}.')));
  }

  Future<void> _editCustomSmartPlaylistArtwork(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose image file'),
              subtitle: const Text(
                'Store a private PNG, JPEG, GIF, or WebP image.',
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickCustomSmartPlaylistArtworkFile(context, rule);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Set image URL'),
              subtitle: const Text('Use an http or https image URL.'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _setCustomSmartPlaylistArtworkUrl(context, rule);
              },
            ),
            if (rule.artworkUri != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove artwork'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _removeCustomSmartPlaylistArtwork(context, rule);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomSmartPlaylistArtworkFile(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await pickSingleFile(
      type: FileType.image,
      dialogTitle: 'Choose smart playlist artwork',
    );
    if (!context.mounted || file == null) {
      return;
    }
    try {
      final bytes = await readPickedFileBytes(file);
      if (!context.mounted) {
        return;
      }
      final artworkUri = await _playlistArtworkFileStore.save(bytes);
      if (!context.mounted) {
        return;
      }
      final updated = await context
          .read<LibraryStore>()
          .updateCustomSmartPlaylistArtwork(rule.id, artworkUri);
      if (!context.mounted || updated == null) {
        return;
      }
      await _playlistArtworkFileStore.delete(rule.artworkUri);
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Updated artwork for ${updated.name}.')),
        );
      }
    } on FormatException catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Exception catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not save artwork: $error')),
        );
      }
    }
  }

  Future<void> _setCustomSmartPlaylistArtworkUrl(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final initialValue =
        rule.artworkUri != null && _isNetworkImageUri(rule.artworkUri!)
        ? rule.artworkUri!.toString()
        : '';
    final value = await _promptForPlaylistArtwork(context, initialValue);
    if (!context.mounted || value == null) {
      return;
    }
    final artworkUri = Uri.tryParse(value.trim());
    if (artworkUri == null || !_isNetworkImageUri(artworkUri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter an http or https image URL.')),
      );
      return;
    }
    final updated = await context
        .read<LibraryStore>()
        .updateCustomSmartPlaylistArtwork(rule.id, artworkUri);
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(rule.artworkUri);
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Updated artwork for ${updated.name}.')),
      );
    }
  }

  Future<void> _removeCustomSmartPlaylistArtwork(
    BuildContext context,
    CustomSmartPlaylist rule,
  ) async {
    final updated = await context
        .read<LibraryStore>()
        .updateCustomSmartPlaylistArtwork(rule.id, null);
    if (!context.mounted || updated == null) {
      return;
    }
    await _playlistArtworkFileStore.delete(rule.artworkUri);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed artwork for ${updated.name}.')),
      );
    }
  }

  Future<void> _showPlaylistShareCard(
    BuildContext context,
    Playlist playlist,
  ) async {
    final tracks = context.read<LibraryStore>().tracksForPlaylist(playlist.id);
    await _showCollectionShareCard(
      context,
      kind: 'playlist',
      title: playlist.name,
      subtitle: playlist.folder.trim().isEmpty
          ? 'Your playlist'
          : playlist.folder.trim(),
      itemCount: tracks.length,
      totalDuration: tracks.fold<Duration>(
        Duration.zero,
        (total, track) => total + track.duration,
      ),
      artwork: PlaylistArtwork(playlist: playlist, tracks: tracks, size: 184),
      fileToken: playlist.id,
    );
  }

  Future<void> _showPlaylistExport(
    BuildContext context,
    Playlist playlist,
    PlaylistDocumentFormat format,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: Text(
                  'Save ${_playlistDocumentFormatLabel(format)} file',
                ),
                subtitle: const Text(
                  'Write a portable playlist to a chosen location.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _savePlaylistExportFile(context, playlist, format);
                },
              ),
              ListTile(
                leading: const Icon(Icons.code_outlined),
                title: Text(
                  'View ${_playlistDocumentFormatLabel(format)} content',
                ),
                subtitle: const Text('Inspect or copy the playlist document.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _showPlaylistExportDocument(context, playlist, format);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _savePlaylistExportFile(
    BuildContext context,
    Playlist playlist,
    PlaylistDocumentFormat format,
  ) async {
    final library = context.read<LibraryStore>();
    final document = library.exportPlaylistDocument(
      playlist.id,
      format: format,
    );
    final extension = _playlistDocumentFormatFileExtension(format);
    final fileName = playlistExportFileName(
      playlistName: playlist.name,
      extension: extension,
    );
    final messenger = ScaffoldMessenger.of(context);
    final bytes = Uint8List.fromList(utf8.encode(document));

    try {
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'Save ${_playlistDocumentFormatLabel(format)} playlist',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: <String>[extension],
        bytes: bytes,
      );
      if (outputPath == null) {
        return;
      }
      if (!Platform.isAndroid && !Platform.isIOS) {
        await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
      }
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName.')));
    } on Exception catch (error) {
      if (!context.mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save playlist file: $error')),
      );
    }
  }

  Future<void> _showPlaylistExportDocument(
    BuildContext context,
    Playlist playlist,
    PlaylistDocumentFormat format,
  ) async {
    final document = context.read<LibraryStore>().exportPlaylistDocument(
      playlist.id,
      format: format,
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Export ${_playlistDocumentFormatLabel(format)}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(document)),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSmartPlaylist(
    BuildContext context,
    SmartPlaylistType type,
  ) async {
    final player = context.read<PlayerController>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return _SmartPlaylistSheet(
          type: type,
          player: player,
          onAddToPlaylist: onAddToPlaylist,
          onLyrics: onLyrics,
        );
      },
    );
  }

  Future<void> _showCustomSmartPlaylist(
    BuildContext context,
    String ruleId,
  ) async {
    final player = context.read<PlayerController>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        return _CustomSmartPlaylistSheet(
          ruleId: ruleId,
          player: player,
          onAddToPlaylist: onAddToPlaylist,
          onLyrics: onLyrics,
        );
      },
    );
  }

  Future<void> _showPlaylist(BuildContext context, String playlistId) async {
    final player = context.read<PlayerController>();

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return _PlaylistSheet(playlistId: playlistId, player: player);
      },
    );
  }

  Future<String?> _promptForPlaylistName(
    BuildContext context, {
    required String title,
    String initialValue = '',
  }) async {
    final controller = TextEditingController(text: initialValue);

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(labelText: 'Playlist name'),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                final normalized = value.trim();
                if (normalized.isNotEmpty) {
                  Navigator.of(dialogContext).pop(normalized);
                }
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final normalized = controller.text.trim();
                  if (normalized.isNotEmpty) {
                    Navigator.of(dialogContext).pop(normalized);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _promptForPlaylistArtwork(
    BuildContext context,
    String initialValue,
  ) async {
    final controller = TextEditingController(text: initialValue);

    try {
      return showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Playlist artwork'),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Image URL',
                hintText: 'https://example.com/cover.jpg',
              ),
              autofillHints: const <String>[AutofillHints.url],
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                Navigator.of(dialogContext).pop(value);
              },
            ),
            actions: <Widget>[
              if (initialValue.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(''),
                  child: const Text('Clear'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<_CustomSmartPlaylistDraft?> _promptForCustomSmartPlaylistRule(
    BuildContext context, {
    required String title,
    CustomSmartPlaylist? initialRule,
  }) async {
    final nameController = TextEditingController(text: initialRule?.name ?? '');
    final queryController = TextEditingController(
      text: initialRule?.query ?? '',
    );
    final sourceIdController = TextEditingController(
      text: initialRule?.sourceId ?? '',
    );
    final artistController = TextEditingController(
      text: initialRule?.artist ?? '',
    );
    final albumController = TextEditingController(
      text: initialRule?.album ?? '',
    );
    final genreController = TextEditingController(
      text: initialRule?.genre ?? '',
    );
    final minimumDurationController = TextEditingController(
      text: (initialRule?.minimumDurationSeconds ?? 0).toString(),
    );
    final maximumDurationController = TextEditingController(
      text: (initialRule?.maximumDurationSeconds ?? 0).toString(),
    );
    final minimumPlayCountController = TextEditingController(
      text: (initialRule?.minimumPlayCount ?? 0).toString(),
    );
    final minimumDaysSinceLastPlayedController = TextEditingController(
      text: (initialRule?.minimumDaysSinceLastPlayed ?? 0).toString(),
    );
    final limitController = TextEditingController(
      text: (initialRule?.limit ?? 50).toString(),
    );
    var favoritesOnly = initialRule?.favoritesOnly ?? false;
    var matchMode = initialRule?.matchMode ?? CustomSmartPlaylistMatchMode.all;
    var ruleGroups = List<CustomSmartPlaylistRuleGroup>.from(
      initialRule?.ruleGroups ?? const <CustomSmartPlaylistRuleGroup>[],
    );
    var sortMode =
        initialRule?.sortMode ?? CustomSmartPlaylistSortMode.recentlyAdded;

    return showDialog<_CustomSmartPlaylistDraft>(
      context: context,
      builder: (dialogContext) {
        return _TextEditingControllerOwner(
          controllers: <TextEditingController>[
            nameController,
            queryController,
            sourceIdController,
            artistController,
            albumController,
            genreController,
            minimumDurationController,
            maximumDurationController,
            minimumPlayCountController,
            minimumDaysSinceLastPlayedController,
            limitController,
          ],
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              _CustomSmartPlaylistDraft? draftFromControllers() {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  return null;
                }

                return _CustomSmartPlaylistDraft(
                  name: name,
                  query: queryController.text.trim(),
                  sourceId: sourceIdController.text.trim(),
                  artist: artistController.text.trim(),
                  album: albumController.text.trim(),
                  genre: genreController.text.trim(),
                  minimumDurationSeconds:
                      int.tryParse(minimumDurationController.text.trim()) ?? 0,
                  maximumDurationSeconds:
                      int.tryParse(maximumDurationController.text.trim()) ?? 0,
                  favoritesOnly: favoritesOnly,
                  minimumPlayCount:
                      int.tryParse(minimumPlayCountController.text.trim()) ?? 0,
                  minimumDaysSinceLastPlayed:
                      int.tryParse(
                        minimumDaysSinceLastPlayedController.text.trim(),
                      ) ??
                      0,
                  matchMode: matchMode,
                  ruleGroups: ruleGroups,
                  sortMode: sortMode,
                  limit: int.tryParse(limitController.text.trim()) ?? 50,
                );
              }

              return AlertDialog(
                key: const Key('smart-playlist-dialog'),
                title: Text(title),
                content: SizedBox(
                  width: double.maxFinite,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        TextField(
                          key: const Key('smart-playlist-name'),
                          autofocus: true,
                          controller: nameController,
                          decoration: const InputDecoration(labelText: 'Name'),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Rule matching',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<CustomSmartPlaylistMatchMode>(
                          segments:
                              const <
                                ButtonSegment<CustomSmartPlaylistMatchMode>
                              >[
                                ButtonSegment<CustomSmartPlaylistMatchMode>(
                                  value: CustomSmartPlaylistMatchMode.all,
                                  label: Text('Match all'),
                                ),
                                ButtonSegment<CustomSmartPlaylistMatchMode>(
                                  value: CustomSmartPlaylistMatchMode.any,
                                  label: Text('Match any'),
                                ),
                              ],
                          selected: <CustomSmartPlaylistMatchMode>{matchMode},
                          onSelectionChanged: (selection) {
                            setDialogState(() => matchMode = selection.first);
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Nested rule groups',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            IconButton(
                              key: const Key('smart-playlist-add-rule-group'),
                              tooltip:
                                  ruleGroups.length >=
                                      maxCustomSmartPlaylistGroupsPerGroup
                                  ? 'Rule group limit reached'
                                  : 'Add rule group',
                              icon: const Icon(Icons.account_tree_outlined),
                              onPressed:
                                  ruleGroups.length >=
                                      maxCustomSmartPlaylistGroupsPerGroup
                                  ? null
                                  : () async {
                                      final group =
                                          await _promptForCustomSmartPlaylistRuleGroup(
                                            context,
                                          );
                                      if (group != null) {
                                        setDialogState(() {
                                          ruleGroups =
                                              <CustomSmartPlaylistRuleGroup>[
                                                ...ruleGroups,
                                                group,
                                              ];
                                        });
                                      }
                                    },
                            ),
                          ],
                        ),
                        if (ruleGroups.isEmpty)
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text('No nested groups.'),
                          )
                        else
                          for (
                            var index = 0;
                            index < ruleGroups.length;
                            index += 1
                          )
                            ListTile(
                              key: ValueKey<String>(
                                'smart-playlist-rule-group-$index',
                              ),
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.account_tree_outlined),
                              title: Text(
                                _customSmartPlaylistRuleGroupSummary(
                                  ruleGroups[index],
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'Remove rule group',
                                icon: const Icon(Icons.close),
                                onPressed: () {
                                  setDialogState(() {
                                    ruleGroups = <CustomSmartPlaylistRuleGroup>[
                                      for (
                                        var itemIndex = 0;
                                        itemIndex < ruleGroups.length;
                                        itemIndex += 1
                                      )
                                        if (itemIndex != index)
                                          ruleGroups[itemIndex],
                                    ];
                                  });
                                },
                              ),
                              onTap: () async {
                                final group =
                                    await _promptForCustomSmartPlaylistRuleGroup(
                                      context,
                                      initialGroup: ruleGroups[index],
                                    );
                                if (group != null) {
                                  setDialogState(() {
                                    ruleGroups = <CustomSmartPlaylistRuleGroup>[
                                      for (
                                        var itemIndex = 0;
                                        itemIndex < ruleGroups.length;
                                        itemIndex += 1
                                      )
                                        if (itemIndex == index)
                                          group
                                        else
                                          ruleGroups[itemIndex],
                                    ];
                                  });
                                }
                              },
                            ),
                        TextField(
                          controller: queryController,
                          decoration: const InputDecoration(
                            labelText: 'Search text',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: sourceIdController,
                          decoration: const InputDecoration(
                            labelText: 'Exact source ID',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: artistController,
                          decoration: const InputDecoration(
                            labelText: 'Exact artist',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: albumController,
                          decoration: const InputDecoration(
                            labelText: 'Exact album',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: genreController,
                          decoration: const InputDecoration(
                            labelText: 'Exact genre',
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: minimumDurationController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum duration (seconds)',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: maximumDurationController,
                          decoration: const InputDecoration(
                            labelText: 'Maximum duration (seconds)',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Favorites only'),
                          value: favoritesOnly,
                          onChanged: (value) {
                            setDialogState(() => favoritesOnly = value);
                          },
                        ),
                        TextField(
                          controller: minimumPlayCountController,
                          decoration: const InputDecoration(
                            labelText: 'Minimum plays',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                        TextField(
                          controller: minimumDaysSinceLastPlayedController,
                          decoration: const InputDecoration(
                            labelText: 'Not played in at least (days)',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                        ),
                        DropdownButtonFormField<CustomSmartPlaylistSortMode>(
                          isExpanded: true,
                          initialValue: sortMode,
                          decoration: const InputDecoration(
                            labelText: 'Sort by',
                          ),
                          items: CustomSmartPlaylistSortMode.values
                              .map(
                                (mode) => DropdownMenuItem(
                                  value: mode,
                                  child: Text(
                                    _customSmartPlaylistSortLabel(mode),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value != null) {
                              setDialogState(() => sortMode = value);
                            }
                          },
                        ),
                        TextField(
                          controller: limitController,
                          decoration: const InputDecoration(
                            labelText: 'Result limit',
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),
                  ),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const Key('smart-playlist-save'),
                    onPressed: () {
                      final draft = draftFromControllers();
                      if (draft != null) {
                        Navigator.of(dialogContext).pop(draft);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<CustomSmartPlaylistRuleGroup?> _promptForCustomSmartPlaylistRuleGroup(
    BuildContext context, {
    CustomSmartPlaylistRuleGroup? initialGroup,
    int depth = 0,
  }) async {
    assert(depth >= 0 && depth < maxCustomSmartPlaylistRuleGroupDepth);
    var matchMode = initialGroup?.matchMode ?? CustomSmartPlaylistMatchMode.all;
    var rules = List<CustomSmartPlaylistRule>.from(
      initialGroup?.rules ?? const <CustomSmartPlaylistRule>[],
    );
    var groups = List<CustomSmartPlaylistRuleGroup>.from(
      initialGroup?.groups ?? const <CustomSmartPlaylistRuleGroup>[],
    );

    return showDialog<CustomSmartPlaylistRuleGroup>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canAddRule =
                rules.length < maxCustomSmartPlaylistRulesPerGroup;
            final atMaximumDepth =
                depth + 1 >= maxCustomSmartPlaylistRuleGroupDepth;
            final canAddNestedGroup =
                !atMaximumDepth &&
                groups.length < maxCustomSmartPlaylistGroupsPerGroup;
            return AlertDialog(
              key: ValueKey<String>('smart-playlist-rule-group-dialog-$depth'),
              title: const Text('Rule group'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SegmentedButton<CustomSmartPlaylistMatchMode>(
                        key: ValueKey<String>(
                          'smart-playlist-rule-group-match-mode-$depth',
                        ),
                        segments:
                            const <ButtonSegment<CustomSmartPlaylistMatchMode>>[
                              ButtonSegment<CustomSmartPlaylistMatchMode>(
                                value: CustomSmartPlaylistMatchMode.all,
                                label: Text('Match all'),
                              ),
                              ButtonSegment<CustomSmartPlaylistMatchMode>(
                                value: CustomSmartPlaylistMatchMode.any,
                                label: Text('Match any'),
                              ),
                            ],
                        selected: <CustomSmartPlaylistMatchMode>{matchMode},
                        onSelectionChanged: (selection) {
                          setDialogState(() => matchMode = selection.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Rules',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (rules.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Add at least one rule or nested group.'),
                        )
                      else
                        for (var index = 0; index < rules.length; index += 1)
                          ListTile(
                            key: ValueKey<String>(
                              'smart-playlist-rule-$depth-$index',
                            ),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _customSmartPlaylistRuleSummary(rules[index]),
                            ),
                            trailing: IconButton(
                              tooltip: 'Remove rule',
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setDialogState(() {
                                  rules = <CustomSmartPlaylistRule>[
                                    for (
                                      var itemIndex = 0;
                                      itemIndex < rules.length;
                                      itemIndex += 1
                                    )
                                      if (itemIndex != index) rules[itemIndex],
                                  ];
                                });
                              },
                            ),
                            onTap: () async {
                              final rule =
                                  await _promptForCustomSmartPlaylistCondition(
                                    context,
                                    initialRule: rules[index],
                                  );
                              if (rule != null) {
                                setDialogState(() => rules[index] = rule);
                              }
                            },
                          ),
                      OutlinedButton.icon(
                        key: ValueKey<String>('smart-playlist-add-rule-$depth'),
                        onPressed: canAddRule
                            ? () async {
                                final rule =
                                    await _promptForCustomSmartPlaylistCondition(
                                      context,
                                    );
                                if (rule != null) {
                                  setDialogState(
                                    () => rules = <CustomSmartPlaylistRule>[
                                      ...rules,
                                      rule,
                                    ],
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.add),
                        label: Text(
                          canAddRule ? 'Add rule' : 'Rule limit reached',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nested groups',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      for (var index = 0; index < groups.length; index += 1)
                        ListTile(
                          key: ValueKey<String>(
                            'smart-playlist-nested-group-$depth-$index',
                          ),
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.account_tree_outlined),
                          title: Text(
                            _customSmartPlaylistRuleGroupSummary(groups[index]),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove nested group',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setDialogState(() {
                                groups = <CustomSmartPlaylistRuleGroup>[
                                  for (
                                    var itemIndex = 0;
                                    itemIndex < groups.length;
                                    itemIndex += 1
                                  )
                                    if (itemIndex != index) groups[itemIndex],
                                ];
                              });
                            },
                          ),
                          onTap: () async {
                            final group =
                                await _promptForCustomSmartPlaylistRuleGroup(
                                  context,
                                  initialGroup: groups[index],
                                  depth: depth + 1,
                                );
                            if (group != null) {
                              setDialogState(() => groups[index] = group);
                            }
                          },
                        ),
                      OutlinedButton.icon(
                        key: ValueKey<String>(
                          'smart-playlist-add-nested-group-$depth',
                        ),
                        onPressed: canAddNestedGroup
                            ? () async {
                                final group =
                                    await _promptForCustomSmartPlaylistRuleGroup(
                                      context,
                                      depth: depth + 1,
                                    );
                                if (group != null) {
                                  setDialogState(
                                    () =>
                                        groups = <CustomSmartPlaylistRuleGroup>[
                                          ...groups,
                                          group,
                                        ],
                                  );
                                }
                              }
                            : null,
                        icon: const Icon(Icons.account_tree_outlined),
                        label: Text(
                          atMaximumDepth
                              ? 'Maximum nesting depth reached'
                              : canAddNestedGroup
                              ? 'Add nested group'
                              : 'Nested group limit reached',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: ValueKey<String>(
                    'smart-playlist-rule-group-save-$depth',
                  ),
                  onPressed: rules.isEmpty && groups.isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                          CustomSmartPlaylistRuleGroup(
                            matchMode: matchMode,
                            rules: rules,
                            groups: groups,
                          ),
                        ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<CustomSmartPlaylistRule?> _promptForCustomSmartPlaylistCondition(
    BuildContext context, {
    CustomSmartPlaylistRule? initialRule,
  }) async {
    var field = initialRule?.field ?? CustomSmartPlaylistRuleField.artist;
    final valueController = TextEditingController(
      text: initialRule?.value ?? '',
    );
    return showDialog<CustomSmartPlaylistRule>(
      context: context,
      builder: (dialogContext) {
        return _TextEditingControllerOwner(
          controllers: <TextEditingController>[valueController],
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final isFavoriteRule =
                  field == CustomSmartPlaylistRuleField.favoritesOnly;
              return AlertDialog(
                key: const Key('smart-playlist-rule-dialog'),
                title: const Text('Rule'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<CustomSmartPlaylistRuleField>(
                      key: const Key('smart-playlist-rule-field'),
                      isExpanded: true,
                      initialValue: field,
                      decoration: const InputDecoration(labelText: 'Field'),
                      items: CustomSmartPlaylistRuleField.values
                          .map(
                            (candidate) => DropdownMenuItem(
                              value: candidate,
                              child: Text(
                                _customSmartPlaylistRuleFieldLabel(candidate),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => field = value);
                        }
                      },
                    ),
                    if (isFavoriteRule)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Matches favorite tracks.'),
                        ),
                      )
                    else
                      TextField(
                        key: const Key('smart-playlist-rule-value'),
                        controller: valueController,
                        decoration: InputDecoration(
                          labelText: _customSmartPlaylistRuleFieldLabel(field),
                        ),
                        keyboardType:
                            field ==
                                    CustomSmartPlaylistRuleField
                                        .minimumDurationSeconds ||
                                field ==
                                    CustomSmartPlaylistRuleField
                                        .maximumDurationSeconds ||
                                field ==
                                    CustomSmartPlaylistRuleField
                                        .minimumPlayCount ||
                                field ==
                                    CustomSmartPlaylistRuleField
                                        .minimumDaysSinceLastPlayed
                            ? TextInputType.number
                            : TextInputType.text,
                      ),
                  ],
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    key: const Key('smart-playlist-rule-save'),
                    onPressed: () {
                      final rule = CustomSmartPlaylistRule(
                        field: field,
                        value: isFavoriteRule ? 'true' : valueController.text,
                      ).normalized();
                      if (rule != null) {
                        Navigator.of(dialogContext).pop(rule);
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _SmartPlaylistSheet extends StatelessWidget {
  const _SmartPlaylistSheet({
    required this.type,
    required this.player,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final SmartPlaylistType type;
  final PlayerController player;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final smartPlaylist = library.smartPlaylists().firstWhere(
      (playlist) => playlist.type == type,
    );
    final tracks = library.tracksForSmartPlaylist(type);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView.separated(
            controller: controller,
            itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: Icon(_smartPlaylistIcon(type)),
                  title: Text(smartPlaylist.name),
                  subtitle: Text('${smartPlaylist.trackCount} track(s)'),
                  trailing: FilledButton.tonalIcon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _playTrackWithResume(
                              context,
                              player,
                              library,
                              tracks.first,
                              queue: tracks,
                            );
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                );
              }

              if (tracks.isEmpty) {
                return ListTile(
                  leading: Icon(_smartPlaylistIcon(type)),
                  title: const Text('No tracks yet'),
                  subtitle: Text(smartPlaylist.description),
                );
              }

              final track = tracks[index - 1];
              return TrackTile(
                track: track,
                onPlay: () => _playTrackWithResume(
                  context,
                  player,
                  library,
                  track,
                  queue: tracks,
                ),
                onStartRadio: () => unawaited(
                  _startTrackRadio(context, player, library, track),
                ),
                onSimilarTracks: () => unawaited(
                  _showSimilarTracks(
                    context,
                    track,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                onShare: () =>
                    unawaited(_copyTrackShareText(context, library, track)),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
                onEditMetadata: () =>
                    unawaited(_showTrackMetadataEditor(context, track)),
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _CustomSmartPlaylistSheet extends StatelessWidget {
  const _CustomSmartPlaylistSheet({
    required this.ruleId,
    required this.player,
    required this.onAddToPlaylist,
    required this.onLyrics,
  });

  final String ruleId;
  final PlayerController player;
  final ValueChanged<Track> onAddToPlaylist;
  final ValueChanged<Track> onLyrics;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final rule = library.customSmartPlaylistById(ruleId);
    if (rule == null) {
      return const SizedBox.shrink();
    }

    final tracks = library.tracksForCustomSmartPlaylist(ruleId);

    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView.separated(
            controller: controller,
            itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  leading: const Icon(Icons.filter_alt_outlined),
                  title: Text(rule.name),
                  subtitle: Text(
                    _customSmartPlaylistSubtitle(rule, tracks.length),
                  ),
                  trailing: FilledButton.tonalIcon(
                    onPressed: tracks.isEmpty
                        ? null
                        : () {
                            Navigator.of(context).pop();
                            _playTrackWithResume(
                              context,
                              player,
                              library,
                              tracks.first,
                              queue: tracks,
                            );
                          },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                );
              }

              if (tracks.isEmpty) {
                return const ListTile(
                  leading: Icon(Icons.filter_alt_outlined),
                  title: Text('No matching tracks'),
                );
              }

              final track = tracks[index - 1];
              return TrackTile(
                track: track,
                onPlay: () => _playTrackWithResume(
                  context,
                  player,
                  library,
                  track,
                  queue: tracks,
                ),
                onStartRadio: () => unawaited(
                  _startTrackRadio(context, player, library, track),
                ),
                onSimilarTracks: () => unawaited(
                  _showSimilarTracks(
                    context,
                    track,
                    onAddToPlaylist: onAddToPlaylist,
                    onLyrics: onLyrics,
                  ),
                ),
                onShare: () =>
                    unawaited(_copyTrackShareText(context, library, track)),
                onFavorite: () => library.toggleFavorite(track.id),
                onAddToPlaylist: () => onAddToPlaylist(track),
                onLyrics: () => onLyrics(track),
                onEditMetadata: () =>
                    unawaited(_showTrackMetadataEditor(context, track)),
                onEditArtwork: track.sourceId == 'local'
                    ? () => unawaited(_editTrackArtwork(context, track))
                    : null,
                onRemove: () => library.removeTrack(track.id),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistSheet extends StatefulWidget {
  const _PlaylistSheet({required this.playlistId, required this.player});

  final String playlistId;
  final PlayerController player;

  @override
  State<_PlaylistSheet> createState() => _PlaylistSheetState();
}

class _PlaylistSheetState extends State<_PlaylistSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryStore>(
      builder: (context, library, _) {
        final playlist = library.playlistById(widget.playlistId);
        if (playlist == null) {
          return const SizedBox.shrink();
        }

        final allTracks = library.tracksForPlaylist(widget.playlistId);
        final tracks = library.tracksForPlaylist(
          widget.playlistId,
          query: _query,
        );
        final trackEntries = tracks
            .map(
              (track) => MapEntry<int, Track>(
                allTracks.indexWhere((candidate) => candidate.id == track.id),
                track,
              ),
            )
            .where((entry) => entry.key != -1)
            .toList(growable: false);
        final hasQuery = _query.trim().isNotEmpty;

        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(
                leading: PlaylistArtwork(
                  playlist: playlist,
                  tracks: allTracks,
                  size: 48,
                ),
                title: Text(playlist.name),
                subtitle: Text(
                  hasQuery
                      ? '${tracks.length} of ${playlist.trackCount} track(s)'
                      : '${playlist.trackCount} track(s)',
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: tracks.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _playTrackWithResume(
                            context,
                            widget.player,
                            library,
                            tracks.first,
                            queue: tracks,
                          );
                        },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play'),
                ),
              ),
              if (allTracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'Find in playlist',
                    leading: const Icon(Icons.search),
                    trailing: <Widget>[
                      if (hasQuery)
                        IconButton(
                          tooltip: 'Clear playlist search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear),
                        ),
                    ],
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              const Divider(height: 1),
              if (allTracks.isEmpty)
                const ListTile(
                  leading: Icon(Icons.playlist_remove),
                  title: Text('No tracks yet'),
                  subtitle: Text('Add tracks from the Library tab.'),
                )
              else if (trackEntries.isEmpty)
                const ListTile(
                  leading: Icon(Icons.search_off),
                  title: Text('No matching tracks'),
                  subtitle: Text('Try another title, artist, or album.'),
                )
              else
                for (final entry in trackEntries)
                  ListTile(
                    leading: const Icon(Icons.music_note_outlined),
                    title: Text(entry.value.title),
                    subtitle: Text(
                      '${entry.value.artist} · ${entry.value.album}',
                    ),
                    trailing: PopupMenuButton<_PlaylistTrackAction>(
                      onSelected: (action) {
                        switch (action) {
                          case _PlaylistTrackAction.moveUp:
                            library.moveTrackInPlaylist(
                              playlist.id,
                              entry.key,
                              entry.key - 1,
                            );
                            break;
                          case _PlaylistTrackAction.moveDown:
                            library.moveTrackInPlaylist(
                              playlist.id,
                              entry.key,
                              entry.key + 1,
                            );
                            break;
                          case _PlaylistTrackAction.editMetadata:
                            unawaited(
                              _showTrackMetadataEditor(context, entry.value),
                            );
                            break;
                          case _PlaylistTrackAction.remove:
                            library.removeTrackFromPlaylist(
                              playlist.id,
                              entry.value.id,
                            );
                            break;
                        }
                      },
                      itemBuilder: (context) =>
                          <PopupMenuEntry<_PlaylistTrackAction>>[
                            PopupMenuItem(
                              value: _PlaylistTrackAction.moveUp,
                              enabled: entry.key > 0,
                              child: const ListTile(
                                leading: Icon(Icons.arrow_upward),
                                title: Text('Move up'),
                              ),
                            ),
                            PopupMenuItem(
                              value: _PlaylistTrackAction.moveDown,
                              enabled: entry.key < allTracks.length - 1,
                              child: const ListTile(
                                leading: Icon(Icons.arrow_downward),
                                title: Text('Move down'),
                              ),
                            ),
                            const PopupMenuItem(
                              value: _PlaylistTrackAction.editMetadata,
                              child: ListTile(
                                leading: Icon(Icons.edit_outlined),
                                title: Text('Edit metadata'),
                              ),
                            ),
                            const PopupMenuItem(
                              value: _PlaylistTrackAction.remove,
                              child: ListTile(
                                leading: Icon(Icons.playlist_remove),
                                title: Text('Remove from playlist'),
                              ),
                            ),
                          ],
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _SmartPlaylistCard extends StatelessWidget {
  const _SmartPlaylistCard({required this.smartPlaylist, required this.onOpen});

  final SmartPlaylist smartPlaylist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(_smartPlaylistIcon(smartPlaylist.type)),
        title: Text(smartPlaylist.name),
        subtitle: Text(
          '${smartPlaylist.trackCount} track(s) · '
          '${smartPlaylist.description}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _CustomSmartPlaylistArtwork extends StatelessWidget {
  const _CustomSmartPlaylistArtwork({required this.rule, required this.tracks});

  final CustomSmartPlaylist rule;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final artworkUri = rule.artworkUri;
    if (artworkUri != null) {
      return TrackArtwork(
        artworkUri: artworkUri,
        size: 40,
        borderRadius: 10,
        fallbackIcon: Icons.filter_alt_outlined,
      );
    }
    if (tracks.isNotEmpty) {
      final track = tracks.first;
      return TrackArtwork(
        artworkUri: track.artworkUri,
        providerId: track.sourceId,
        providerArtworkId: track.providerArtworkId,
        providerArtworkVersion: track.providerArtworkVersion,
        artworkCrop: track.artworkCrop,
        size: 40,
        borderRadius: 10,
        fallbackIcon: Icons.filter_alt_outlined,
      );
    }
    return const Icon(Icons.filter_alt_outlined);
  }
}

class _CustomSmartPlaylistCard extends StatelessWidget {
  const _CustomSmartPlaylistCard({
    required this.rule,
    required this.tracks,
    required this.onOpen,
    required this.onEdit,
    required this.onArtwork,
    required this.onCopyImportLink,
    this.onPrivateShare,
    this.onRefreshPublicSubscription,
    this.onUnsubscribePublicSubscription,
    required this.onDuplicate,
    required this.onDelete,
  });

  final CustomSmartPlaylist rule;
  final List<Track> tracks;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onArtwork;
  final VoidCallback onCopyImportLink;
  final VoidCallback? onPrivateShare;
  final VoidCallback? onRefreshPublicSubscription;
  final VoidCallback? onUnsubscribePublicSubscription;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: _CustomSmartPlaylistArtwork(rule: rule, tracks: tracks),
        title: Text(rule.name),
        subtitle: Text(_customSmartPlaylistSubtitle(rule, tracks.length)),
        onTap: onOpen,
        trailing: PopupMenuButton<_CustomSmartPlaylistAction>(
          key: ValueKey<String>('smart-playlist-actions-${rule.id}'),
          onSelected: (action) {
            switch (action) {
              case _CustomSmartPlaylistAction.edit:
                onEdit();
                break;
              case _CustomSmartPlaylistAction.artwork:
                onArtwork();
                break;
              case _CustomSmartPlaylistAction.copyImportLink:
                onCopyImportLink();
                break;
              case _CustomSmartPlaylistAction.privateShare:
                onPrivateShare?.call();
                break;
              case _CustomSmartPlaylistAction.refreshPublicSubscription:
                onRefreshPublicSubscription?.call();
                break;
              case _CustomSmartPlaylistAction.unsubscribePublicSubscription:
                onUnsubscribePublicSubscription?.call();
                break;
              case _CustomSmartPlaylistAction.duplicate:
                onDuplicate();
                break;
              case _CustomSmartPlaylistAction.delete:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) =>
              <PopupMenuEntry<_CustomSmartPlaylistAction>>[
                PopupMenuItem(
                  value: _CustomSmartPlaylistAction.edit,
                  child: ListTile(
                    leading: Icon(Icons.tune),
                    title: Text('Edit rules'),
                  ),
                ),
                PopupMenuItem(
                  value: _CustomSmartPlaylistAction.artwork,
                  child: ListTile(
                    leading: Icon(Icons.image_outlined),
                    title: Text('Artwork'),
                  ),
                ),
                PopupMenuItem(
                  value: _CustomSmartPlaylistAction.copyImportLink,
                  child: ListTile(
                    leading: Icon(Icons.link_outlined),
                    title: Text('Copy import link'),
                  ),
                ),
                if (onPrivateShare != null)
                  const PopupMenuItem(
                    value: _CustomSmartPlaylistAction.privateShare,
                    child: ListTile(
                      leading: Icon(Icons.group_add_outlined),
                      title: Text('Private collaboration'),
                    ),
                  ),
                if (onRefreshPublicSubscription != null)
                  const PopupMenuItem(
                    value: _CustomSmartPlaylistAction.refreshPublicSubscription,
                    child: ListTile(
                      leading: Icon(Icons.refresh_outlined),
                      title: Text('Refresh public subscription'),
                    ),
                  ),
                if (onUnsubscribePublicSubscription != null)
                  const PopupMenuItem(
                    value: _CustomSmartPlaylistAction
                        .unsubscribePublicSubscription,
                    child: ListTile(
                      leading: Icon(Icons.bookmark_remove_outlined),
                      title: Text('Unsubscribe public link'),
                    ),
                  ),
                PopupMenuItem(
                  value: _CustomSmartPlaylistAction.duplicate,
                  child: ListTile(
                    leading: Icon(Icons.copy_outlined),
                    title: Text('Duplicate'),
                  ),
                ),
                PopupMenuItem(
                  value: _CustomSmartPlaylistAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete'),
                  ),
                ),
              ],
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.tracks,
    required this.onOpen,
    required this.onExport,
    required this.onShare,
    required this.onCopyImportLink,
    required this.onShareCard,
    required this.onArtwork,
    required this.onDuplicate,
    required this.onRename,
    required this.onMoveToFolder,
    required this.onDelete,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final VoidCallback onOpen;
  final ValueChanged<PlaylistDocumentFormat> onExport;
  final VoidCallback onShare;
  final VoidCallback onCopyImportLink;
  final VoidCallback onShareCard;
  final VoidCallback onArtwork;
  final VoidCallback onDuplicate;
  final VoidCallback onRename;
  final VoidCallback onMoveToFolder;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: PlaylistArtwork(playlist: playlist, tracks: tracks),
        title: Text(playlist.name),
        subtitle: Text(
          playlist.folder.trim().isEmpty
              ? '${playlist.trackCount} track(s)'
              : '${playlist.folder} · ${playlist.trackCount} track(s)',
        ),
        onTap: onOpen,
        trailing: PopupMenuButton<_PlaylistAction>(
          onSelected: (action) {
            switch (action) {
              case _PlaylistAction.exportJson:
                onExport(PlaylistDocumentFormat.json);
                break;
              case _PlaylistAction.exportM3u:
                onExport(PlaylistDocumentFormat.m3u);
                break;
              case _PlaylistAction.exportPls:
                onExport(PlaylistDocumentFormat.pls);
                break;
              case _PlaylistAction.exportXspf:
                onExport(PlaylistDocumentFormat.xspf);
                break;
              case _PlaylistAction.exportWpl:
                onExport(PlaylistDocumentFormat.wpl);
                break;
              case _PlaylistAction.exportCsv:
                onExport(PlaylistDocumentFormat.csv);
                break;
              case _PlaylistAction.share:
                onShare();
                break;
              case _PlaylistAction.copyImportLink:
                onCopyImportLink();
                break;
              case _PlaylistAction.shareCard:
                onShareCard();
                break;
              case _PlaylistAction.duplicate:
                onDuplicate();
                break;
              case _PlaylistAction.rename:
                onRename();
                break;
              case _PlaylistAction.folder:
                onMoveToFolder();
                break;
              case _PlaylistAction.artwork:
                onArtwork();
                break;
              case _PlaylistAction.delete:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => const <PopupMenuEntry<_PlaylistAction>>[
            PopupMenuItem(
              value: _PlaylistAction.exportJson,
              child: ListTile(
                leading: Icon(Icons.data_object),
                title: Text('Export JSON'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.exportM3u,
              child: ListTile(
                leading: Icon(Icons.queue_music),
                title: Text('Export M3U'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.exportPls,
              child: ListTile(
                leading: Icon(Icons.format_list_numbered),
                title: Text('Export PLS'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.exportXspf,
              child: ListTile(
                leading: Icon(Icons.code_outlined),
                title: Text('Export XSPF'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.exportWpl,
              child: ListTile(
                leading: Icon(Icons.library_music_outlined),
                title: Text('Export WPL'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.exportCsv,
              child: ListTile(
                leading: Icon(Icons.table_chart_outlined),
                title: Text('Export CSV'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.share,
              child: ListTile(
                leading: Icon(Icons.ios_share),
                title: Text('Copy share text'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.copyImportLink,
              child: ListTile(
                leading: Icon(Icons.link_outlined),
                title: Text('Copy import link'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.shareCard,
              child: ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Save share card'),
              ),
            ),
            PopupMenuDivider(),
            PopupMenuItem(
              value: _PlaylistAction.duplicate,
              child: ListTile(
                leading: Icon(Icons.copy_outlined),
                title: Text('Duplicate'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.rename,
              child: ListTile(
                leading: Icon(Icons.drive_file_rename_outline),
                title: Text('Rename'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.folder,
              child: ListTile(
                leading: Icon(Icons.drive_folder_upload_outlined),
                title: Text('Move to folder'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.artwork,
              child: ListTile(
                leading: Icon(Icons.image_outlined),
                title: Text('Artwork'),
              ),
            ),
            PopupMenuItem(
              value: _PlaylistAction.delete,
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Delete'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylists extends StatelessWidget {
  const _EmptyPlaylists({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          const Icon(Icons.queue_music, size: 56),
          const SizedBox(height: 16),
          Text(
            'No playlists yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'Create manual playlists and add tracks from your library.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Create playlist'),
          ),
        ],
      ),
    );
  }
}

bool _isNetworkImageUri(Uri uri) {
  return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
}

enum _PlaylistAction {
  exportJson,
  exportM3u,
  exportPls,
  exportXspf,
  exportWpl,
  exportCsv,
  share,
  copyImportLink,
  shareCard,
  duplicate,
  rename,
  folder,
  artwork,
  delete,
}

enum _CustomSmartPlaylistAction {
  edit,
  artwork,
  copyImportLink,
  privateShare,
  refreshPublicSubscription,
  unsubscribePublicSubscription,
  duplicate,
  delete,
}

enum _PlaylistTrackAction { moveUp, moveDown, editMetadata, remove }
