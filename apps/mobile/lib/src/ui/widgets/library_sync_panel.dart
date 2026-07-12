import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/library_sync_client.dart';
import '../../data/library_sync_store.dart';
import '../../domain/library_sync_account.dart';

enum _LibrarySyncConflictChoice { server, merge, local }

class LibrarySyncPanel extends StatelessWidget {
  const LibrarySyncPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<LibrarySyncStore>();
    final library = context.watch<LibraryStore>();
    final account = sync.account;
    final actionsEnabled = sync.loaded && !sync.busy && !library.offlineModeEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          key: const Key('library-sync-status'),
          leading: Icon(
            sync.isConfigured ? Icons.cloud_done_outlined : Icons.cloud_outlined,
          ),
          title: const Text('Cross-device library sync'),
          subtitle: Text(_statusText(sync)),
          trailing: IconButton(
            key: const Key('library-sync-configure'),
            tooltip: sync.isConfigured ? 'Edit sync server' : 'Configure sync server',
            onPressed: actionsEnabled
                ? () => _configure(context, account: account)
                : null,
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
        if (sync.busy)
          const LinearProgressIndicator(key: Key('library-sync-progress')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sync server configured.')),
    );
  }

  static Future<void> _upload(BuildContext context) async {
    final sync = context.read<LibrarySyncStore>();
    final library = context.read<LibraryStore>();
    try {
      final result = await sync.push(library);
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
          final result = await sync.pull(library);
          if (context.mounted) {
            _showSuccess(
              context,
              'Downloaded server revision ${result.revision}.',
            );
          }
        } else if (choice == _LibrarySyncConflictChoice.merge) {
          final result = await sync.mergeAndPush(library);
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
            onPressed: () => Navigator.of(dialogContext).pop(
              _LibrarySyncConflictChoice.server,
            ),
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Use server copy'),
          ),
          OutlinedButton.icon(
            key: const Key('library-sync-merge'),
            onPressed: () => Navigator.of(dialogContext).pop(
              _LibrarySyncConflictChoice.merge,
            ),
            icon: const Icon(Icons.merge_type),
            label: const Text('Merge both'),
          ),
          FilledButton.icon(
            key: const Key('library-sync-use-local'),
            onPressed: () => Navigator.of(dialogContext).pop(
              _LibrarySyncConflictChoice.local,
            ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static void _showError(BuildContext context, Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

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
                        : () => setState(
                              () => _obscureToken = !_obscureToken,
                            ),
                    icon: Icon(
                      _obscureToken ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
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
                  subtitle: const Text('The sync token will be sent without TLS.'),
                  value: _allowInsecureHttp,
                  onChanged: _saving
                      ? null
                      : (value) => setState(
                            () => _allowInsecureHttp = value ?? false,
                          ),
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
      await context.read<LibrarySyncStore>().testAndSave(
            context.read<LibraryStore>(),
            account,
            token,
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = token.isEmpty
            ? error.toString()
            : error.toString().replaceAll(token, '[redacted]');
      });
    }
  }
}
