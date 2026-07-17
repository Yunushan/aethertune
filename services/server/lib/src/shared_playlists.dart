import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum SharedPlaylistRole {
  viewer,
  editor,
}

const sharedPlaylistInviteLifetime = Duration(days: 7);

SharedPlaylistRole? sharedPlaylistRoleFromWire(Object? value) {
  return switch (value) {
    'viewer' => SharedPlaylistRole.viewer,
    'editor' => SharedPlaylistRole.editor,
    _ => null,
  };
}

String sharedPlaylistRoleToWire(SharedPlaylistRole role) => switch (role) {
  SharedPlaylistRole.viewer => 'viewer',
  SharedPlaylistRole.editor => 'editor',
};

class SharedPlaylistRecord {
  const SharedPlaylistRecord({
    required this.id,
    required this.ownerId,
    required this.revision,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.checksum,
    required this.document,
    this.collaborators = const <String, SharedPlaylistRole>{},
  });

  final String id;
  final String ownerId;
  final int revision;
  final DateTime updatedAt;
  final String updatedByDevice;
  final String checksum;
  final Map<String, Object?> document;
  final Map<String, SharedPlaylistRole> collaborators;

  SharedPlaylistRole? roleFor(String accountId) {
    if (accountId == ownerId) {
      return SharedPlaylistRole.editor;
    }
    return collaborators[accountId];
  }

  bool isOwner(String accountId) => accountId == ownerId;

  Map<String, Object?> toStorageJson() => <String, Object?>{
    'id': id,
    'ownerId': ownerId,
    'revision': revision,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'updatedByDevice': updatedByDevice,
    'checksum': checksum,
    'document': document,
    'collaborators': collaborators.map(
      (accountId, role) => MapEntry<String, String>(
        accountId,
        sharedPlaylistRoleToWire(role),
      ),
    ),
  };

  factory SharedPlaylistRecord.fromStorageJson(Map<String, Object?> json) {
    final id = json['id'];
    final ownerId = json['ownerId'];
    final revision = json['revision'];
    final updatedAt = json['updatedAt'];
    final updatedByDevice = json['updatedByDevice'];
    final checksum = json['checksum'];
    final document = json['document'];
    final collaborators = json['collaborators'];
    if (id is! String ||
        ownerId is! String ||
        revision is! int ||
        updatedAt is! String ||
        updatedByDevice is! String ||
        checksum is! String ||
        document is! Map ||
        collaborators is! Map ||
        !_isSharedPlaylistId(id) ||
        !_isAccountId(ownerId) ||
        revision <= 0 ||
        updatedByDevice.trim().isEmpty ||
        checksum.isEmpty) {
      throw const FormatException('Stored shared playlist is invalid.');
    }
    final parsedCollaborators = <String, SharedPlaylistRole>{};
    for (final entry in collaborators.entries) {
      if (entry.key is! String || !_isAccountId(entry.key as String)) {
        throw const FormatException('Stored shared playlist is invalid.');
      }
      final role = sharedPlaylistRoleFromWire(entry.value);
      if (role == null || entry.key == ownerId) {
        throw const FormatException('Stored shared playlist is invalid.');
      }
      parsedCollaborators[entry.key as String] = role;
    }
    final parsedDocument = Map<String, Object?>.from(document);
    validateSharedPlaylistDocument(parsedDocument);
    final canonicalChecksum = sha256
        .convert(utf8.encode(jsonEncode(parsedDocument)))
        .toString();
    if (canonicalChecksum != checksum) {
      throw const FormatException('Stored shared playlist checksum is invalid.');
    }
    final parsedUpdatedAt = DateTime.tryParse(updatedAt)?.toUtc();
    if (parsedUpdatedAt == null) {
      throw const FormatException('Stored shared playlist is invalid.');
    }
    return SharedPlaylistRecord(
      id: id,
      ownerId: ownerId,
      revision: revision,
      updatedAt: parsedUpdatedAt,
      updatedByDevice: updatedByDevice,
      checksum: checksum,
      document: parsedDocument,
      collaborators: Map<String, SharedPlaylistRole>.unmodifiable(
        parsedCollaborators,
      ),
    );
  }
}

class SharedPlaylistWriteResult {
  const SharedPlaylistWriteResult._({
    required this.isConflict,
    required this.record,
  });

  factory SharedPlaylistWriteResult.saved(SharedPlaylistRecord record) {
    return SharedPlaylistWriteResult._(isConflict: false, record: record);
  }

  factory SharedPlaylistWriteResult.conflict(SharedPlaylistRecord? record) {
    return SharedPlaylistWriteResult._(isConflict: true, record: record);
  }

  final bool isConflict;
  final SharedPlaylistRecord? record;
}

abstract interface class SharedPlaylistStore {
  Future<SharedPlaylistRecord?> read(String playlistId);

  Future<SharedPlaylistWriteResult> write({
    required String playlistId,
    required String ownerId,
    required int baseRevision,
    required String deviceId,
    required Map<String, Object?> document,
    required Map<String, SharedPlaylistRole> collaborators,
    required DateTime updatedAt,
  });

  Future<SharedPlaylistWriteResult> delete({
    required String playlistId,
    required int baseRevision,
  });
}

class MemorySharedPlaylistStore implements SharedPlaylistStore {
  final Map<String, SharedPlaylistRecord> _records =
      <String, SharedPlaylistRecord>{};

  @override
  Future<SharedPlaylistRecord?> read(String playlistId) async =>
      _records[playlistId];

  @override
  Future<SharedPlaylistWriteResult> write({
    required String playlistId,
    required String ownerId,
    required int baseRevision,
    required String deviceId,
    required Map<String, Object?> document,
    required Map<String, SharedPlaylistRole> collaborators,
    required DateTime updatedAt,
  }) async {
    final current = _records[playlistId];
    if ((current?.revision ?? 0) != baseRevision) {
      return SharedPlaylistWriteResult.conflict(current);
    }
    final saved = _newSharedPlaylistRecord(
      playlistId: playlistId,
      ownerId: ownerId,
      revision: baseRevision + 1,
      deviceId: deviceId,
      document: document,
      collaborators: collaborators,
      updatedAt: updatedAt,
    );
    _records[playlistId] = saved;
    return SharedPlaylistWriteResult.saved(saved);
  }

  @override
  Future<SharedPlaylistWriteResult> delete({
    required String playlistId,
    required int baseRevision,
  }) async {
    final current = _records[playlistId];
    if (current == null || current.revision != baseRevision) {
      return SharedPlaylistWriteResult.conflict(current);
    }
    _records.remove(playlistId);
    return SharedPlaylistWriteResult.saved(current);
  }
}

class FileSharedPlaylistStore implements SharedPlaylistStore {
  FileSharedPlaylistStore(this.rootDirectory);

  final Directory rootDirectory;
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  @override
  Future<SharedPlaylistRecord?> read(String playlistId) async {
    if (!_isSharedPlaylistId(playlistId)) {
      return null;
    }
    final file = _fileFor(playlistId);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return SharedPlaylistRecord.fromStorageJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<SharedPlaylistWriteResult> write({
    required String playlistId,
    required String ownerId,
    required int baseRevision,
    required String deviceId,
    required Map<String, Object?> document,
    required Map<String, SharedPlaylistRole> collaborators,
    required DateTime updatedAt,
  }) {
    return _serialized(playlistId, () async {
      final current = await read(playlistId);
      if ((current?.revision ?? 0) != baseRevision) {
        return SharedPlaylistWriteResult.conflict(current);
      }
      final saved = _newSharedPlaylistRecord(
        playlistId: playlistId,
        ownerId: ownerId,
        revision: baseRevision + 1,
        deviceId: deviceId,
        document: document,
        collaborators: collaborators,
        updatedAt: updatedAt,
      );
      await rootDirectory.create(recursive: true);
      final target = _fileFor(playlistId);
      final temporary = File(
        p.join(
          rootDirectory.path,
          '.${target.uri.pathSegments.last}.${DateTime.now().microsecondsSinceEpoch}.tmp',
        ),
      );
      await temporary.writeAsString(jsonEncode(saved.toStorageJson()), flush: true);
      await temporary.rename(target.path);
      return SharedPlaylistWriteResult.saved(saved);
    });
  }

  @override
  Future<SharedPlaylistWriteResult> delete({
    required String playlistId,
    required int baseRevision,
  }) {
    return _serialized(playlistId, () async {
      final current = await read(playlistId);
      if (current == null || current.revision != baseRevision) {
        return SharedPlaylistWriteResult.conflict(current);
      }
      final target = _fileFor(playlistId);
      if (await target.exists()) {
        await target.delete();
      }
      return SharedPlaylistWriteResult.saved(current);
    });
  }

  File _fileFor(String playlistId) {
    final digest = sha256.convert(utf8.encode(playlistId)).toString();
    return File(p.join(rootDirectory.path, '$digest.json'));
  }

  Future<T> _serialized<T>(String playlistId, Future<T> Function() action) {
    final previous = _writeTails[playlistId] ?? Future<void>.value();
    final completer = Completer<void>();
    _writeTails[playlistId] = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      completer.complete();
      if (identical(_writeTails[playlistId], completer.future)) {
        _writeTails.remove(playlistId);
      }
    });
  }
}

class SharedPlaylistInvite {
  const SharedPlaylistInvite({
    required this.playlistId,
    required this.role,
    required this.expiresAt,
  });

  final String playlistId;
  final SharedPlaylistRole role;
  final DateTime expiresAt;
}

abstract interface class SharedPlaylistInviteStore {
  Future<String> issue({
    required String playlistId,
    required SharedPlaylistRole role,
    required DateTime expiresAt,
  });

  Future<SharedPlaylistInvite?> lookup(String inviteCode);

  /// Atomically returns and invalidates an invitation code.
  ///
  /// Invitations are capability tokens, so a successful consumption is final
  /// even if a later playlist mutation conflicts and the caller must retry.
  Future<SharedPlaylistInvite?> consume(String inviteCode);

  /// Invalidates every unconsumed invitation for one playlist.
  ///
  /// A code already claimed by [consume] is intentionally not touched so an
  /// in-flight join cannot be interrupted halfway through its atomic claim.
  Future<int> invalidateForPlaylist(String playlistId);
}

class MemorySharedPlaylistInviteStore implements SharedPlaylistInviteStore {
  final Map<String, SharedPlaylistInvite> _invites =
      <String, SharedPlaylistInvite>{};

  @override
  Future<String> issue({
    required String playlistId,
    required SharedPlaylistRole role,
    required DateTime expiresAt,
  }) async {
    final code = newSharedPlaylistInviteCode();
    _invites[code] = SharedPlaylistInvite(
      playlistId: playlistId,
      role: role,
      expiresAt: expiresAt.toUtc(),
    );
    return code;
  }

  @override
  Future<SharedPlaylistInvite?> lookup(String inviteCode) async =>
      isSharedPlaylistInviteCode(inviteCode) ? _invites[inviteCode] : null;

  @override
  Future<SharedPlaylistInvite?> consume(String inviteCode) async {
    if (!isSharedPlaylistInviteCode(inviteCode)) {
      return null;
    }
    return _invites.remove(inviteCode);
  }

  @override
  Future<int> invalidateForPlaylist(String playlistId) async {
    var invalidated = 0;
    final codes = _invites.entries
        .where((entry) => entry.value.playlistId == playlistId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final code in codes) {
      if (_invites.remove(code) != null) {
        invalidated += 1;
      }
    }
    return invalidated;
  }
}

class FileSharedPlaylistInviteStore implements SharedPlaylistInviteStore {
  FileSharedPlaylistInviteStore(this.rootDirectory);

  final Directory rootDirectory;

  @override
  Future<String> issue({
    required String playlistId,
    required SharedPlaylistRole role,
    required DateTime expiresAt,
  }) async {
    await rootDirectory.create(recursive: true);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final code = newSharedPlaylistInviteCode();
      final file = _fileFor(code);
      if (await file.exists()) {
        continue;
      }
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'playlistId': playlistId,
          'role': sharedPlaylistRoleToWire(role),
          'expiresAt': expiresAt.toUtc().toIso8601String(),
        }),
        flush: true,
      );
      return code;
    }
    throw StateError('Could not allocate a shared-playlist invite.');
  }

  @override
  Future<SharedPlaylistInvite?> lookup(String inviteCode) async {
    if (!isSharedPlaylistInviteCode(inviteCode)) {
      return null;
    }
    final file = _fileFor(inviteCode);
    if (!await file.exists()) {
      return null;
    }
    return _readInviteFile(file);
  }

  @override
  Future<SharedPlaylistInvite?> consume(String inviteCode) async {
    if (!isSharedPlaylistInviteCode(inviteCode)) {
      return null;
    }
    final source = _fileFor(inviteCode);
    if (!await source.exists()) {
      return null;
    }
    final claimed = File(
      p.join(
        rootDirectory.path,
        '.${source.uri.pathSegments.last}.${DateTime.now().microsecondsSinceEpoch}.claimed',
      ),
    );
    try {
      await source.rename(claimed.path);
    } on FileSystemException {
      return null;
    }
    try {
      return await _readInviteFile(claimed);
    } finally {
      if (await claimed.exists()) {
        await claimed.delete();
      }
    }
  }

  @override
  Future<int> invalidateForPlaylist(String playlistId) async {
    if (!_isSharedPlaylistId(playlistId) || !await rootDirectory.exists()) {
      return 0;
    }
    var invalidated = 0;
    await for (final entity in rootDirectory.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      final invite = await _readInviteFile(entity);
      if (invite?.playlistId != playlistId) {
        continue;
      }
      try {
        await entity.delete();
        invalidated += 1;
      } on FileSystemException {
        // A concurrent consume/delete won the race; that code is invalid too.
      }
    }
    return invalidated;
  }

  File _fileFor(String code) {
    final digest = sha256.convert(utf8.encode(code)).toString();
    return File(p.join(rootDirectory.path, '$digest.json'));
  }

  Future<SharedPlaylistInvite?> _readInviteFile(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final playlistId = decoded['playlistId'];
      final role = sharedPlaylistRoleFromWire(decoded['role']);
      final expiresAt = decoded['expiresAt'];
      if (playlistId is! String ||
          !_isSharedPlaylistId(playlistId) ||
          role == null ||
          expiresAt is! String) {
        return null;
      }
      final parsedExpiresAt = DateTime.tryParse(expiresAt)?.toUtc();
      if (parsedExpiresAt == null) {
        return null;
      }
      return SharedPlaylistInvite(
        playlistId: playlistId,
        role: role,
        expiresAt: parsedExpiresAt,
      );
    } on Object {
      return null;
    }
  }
}

void validateSharedPlaylistDocument(Map<String, Object?> document) {
  const allowed = <String>{'version', 'name', 'trackIds'};
  if (document.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Shared playlists contain unsupported fields.');
  }
  final name = document['name'];
  final trackIds = document['trackIds'];
  if (document['version'] != 1 ||
      name is! String ||
      name != name.trim() ||
      name.isEmpty ||
      name.length > 160 ||
      trackIds is! List ||
      trackIds.length > 500) {
    throw const FormatException('Shared playlist document is invalid.');
  }
  for (final trackId in trackIds) {
    if (trackId is! String ||
        trackId != trackId.trim() ||
        trackId.isEmpty ||
        trackId.length > 256) {
      throw const FormatException('Shared playlist track IDs are invalid.');
    }
  }
}

SharedPlaylistRecord _newSharedPlaylistRecord({
  required String playlistId,
  required String ownerId,
  required int revision,
  required String deviceId,
  required Map<String, Object?> document,
  required Map<String, SharedPlaylistRole> collaborators,
  required DateTime updatedAt,
}) {
  if (!_isSharedPlaylistId(playlistId) ||
      !_isAccountId(ownerId) ||
      revision <= 0 ||
      deviceId.trim().isEmpty ||
      deviceId.length > 128) {
    throw const FormatException('Shared playlist metadata is invalid.');
  }
  final copiedDocument = Map<String, Object?>.from(document);
  validateSharedPlaylistDocument(copiedDocument);
  final copiedCollaborators = <String, SharedPlaylistRole>{};
  for (final entry in collaborators.entries) {
    if (!_isAccountId(entry.key) || entry.key == ownerId) {
      throw const FormatException('Shared playlist collaborators are invalid.');
    }
    copiedCollaborators[entry.key] = entry.value;
  }
  return SharedPlaylistRecord(
    id: playlistId,
    ownerId: ownerId,
    revision: revision,
    updatedAt: updatedAt.toUtc(),
    updatedByDevice: deviceId.trim(),
    checksum: sha256.convert(utf8.encode(jsonEncode(copiedDocument))).toString(),
    document: Map<String, Object?>.unmodifiable(copiedDocument),
    collaborators: Map<String, SharedPlaylistRole>.unmodifiable(copiedCollaborators),
  );
}

bool isSharedPlaylistInviteCode(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);

String newSharedPlaylistInviteCode() => base64Url.encode(
  List<int>.generate(18, (_) => _sharedPlaylistRandom.nextInt(256)),
);

String newSharedPlaylistId() => base64Url.encode(
  List<int>.generate(18, (_) => _sharedPlaylistRandom.nextInt(256)),
);

bool _isSharedPlaylistId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);

bool _isAccountId(String value) =>
    value.trim().isNotEmpty && value.length <= 256;

final _sharedPlaylistRandom = Random.secure();
