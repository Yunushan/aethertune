import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'src/authentication.dart';

export 'src/authentication.dart';

const _jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};
const maxSyncSnapshotBytes = 8 * 1024 * 1024;
const maxManagedAuthRequestBytes = 16 * 1024;

typedef ServerRequestLogger = void Function(ServerRequestLogEntry entry);

class ServerRequestLogEntry {
  const ServerRequestLogEntry({
    required this.timestamp,
    required this.method,
    required this.route,
    required this.statusCode,
    required this.durationMilliseconds,
  });

  final DateTime timestamp;
  final String method;
  final String route;
  final int statusCode;
  final int durationMilliseconds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'timestamp': timestamp.toUtc().toIso8601String(),
      'method': method,
      'route': route,
      'statusCode': statusCode,
      'durationMilliseconds': durationMilliseconds,
    };
  }
}

const _tracks = <CatalogTrack>[
  CatalogTrack(
    id: 'local-files',
    title: 'Local Files',
    artist: 'AetherTune',
    album: 'Core Sources',
    sourceId: 'local',
  ),
  CatalogTrack(
    id: 'self-hosted',
    title: 'Self-hosted Library',
    artist: 'Jellyfin / Navidrome / Subsonic',
    album: 'Server Roadmap',
    sourceId: 'self-hosted',
  ),
  CatalogTrack(
    id: 'open-catalogs',
    title: 'Open Catalogs',
    artist: 'Podcasts / Radio / Internet Archive',
    album: 'Provider Roadmap',
    sourceId: 'open-catalogs',
  ),
];

Handler createServerHandler({
  DateTime Function()? clock,
  SyncAuthenticator? syncAuthenticator,
  ManagedSyncAccountRegistry? managedSyncAccounts,
  OperationsAuthenticator? operationsAuthenticator,
  LibrarySyncSnapshotStore? syncStore,
  ServerRequestLogger? requestLogger,
}) {
  final now = clock ?? DateTime.now;
  final authenticator = syncAuthenticator ?? const DisabledSyncAuthenticator();
  final operations =
      operationsAuthenticator ?? const DisabledOperationsAuthenticator();
  final snapshots = syncStore ?? MemoryLibrarySyncSnapshotStore();
  final startedAt = now().toUtc();
  var requestsTotal = 0;

  Future<Response> route(Request request) async {
    switch (request.url.path) {
      case 'health':
        if (request.method != 'GET') {
          return _methodNotAllowed(request);
        }
        return _jsonResponse(
          200,
          <String, Object?>{
            'status': 'ok',
            'service': 'aethertune-server',
            'timestamp': now().toUtc().toIso8601String(),
          },
        );
      case 'api/v1/metrics':
        if (request.method != 'GET') {
          return _methodNotAllowed(request);
        }
        if (operations.isConfigured) {
          final token = _bearerToken(request.headers['authorization'] ?? '');
          if (token == null || !operations.authenticate(token)) {
            return _unauthorizedResponse();
          }
        }
        final uptime = now().toUtc().difference(startedAt);
        return _jsonResponse(
          200,
          <String, Object?>{
            'service': 'aethertune-server',
            'startedAt': startedAt.toIso8601String(),
            'uptimeSeconds': uptime.isNegative ? 0 : uptime.inSeconds,
            'requestsTotal': requestsTotal,
            'librarySync': authenticator.isConfigured,
          },
        );
      case 'api/v1/info':
        if (request.method != 'GET') {
          return _methodNotAllowed(request);
        }
        return _jsonResponse(
          200,
          <String, Object?>{
            'name': 'AetherTune',
            'service': 'aethertune-server',
            'version': '0.3.0',
            'librarySync': authenticator.isConfigured,
            'managedAuthentication': managedSyncAccounts != null,
            'supportedClients': <String>[
              'android',
              'ios',
              'linux',
              'macos',
              'windows',
            ],
          },
        );
      case 'api/v1/tracks':
        if (request.method != 'GET') {
          return _methodNotAllowed(request);
        }
        final query = request.url.queryParameters['q'] ?? '';
        return _jsonResponse(
          200,
          <String, Object?>{
            'tracks': searchCatalog(query)
                .map((track) => track.toJson())
                .toList(growable: false),
          },
        );
      case 'api/v1/auth/profile':
        return _handleAuthProfile(
          request,
          authenticator: authenticator,
          managedAccounts: managedSyncAccounts,
        );
      case 'api/v1/admin/sync-accounts':
        return _handleManagedSyncAccounts(
          request,
          operations: operations,
          managedAccounts: managedSyncAccounts,
        );
      case 'api/v1/admin/sync-tokens':
        return _handleManagedSyncTokens(
          request,
          operations: operations,
          managedAccounts: managedSyncAccounts,
        );
      case 'api/v1/sync/library':
        return _handleLibrarySync(
          request,
          authenticator: authenticator,
          snapshots: snapshots,
          now: now,
        );
      default:
        return _jsonResponse(
          404,
          <String, Object?>{
            'error': 'not_found',
            'path': '/${request.url.path}',
          },
        );
    }
  }

  return (Request request) async {
    requestsTotal += 1;
    final requestStartedAt = now().toUtc();
    try {
      final response = await route(request);
      _writeRequestLog(
        requestLogger,
        request: request,
        response: response,
        requestStartedAt: requestStartedAt,
        finishedAt: now().toUtc(),
      );
      return response;
    } on Object {
      _writeRequestLog(
        requestLogger,
        request: request,
        response: Response.internalServerError(),
        requestStartedAt: requestStartedAt,
        finishedAt: now().toUtc(),
      );
      rethrow;
    }
  };
}

void _writeRequestLog(
  ServerRequestLogger? requestLogger, {
  required Request request,
  required Response response,
  required DateTime requestStartedAt,
  required DateTime finishedAt,
}) {
  if (requestLogger == null) {
    return;
  }

  final elapsed = finishedAt.difference(requestStartedAt);
  try {
    requestLogger(
      ServerRequestLogEntry(
        timestamp: finishedAt,
        method: request.method,
        route: _logRoute(request.url.path),
        statusCode: response.statusCode,
        durationMilliseconds: elapsed.isNegative ? 0 : elapsed.inMilliseconds,
      ),
    );
  } on Object {
    // Logging is optional observability and must not interrupt client requests.
  }
}

String _logRoute(String path) {
  return switch (path) {
    'health' => '/health',
    'api/v1/info' => '/api/v1/info',
    'api/v1/metrics' => '/api/v1/metrics',
    'api/v1/tracks' => '/api/v1/tracks',
    'api/v1/auth/profile' => '/api/v1/auth/profile',
    'api/v1/admin/sync-accounts' => '/api/v1/admin/sync-accounts',
    'api/v1/admin/sync-tokens' => '/api/v1/admin/sync-tokens',
    'api/v1/sync/library' => '/api/v1/sync/library',
    _ => '/not-found',
  };
}

Future<Response> _handleAuthProfile(
  Request request, {
  required SyncAuthenticator authenticator,
  required ManagedSyncAccountRegistry? managedAccounts,
}) async {
  if (request.method != 'GET') {
    return _methodNotAllowed(request);
  }
  if (!authenticator.isConfigured) {
    return _jsonResponse(
      503,
      <String, Object?>{'error': 'sync_not_configured'},
    );
  }

  final token = _bearerToken(request.headers['authorization'] ?? '');
  final accountId = token == null ? null : authenticator.authenticate(token);
  if (accountId == null) {
    return _unauthorizedResponse();
  }
  final principal =
      token == null ? null : managedAccounts?.authenticatePrincipal(token);
  final managedProfile =
      principal == null ? null : managedAccounts?.account(principal.accountId);
  return _jsonResponse(
    200,
    <String, Object?>{
      'account': <String, Object?>{
        'id': accountId,
        'displayName': managedProfile?.displayName,
        'managed': managedProfile != null,
      },
      'device': principal?.token.toJson(),
    },
  );
}

Future<Response> _handleManagedSyncAccounts(
  Request request, {
  required OperationsAuthenticator operations,
  required ManagedSyncAccountRegistry? managedAccounts,
}) async {
  final rejection = _managedAuthAdminRejection(request, operations);
  if (rejection != null) {
    return rejection;
  }
  if (managedAccounts == null) {
    return _jsonResponse(
      503,
      <String, Object?>{'error': 'managed_auth_not_configured'},
    );
  }
  if (request.method != 'GET') {
    return _methodNotAllowed(request);
  }
  return _jsonResponse(
    200,
    <String, Object?>{
      'accounts': managedAccounts.accounts
          .map((account) => account.toJson())
          .toList(growable: false),
    },
  );
}

Future<Response> _handleManagedSyncTokens(
  Request request, {
  required OperationsAuthenticator operations,
  required ManagedSyncAccountRegistry? managedAccounts,
}) async {
  final rejection = _managedAuthAdminRejection(request, operations);
  if (rejection != null) {
    return rejection;
  }
  if (managedAccounts == null) {
    return _jsonResponse(
      503,
      <String, Object?>{'error': 'managed_auth_not_configured'},
    );
  }
  if (request.method != 'POST' && request.method != 'DELETE') {
    return _methodNotAllowed(request);
  }

  try {
    final body = await _readBoundedJson(
      request,
      maxBytes: maxManagedAuthRequestBytes,
    );
    final accountId = _requiredString(body, 'accountId');
    if (request.method == 'DELETE') {
      final tokenId = _requiredString(body, 'tokenId');
      final revoked = await managedAccounts.revokeToken(
        accountId: accountId,
        tokenId: tokenId,
      );
      if (!revoked) {
        return _jsonResponse(
          404,
          <String, Object?>{'error': 'managed_token_not_found'},
        );
      }
      return _jsonResponse(
        200,
        <String, Object?>{
          'revoked': true,
          'accountId': accountId,
          'tokenId': tokenId,
        },
      );
    }

    final displayName = _optionalString(body, 'displayName');
    final deviceName = _requiredString(body, 'deviceName');
    final replaceTokenId = _optionalString(body, 'replaceTokenId');
    final issued = await managedAccounts.issueToken(
      accountId: accountId,
      displayName: displayName,
      deviceName: deviceName,
      replaceTokenId: replaceTokenId,
    );
    return _jsonResponse(
      201,
      <String, Object?>{
        'tokenType': 'Bearer',
        'token': issued.token,
        'account': issued.account.toJson(),
        'device': issued.device.toJson(),
        'replacedTokenId': issued.replacedTokenId,
      },
    );
  } on _PayloadTooLarge catch (error) {
    return _jsonResponse(
      413,
      <String, Object?>{
        'error': 'payload_too_large',
        'maxBytes': error.maxBytes,
      },
    );
  } on FormatException catch (error) {
    return _jsonResponse(
      400,
      <String, Object?>{
        'error': 'invalid_auth_request',
        'message': error.message,
      },
    );
  }
}

Response? _managedAuthAdminRejection(
  Request request,
  OperationsAuthenticator operations,
) {
  if (!operations.isConfigured) {
    return _jsonResponse(
      503,
      <String, Object?>{'error': 'operations_auth_not_configured'},
    );
  }
  final token = _bearerToken(request.headers['authorization'] ?? '');
  if (token == null || !operations.authenticate(token)) {
    return _unauthorizedResponse();
  }
  return null;
}

String _requiredString(Map<String, Object?> body, String fieldName) {
  final value = body[fieldName];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName is required.');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> body, String fieldName) {
  final value = body[fieldName];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$fieldName must be a non-empty string.');
  }
  return value.trim();
}

Future<Response> _handleLibrarySync(
  Request request, {
  required SyncAuthenticator authenticator,
  required LibrarySyncSnapshotStore snapshots,
  required DateTime Function() now,
}) async {
  if (!authenticator.isConfigured) {
    return _jsonResponse(
      503,
      <String, Object?>{'error': 'sync_not_configured'},
    );
  }

  final authorization = request.headers['authorization'] ?? '';
  final token = _bearerToken(authorization);
  final userId = token == null ? null : authenticator.authenticate(token);
  if (userId == null) {
    return _unauthorizedResponse();
  }

  switch (request.method) {
    case 'GET':
      final snapshot = await snapshots.read(userId);
      return _jsonResponse(
        200,
        snapshot?.toResponseJson() ??
            <String, Object?>{
              'revision': 0,
              'updatedAt': null,
              'updatedByDevice': null,
              'checksum': null,
              'snapshot': null,
            },
      );
    case 'PUT':
      try {
        final body = await _readBoundedJson(request);
        final mutation = _syncMutationFields(body);
        final rawSnapshot = body['snapshot'];
        if (rawSnapshot is! Map) {
          throw const FormatException('snapshot must be an object.');
        }
        final snapshot = Map<String, Object?>.from(rawSnapshot);
        _validateSyncSnapshot(snapshot);
        final canonicalSnapshot = jsonEncode(snapshot);
        final checksum =
            sha256.convert(utf8.encode(canonicalSnapshot)).toString();
        final result = await snapshots.write(
          userId: userId,
          baseRevision: mutation.baseRevision,
          deviceId: mutation.deviceId,
          snapshot: snapshot,
          checksum: checksum,
          updatedAt: now().toUtc(),
        );
        if (result.isConflict) {
          final current = result.snapshot;
          return _jsonResponse(
            409,
            <String, Object?>{
              'error': 'sync_conflict',
              'currentRevision': current?.revision ?? 0,
              'updatedAt': current?.updatedAt.toIso8601String(),
              'updatedByDevice': current?.updatedByDevice,
              'checksum': current?.checksum,
            },
          );
        }
        return _jsonResponse(200, result.snapshot!.toMetadataJson());
      } on _PayloadTooLarge catch (error) {
        return _jsonResponse(
          413,
          <String, Object?>{
            'error': 'payload_too_large',
            'maxBytes': error.maxBytes,
          },
        );
      } on FormatException catch (error) {
        return _jsonResponse(
          400,
          <String, Object?>{
            'error': 'invalid_sync_snapshot',
            'message': error.message,
          },
        );
      }
    case 'DELETE':
      try {
        final mutation = _syncMutationFields(await _readBoundedJson(request));
        final result = await snapshots.delete(
          userId: userId,
          baseRevision: mutation.baseRevision,
          deviceId: mutation.deviceId,
          updatedAt: now().toUtc(),
        );
        if (result.isConflict) {
          final current = result.snapshot;
          return _jsonResponse(
            409,
            <String, Object?>{
              'error': 'sync_conflict',
              'currentRevision': current?.revision ?? 0,
              'updatedAt': current?.updatedAt.toIso8601String(),
              'updatedByDevice': current?.updatedByDevice,
              'checksum': current?.checksum,
            },
          );
        }
        return _jsonResponse(200, result.snapshot!.toMetadataJson());
      } on _PayloadTooLarge catch (error) {
        return _jsonResponse(
          413,
          <String, Object?>{
            'error': 'payload_too_large',
            'maxBytes': error.maxBytes,
          },
        );
      } on FormatException catch (error) {
        return _jsonResponse(
          400,
          <String, Object?>{
            'error': 'invalid_sync_snapshot',
            'message': error.message,
          },
        );
      }
    default:
      return _methodNotAllowed(request);
  }
}

({int baseRevision, String deviceId}) _syncMutationFields(
  Map<String, Object?> body,
) {
  final baseRevision = body['baseRevision'];
  final rawDeviceId = body['deviceId'];
  if (baseRevision is! int || baseRevision < 0) {
    throw const FormatException('baseRevision must be a non-negative integer.');
  }
  if (rawDeviceId is! String || rawDeviceId.trim().isEmpty) {
    throw const FormatException('deviceId is required.');
  }
  final deviceId = rawDeviceId.trim();
  if (deviceId.length > 128) {
    throw const FormatException('deviceId is too long.');
  }
  return (baseRevision: baseRevision, deviceId: deviceId);
}

Future<Map<String, Object?>> _readBoundedJson(
  Request request, {
  int maxBytes = maxSyncSnapshotBytes,
}) async {
  final builder = BytesBuilder(copy: false);
  var byteCount = 0;
  await for (final chunk in request.read()) {
    byteCount += chunk.length;
    if (byteCount > maxBytes) {
      throw _PayloadTooLarge(maxBytes);
    }
    builder.add(chunk);
  }

  final decoded = jsonDecode(utf8.decode(builder.takeBytes()));
  if (decoded is! Map) {
    throw const FormatException('Request body must be an object.');
  }
  return Map<String, Object?>.from(decoded);
}

void _validateSyncSnapshot(Map<String, Object?> snapshot) {
  if (snapshot['syncVersion'] != 1 || snapshot['version'] != 1) {
    throw const FormatException('Unsupported sync snapshot version.');
  }
  final tracks = snapshot['tracks'];
  if (tracks is! List) {
    throw const FormatException('Snapshot tracks must be a list.');
  }
  for (final item in tracks) {
    if (item is! Map) {
      throw const FormatException('Snapshot contains an invalid track.');
    }
    final track = Map<String, Object?>.from(item);
    final localPath = track['localPath'];
    if (localPath is String && localPath.trim().isNotEmpty) {
      throw const FormatException(
        'Portable sync snapshots cannot contain local file paths.',
      );
    }
  }
  final offlineQueue = snapshot['offlineCacheQueue'];
  if (offlineQueue is List && offlineQueue.isNotEmpty) {
    throw const FormatException(
      'Portable sync snapshots cannot contain device cache jobs.',
    );
  }
}

String? _bearerToken(String authorization) {
  final match = RegExp(r'^Bearer\s+([^\s]+)$', caseSensitive: false).firstMatch(
    authorization.trim(),
  );
  return match?.group(1);
}

Response _unauthorizedResponse() {
  return _jsonResponse(
    401,
    <String, Object?>{'error': 'unauthorized'},
    headers: const <String, String>{'www-authenticate': 'Bearer'},
  );
}

List<CatalogTrack> searchCatalog(String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    return _tracks;
  }

  return _tracks.where((track) => track.matches(normalized)).toList();
}

Response _methodNotAllowed(Request request) {
  return _jsonResponse(
    405,
    <String, Object?>{
      'error': 'method_not_allowed',
      'method': request.method,
    },
  );
}

Response _jsonResponse(
  int statusCode,
  Map<String, Object?> body, {
  Map<String, String> headers = const <String, String>{},
}) {
  return Response(
    statusCode,
    body: jsonEncode(body),
    headers: <String, String>{..._jsonHeaders, ...headers},
  );
}

class LibrarySyncSnapshot {
  const LibrarySyncSnapshot({
    required this.revision,
    required this.updatedAt,
    required this.updatedByDevice,
    this.checksum,
    this.snapshot,
  }) : assert((checksum == null) == (snapshot == null));

  const LibrarySyncSnapshot.deleted({
    required this.revision,
    required this.updatedAt,
    required this.updatedByDevice,
  })  : checksum = null,
        snapshot = null;

  final int revision;
  final DateTime updatedAt;
  final String updatedByDevice;
  final String? checksum;
  final Map<String, Object?>? snapshot;

  Map<String, Object?> toMetadataJson() {
    return <String, Object?>{
      'revision': revision,
      'updatedAt': updatedAt.toIso8601String(),
      'updatedByDevice': updatedByDevice,
      'checksum': checksum,
    };
  }

  Map<String, Object?> toResponseJson() {
    return <String, Object?>{
      ...toMetadataJson(),
      'snapshot': snapshot,
    };
  }

  Map<String, Object?> toStorageJson() => toResponseJson();

  factory LibrarySyncSnapshot.fromStorageJson(Map<String, Object?> json) {
    final revision = json['revision'];
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    final updatedByDevice = json['updatedByDevice'];
    final checksum = json['checksum'];
    final rawSnapshot = json['snapshot'];
    if (revision is! int ||
        revision <= 0 ||
        updatedAt == null ||
        updatedByDevice is! String) {
      throw const FormatException('Stored sync snapshot is invalid.');
    }
    if (rawSnapshot == null) {
      if (checksum != null) {
        throw const FormatException('Stored sync deletion is invalid.');
      }
      return LibrarySyncSnapshot.deleted(
        revision: revision,
        updatedAt: updatedAt.toUtc(),
        updatedByDevice: updatedByDevice,
      );
    }
    if (checksum is! String || rawSnapshot is! Map) {
      throw const FormatException('Stored sync snapshot is invalid.');
    }
    final snapshot = Map<String, Object?>.from(rawSnapshot);
    final actualChecksum =
        sha256.convert(utf8.encode(jsonEncode(snapshot))).toString();
    if (actualChecksum != checksum) {
      throw const FormatException(
        'Stored sync snapshot checksum does not match.',
      );
    }
    return LibrarySyncSnapshot(
      revision: revision,
      updatedAt: updatedAt.toUtc(),
      updatedByDevice: updatedByDevice,
      checksum: checksum,
      snapshot: snapshot,
    );
  }
}

class LibrarySyncWriteResult {
  const LibrarySyncWriteResult._({
    required this.isConflict,
    required this.snapshot,
  });

  factory LibrarySyncWriteResult.saved(LibrarySyncSnapshot snapshot) {
    return LibrarySyncWriteResult._(isConflict: false, snapshot: snapshot);
  }

  factory LibrarySyncWriteResult.conflict(LibrarySyncSnapshot? snapshot) {
    return LibrarySyncWriteResult._(isConflict: true, snapshot: snapshot);
  }

  final bool isConflict;
  final LibrarySyncSnapshot? snapshot;
}

abstract interface class LibrarySyncSnapshotStore {
  Future<LibrarySyncSnapshot?> read(String userId);

  Future<LibrarySyncWriteResult> write({
    required String userId,
    required int baseRevision,
    required String deviceId,
    required Map<String, Object?> snapshot,
    required String checksum,
    required DateTime updatedAt,
  });

  Future<LibrarySyncWriteResult> delete({
    required String userId,
    required int baseRevision,
    required String deviceId,
    required DateTime updatedAt,
  });
}

class MemoryLibrarySyncSnapshotStore implements LibrarySyncSnapshotStore {
  final Map<String, LibrarySyncSnapshot> _snapshots =
      <String, LibrarySyncSnapshot>{};

  @override
  Future<LibrarySyncSnapshot?> read(String userId) async => _snapshots[userId];

  @override
  Future<LibrarySyncWriteResult> write({
    required String userId,
    required int baseRevision,
    required String deviceId,
    required Map<String, Object?> snapshot,
    required String checksum,
    required DateTime updatedAt,
  }) async {
    final current = _snapshots[userId];
    if ((current?.revision ?? 0) != baseRevision) {
      return LibrarySyncWriteResult.conflict(current);
    }
    final saved = LibrarySyncSnapshot(
      revision: baseRevision + 1,
      updatedAt: updatedAt.toUtc(),
      updatedByDevice: deviceId,
      checksum: checksum,
      snapshot: Map<String, Object?>.from(snapshot),
    );
    _snapshots[userId] = saved;
    return LibrarySyncWriteResult.saved(saved);
  }

  @override
  Future<LibrarySyncWriteResult> delete({
    required String userId,
    required int baseRevision,
    required String deviceId,
    required DateTime updatedAt,
  }) async {
    final current = _snapshots[userId];
    if ((current?.revision ?? 0) != baseRevision) {
      return LibrarySyncWriteResult.conflict(current);
    }
    final deleted = LibrarySyncSnapshot.deleted(
      revision: baseRevision + 1,
      updatedAt: updatedAt.toUtc(),
      updatedByDevice: deviceId,
    );
    _snapshots[userId] = deleted;
    return LibrarySyncWriteResult.saved(deleted);
  }
}

class FileLibrarySyncSnapshotStore implements LibrarySyncSnapshotStore {
  FileLibrarySyncSnapshotStore(this.rootDirectory);

  final Directory rootDirectory;
  final Map<String, Future<void>> _writeTails = <String, Future<void>>{};

  @override
  Future<LibrarySyncSnapshot?> read(String userId) {
    return _serialized(userId, () => _readUnlocked(userId));
  }

  @override
  Future<LibrarySyncWriteResult> write({
    required String userId,
    required int baseRevision,
    required String deviceId,
    required Map<String, Object?> snapshot,
    required String checksum,
    required DateTime updatedAt,
  }) {
    return _serialized(userId, () async {
      final current = await _readUnlocked(userId);
      if ((current?.revision ?? 0) != baseRevision) {
        return LibrarySyncWriteResult.conflict(current);
      }

      final saved = LibrarySyncSnapshot(
        revision: baseRevision + 1,
        updatedAt: updatedAt.toUtc(),
        updatedByDevice: deviceId,
        checksum: checksum,
        snapshot: Map<String, Object?>.from(snapshot),
      );
      await _writeUnlocked(userId, saved);
      return LibrarySyncWriteResult.saved(saved);
    });
  }

  @override
  Future<LibrarySyncWriteResult> delete({
    required String userId,
    required int baseRevision,
    required String deviceId,
    required DateTime updatedAt,
  }) {
    return _serialized(userId, () async {
      final current = await _readUnlocked(userId);
      if ((current?.revision ?? 0) != baseRevision) {
        return LibrarySyncWriteResult.conflict(current);
      }
      final deleted = LibrarySyncSnapshot.deleted(
        revision: baseRevision + 1,
        updatedAt: updatedAt.toUtc(),
        updatedByDevice: deviceId,
      );
      await _writeUnlocked(userId, deleted);
      return LibrarySyncWriteResult.saved(deleted);
    });
  }

  Future<void> _writeUnlocked(
    String userId,
    LibrarySyncSnapshot saved,
  ) async {
    final directory = _userDirectory(userId);
    await directory.create(recursive: true);
    final finalFile = File(
      p.join(directory.path, 'snapshot-${saved.revision}.json'),
    );
    final temporaryFile = File(
      p.join(
        directory.path,
        '.snapshot-${saved.revision}-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    await temporaryFile.writeAsString(
      jsonEncode(saved.toStorageJson()),
      flush: true,
    );
    await temporaryFile.rename(finalFile.path);

    await for (final entity in directory.list()) {
      if (entity is File &&
          entity.path != finalFile.path &&
          p.basename(entity.path).startsWith('snapshot-') &&
          p.extension(entity.path) == '.json') {
        try {
          await entity.delete();
        } on FileSystemException {
          // The newest complete revision is already durable.
        }
      }
    }
  }

  Future<LibrarySyncSnapshot?> _readUnlocked(String userId) async {
    final directory = _userDirectory(userId);
    if (!await directory.exists()) {
      return null;
    }
    final candidates = <({int revision, File file})>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      final match = RegExp(r'^snapshot-(\d+)\.json$').firstMatch(
        p.basename(entity.path),
      );
      final revision = int.tryParse(match?.group(1) ?? '');
      if (revision != null) {
        candidates.add((revision: revision, file: entity));
      }
    }
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((left, right) => right.revision.compareTo(left.revision));
    final decoded = jsonDecode(await candidates.first.file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('Stored sync snapshot must be an object.');
    }
    return LibrarySyncSnapshot.fromStorageJson(
      Map<String, Object?>.from(decoded),
    );
  }

  Directory _userDirectory(String userId) {
    final userHash = sha256.convert(utf8.encode(userId)).toString();
    return Directory(p.join(rootDirectory.path, userHash));
  }

  Future<T> _serialized<T>(String userId, Future<T> Function() action) {
    final previous = _writeTails[userId] ?? Future<void>.value();
    final completer = Completer<void>();
    _writeTails[userId] = completer.future;
    return previous.then((_) => action()).whenComplete(() {
      completer.complete();
      if (identical(_writeTails[userId], completer.future)) {
        _writeTails.remove(userId);
      }
    });
  }
}

class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.sourceId,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String sourceId;

  bool matches(String query) {
    return title.toLowerCase().contains(query) ||
        artist.toLowerCase().contains(query) ||
        album.toLowerCase().contains(query) ||
        sourceId.toLowerCase().contains(query);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'artist': artist,
      'album': album,
      'sourceId': sourceId,
    };
  }
}

class _PayloadTooLarge implements Exception {
  const _PayloadTooLarge(this.maxBytes);

  final int maxBytes;
}
