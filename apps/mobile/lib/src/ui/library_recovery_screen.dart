import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/file_picker_adapter.dart';
import '../data/library_store.dart';
import '../domain/backup_file_document.dart';

class LibraryRecoveryScreen extends StatefulWidget {
  const LibraryRecoveryScreen({
    super.key,
    required this.library,
    this.chooseBackup,
    this.saveRecovery,
  });
  final LibraryStore library;
  final Future<String?> Function()? chooseBackup;
  final Future<void> Function(String)? saveRecovery;

  @override
  State<LibraryRecoveryScreen> createState() => _LibraryRecoveryScreenState();
}

class _LibraryRecoveryScreenState extends State<LibraryRecoveryScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final data = await widget.library.exportRecoveryJson();
    if (widget.saveRecovery != null) {
      await widget.saveRecovery!(data);
      return;
    }
    final bytes = Uint8List.fromList(utf8.encode(data));
    final uri = await FilePicker.saveFile(
      dialogTitle: 'Save library recovery data',
      fileName: 'aethertune-recovery.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    if (uri != null && !Platform.isAndroid && !Platform.isIOS) {
      await File.fromUri(uri).writeAsBytes(bytes, flush: true);
    }
  }

  Future<void> _import() async {
    String? backup;
    if (widget.chooseBackup != null) {
      backup = await widget.chooseBackup!();
    } else {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: [aetherTuneBackupFileExtension],
      );
      if (files.isNotEmpty) {
        backup = decodeAetherTuneBackupFile(
          await readPickedFileBytes(files.first),
        );
      }
    }
    if (backup != null) await widget.library.restoreBackupForRecovery(backup);
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Start an empty library?'),
        content: const Text(
          'The current library will be replaced. Existing snapshot files are kept in the recovery archive. Export recovery data first to keep a separate copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start empty'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _run(widget.library.resetAfterLoadFailure);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Library recovery')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.library.loadError ?? 'Your library needs recovery.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_busy) const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : () => _run(widget.library.load),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(_export),
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Export recovery data'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.library.recoverPreviousLibrary),
                      icon: const Icon(Icons.history),
                      label: const Text('Restore previous snapshot'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(_import),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Import backup'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _reset,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Start empty library'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class LibrarySaveFailureNotice extends StatelessWidget {
  const LibrarySaveFailureNotice({
    super.key,
    required this.library,
    required this.child,
  });
  final LibraryStore library;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (library.saveError == null) return child;
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          ConstrainedBox(
            // Long errors and large text must leave room for the current page.
            constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          library.saveError!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: library.reloadSavedLibrary,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reload saved library'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
