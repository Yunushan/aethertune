import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import '../data/file_library_storage.dart';
import '../domain/track_queue.dart';

@visibleForTesting
LibraryStorage Function() playerStorageFactory = () => FileLibraryStorage(
  directory: () async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'player'),
  ),
);

/// Player data has its own snapshot and revision, independent of library writes.
/// A failed write blocks further saves until the durable state is reloaded.
class PlayerStateStore {
  PlayerStateStore({LibraryStorage? storage})
    : _storage = storage ?? playerStorageFactory();

  static const queueKey = 'aethertune.player_queue.v1';
  static const queuesKey = 'aethertune.player_queues.v2';
  static const settingsKey = 'aethertune.playback_settings.v1';
  final LibraryStorage _storage;
  Future<void> _tail = Future<void>.value();
  String? _revision;
  Map<String, Object?> _values = const {};
  bool _loaded = false;
  String? _error;

  Map<String, Object?> get values => _values;
  String? get error => _error;
  bool get ready => _loaded && _error == null;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  Future<bool> load() => _serialized(() async {
    if (_error != null) return false;
    return _loaded || await _read();
  });

  Future<bool> _read() async {
    try {
      var snapshot = await _storage.read();
      final Map<String, Object?> values;
      if (snapshot == null) {
        // Read the legacy backend without replacing SharedPreferences' shared
        // cache while other stores are committing their startup migrations.
        final prefs = await SharedPreferencesStorePlatform.instance.getAll();
        values = {
          for (final key in [queueKey, queuesKey, settingsKey])
            if (prefs.containsKey('flutter.$key')) key: prefs['flutter.$key'],
        };
        _validate(values);
        snapshot = await _storage.write(values, expectedRevision: null);
        // Retain original preference bytes for recovery; never mirror new saves.
      } else {
        values = snapshot.values;
        _validate(values);
      }
      _values = Map.unmodifiable(values);
      _revision = snapshot.revision;
      _loaded = true;
      _error = null;
      return true;
    } on Object {
      reportLoadFailure();
      return false;
    }
  }

  Future<bool> write(Map<String, Object?> updates) {
    // Capture before yielding so later caller mutations cannot change this save.
    final captured = Map<String, Object?>.from(updates);
    return _serialized(() async {
      if (_error != null || (!_loaded && !await _read())) return false;
      try {
        final values = {..._values, ...captured}
          ..removeWhere((_, value) => value == null);
        _validate(values);
        final snapshot = await _storage.write(
          values,
          expectedRevision: _revision,
        );
        _revision = snapshot.revision;
        _values = Map.unmodifiable(values);
        return true;
      } on Object catch (error) {
        _error = error is LibraryStorageConflict
            ? 'Saved player data changed in another process. Reload before making more changes.'
            : 'Player changes could not be saved. The last saved queues and settings are preserved. Check available storage and reload before retrying.';
        return false;
      }
    });
  }

  Future<bool> reload({bool previous = false}) => _serialized(() async {
    try {
      if (previous) await _storage.recoverPrevious();
      return await _read();
    } on Object {
      _error =
          'The previous player snapshot could not be restored. Existing files were kept.';
      return false;
    }
  });

  void reportLoadFailure() {
    _error =
        'Saved player data could not be loaded. Existing data was kept. Retry loading or restore the previous snapshot.';
  }

  void reportPlaybackRestoreFailure() {
    _error =
        'Saved player settings could not be applied to the audio device. Existing data was kept. Reload before retrying.';
  }

  static Map<String, Object?>? _document(
    Map<String, Object?> values,
    String key,
  ) {
    final raw = values[key];
    if (raw == null) return null;
    if (raw is! String || raw.isEmpty) {
      throw const FormatException('Invalid player snapshot value.');
    }
    return Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  static void _validate(Map<String, Object?> values) {
    final queue = _document(values, queueKey);
    if (queue != null) _validateQueue(queue);
    final collection = _document(values, queuesKey);
    if (collection != null) {
      final decoded = SavedTrackQueueCollection.fromJson(collection);
      final rawQueues = collection['queues'] as List;
      if (decoded.queues.length != rawQueues.length) {
        throw const FormatException('Player queues would be discarded.');
      }
      for (final raw in rawQueues) {
        _validateQueue(
          Map<String, Object?>.from((raw as Map)['snapshot'] as Map),
        );
      }
    }
    _document(values, settingsKey);
  }

  static void _validateQueue(Map<String, Object?> queue) {
    final rawTracks = queue['tracks'];
    if (rawTracks is! List || rawTracks.any((track) => track is! Map)) {
      throw const FormatException('Player queue tracks are invalid.');
    }
    TrackQueueSnapshot.fromJson(queue);
  }
}
