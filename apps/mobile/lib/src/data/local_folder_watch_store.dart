import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../domain/lyrics_document.dart';
import 'library_store.dart';
import 'local_folder_scanner.dart';

typedef LocalFolderScan = Future<LocalFolderScanResult> Function(
  String rootPath, {
  DateTime? importedAt,
});

typedef LocalFolderWatchStreamFactory = Stream<String> Function(String rootPath);

/// Keeps user-selected local folders reconciled after filesystem changes.
///
/// The service intentionally owns no persistent data. `LibraryStore` retains
/// the selected roots while this object owns only process-lifetime watchers.
class LocalFolderWatchStore extends ChangeNotifier {
  LocalFolderWatchStore({
    LocalFolderScan? scanner,
    LocalFolderWatchStreamFactory? watchStreamFactory,
    this.debounce = const Duration(milliseconds: 750),
  })  : _scanner = scanner ?? const LocalFolderScanner().scan,
        _watchStreamFactory = watchStreamFactory ?? _watchDirectory;

  final LocalFolderScan _scanner;
  final LocalFolderWatchStreamFactory _watchStreamFactory;
  final Duration debounce;
  final Map<String, StreamSubscription<String>> _subscriptions =
      <String, StreamSubscription<String>>{};
  final Map<String, Timer> _debounceTimers = <String, Timer>{};
  final Set<String> _refreshingRoots = <String>{};
  final Set<String> _refreshRequested = <String>{};
  final Map<String, DateTime> _lastRefreshedAt = <String, DateTime>{};
  final Map<String, String> _errorsByRoot = <String, String>{};
  LibraryStore? _library;

  bool isRefreshing(String rootPath) => _refreshingRoots.contains(rootPath);

  DateTime? lastRefreshedAt(String rootPath) => _lastRefreshedAt[rootPath];

  String? errorFor(String rootPath) => _errorsByRoot[rootPath];

  void updateLibrary(LibraryStore library) {
    _library = library;
    _synchronizeSubscriptions();
  }

  Future<void> refresh(String rootPath) async {
    final library = _library;
    if (library == null || !library.watchedLocalFolderPaths.contains(rootPath)) {
      return;
    }
    if (_refreshingRoots.contains(rootPath)) {
      _refreshRequested.add(rootPath);
      return;
    }

    _refreshingRoots.add(rootPath);
    _errorsByRoot.remove(rootPath);
    notifyListeners();
    try {
      final result = await _scanner(rootPath, importedAt: DateTime.now());
      await library.reconcileWatchedLocalFolder(
        rootPath,
        tracks: result.tracks,
        sidecarLyricsByTrackId: result.sidecarLyricsByTrackId,
        pruneMissing: result.inaccessibleDirectoryCount == 0,
      );
      _lastRefreshedAt[rootPath] = DateTime.now();
    } on Object catch (error) {
      _errorsByRoot[rootPath] = _safeErrorMessage(error);
    } finally {
      _refreshingRoots.remove(rootPath);
      notifyListeners();
    }

    if (_refreshRequested.remove(rootPath)) {
      unawaited(refresh(rootPath));
    }
  }

  void _synchronizeSubscriptions() {
    final library = _library;
    if (library == null || !library.loaded) {
      return;
    }
    final roots = library.watchedLocalFolderPaths.toSet();
    final removedRoots = _subscriptions.keys
        .where((root) => !roots.contains(root))
        .toList(growable: false);
    for (final root in removedRoots) {
      _cancelRoot(root);
    }

    for (final root in roots) {
      if (_subscriptions.containsKey(root)) {
        continue;
      }
      try {
        _subscriptions[root] = _watchStreamFactory(root).listen(
              (changedPath) => _onFilesystemChange(root, changedPath),
              onError: (Object error, StackTrace _) {
                _errorsByRoot[root] = _safeErrorMessage(error);
                notifyListeners();
              },
            );
        unawaited(refresh(root));
      } on Object catch (error) {
        _errorsByRoot[root] = _safeErrorMessage(error);
        notifyListeners();
      }
    }
  }

  void _onFilesystemChange(String rootPath, String changedPath) {
    if (!_isRelevantChange(changedPath)) {
      return;
    }
    _debounceTimers.remove(rootPath)?.cancel();
    _debounceTimers[rootPath] = Timer(debounce, () {
      _debounceTimers.remove(rootPath);
      unawaited(refresh(rootPath));
    });
  }

  bool _isRelevantChange(String changedPath) {
    final extension = path.extension(changedPath).toLowerCase();
    if (extension.isEmpty) {
      return true;
    }
    return supportedLocalAudioExtensions.contains(extension) ||
        isSupportedLyricsDocumentName(path.basename(changedPath));
  }

  void _cancelRoot(String rootPath) {
    _debounceTimers.remove(rootPath)?.cancel();
    unawaited(_subscriptions.remove(rootPath)?.cancel());
    _refreshingRoots.remove(rootPath);
    _refreshRequested.remove(rootPath);
    _lastRefreshedAt.remove(rootPath);
    _errorsByRoot.remove(rootPath);
  }

  @override
  void dispose() {
    for (final rootPath in _subscriptions.keys.toList(growable: false)) {
      _cancelRoot(rootPath);
    }
    super.dispose();
  }
}

Stream<String> _watchDirectory(String rootPath) {
  return Directory(rootPath)
      .watch(recursive: true)
      .map((event) => event.path);
}

String _safeErrorMessage(Object error) {
  final message = error.toString().trim();
  return message.isEmpty ? 'Folder monitoring failed.' : message;
}
