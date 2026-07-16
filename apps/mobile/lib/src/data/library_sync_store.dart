import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/library_sync_account.dart';
import '../domain/library_sync_profile.dart';
import '../domain/track_queue.dart';
import '../player/player_controller.dart';
import 'library_store.dart';
import 'library_sync_client.dart';
import 'library_sync_credential_vault.dart';
import 'provider_error.dart';

typedef LibrarySyncClientFactory =
    LibrarySyncGateway Function(LibrarySyncAccount account, String token);

class LibrarySyncStore extends ChangeNotifier {
  LibrarySyncStore({
    LibrarySyncCredentialVault? credentialVault,
    LibrarySyncClientFactory? clientFactory,
    DateTime Function()? clock,
  }) : _credentialVault = credentialVault ?? SecureLibrarySyncCredentialVault(),
       _clientFactory =
           clientFactory ??
           ((account, token) =>
               LibrarySyncClient(account: account, token: token)),
       _clock = clock ?? DateTime.now;

  static const _metadataKey = 'aethertune.library_sync.metadata.v1';
  static const automaticUploadInterval = Duration(minutes: 15);

  final LibrarySyncCredentialVault _credentialVault;
  final LibrarySyncClientFactory _clientFactory;
  final DateTime Function() _clock;

  LibrarySyncAccount? _account;
  LibrarySyncProfile? _profile;
  String? _token;
  int _lastKnownRevision = 0;
  int _remoteRevision = 0;
  DateTime? _lastSyncAt;
  DateTime? _remoteUpdatedAt;
  String? _remoteUpdatedByDevice;
  bool _automaticUploadEnabled = false;
  bool _queueSyncEnabled = false;
  DateTime? _lastAutomaticUploadAttemptAt;
  DateTime? _lastAutomaticUploadAt;
  LibrarySyncConflictException? _conflict;
  String? _lastError;
  bool _loaded = false;
  bool _busy = false;

  LibrarySyncAccount? get account => _account;
  LibrarySyncProfile? get profile => _profile;
  int get lastKnownRevision => _lastKnownRevision;
  int get remoteRevision => _remoteRevision;
  DateTime? get lastSyncAt => _lastSyncAt;
  DateTime? get remoteUpdatedAt => _remoteUpdatedAt;
  String? get remoteUpdatedByDevice => _remoteUpdatedByDevice;
  bool get automaticUploadEnabled => _automaticUploadEnabled;
  bool get queueSyncEnabled => _queueSyncEnabled;
  DateTime? get lastAutomaticUploadAt => _lastAutomaticUploadAt;
  LibrarySyncConflictException? get conflict => _conflict;
  String? get lastError => _lastError;
  bool get loaded => _loaded;
  bool get busy => _busy;
  bool get isConfigured => _account != null && (_token ?? '').isNotEmpty;

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_metadataKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const FormatException('Sync metadata must be an object.');
        }
        final metadata = Map<String, Object?>.from(decoded);
        final rawAccount = metadata['account'];
        if (rawAccount is! Map) {
          throw const FormatException('Sync account metadata is missing.');
        }
        _account = LibrarySyncAccount.fromJson(
          Map<String, Object?>.from(rawAccount),
        );
        _profile = _optionalProfile(metadata['profile']);
        _lastKnownRevision = _nonNegativeInt(metadata['lastKnownRevision']);
        _remoteRevision = _nonNegativeInt(metadata['remoteRevision']);
        _lastSyncAt = _optionalDate(metadata['lastSyncAt']);
        _remoteUpdatedAt = _optionalDate(metadata['remoteUpdatedAt']);
        _remoteUpdatedByDevice = _optionalString(
          metadata['remoteUpdatedByDevice'],
        );
        _automaticUploadEnabled = metadata['automaticUploadEnabled'] == true;
        _queueSyncEnabled = metadata['queueSyncEnabled'] == true;
        _lastAutomaticUploadAttemptAt = _optionalDate(
          metadata['lastAutomaticUploadAttemptAt'],
        );
        _lastAutomaticUploadAt = _optionalDate(
          metadata['lastAutomaticUploadAt'],
        );
        _token = await _credentialVault.read();
      }
      _lastError = null;
    } on Object catch (error) {
      _lastError = 'Could not load library sync settings: $error';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<LibrarySyncRemoteSnapshot> testAndSave(
    LibraryStore library,
    LibrarySyncAccount account,
    String token,
  ) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      throw const FormatException('Sync token is required.');
    }
    return _runBusy(() async {
      _requireOnline(library);
      LibrarySyncRemoteSnapshot remote;
      LibrarySyncProfile? profile;
      try {
        final client = _clientFactory(account, normalizedToken);
        remote = await client.fetch();
        if (client is LibrarySyncProfileGateway) {
          profile = await (client as LibrarySyncProfileGateway).fetchProfile();
        }
      } on Object catch (error) {
        throw ProviderRequestException(
          safeProviderErrorMessage(
            error,
            providerName: 'Library sync',
            secrets: <String>[normalizedToken],
          ),
        );
      }

      final oldAccount = _account;
      final oldProfile = _profile;
      final oldToken = _token;
      final oldKnownRevision = _lastKnownRevision;
      final oldRemoteRevision = _remoteRevision;
      final oldRemoteUpdatedAt = _remoteUpdatedAt;
      final oldRemoteUpdatedByDevice = _remoteUpdatedByDevice;
      try {
        await _credentialVault.write(normalizedToken);
        final sameServer = oldAccount?.baseUri == account.baseUri;
        _account = account;
        _profile = profile;
        _token = normalizedToken;
        _lastKnownRevision = sameServer ? oldKnownRevision : 0;
        _applyRemoteMetadata(remote);
        _conflict = null;
        await _saveMetadata();
      } on Object catch (error) {
        _account = oldAccount;
        _profile = oldProfile;
        _token = oldToken;
        _lastKnownRevision = oldKnownRevision;
        _remoteRevision = oldRemoteRevision;
        _remoteUpdatedAt = oldRemoteUpdatedAt;
        _remoteUpdatedByDevice = oldRemoteUpdatedByDevice;
        try {
          if (oldToken == null || oldToken.isEmpty) {
            await _credentialVault.delete();
          } else {
            await _credentialVault.write(oldToken);
          }
        } on Object {
          throw const ProviderRequestException(
            'Library sync settings failed and the previous secure token could not be restored.',
          );
        }
        throw ProviderRequestException(
          safeProviderErrorMessage(
            error,
            providerName: 'Library sync',
            secrets: <String>[normalizedToken, if (oldToken != null) oldToken],
          ),
        );
      }
      return remote;
    });
  }

  Future<LibrarySyncRemoteSnapshot> push(
    LibraryStore library, {
    int? baseRevision,
    PlayerController? player,
  }) {
    return _runBusy(() async {
      _requireOnline(library);
      final client = _requireClient();
      final snapshot = _snapshotForPush(library, player: player);
      try {
        final result = await client.push(
          baseRevision: baseRevision ?? _lastKnownRevision,
          snapshot: snapshot,
        );
        _lastKnownRevision = result.revision;
        _applyRemoteMetadata(result);
        _lastSyncAt = _clock().toUtc();
        _conflict = null;
        await _saveMetadata();
        return result;
      } on LibrarySyncConflictException catch (error) {
        _conflict = error;
        _remoteRevision = error.currentRevision;
        _remoteUpdatedAt = error.updatedAt;
        _remoteUpdatedByDevice = error.updatedByDevice;
        await _saveMetadata();
        rethrow;
      }
    });
  }

  Future<void> setAutomaticUploadEnabled(bool enabled) async {
    if (_automaticUploadEnabled == enabled) {
      return;
    }

    final previous = _automaticUploadEnabled;
    _automaticUploadEnabled = enabled;
    try {
      await _saveMetadata();
    } on Object {
      _automaticUploadEnabled = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setQueueSyncEnabled(bool enabled) async {
    if (_queueSyncEnabled == enabled) {
      return;
    }

    final previous = _queueSyncEnabled;
    _queueSyncEnabled = enabled;
    try {
      await _saveMetadata();
    } on Object {
      _queueSyncEnabled = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<LibrarySyncProfile?> refreshProfile(LibraryStore library) {
    return _runBusy(() async {
      _requireOnline(library);
      final client = _requireClient();
      if (client is! LibrarySyncProfileGateway) {
        return _profile;
      }
      final previous = _profile;
      final refreshed = await (client as LibrarySyncProfileGateway)
          .fetchProfile();
      _profile = refreshed;
      try {
        await _saveMetadata();
      } on Object {
        _profile = previous;
        rethrow;
      }
      return refreshed;
    });
  }

  Future<LibrarySyncProfile> updateProfile(
    LibraryStore library, {
    required String displayName,
    required String deviceName,
  }) {
    final normalizedDisplayName = normalizeLibrarySyncProfileDisplayName(
      displayName,
    );
    final normalizedDeviceName = normalizeLibrarySyncProfileDeviceName(
      deviceName,
    );
    return _runBusy(() async {
      _requireOnline(library);
      final previousProfile = _profile;
      final previousAccount = _account;
      final previousDevice = previousProfile?.device;
      if (previousProfile == null ||
          !previousProfile.managed ||
          !previousProfile.editable ||
          previousDevice == null ||
          previousAccount == null) {
        throw StateError('This sync account does not support profile editing.');
      }
      final client = _requireClient();
      if (client is! LibrarySyncProfileEditorGateway) {
        throw StateError('This sync server does not support profile editing.');
      }
      final updated = await (client as LibrarySyncProfileEditorGateway)
          .updateProfile(
            displayName: normalizedDisplayName,
            deviceName: normalizedDeviceName,
          );
      if (!updated.managed ||
          updated.id != previousProfile.id ||
          updated.device?.id != previousDevice.id) {
        throw const ProviderRequestException(
          'Library sync returned a different account or device identity.',
        );
      }

      _profile = updated;
      _account = LibrarySyncAccount(
        baseUri: previousAccount.baseUri,
        deviceId: updated.device!.name,
        allowInsecureHttp: previousAccount.allowInsecureHttp,
      );
      try {
        await _saveMetadata();
      } on Object {
        _profile = previousProfile;
        _account = previousAccount;
        rethrow;
      }
      return updated;
    });
  }

  Future<bool> uploadAutomaticallyIfDue(
    LibraryStore library, {
    PlayerController? player,
  }) async {
    if (!_loaded ||
        !_automaticUploadEnabled ||
        !isConfigured ||
        library.offlineModeEnabled ||
        _busy) {
      return false;
    }

    final now = _clock().toUtc();
    final previousAttempt = _lastAutomaticUploadAttemptAt;
    if (previousAttempt != null &&
        now.difference(previousAttempt) < automaticUploadInterval) {
      return false;
    }

    _lastAutomaticUploadAttemptAt = now;
    try {
      await _saveMetadata();
      final client = _requireClient();
      if (client is LibrarySyncMetadataGateway) {
        final metadataClient = client as LibrarySyncMetadataGateway;
        final remote = await metadataClient.fetchMetadata();
        if (remote != null && remote.revision != _lastKnownRevision) {
          _conflict = LibrarySyncConflictException(
            currentRevision: remote.revision,
            updatedAt: remote.updatedAt,
            updatedByDevice: remote.updatedByDevice,
            checksum: remote.checksum,
          );
          _applyRemoteMetadata(remote);
          await _saveMetadata();
          return false;
        }
        final remoteChecksum = remote?.checksum;
        if (remoteChecksum != null &&
            remoteChecksum ==
                sha256
                    .convert(
                      utf8.encode(
                        jsonEncode(_snapshotForPush(library, player: player)),
                      ),
                    )
                    .toString()) {
          return false;
        }
      }
      await push(library, player: player);
      _lastAutomaticUploadAt = now;
      await _saveMetadata();
      notifyListeners();
      return true;
    } on Object {
      return false;
    }
  }

  Future<LibrarySyncRemoteSnapshot> pull(
    LibraryStore library, {
    PlayerController? player,
  }) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await _requireClient().fetch();
      final remoteSnapshot = remote.snapshot;
      if (remoteSnapshot == null) {
        throw StateError(
          'The sync server does not have a library snapshot yet.',
        );
      }
      final queueSnapshot = _queueSyncEnabled
          ? _queueSnapshotFrom(remoteSnapshot)
          : null;
      final queuePlayer = queueSnapshot == null
          ? null
          : _requireQueuePlayer(player);
      await library.restoreSyncSnapshotJson(jsonEncode(remoteSnapshot));
      if (queuePlayer != null && queueSnapshot != null) {
        await queuePlayer.restoreQueueSyncSnapshot(
          queueSnapshot,
          library.tracks,
        );
      }
      _lastKnownRevision = remote.revision;
      _applyRemoteMetadata(remote);
      _lastSyncAt = _clock().toUtc();
      _conflict = null;
      await _saveMetadata();
      return remote;
    });
  }

  Future<LibrarySyncRemoteSnapshot> mergeAndPush(
    LibraryStore library, {
    PlayerController? player,
  }) {
    return _runBusy(() async {
      _requireOnline(library);
      final client = _requireClient();
      final remote = await client.fetch();
      final remoteSnapshot = remote.snapshot;
      if (remoteSnapshot == null) {
        throw StateError(
          'The sync server does not have a library snapshot yet.',
        );
      }
      final localBeforeMerge = library.exportSyncSnapshotJson();
      final localQueueSnapshot = _queueSyncEnabled
          ? _requireQueuePlayer(player).exportQueueSyncSnapshot(library.tracks)
          : null;
      final remoteQueueSnapshot = _queueSyncEnabled
          ? _queueSnapshotFrom(remoteSnapshot)
          : null;
      final mergedQueueSnapshot = _newestQueueSnapshot(
        localQueueSnapshot,
        remoteQueueSnapshot,
      );
      var remoteAcceptedMerge = false;
      try {
        await library.mergeSyncSnapshotJson(jsonEncode(remoteSnapshot));
        final result = await client.push(
          baseRevision: remote.revision,
          snapshot: _snapshotForPush(
            library,
            player: player,
            queueSnapshot: mergedQueueSnapshot,
          ),
        );
        remoteAcceptedMerge = true;
        if (_queueSyncEnabled &&
            remoteQueueSnapshot != null &&
            identical(mergedQueueSnapshot, remoteQueueSnapshot)) {
          await _requireQueuePlayer(player).restoreQueueSyncSnapshot(
            remoteQueueSnapshot,
            library.tracks,
          );
        }
        _lastKnownRevision = result.revision;
        _applyRemoteMetadata(result);
        _lastSyncAt = _clock().toUtc();
        _conflict = null;
        await _saveMetadata();
        return result;
      } on Object {
        if (!remoteAcceptedMerge) {
          await library.restoreSyncSnapshotJson(localBeforeMerge);
        }
        rethrow;
      }
    });
  }

  Future<LibrarySyncRemoteSnapshot> deleteRemoteSnapshot(LibraryStore library) {
    return _runBusy(() async {
      _requireOnline(library);
      final client = _requireClient();
      try {
        final result = await client.delete(baseRevision: _remoteRevision);
        _lastKnownRevision = result.revision;
        _applyRemoteMetadata(result);
        _lastSyncAt = _clock().toUtc();
        _automaticUploadEnabled = false;
        _conflict = null;
        await _saveMetadata();
        return result;
      } on LibrarySyncConflictException catch (error) {
        _conflict = error;
        _remoteRevision = error.currentRevision;
        _remoteUpdatedAt = error.updatedAt;
        _remoteUpdatedByDevice = error.updatedByDevice;
        await _saveMetadata();
        rethrow;
      }
    });
  }

  Future<void> remove() async {
    await _runBusy(() async {
      final oldToken = _token;
      try {
        await _credentialVault.delete();
        final prefs = await SharedPreferences.getInstance();
        final removed = await prefs.remove(_metadataKey);
        if (!removed && prefs.containsKey(_metadataKey)) {
          throw StateError('Could not remove library sync metadata.');
        }
      } on Object {
        if (oldToken != null && oldToken.isNotEmpty) {
          await _credentialVault.write(oldToken);
        }
        rethrow;
      }
      _account = null;
      _profile = null;
      _token = null;
      _lastKnownRevision = 0;
      _remoteRevision = 0;
      _lastSyncAt = null;
      _remoteUpdatedAt = null;
      _remoteUpdatedByDevice = null;
      _automaticUploadEnabled = false;
      _queueSyncEnabled = false;
      _lastAutomaticUploadAttemptAt = null;
      _lastAutomaticUploadAt = null;
      _conflict = null;
    });
  }

  LibrarySyncGateway _requireClient() {
    final account = _account;
    final token = _token;
    if (account == null || token == null || token.isEmpty) {
      throw StateError('Configure a library sync server first.');
    }
    return _clientFactory(account, token);
  }

  /// Creates the authenticated client used for account-scoped social sessions.
  /// The secure sync token stays owned by this store.
  ListenTogetherGateway createListenTogetherGateway() {
    final client = _requireClient();
    if (client is! ListenTogetherGateway) {
      throw StateError('This library sync server does not support listen together.');
    }
    return client as ListenTogetherGateway;
  }

  void _requireOnline(LibraryStore library) {
    if (library.offlineModeEnabled) {
      throw StateError('Turn off offline mode before syncing the library.');
    }
  }

  Map<String, Object?> _snapshotForPush(
    LibraryStore library, {
    required PlayerController? player,
    TrackQueueReferenceSnapshot? queueSnapshot,
  }) {
    final decoded = jsonDecode(library.exportSyncSnapshotJson());
    if (decoded is! Map) {
      throw const FormatException('Portable library snapshot is invalid.');
    }
    final snapshot = Map<String, Object?>.from(decoded);
    if (!_queueSyncEnabled) {
      snapshot.remove('queueSync');
      return snapshot;
    }

    final queue = queueSnapshot ??
        _requireQueuePlayer(player).exportQueueSyncSnapshot(library.tracks);
    snapshot['queueSync'] = queue.toJson();
    return snapshot;
  }

  PlayerController _requireQueuePlayer(PlayerController? player) {
    if (player == null) {
      throw StateError(
        'Queue sync requires an active player controller on this device.',
      );
    }
    return player;
  }

  TrackQueueReferenceSnapshot? _queueSnapshotFrom(
    Map<String, Object?> snapshot,
  ) {
    final raw = snapshot['queueSync'];
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      throw const FormatException('Queue sync snapshot must be an object.');
    }
    return TrackQueueReferenceSnapshot.fromJson(
      Map<String, Object?>.from(raw),
    );
  }

  TrackQueueReferenceSnapshot? _newestQueueSnapshot(
    TrackQueueReferenceSnapshot? local,
    TrackQueueReferenceSnapshot? remote,
  ) {
    if (local == null || remote == null) {
      return local ?? remote;
    }
    return remote.updatedAt.isAfter(local.updatedAt) ? remote : local;
  }

  void _applyRemoteMetadata(LibrarySyncRemoteSnapshot remote) {
    _remoteRevision = remote.revision;
    _remoteUpdatedAt = remote.updatedAt;
    _remoteUpdatedByDevice = remote.updatedByDevice;
  }

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError('A library sync operation is already running.');
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      return await action();
    } on Object catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _saveMetadata() async {
    final account = _account;
    if (account == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _metadataKey,
      jsonEncode(<String, Object?>{
        'account': account.toJson(),
        'profile': _profile?.toJson(),
        'lastKnownRevision': _lastKnownRevision,
        'remoteRevision': _remoteRevision,
        'lastSyncAt': _lastSyncAt?.toIso8601String(),
        'remoteUpdatedAt': _remoteUpdatedAt?.toIso8601String(),
        'remoteUpdatedByDevice': _remoteUpdatedByDevice,
        'automaticUploadEnabled': _automaticUploadEnabled,
        'queueSyncEnabled': _queueSyncEnabled,
        'lastAutomaticUploadAttemptAt': _lastAutomaticUploadAttemptAt
            ?.toIso8601String(),
        'lastAutomaticUploadAt': _lastAutomaticUploadAt?.toIso8601String(),
      }),
    );
    if (!saved) {
      throw StateError('Could not save library sync metadata.');
    }
  }
}

int _nonNegativeInt(Object? value) {
  return value is int && value >= 0 ? value : 0;
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

DateTime? _optionalDate(Object? value) {
  final raw = _optionalString(value);
  return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}

LibrarySyncProfile? _optionalProfile(Object? value) {
  if (value is! Map) {
    return null;
  }
  try {
    return LibrarySyncProfile.fromJson(Map<String, Object?>.from(value));
  } on FormatException {
    return null;
  }
}
