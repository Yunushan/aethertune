import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

final class LibraryStorageException implements Exception {
  const LibraryStorageException(this.message);
  final String message;
  @override
  String toString() => message;
}

final class LibraryStorageConflict implements Exception {
  const LibraryStorageConflict();
  @override
  String toString() =>
      'The saved library changed in another process. Reload it before making more changes.';
}

final class LibraryStoredSnapshot {
  LibraryStoredSnapshot(this.revision, Map<String, Object?> values)
    : values = Map.unmodifiable(values);
  final String revision;
  final Map<String, Object?> values;
}

abstract interface class LibraryStorage {
  Future<LibraryStoredSnapshot?> read();
  Future<LibraryStoredSnapshot> write(
    Map<String, Object?> values, {
    required String? expectedRevision,
  });
  Future<LibraryStoredSnapshot> replaceForRecovery(Map<String, Object?> values);
  Future<void> recoverPrevious();
  Future<Map<String, Object?>> recoveryData();
}

/// All library sections share one commit boundary. Previous bytes remain
/// available for explicit recovery; corrupt state is never silently replaced.
final class FileLibraryStorage implements LibraryStorage {
  FileLibraryStorage({required this._directory, this.beforeCommit});

  static const maximumSnapshotBytes = 64 * 1024 * 1024;
  final Future<Directory> Function() _directory;
  // Test-only pause/failure hook before either snapshot is replaced.
  final Future<void> Function(File pending)? beforeCommit;
  static final Map<String, Future<void>> _queues = {};
  static final Random _random = Random.secure();

  Future<T> _locked<T>(Future<T> Function(Directory) action) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final canonical = await directory.resolveSymbolicLinks();
    final previous = _queues[canonical] ?? Future<void>.value();
    final gate = Completer<void>();
    _queues[canonical] = gate.future;
    await previous;
    Database? lock;
    try {
      final lockFile = File(p.join(canonical, 'library.lock.sqlite'));
      await _rejectLink(lockFile);
      // SQLite coordinates locks across both isolates and processes. Dart's
      // File.lock alone cannot exclude other isolates on Linux/macOS.
      lock = sqlite3.open(lockFile.path);
      final deadline = Stopwatch()..start();
      while (true) {
        try {
          lock.execute('BEGIN EXCLUSIVE');
          break;
        } on SqliteException catch (error) {
          if (error.resultCode != 5 && error.resultCode != 6) rethrow;
          if (deadline.elapsed >= const Duration(seconds: 10)) {
            throw const LibraryStorageException(
              'Library storage is busy. Try again.',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }
      return await action(Directory(canonical));
    } finally {
      try {
        lock?.close();
      } finally {
        gate.complete();
        if (identical(_queues[canonical], gate.future)) {
          _queues.remove(canonical);
        }
      }
    }
  }

  File _file(Directory directory, String name) =>
      File(p.join(directory.path, name));

  Future<String?> _readRaw(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw const LibraryStorageException(
        'Library storage must contain regular files, not links.',
      );
    }
    if (await file.length() > maximumSnapshotBytes) {
      throw const LibraryStorageException(
        'The saved library exceeds the supported snapshot size.',
      );
    }
    return file.readAsString();
  }

  LibraryStoredSnapshot _decode(String raw) {
    final document = jsonDecode(raw);
    if (document is! Map ||
        document['format'] != 1 ||
        document['payload'] is! String ||
        document['checksum'] is! String ||
        document['generation'] is! String) {
      throw const FormatException('Invalid library snapshot envelope.');
    }
    final payload = document['payload'] as String;
    if (sha256.convert(utf8.encode(payload)).toString() !=
        document['checksum']) {
      throw const FormatException('Library snapshot checksum mismatch.');
    }
    final values = jsonDecode(payload);
    if (values is! Map) {
      throw const FormatException('Invalid library snapshot data.');
    }
    return LibraryStoredSnapshot(
      sha256.convert(utf8.encode(raw)).toString(),
      Map<String, Object?>.from(values),
    );
  }

  @override
  Future<LibraryStoredSnapshot?> read() => _locked((directory) async {
    final raw = await _readRaw(_file(directory, 'library.json'));
    if (raw == null) {
      if (await _file(directory, 'library.previous.json').exists()) {
        throw const LibraryStorageException(
          'The current library is missing. A previous snapshot is available for recovery.',
        );
      }
      return null;
    }
    return _decode(raw);
  });

  @override
  Future<LibraryStoredSnapshot> write(
    Map<String, Object?> values, {
    required String? expectedRevision,
  }) => _locked((directory) async {
    final raw = await _readRaw(_file(directory, 'library.json'));
    final current = raw == null ? null : _decode(raw);
    if (current?.revision != expectedRevision) {
      throw const LibraryStorageConflict();
    }
    return _commit(directory, values, previousRaw: raw);
  });

  Future<LibraryStoredSnapshot> _commit(
    Directory directory,
    Map<String, Object?> values, {
    String? previousRaw,
  }) async {
    final payload = jsonEncode(values);
    final raw = jsonEncode({
      'format': 1,
      'generation': List.generate(
        16,
        (_) => _random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
      'checksum': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
    final bytes = utf8.encode(raw);
    if (bytes.length > maximumSnapshotBytes) {
      throw const LibraryStorageException(
        'The library exceeds the supported snapshot size.',
      );
    }
    final pending = _file(directory, 'library.pending');
    await _rejectLink(pending);
    await pending.writeAsBytes(bytes, flush: true);
    // Injection happens at the actual pre-commit boundary for crash/disk tests.
    await beforeCommit?.call(pending);
    if (previousRaw != null) {
      final previousPending = _file(directory, 'library.previous.pending');
      await _rejectLink(previousPending);
      await previousPending.writeAsString(previousRaw, flush: true);
      await _rejectLink(_file(directory, 'library.previous.json'));
      await previousPending.rename(
        _file(directory, 'library.previous.json').path,
      );
    }
    final target = _file(directory, 'library.json');
    await _rejectLink(target);
    await pending.rename(target.path);
    // No fallible I/O after commit: a successful replacement must not be
    // reported to the caller as an unsuccessful save.
    return LibraryStoredSnapshot(sha256.convert(bytes).toString(), values);
  }

  Future<void> _rejectLink(File file) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file &&
        type != FileSystemEntityType.notFound) {
      throw const LibraryStorageException(
        'Library snapshot destination is not a regular file.',
      );
    }
  }

  Future<void> _archive(Directory directory) async {
    final archive = Directory(
      p.join(
        directory.path,
        'recovery',
        '${DateTime.now().toUtc().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}',
      ),
    );
    await archive.create(recursive: true);
    for (final name in [
      'library.json',
      'library.previous.json',
      'library.pending',
    ]) {
      final source = _file(directory, name);
      await _rejectLink(source);
      if (await source.exists()) {
        final copy = await source.copy(p.join(archive.path, name));
        final handle = await copy.open(mode: FileMode.append);
        try {
          await handle.flush();
        } finally {
          await handle.close();
        }
      }
    }
  }

  @override
  Future<LibraryStoredSnapshot> replaceForRecovery(
    Map<String, Object?> values,
  ) => _locked((directory) async {
    await _archive(directory);
    return _commit(directory, values);
  });

  @override
  Future<void> recoverPrevious() => _locked((directory) async {
    final raw = await _readRaw(_file(directory, 'library.previous.json'));
    if (raw == null) {
      throw const LibraryStorageException(
        'No previous library snapshot is available.',
      );
    }
    final previous = _decode(raw);
    await _archive(directory);
    await _commit(directory, previous.values);
  });

  @override
  Future<Map<String, Object?>> recoveryData() => _locked((directory) async {
    final data = <String, Object?>{'directory': directory.path};
    for (final name in [
      'library.json',
      'library.previous.json',
      'library.pending',
    ]) {
      final file = _file(directory, name);
      await _rejectLink(file);
      if (await file.exists()) {
        data[name] = await file.length() <= maximumSnapshotBytes
            ? {'base64': base64Encode(await file.readAsBytes())}
            : {
                'error':
                    'File too large to embed; original remains at ${file.path}',
              };
      }
    }
    return data;
  });
}

/// Typed reads shared by legacy preferences and versioned snapshots.
final class LibraryValues {
  LibraryValues(this.values);
  final Map<String, Object?> values;
  String? getString(String key) => values[key] as String?;
  bool? getBool(String key) => values[key] as bool?;
  int? getInt(String key) => values[key] as int?;
  double? getDouble(String key) => (values[key] as num?)?.toDouble();
  List<String>? getStringList(String key) =>
      (values[key] as List?)?.cast<String>().toList();
}
