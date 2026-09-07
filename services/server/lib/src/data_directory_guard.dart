import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

const serverDataDirectoryLockFileName = '.server.lock';
const serverInstanceLockFileName = '.server.instance.lock';
const serverBackupIntentLockFileName = '.backup.intent.lock';
const serverBackupSnapshotLockFileName = '.backup.snapshot.lock';

/// One instance per server isolate. Request admission is serialized because
/// POSIX record locks belong to a process, not to an individual request/handle.
final class ServerDataDirectoryGuard {
  ServerDataDirectoryGuard._(this._directory, this._handles);
  static final Set<String> _openPaths = {};
  final String _directory;
  final List<RandomAccessFile> _handles;
  Future<void> _tail = Future.value();
  Completer<void>? _drained;
  int _active = 0;
  bool _initializing = true;
  bool _closing = false;

  static Future<ServerDataDirectoryGuard> open(Directory directory) async {
    await directory.create(recursive: true);
    final canonical = await directory.resolveSymbolicLinks();
    if (!_openPaths.add(canonical)) {
      throw const FileSystemException('Server data directory is already open.');
    }
    final handles = <RandomAccessFile>[];
    try {
      for (final name in [
        serverInstanceLockFileName,
        serverDataDirectoryLockFileName,
        serverBackupIntentLockFileName,
        serverBackupSnapshotLockFileName,
      ]) {
        final file = File(p.join(canonical, name));
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type != FileSystemEntityType.file &&
            type != FileSystemEntityType.notFound) {
          throw FileSystemException(
            'Server lock must be a regular file.',
            file.path,
          );
        }
        handles.add(await file.open(mode: FileMode.append));
        if (handles.length == 1) {
          await handles.last.lock(FileLock.exclusive, 0, 1);
        } else if (handles.length == 2) {
          // Legacy binaries hold this file exclusively. Shared ownership also
          // lets backups prevent an incompatible binary starting mid-snapshot.
          await handles.last.lock(FileLock.shared, 0, 1);
        }
      }
      final guard = ServerDataDirectoryGuard._(canonical, handles);
      if (!await guard._enter()) {
        throw const FileSystemException('A server backup is in progress.');
      }
      return guard;
    } on Object {
      for (final handle in handles.reversed) {
        await handle.close();
      }
      _openPaths.remove(canonical);
      rethrow;
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<bool> _enter() => _serialized(() async {
    if (_closing) return false;
    final intent = _handles[2];
    try {
      await intent.lock(FileLock.shared, 0, 1);
    } on FileSystemException {
      return false;
    }
    try {
      if (_active == 0) {
        try {
          await _handles[3].lock(FileLock.shared, 0, 1);
        } on FileSystemException {
          return false;
        }
      }
      _active++;
      return true;
    } finally {
      await intent.unlock(0, 1);
    }
  });

  Future<void> _leave() => _serialized(() async {
    _active--;
    if (_active == 0) {
      await _handles[3].unlock(0, 1);
      _drained?.complete();
      _drained = null;
    }
  });

  Future<void> initializationComplete() async {
    if (_initializing) {
      _initializing = false;
      await _leave();
    }
  }

  Middleware get middleware =>
      (inner) => (request) async {
        // Liveness must not trigger restarts during a deliberate snapshot pause.
        if (request.method == 'GET' && request.url.path == 'health') {
          return inner(request);
        }
        if (!await _enter()) {
          return Response(
            503,
            body: '{"error":"backup_in_progress"}',
            headers: {
              'content-type': 'application/json; charset=utf-8',
              'cache-control': 'no-store',
              'retry-after': '1',
            },
          );
        }
        try {
          return await inner(request);
        } finally {
          await _leave();
        }
      };

  Future<void> close() async {
    _closing = true;
    await initializationComplete();
    await _tail;
    if (_active > 0) {
      _drained ??= Completer<void>();
      await _drained!.future;
    }
    for (final handle in _handles.reversed) {
      await handle.close();
    }
    _openPaths.remove(_directory);
  }
}
