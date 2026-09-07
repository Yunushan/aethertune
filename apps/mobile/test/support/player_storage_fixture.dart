import 'dart:async';

import 'package:aethertune/src/data/file_library_storage.dart';

class ControlledPlayerStorage implements LibraryStorage {
  LibraryStoredSnapshot? current;
  LibraryStoredSnapshot? previous;
  bool failWrites = false;
  bool failReads = false;
  int writes = 0;
  Completer<void>? writeStarted;
  Completer<void>? releaseWrite;

  @override
  Future<LibraryStoredSnapshot?> read() async {
    if (failReads) throw const LibraryStorageException('Read failure');
    return current;
  }

  @override
  Future<LibraryStoredSnapshot> write(
    Map<String, Object?> values, {
    required String? expectedRevision,
  }) async {
    writes++;
    if (writeStarted?.isCompleted == false) writeStarted!.complete();
    await releaseWrite?.future;
    if (failWrites) throw const LibraryStorageException('Disk full');
    if (expectedRevision != current?.revision) {
      throw const LibraryStorageConflict();
    }
    previous = current;
    return current = LibraryStoredSnapshot('generation-$writes', values);
  }

  @override
  Future<void> recoverPrevious() async {
    if (previous == null) {
      throw const LibraryStorageException('No previous data');
    }
    current = LibraryStoredSnapshot('recovered-${writes++}', previous!.values);
  }

  @override
  Future<LibraryStoredSnapshot> replaceForRecovery(
    Map<String, Object?> values,
  ) async => current = LibraryStoredSnapshot('reset-${writes++}', values);

  @override
  Future<Map<String, Object?>> recoveryData() async => {
    'current': current?.values,
  };
}
