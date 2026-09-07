import 'dart:convert';

import 'package:aethertune/src/data/library_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A snapshot fixture only. It is never selected by application entrypoints.
final class PreferencesLibraryStorageFixture implements LibraryStorage {
  PreferencesLibraryStorageFixture({this.key = 'aethertune.test.snapshot'});
  final String key;
  static int _generation = 0;

  LibraryStoredSnapshot? _decode(String? raw) {
    if (raw == null) return null;
    final decoded = jsonDecode(raw) as Map;
    return LibraryStoredSnapshot(
      decoded['revision'] as String,
      Map<String, Object?>.from(decoded['values'] as Map),
    );
  }

  @override
  Future<LibraryStoredSnapshot?> read() async =>
      _decode((await SharedPreferences.getInstance()).getString(key));

  @override
  Future<LibraryStoredSnapshot> write(
    Map<String, Object?> values, {
    required String? expectedRevision,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(key);
    if (_decode(previous)?.revision != expectedRevision) {
      throw const LibraryStorageConflict();
    }
    final snapshot = LibraryStoredSnapshot('fixture-${_generation++}', values);
    final accepted = await prefs.setString(
      key,
      jsonEncode({'revision': snapshot.revision, 'values': values}),
    );
    if (!accepted) {
      await prefs.reload();
      throw const LibraryStorageException('Fixture rejected write.');
    }
    if (previous != null) await prefs.setString('$key.previous', previous);
    return snapshot;
  }

  @override
  Future<LibraryStoredSnapshot> replaceForRecovery(
    Map<String, Object?> values,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(key);
    if (previous != null) await prefs.setString('$key.archive', previous);
    await prefs.remove(key);
    return write(values, expectedRevision: null);
  }

  @override
  Future<void> recoverPrevious() async {
    final prefs = await SharedPreferences.getInstance();
    final previous = _decode(prefs.getString('$key.previous'));
    if (previous == null) {
      throw const LibraryStorageException('No previous snapshot.');
    }
    await replaceForRecovery(previous.values);
  }

  @override
  Future<Map<String, Object?>> recoveryData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'current': prefs.getString(key),
      'previous': prefs.getString('$key.previous'),
    };
  }
}
