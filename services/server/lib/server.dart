import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import 'src/authentication.dart';
import 'src/shared_playlists.dart';

export 'src/authentication.dart';
export 'src/shared_playlists.dart';

const _jsonHeaders = <String, String>{
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};
const maxSyncSnapshotBytes = 8 * 1024 * 1024;
const maxManagedAuthRequestBytes = 16 * 1024;
const maxListenTogetherSessionBytes = 32 * 1024;
const maxSharedPlaylistBytes = 64 * 1024;
final _listenTogetherInviteRandom = Random.secure();

typedef ServerRequestLogger = void Function(ServerRequestLogEntry entry);

final class ServerRequestRateLimiter {
  ServerRequestRateLimiter({
    this.maximumRequests = 120,
    this.maximumBuckets = 4096,
    this.window = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (maximumRequests <= 0 || maximumBuckets <= 0 || window <= Duration.zero) {
      throw ArgumentError('Rate limit bounds must be positive.');
    }
  }

  final int maximumRequests;
  final int maximumBuckets;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, _RateLimitWindow> _windows = <String, _RateLimitWindow>{};

  Duration? check(Request request) {
    final now = _clock().toUtc();
    final token = _bearerToken(request.headers['authorization'] ?? '');
    final key = token == null
        ? 'anonymous'
        : sha256.convert(utf8.encode(token)).toString();
    _windows.removeWhere(
      (_, entry) => !now.isBefore(entry.startedAt.add(window)),
    );
    final current = _windows[key];
    if (current == null && _windows.length >= maximumBuckets) {
      return window;
    }
    if (current == null || !now.isBefore(current.startedAt.add(window))) {
      _windows[key] = _RateLimitWindow(now, 1);
      return null;
    }
    if (current.requests >= maximumRequests) {
      return current.startedAt.add(window).difference(now);
    }
    current.requests += 1;
    return null;
  }
}

ServerRequestRateLimiter serverRequestRateLimiterFromEnvironment(
  Map<String, String> environment, {
  DateTime Function()? clock,
}) {
  final raw = environment['AETHERTUNE_RATE_LIMIT_PER_MINUTE'];
  if (raw == null || raw.trim().isEmpty) {
    return ServerRequestRateLimiter(clock: clock);
  }
  final maximumRequests = int.tryParse(raw.trim());
  if (maximumRequests == null || maximumRequests <= 0) {
    throw const FormatException(
      'AETHERTUNE_RATE_LIMIT_PER_MINUTE must be a positive integer.',
    );
  }
  return ServerRequestRateLimiter(
    maximumRequests: maximumRequests,
    clock: clock,
  );
}

final class _RateLimitWindow {
  _RateLimitWindow(this.startedAt, this.requests);

  final DateTime startedAt;
  int requests;
}

/// Resolves the network interface used by the server executable.
///
/// Native deployments stay private by default. Containers must explicitly set
/// `0.0.0.0` because their loopback interface is isolated from the published
/// host port.
InternetAddress serverListenAddress(String? configuredAddress) {
  final normalized = configuredAddress?.trim();
  if (normalized == null || normalized.isEmpty) {
    return InternetAddress.loopbackIPv4;
  }
  final address = InternetAddress.tryParse(normalized);
  if (address == null) {
    throw FormatException(
      'AETHERTUNE_LISTEN_ADDRESS must be an IPv4 or IPv6 address.',
    );
  }
  return address;
}

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
  LibrarySyncSnapshotStore? listenTogetherStore,
  ListenTogetherInviteStore? listenTogetherInviteStore,
  SharedPlaylistStore? sharedPlaylistStore,
  SharedPlaylistInviteStore? sharedPlaylistInviteStore,
  ServerRequestLogger? requestLogger,
  ServerRequestRateLimiter? requestRateLimiter,
}) {
  final now = clock ?? DateTime.now;
  final authenticator = syncAuthenticator ?? const DisabledSyncAuthenticator();
  final operations =
      operationsAuthenticator ?? const DisabledOperationsAuthenticator();
  final snapshots = syncStore ?? MemoryLibrarySyncSnapshotStore();
  final sessions = listenTogetherStore ?? MemoryLibrarySyncSnapshotStore();
  final invites = listenTogetherInviteStore ?? MemoryListenTogetherInviteStore();
  final sharedPlaylists = sharedPlaylistStore ?? MemorySharedPlaylistStore();
  final sharedPlaylistInvites =
      sharedPlaylistInviteStore ?? MemorySharedPlaylistInviteStore();
  final startedAt = now().toUtc();
  var requestsTotal = 0;
  final rateLimiter = requestRateLimiter ?? ServerRequestRateLimiter(clock: now);

  Future<Response> route(Request request) async {
    if (request.url.path.startsWith('api/v1/public-profiles/')) {
      return _handlePublicProfile(request, managedAccounts: managedSyncAccounts);
    }
    if (request.url.path.startsWith('api/v1/shared-playlist-invites/')) {
      return _handleSharedPlaylistInviteJoin(
        request,
        authenticator: authenticator,
        playlists: sharedPlaylists,
        invites: sharedPlaylistInvites,
        now: now,
      );
    }
    if (request.url.path.startsWith('api/v1/shared-playlists/')) {
      return _handleSharedPlaylistItem(
        request,
        authenticator: authenticator,
        playlists: sharedPlaylists,
        invites: sharedPlaylistInvites,
        now: now,
      );
    }
    if (request.url.path.startsWith('api/v1/listen-together/invites/')) {
      return _handleListenTogetherInviteJoin(
        request,
        authenticator: authenticator,
        sessions: sessions,
        invites: invites,
      );
    }
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
            'listenTogether': authenticator.isConfigured,
            'sharedPlaylists': authenticator.isConfigured,
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
            'listenTogether': authenticator.isConfigured,
            'sharedPlaylists': authenticator.isConfigured,
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
      case 'api/v1/admin/sync-recovery-codes':
        return _handleManagedRecoveryCodeIssue(
          request,
          operations: operations,
          managedAccounts: managedSyncAccounts,
        );
      case 'api/v1/sync/recovery':
        return _handleManagedRecoveryRedemption(
          request,
          managedAccounts: managedSyncAccounts,
        );
      case 'api/v1/sync/library':
        return _handleLibrarySync(
          request,
          authenticator: authenticator,
          snapshots: snapshots,
          now: now,
        );
      case 'api/v1/sync/library/metadata':
        return _handleLibrarySyncMetadata(
          request,
          authenticator: authenticator,
          snapshots: snapshots,
        );
      case 'api/v1/listen-together/session':
        return _handleListenTogetherSession(
          request,
          authenticator: authenticator,
          sessions: sessions,
          now: now,
        );
      case 'api/v1/listen-together/session/invite':
        return _handleListenTogetherInviteIssue(
          request,
          authenticator: authenticator,
          sessions: sessions,
          invites: invites,
        );
      case 'api/v1/shared-playlists':
        return _handleSharedPlaylistCollection(
          request,
          authenticator: authenticator,
          playlists: sharedPlaylists,
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
      final retryAfter = rateLimiter.check(request);
      if (retryAfter != null) {
        final response = _jsonResponse(
          429,
          <String, Object?>{'error': 'rate_limited'},
          headers: <String, String>{
            'retry-after': retryAfter.inSeconds.clamp(1, 60).toString(),
          },
        );
        _writeRequestLog(
          requestLogger,
          request: request,
          response: response,
          requestStartedAt: requestStartedAt,
          finishedAt: now().toUtc(),
        );
        return response;
      }
      await _recordManagedDeviceActivity(
        request,
        authenticator: authenticator,
        managedAccounts: managedSyncAccounts,
      );
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

Future<void> _recordManagedDeviceActivity(
  Request request, {
  required SyncAuthenticator authenticator,
  required ManagedSyncAccountRegistry? managedAccounts,
}) async {
  if (managedAccounts == null || !_isManagedActivityRoute(request.url.path)) {
    return;
  }
  final token = _bearerToken(request.headers['authorization'] ?? '');
  if (token == null) {
    return;
  }
  final authenticatedAccountId = authenticator.authenticate(token);
  final principal = managedAccounts.authenticatePrincipal(token);
  if (authenticatedAccountId == null ||
      principal == null ||
      principal.accountId != authenticatedAccountId) {
    return;
  }

  try {
    await managedAccounts.recordAuthenticatedUse(
      accountId: principal.accountId,
      tokenId: principal.token.id,
    );
  } on Object {
    // Device activity is operational metadata and must not deny playback or
    // sync if its durable write is temporarily unavailable.
  }
}

bool _isManagedActivityRoute(String path) {
  return path == 'api/v1/auth/profile' ||
      path == 'api/v1/sync/library' ||
      path == 'api/v1/sync/library/metadata' ||
      path == 'api/v1/listen-together/session' ||
      path == 'api/v1/listen-together/session/invite' ||
      path.startsWith('api/v1/listen-together/invites/') ||
      path == 'api/v1/shared-playlists' ||
      path.startsWith('api/v1/shared-playlists/') ||
      path.startsWith('api/v1/shared-playlist-invites/');
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
  if (path.startsWith('api/v1/listen-together/invites/')) {
    return '/api/v1/listen-together/invites/:code';
  }
  if (path.startsWith('api/v1/shared-playlist-invites/')) {
    return '/api/v1/shared-playlist-invites/:code';
  }
  if (path.startsWith('api/v1/shared-playlists/')) {
    return '/api/v1/shared-playlists/:id';
  }
  return switch (path) {
    'health' => '/health',
    'api/v1/info' => '/api/v1/info',
    'api/v1/metrics' => '/api/v1/metrics',
    'api/v1/tracks' => '/api/v1/tracks',
    'api/v1/auth/profile' => '/api/v1/auth/profile',
    'api/v1/admin/sync-accounts' => '/api/v1/admin/sync-accounts',
    'api/v1/admin/sync-tokens' => '/api/v1/admin/sync-tokens',
    'api/v1/sync/library' => '/api/v1/sync/library',
    'api/v1/sync/library/metadata' => '/api/v1/sync/library/metadata',
    'api/v1/listen-together/session' => '/api/v1/listen-together/session',
    'api/v1/shared-playlists' => '/api/v1/shared-playlists',
    _ => '/not-found',
  };
}

Future<Response> _handleAuthProfile(
  Request request, {
  required SyncAuthenticator authenticator,
  required ManagedSyncAccountRegistry? managedAccounts,
}) async {
  if (request.method != 'GET' && request.method != 'PATCH') {
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
  final candidatePrincipal =
      token == null ? null : managedAccounts?.authenticatePrincipal(token);
  final principal = candidatePrincipal?.accountId == accountId
      ? candidatePrincipal
      : null;
  final managedProfile =
      principal == null ? null : managedAccounts?.account(principal.accountId);
  if (request.method == 'GET') {
    return _jsonResponse(
      200,
      _authProfileJson(
        accountId: accountId,
        account: managedProfile,
        device: principal?.token,
      ),
    );
  }
  if (managedAccounts == null || principal == null || managedProfile == null) {
    return _jsonResponse(
      409,
      <String, Object?>{'error': 'profile_not_managed'},
    );
  }

  try {
    final body = await _readBoundedJson(
      request,
      maxBytes: maxManagedAuthRequestBytes,
    );
    final hasDisplayName = body.containsKey('displayName');
    final hasDeviceName = body.containsKey('deviceName');
    final hasAvatarTone = body.containsKey('avatarTone');
    final hasPublicProfileEnabled = body.containsKey('publicProfileEnabled');
    if (!hasDisplayName &&
        !hasDeviceName &&
        !hasAvatarTone &&
        !hasPublicProfileEnabled) {
      throw const FormatException(
        'At least one profile field must be provided.',
      );
    }
    final updated = await managedAccounts.updateProfile(
      accountId: principal.accountId,
      tokenId: principal.token.id,
      displayName: hasDisplayName ? _requiredString(body, 'displayName') : null,
      deviceName: hasDeviceName ? _requiredString(body, 'deviceName') : null,
      avatarToneProvided: hasAvatarTone,
      avatarTone:
          hasAvatarTone ? _optionalAvatarTone(body['avatarTone']) : null,
      publicProfileEnabledProvided: hasPublicProfileEnabled,
      publicProfileEnabled: hasPublicProfileEnabled
          ? _requiredBool(body, 'publicProfileEnabled')
          : false,
    );
    if (updated == null) {
      return _unauthorizedResponse();
    }
    return _jsonResponse(
      200,
      _authProfileJson(
        accountId: updated.account.id,
        account: updated.account,
        device: updated.device,
      ),
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

Map<String, Object?> _authProfileJson({
  required String accountId,
  required ManagedSyncAccountProfile? account,
  required ManagedSyncTokenMetadata? device,
}) {
  return <String, Object?>{
    'account': <String, Object?>{
      'id': accountId,
      'displayName': account?.displayName,
      'avatarTone': account?.avatarTone,
      'publicProfileEnabled': account?.publicProfileEnabled ?? false,
      'managed': account != null,
      'editable': account != null && device != null,
    },
    'device': device?.toJson(),
  };
}

Future<Response> _handlePublicProfile(
  Request request, {
  required ManagedSyncAccountRegistry? managedAccounts,
}) async {
  if (request.method != 'GET') {
    return _methodNotAllowed(request);
  }
  if (managedAccounts == null) {
    return _jsonResponse(404, <String, Object?>{'error': 'not_found'});
  }
  final segments = request.url.pathSegments;
  if (segments.length != 4 ||
      segments[0] != 'api' ||
      segments[1] != 'v1' ||
      segments[2] != 'public-profiles') {
    return _jsonResponse(404, <String, Object?>{'error': 'not_found'});
  }
  final account = managedAccounts.account(segments[3]);
  if (account == null || !account.publicProfileEnabled) {
    return _jsonResponse(404, <String, Object?>{'error': 'not_found'});
  }
  return _jsonResponse(200, <String, Object?>{
    'id': account.id,
    'displayName': account.displayName,
    'avatarTone': account.avatarTone,
  });
}

String? _optionalAvatarTone(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw const FormatException('avatarTone must be a string or null.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is! bool) {
    throw FormatException('$key must be a boolean.');
  }
  return value;
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

Future<Response> _handleManagedRecoveryCodeIssue(
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
  if (request.method != 'POST') {
    return _methodNotAllowed(request);
  }
  try {
    final body = await _readBoundedJson(
      request,
      maxBytes: maxManagedAuthRequestBytes,
    );
    final issued = await managedAccounts.issueRecoveryCode(
      accountId: _requiredString(body, 'accountId'),
    );
    return _jsonResponse(201, <String, Object?>{
      'recoveryCode': issued.code,
      'expiresAt': issued.expiresAt.toIso8601String(),
    });
  } on FormatException catch (error) {
    return _jsonResponse(400, <String, Object?>{
      'error': 'invalid_auth_request',
      'message': error.message,
    });
  }
}

Future<Response> _handleManagedRecoveryRedemption(
  Request request, {
  required ManagedSyncAccountRegistry? managedAccounts,
}) async {
  if (managedAccounts == null) {
    return _jsonResponse(
      503,
      <String, Object?>{'error': 'managed_auth_not_configured'},
    );
  }
  if (request.method != 'POST') {
    return _methodNotAllowed(request);
  }
  try {
    final body = await _readBoundedJson(
      request,
      maxBytes: maxManagedAuthRequestBytes,
    );
    final issued = await managedAccounts.redeemRecoveryCode(
      code: _requiredString(body, 'recoveryCode'),
      deviceName: _requiredString(body, 'deviceName'),
    );
    if (issued == null) {
      return _jsonResponse(401, <String, Object?>{'error': 'invalid_recovery_code'});
    }
    return _jsonResponse(201, <String, Object?>{
      'tokenType': 'Bearer',
      'token': issued.token,
      'account': issued.account.toJson(),
      'device': issued.device.toJson(),
    });
  } on FormatException catch (error) {
    return _jsonResponse(400, <String, Object?>{
      'error': 'invalid_recovery_request',
      'message': error.message,
    });
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

Future<Response> _handleLibrarySyncMetadata(
  Request request, {
  required SyncAuthenticator authenticator,
  required LibrarySyncSnapshotStore snapshots,
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
  final userId = token == null ? null : authenticator.authenticate(token);
  if (userId == null) {
    return _unauthorizedResponse();
  }

  final snapshot = await snapshots.read(userId);
  return _jsonResponse(
    200,
    snapshot?.toMetadataJson() ??
        <String, Object?>{
          'revision': 0,
          'updatedAt': null,
          'updatedByDevice': null,
          'checksum': null,
        },
  );
}

Future<Response> _handleSharedPlaylistCollection(
  Request request, {
  required SyncAuthenticator authenticator,
  required SharedPlaylistStore playlists,
  required DateTime Function() now,
}) async {
  if (request.method != 'POST') {
    return _methodNotAllowed(request);
  }
  final ownerId = _authenticatedSharedPlaylistUser(request, authenticator);
  if (ownerId == null) {
    return authenticator.isConfigured
        ? _unauthorizedResponse()
        : _jsonResponse(503, <String, Object?>{'error': 'sync_not_configured'});
  }
  try {
    final body = await _readBoundedJson(
      request,
      maxBytes: maxSharedPlaylistBytes,
    );
    final mutation = _syncMutationFields(body);
    final rawDocument = body['playlist'];
    if (rawDocument is! Map) {
      throw const FormatException('playlist must be an object.');
    }
    final document = Map<String, Object?>.from(rawDocument);
    validateSharedPlaylistDocument(document);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final playlistId = newSharedPlaylistId();
      final result = await playlists.write(
        playlistId: playlistId,
        ownerId: ownerId,
        baseRevision: 0,
        deviceId: mutation.deviceId,
        document: document,
        collaborators: const <String, SharedPlaylistRole>{},
        updatedAt: now().toUtc(),
      );
      if (!result.isConflict) {
        return _jsonResponse(
          201,
          _sharedPlaylistResponse(result.record!, ownerId),
        );
      }
    }
    throw StateError('Could not allocate a shared playlist.');
  } on _PayloadTooLarge catch (error) {
    return _jsonResponse(
      413,
      <String, Object?>{'error': 'payload_too_large', 'maxBytes': error.maxBytes},
    );
  } on FormatException catch (error) {
    return _jsonResponse(
      400,
      <String, Object?>{
        'error': 'invalid_shared_playlist',
        'message': error.message,
      },
    );
  }
}

Future<Response> _handleSharedPlaylistItem(
  Request request, {
  required SyncAuthenticator authenticator,
  required SharedPlaylistStore playlists,
  required SharedPlaylistInviteStore invites,
  required DateTime Function() now,
}) async {
  final accountId = _authenticatedSharedPlaylistUser(request, authenticator);
  if (accountId == null) {
    return authenticator.isConfigured
        ? _unauthorizedResponse()
        : _jsonResponse(503, <String, Object?>{'error': 'sync_not_configured'});
  }
  final segments = request.url.pathSegments;
  if (segments.length < 4 || segments[0] != 'api' || segments[1] != 'v1') {
    return _jsonResponse(404, <String, Object?>{'error': 'not_found'});
  }
  final playlistId = segments[3];
  final isInviteEndpoint =
      segments.length == 5 && segments[4] == 'invites';
  final isHistoryEndpoint =
      segments.length == 5 && segments[4] == 'revisions';
  final isCollaboratorEndpoint =
      segments.length == 6 && segments[4] == 'collaborators';
  if (segments.length != 4 &&
      !isInviteEndpoint &&
      !isHistoryEndpoint &&
      !isCollaboratorEndpoint) {
    return _jsonResponse(404, <String, Object?>{'error': 'not_found'});
  }
  final record = await playlists.read(playlistId);
  if (record == null || record.roleFor(accountId) == null) {
    return _jsonResponse(404, <String, Object?>{'error': 'shared_playlist_not_found'});
  }
  if (isHistoryEndpoint) {
    if (request.method != 'GET') {
      return _methodNotAllowed(request);
    }
    final history = await playlists.readHistory(playlistId);
    return _jsonResponse(
      200,
      <String, Object?>{
        'revisions': history
            .map(_sharedPlaylistRevisionResponse)
            .toList(growable: false),
      },
    );
  }
  if (isInviteEndpoint) {
    if (!record.isOwner(accountId)) {
      return _sharedPlaylistForbidden();
    }
    if (request.method == 'DELETE') {
      final invalidated = await invites.invalidateForPlaylist(playlistId);
      return _jsonResponse(
        200,
        <String, Object?>{'invalidated': invalidated},
      );
    }
    if (request.method != 'POST') {
      return _methodNotAllowed(request);
    }
    try {
      final body = await _readBoundedJson(request, maxBytes: maxSharedPlaylistBytes);
      final role = sharedPlaylistRoleFromWire(body['role']);
      if (role == null) {
        throw const FormatException('Invite role must be viewer or editor.');
      }
      final expiresAt = now().toUtc().add(sharedPlaylistInviteLifetime);
      final code = await invites.issue(
        playlistId: playlistId,
        role: role,
        expiresAt: expiresAt,
      );
      return _jsonResponse(
        201,
        <String, Object?>{
          'inviteCode': code,
          'role': sharedPlaylistRoleToWire(role),
          'expiresAt': expiresAt.toIso8601String(),
        },
      );
    } on _PayloadTooLarge catch (error) {
      return _jsonResponse(
        413,
        <String, Object?>{'error': 'payload_too_large', 'maxBytes': error.maxBytes},
      );
    } on FormatException catch (error) {
      return _jsonResponse(
        400,
        <String, Object?>{
          'error': 'invalid_shared_playlist_invite',
          'message': error.message,
        },
      );
    }
  }
  if (isCollaboratorEndpoint) {
    if (request.method != 'DELETE') {
      return _methodNotAllowed(request);
    }
    if (!record.isOwner(accountId)) {
      return _sharedPlaylistForbidden();
    }
    final collaboratorId = segments[5];
    if (collaboratorId.trim().isEmpty ||
        collaboratorId.length > 256 ||
        !record.collaborators.containsKey(collaboratorId)) {
      return _jsonResponse(
        404,
        <String, Object?>{'error': 'shared_playlist_collaborator_not_found'},
      );
    }
    try {
      final mutation = _syncMutationFields(
        await _readBoundedJson(request, maxBytes: maxSharedPlaylistBytes),
      );
      final collaborators = <String, SharedPlaylistRole>{
        ...record.collaborators,
      }..remove(collaboratorId);
      final result = await playlists.write(
        playlistId: record.id,
        ownerId: record.ownerId,
        baseRevision: mutation.baseRevision,
        deviceId: mutation.deviceId,
        document: record.document,
        collaborators: collaborators,
        updatedAt: now().toUtc(),
      );
      if (result.isConflict) {
        return _sharedPlaylistConflict(result.record);
      }
      return _jsonResponse(200, _sharedPlaylistResponse(result.record!, accountId));
    } on _PayloadTooLarge catch (error) {
      return _jsonResponse(
        413,
        <String, Object?>{'error': 'payload_too_large', 'maxBytes': error.maxBytes},
      );
    } on FormatException catch (error) {
      return _jsonResponse(
        400,
        <String, Object?>{
          'error': 'invalid_shared_playlist',
          'message': error.message,
        },
      );
    }
  }
  switch (request.method) {
    case 'GET':
      return _jsonResponse(200, _sharedPlaylistResponse(record, accountId));
    case 'PUT':
      if (record.roleFor(accountId) != SharedPlaylistRole.editor) {
        return _sharedPlaylistForbidden();
      }
      try {
        final body = await _readBoundedJson(
          request,
          maxBytes: maxSharedPlaylistBytes,
        );
        final mutation = _syncMutationFields(body);
        final rawDocument = body['playlist'];
        if (rawDocument is! Map) {
          throw const FormatException('playlist must be an object.');
        }
        final document = Map<String, Object?>.from(rawDocument);
        validateSharedPlaylistDocument(document);
        final result = await playlists.write(
          playlistId: record.id,
          ownerId: record.ownerId,
          baseRevision: mutation.baseRevision,
          deviceId: mutation.deviceId,
          document: document,
          collaborators: record.collaborators,
          updatedAt: now().toUtc(),
        );
        if (result.isConflict) {
          return _sharedPlaylistConflict(result.record);
        }
        return _jsonResponse(200, _sharedPlaylistResponse(result.record!, accountId));
      } on _PayloadTooLarge catch (error) {
        return _jsonResponse(
          413,
          <String, Object?>{'error': 'payload_too_large', 'maxBytes': error.maxBytes},
        );
      } on FormatException catch (error) {
        return _jsonResponse(
          400,
          <String, Object?>{
            'error': 'invalid_shared_playlist',
            'message': error.message,
          },
        );
      }
    case 'DELETE':
      if (!record.isOwner(accountId)) {
        return _sharedPlaylistForbidden();
      }
      try {
        final mutation = _syncMutationFields(
          await _readBoundedJson(request, maxBytes: maxSharedPlaylistBytes),
        );
        final result = await playlists.delete(
          playlistId: record.id,
          baseRevision: mutation.baseRevision,
        );
        if (result.isConflict) {
          return _sharedPlaylistConflict(result.record);
        }
        return _jsonResponse(200, <String, Object?>{'deleted': true});
      } on _PayloadTooLarge catch (error) {
        return _jsonResponse(
          413,
          <String, Object?>{'error': 'payload_too_large', 'maxBytes': error.maxBytes},
        );
      } on FormatException catch (error) {
        return _jsonResponse(
          400,
          <String, Object?>{
            'error': 'invalid_shared_playlist',
            'message': error.message,
          },
        );
      }
    default:
      return _methodNotAllowed(request);
  }
}

Future<Response> _handleSharedPlaylistInviteJoin(
  Request request, {
  required SyncAuthenticator authenticator,
  required SharedPlaylistStore playlists,
  required SharedPlaylistInviteStore invites,
  required DateTime Function() now,
}) async {
  if (request.method != 'POST') {
    return _methodNotAllowed(request);
  }
  final accountId = _authenticatedSharedPlaylistUser(request, authenticator);
  if (accountId == null) {
    return authenticator.isConfigured
        ? _unauthorizedResponse()
        : _jsonResponse(503, <String, Object?>{'error': 'sync_not_configured'});
  }
  final code = request.url.pathSegments.last;
  final invite = await invites.consume(code);
  if (invite == null || !invite.expiresAt.isAfter(now().toUtc())) {
    return _jsonResponse(404, <String, Object?>{'error': 'shared_playlist_invite_not_found'});
  }
  final record = await playlists.read(invite.playlistId);
  if (record == null) {
    return _jsonResponse(404, <String, Object?>{'error': 'shared_playlist_invite_not_found'});
  }
  final existingRole = record.roleFor(accountId);
  if (existingRole != null) {
    return _jsonResponse(200, _sharedPlaylistResponse(record, accountId));
  }
  final collaborators = <String, SharedPlaylistRole>{
    ...record.collaborators,
    accountId: invite.role,
  };
  final result = await playlists.write(
    playlistId: record.id,
    ownerId: record.ownerId,
    baseRevision: record.revision,
    deviceId: 'invite-join',
    document: record.document,
    collaborators: collaborators,
    updatedAt: now().toUtc(),
  );
  if (result.isConflict) {
    return _sharedPlaylistConflict(result.record);
  }
  return _jsonResponse(200, _sharedPlaylistResponse(result.record!, accountId));
}

String? _authenticatedSharedPlaylistUser(
  Request request,
  SyncAuthenticator authenticator,
) {
  if (!authenticator.isConfigured) {
    return null;
  }
  final token = _bearerToken(request.headers['authorization'] ?? '');
  return token == null ? null : authenticator.authenticate(token);
}

Response _sharedPlaylistForbidden() =>
    _jsonResponse(403, <String, Object?>{'error': 'shared_playlist_forbidden'});

Response _sharedPlaylistConflict(SharedPlaylistRecord? record) {
  return _jsonResponse(
    409,
    <String, Object?>{
      'error': 'shared_playlist_conflict',
      'currentRevision': record?.revision ?? 0,
      'updatedAt': record?.updatedAt.toIso8601String(),
      'updatedByDevice': record?.updatedByDevice,
      'checksum': record?.checksum,
    },
  );
}

Map<String, Object?> _sharedPlaylistResponse(
  SharedPlaylistRecord record,
  String accountId,
) {
  final isOwner = record.isOwner(accountId);
  final role = isOwner ? 'owner' : sharedPlaylistRoleToWire(record.roleFor(accountId)!);
  return <String, Object?>{
    'id': record.id,
    'revision': record.revision,
    'updatedAt': record.updatedAt.toIso8601String(),
    'updatedByDevice': record.updatedByDevice,
    'checksum': record.checksum,
    'role': role,
    'playlist': record.document,
    if (isOwner)
      'collaborators': record.collaborators.map(
        (id, collaboratorRole) => MapEntry<String, String>(
          id,
          sharedPlaylistRoleToWire(collaboratorRole),
        ),
      ),
  };
}

Map<String, Object?> _sharedPlaylistRevisionResponse(
  SharedPlaylistRecord record,
) {
  return <String, Object?>{
    'revision': record.revision,
    'updatedAt': record.updatedAt.toIso8601String(),
    'updatedByDevice': record.updatedByDevice,
    'checksum': record.checksum,
    'playlist': record.document,
  };
}

Future<Response> _handleListenTogetherSession(
  Request request, {
  required SyncAuthenticator authenticator,
  required LibrarySyncSnapshotStore sessions,
  required DateTime Function() now,
}) async {
  if (!authenticator.isConfigured) {
    return _jsonResponse(
      503,
      <String, Object?>{'error': 'sync_not_configured'},
    );
  }

  final token = _bearerToken(request.headers['authorization'] ?? '');
  final userId = token == null ? null : authenticator.authenticate(token);
  if (userId == null) {
    return _unauthorizedResponse();
  }

  switch (request.method) {
    case 'GET':
      final session = await sessions.read(userId);
      return _jsonResponse(200, _listenTogetherSessionResponse(session));
    case 'PUT':
      try {
        final body = await _readBoundedJson(
          request,
          maxBytes: maxListenTogetherSessionBytes,
        );
        final mutation = _syncMutationFields(body);
        final rawSession = body['session'];
        if (rawSession is! Map) {
          throw const FormatException('session must be an object.');
        }
        final session = Map<String, Object?>.from(rawSession);
        _validateListenTogetherSession(session);
        final checksum = sha256
            .convert(utf8.encode(jsonEncode(session)))
            .toString();
        final result = await sessions.write(
          userId: userId,
          baseRevision: mutation.baseRevision,
          deviceId: mutation.deviceId,
          snapshot: session,
          checksum: checksum,
          updatedAt: now().toUtc(),
        );
        if (result.isConflict) {
          return _listenTogetherConflict(result.snapshot);
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
            'error': 'invalid_listen_together_session',
            'message': error.message,
          },
        );
      }
    case 'DELETE':
      try {
        final mutation = _syncMutationFields(
          await _readBoundedJson(
            request,
            maxBytes: maxListenTogetherSessionBytes,
          ),
        );
        final result = await sessions.delete(
          userId: userId,
          baseRevision: mutation.baseRevision,
          deviceId: mutation.deviceId,
          updatedAt: now().toUtc(),
        );
        if (result.isConflict) {
          return _listenTogetherConflict(result.snapshot);
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
            'error': 'invalid_listen_together_session',
            'message': error.message,
          },
        );
      }
    default:
      return _methodNotAllowed(request);
  }
}

Future<Response> _handleListenTogetherInviteIssue(
  Request request, {
  required SyncAuthenticator authenticator,
  required LibrarySyncSnapshotStore sessions,
  required ListenTogetherInviteStore invites,
}) async {
  if (request.method != 'POST') {
    return _methodNotAllowed(request);
  }
  final userId = _authenticatedListenTogetherUser(request, authenticator);
  if (userId == null) {
    return authenticator.isConfigured
        ? _unauthorizedResponse()
        : _jsonResponse(503, <String, Object?>{'error': 'sync_not_configured'});
  }
  final session = await sessions.read(userId);
  if (session == null || session.snapshot == null) {
    return _jsonResponse(409, <String, Object?>{'error': 'no_active_session'});
  }
  final code = await invites.issue(userId, session.revision);
  return _jsonResponse(201, <String, Object?>{'inviteCode': code});
}

Future<Response> _handleListenTogetherInviteJoin(
  Request request, {
  required SyncAuthenticator authenticator,
  required LibrarySyncSnapshotStore sessions,
  required ListenTogetherInviteStore invites,
}) async {
  if (request.method != 'GET') {
    return _methodNotAllowed(request);
  }
  if (_authenticatedListenTogetherUser(request, authenticator) == null) {
    return authenticator.isConfigured
        ? _unauthorizedResponse()
        : _jsonResponse(503, <String, Object?>{'error': 'sync_not_configured'});
  }
  final code = request.url.pathSegments.last;
  final invite = await invites.lookup(code);
  final session = invite == null ? null : await sessions.read(invite.ownerId);
  if (session?.snapshot == null || session!.revision != invite!.sessionRevision) {
    return _jsonResponse(404, <String, Object?>{'error': 'invite_not_found'});
  }
  return _jsonResponse(200, _listenTogetherSessionResponse(session));
}

String? _authenticatedListenTogetherUser(
  Request request,
  SyncAuthenticator authenticator,
) {
  if (!authenticator.isConfigured) {
    return null;
  }
  final token = _bearerToken(request.headers['authorization'] ?? '');
  return token == null ? null : authenticator.authenticate(token);
}

Response _listenTogetherConflict(LibrarySyncSnapshot? current) {
  return _jsonResponse(
    409,
    <String, Object?>{
      'error': 'listen_together_conflict',
      'currentRevision': current?.revision ?? 0,
      'updatedAt': current?.updatedAt.toIso8601String(),
      'updatedByDevice': current?.updatedByDevice,
      'checksum': current?.checksum,
    },
  );
}

Map<String, Object?> _listenTogetherSessionResponse(
  LibrarySyncSnapshot? session,
) {
  return <String, Object?>{
    ...(session?.toMetadataJson() ??
        <String, Object?>{
          'revision': 0,
          'updatedAt': null,
          'updatedByDevice': null,
          'checksum': null,
        }),
    'session': session?.snapshot,
  };
}

void _validateListenTogetherSession(Map<String, Object?> session) {
  const legacyFields = <String>{
    'version',
    'trackIds',
    'currentTrackId',
    'positionMilliseconds',
    'playing',
  };
  const currentFields = <String>{...legacyFields, 'currentIndex'};
  final version = session['version'];
  if (version != 1 && version != 2) {
    throw const FormatException('Unsupported listen-together session version.');
  }
  final allowedFields = version == 1 ? legacyFields : currentFields;
  if (session.keys.any((key) => !allowedFields.contains(key))) {
    throw const FormatException(
      'Listen-together sessions contain unsupported fields.',
    );
  }
  final trackIds = session['trackIds'];
  if (trackIds is! List || trackIds.length > 500) {
    throw const FormatException('session trackIds must contain at most 500 IDs.');
  }
  final normalizedIds = <String>[];
  for (final value in trackIds) {
    if (value is! String ||
        value != value.trim() ||
        value.isEmpty ||
        value.length > 256) {
      throw const FormatException('session trackIds must be bounded strings.');
    }
    normalizedIds.add(value);
  }
  if (version == 1 && normalizedIds.toSet().length != normalizedIds.length) {
    throw const FormatException('session trackIds must not repeat.');
  }
  final currentTrackId = session['currentTrackId'];
  if (currentTrackId != null &&
      (currentTrackId is! String ||
          currentTrackId != currentTrackId.trim() ||
          !normalizedIds.contains(currentTrackId))) {
    throw const FormatException('session currentTrackId must belong to trackIds.');
  }
  final currentIndex = session['currentIndex'];
  if (version == 2 &&
      (currentIndex is! int ||
          currentIndex < 0 ||
          currentIndex >= normalizedIds.length ||
          currentTrackId != normalizedIds[currentIndex])) {
    throw const FormatException(
      'session currentIndex must select the current queue item.',
    );
  }
  final positionMilliseconds = session['positionMilliseconds'];
  if (positionMilliseconds is! int ||
      positionMilliseconds < 0 ||
      positionMilliseconds > 7 * 24 * 60 * 60 * 1000) {
    throw const FormatException('session positionMilliseconds is invalid.');
  }
  if (session['playing'] is! bool) {
    throw const FormatException('session playing must be a boolean.');
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

abstract interface class ListenTogetherInviteStore {
  Future<String> issue(String ownerId, int sessionRevision);

  Future<ListenTogetherInvite?> lookup(String inviteCode);
}

class ListenTogetherInvite {
  const ListenTogetherInvite({
    required this.ownerId,
    required this.sessionRevision,
  });

  final String ownerId;
  final int sessionRevision;
}

class MemoryListenTogetherInviteStore implements ListenTogetherInviteStore {
  final Map<String, ListenTogetherInvite> _invitesByCode =
      <String, ListenTogetherInvite>{};

  @override
  Future<String> issue(String ownerId, int sessionRevision) async {
    final code = _newListenTogetherInviteCode();
    _invitesByCode[code] = ListenTogetherInvite(
      ownerId: ownerId,
      sessionRevision: sessionRevision,
    );
    return code;
  }

  @override
  Future<ListenTogetherInvite?> lookup(String inviteCode) async {
    return _isListenTogetherInviteCode(inviteCode)
        ? _invitesByCode[inviteCode]
        : null;
  }
}

class FileListenTogetherInviteStore implements ListenTogetherInviteStore {
  FileListenTogetherInviteStore(this.rootDirectory);

  final Directory rootDirectory;

  @override
  Future<String> issue(String ownerId, int sessionRevision) async {
    await rootDirectory.create(recursive: true);
    for (var attempt = 0; attempt < 4; attempt += 1) {
      final code = _newListenTogetherInviteCode();
      final file = _fileFor(code);
      if (await file.exists()) {
        continue;
      }
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'ownerId': ownerId,
          'sessionRevision': sessionRevision,
        }),
        flush: true,
      );
      return code;
    }
    throw StateError('Could not allocate a listen-together invite.');
  }

  @override
  Future<ListenTogetherInvite?> lookup(String inviteCode) async {
    if (!_isListenTogetherInviteCode(inviteCode)) {
      return null;
    }
    final file = _fileFor(inviteCode);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      final ownerId = decoded['ownerId'];
      final sessionRevision = decoded['sessionRevision'];
      if (ownerId is! String || ownerId.isEmpty ||
          sessionRevision is! int || sessionRevision <= 0) {
        return null;
      }
      return ListenTogetherInvite(
        ownerId: ownerId,
        sessionRevision: sessionRevision,
      );
    } on Object {
      return null;
    }
  }

  File _fileFor(String code) {
    final digest = sha256.convert(utf8.encode(code)).toString();
    return File(p.join(rootDirectory.path, '$digest.json'));
  }
}

String _newListenTogetherInviteCode() {
  return base64Url.encode(
    List<int>.generate(18, (_) => _listenTogetherInviteRandom.nextInt(256)),
  );
}

bool _isListenTogetherInviteCode(String value) {
  return RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);
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
