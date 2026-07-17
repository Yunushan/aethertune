import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/library_sync_account.dart';
import '../domain/library_sync_profile.dart';
import '../domain/listen_together_session.dart';
import 'provider_error.dart';

const maxLibrarySyncResponseBytes = 9 * 1024 * 1024;

typedef LibrarySyncHttpExecutor =
    Future<LibrarySyncHttpResponse> Function(
      String method,
      Uri uri, {
      required Map<String, String> headers,
      String? body,
    });

class LibrarySyncHttpResponse {
  const LibrarySyncHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

class LibrarySyncRemoteSnapshot {
  const LibrarySyncRemoteSnapshot({
    required this.revision,
    this.updatedAt,
    this.updatedByDevice,
    this.checksum,
    this.snapshot,
  });

  final int revision;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final String? checksum;
  final Map<String, Object?>? snapshot;

  bool get hasSnapshot => revision > 0 && snapshot != null;
}

class LibrarySyncConflictException implements Exception {
  const LibrarySyncConflictException({
    required this.currentRevision,
    this.updatedAt,
    this.updatedByDevice,
    this.checksum,
  });

  final int currentRevision;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final String? checksum;

  @override
  String toString() {
    return 'The server library changed at revision $currentRevision.';
  }
}

class ListenTogetherRemoteSession {
  const ListenTogetherRemoteSession({
    required this.revision,
    this.updatedAt,
    this.updatedByDevice,
    this.checksum,
    this.session,
  });

  final int revision;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final String? checksum;
  final ListenTogetherSession? session;
}

class ListenTogetherConflictException implements Exception {
  const ListenTogetherConflictException({
    required this.currentRevision,
    this.updatedAt,
    this.updatedByDevice,
    this.checksum,
  });

  final int currentRevision;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final String? checksum;
}

enum SharedPlaylistAccessRole { owner, editor, viewer }

class SharedPlaylistRemote {
  const SharedPlaylistRemote({
    required this.id,
    required this.revision,
    required this.role,
    required this.name,
    required this.trackIds,
    this.updatedAt,
    this.updatedByDevice,
    this.checksum,
    this.collaborators = const <String, SharedPlaylistAccessRole>{},
  });

  final String id;
  final int revision;
  final SharedPlaylistAccessRole role;
  final String name;
  final List<String> trackIds;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final String? checksum;
  final Map<String, SharedPlaylistAccessRole> collaborators;

  bool get canEdit => role != SharedPlaylistAccessRole.viewer;
  bool get isOwner => role == SharedPlaylistAccessRole.owner;
}

class SharedPlaylistInvitation {
  const SharedPlaylistInvitation({
    required this.code,
    required this.role,
    required this.expiresAt,
  });

  final String code;
  final SharedPlaylistAccessRole role;
  final DateTime expiresAt;
}

class SharedPlaylistRevision {
  const SharedPlaylistRevision({
    required this.revision,
    required this.name,
    required this.trackIds,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.checksum,
  });

  final int revision;
  final String name;
  final List<String> trackIds;
  final DateTime updatedAt;
  final String updatedByDevice;
  final String checksum;
}

class SharedPlaylistConflictException implements Exception {
  const SharedPlaylistConflictException({
    required this.currentRevision,
    this.updatedAt,
    this.updatedByDevice,
    this.checksum,
  });

  final int currentRevision;
  final DateTime? updatedAt;
  final String? updatedByDevice;
  final String? checksum;
}

abstract interface class LibrarySyncGateway {
  Future<LibrarySyncRemoteSnapshot> fetch();

  Future<LibrarySyncRemoteSnapshot> push({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  });

  Future<LibrarySyncRemoteSnapshot> delete({required int baseRevision});
}

abstract interface class LibrarySyncMetadataGateway {
  Future<LibrarySyncRemoteSnapshot?> fetchMetadata();
}

abstract interface class ListenTogetherGateway {
  Future<ListenTogetherRemoteSession> fetchListenTogetherSession();

  Future<ListenTogetherRemoteSession> publishListenTogetherSession({
    required int baseRevision,
    required ListenTogetherSession session,
  });

  Future<ListenTogetherRemoteSession> leaveListenTogetherSession({
    required int baseRevision,
  });

  Future<String> issueListenTogetherInvite();

  Future<ListenTogetherRemoteSession> fetchListenTogetherInvite(
    String inviteCode,
  );
}

abstract interface class SharedPlaylistGateway {
  Future<SharedPlaylistRemote> createSharedPlaylist({
    required String name,
    required List<String> trackIds,
  });

  Future<SharedPlaylistRemote> fetchSharedPlaylist(String playlistId);

  Future<List<SharedPlaylistRevision>> fetchSharedPlaylistHistory(
    String playlistId,
  );

  Future<SharedPlaylistRemote> updateSharedPlaylist({
    required String playlistId,
    required int baseRevision,
    required String name,
    required List<String> trackIds,
  });

  Future<void> deleteSharedPlaylist({
    required String playlistId,
    required int baseRevision,
  });

  Future<SharedPlaylistInvitation> issueSharedPlaylistInvite({
    required String playlistId,
    required SharedPlaylistAccessRole role,
  });

  Future<int> invalidateSharedPlaylistInvites({
    required String playlistId,
  });

  Future<SharedPlaylistRemote> revokeSharedPlaylistCollaborator({
    required String playlistId,
    required String collaboratorId,
    required int baseRevision,
  });

  Future<SharedPlaylistRemote> joinSharedPlaylistInvite(String inviteCode);
}

abstract interface class LibrarySyncProfileGateway {
  Future<LibrarySyncProfile?> fetchProfile();
}

abstract interface class LibrarySyncProfileEditorGateway {
  Future<LibrarySyncProfile> updateProfile({
    required String displayName,
    required String deviceName,
  });
}

class LibrarySyncClient
    implements
        LibrarySyncGateway,
        LibrarySyncMetadataGateway,
        ListenTogetherGateway,
        SharedPlaylistGateway,
        LibrarySyncProfileGateway,
        LibrarySyncProfileEditorGateway {
  LibrarySyncClient({
    required this.account,
    required this.token,
    LibrarySyncHttpExecutor? httpExecutor,
  }) : _httpExecutor = httpExecutor ?? executeLibrarySyncHttpRequest;

  final LibrarySyncAccount account;
  final String token;
  final LibrarySyncHttpExecutor _httpExecutor;

  @override
  Future<LibrarySyncProfile?> fetchProfile() async {
    final response = await _execute(
      'GET',
      endpoint: account.profileEndpointUri,
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return LibrarySyncProfile.fromServerJson(_jsonObject(response.body));
  }

  @override
  Future<LibrarySyncProfile> updateProfile({
    required String displayName,
    required String deviceName,
  }) async {
    final response = await _execute(
      'PATCH',
      endpoint: account.profileEndpointUri,
      body: jsonEncode(<String, Object?>{
        'displayName': normalizeLibrarySyncProfileDisplayName(displayName),
        'deviceName': normalizeLibrarySyncProfileDeviceName(deviceName),
      }),
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return LibrarySyncProfile.fromServerJson(_jsonObject(response.body));
  }

  @override
  Future<LibrarySyncRemoteSnapshot> fetch() async {
    final response = await _execute('GET');
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    final result = _parseRemoteSnapshot(response.body);
    final snapshot = result.snapshot;
    if (snapshot != null) {
      final expected = result.checksum;
      final actual = sha256
          .convert(utf8.encode(jsonEncode(snapshot)))
          .toString();
      if (expected == null || expected != actual) {
        throw const ProviderRequestException(
          'Library sync response checksum does not match.',
        );
      }
    }
    return result;
  }

  @override
  Future<LibrarySyncRemoteSnapshot?> fetchMetadata() async {
    final response = await _execute(
      'GET',
      endpoint: account.libraryMetadataEndpointUri,
    );
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseRemoteMetadata(response.body);
  }

  @override
  Future<ListenTogetherRemoteSession> fetchListenTogetherSession() async {
    final response = await _execute(
      'GET',
      endpoint: account.listenTogetherEndpointUri,
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseListenTogetherSession(response.body);
  }

  @override
  Future<ListenTogetherRemoteSession> publishListenTogetherSession({
    required int baseRevision,
    required ListenTogetherSession session,
  }) async {
    final response = await _execute(
      'PUT',
      endpoint: account.listenTogetherEndpointUri,
      body: jsonEncode(<String, Object?>{
        'baseRevision': baseRevision,
        'deviceId': account.deviceId,
        'session': session.toJson(),
      }),
    );
    if (response.statusCode == 409) {
      throw _parseListenTogetherConflict(response.body);
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseListenTogetherMetadata(response.body);
  }

  @override
  Future<ListenTogetherRemoteSession> leaveListenTogetherSession({
    required int baseRevision,
  }) async {
    final response = await _execute(
      'DELETE',
      endpoint: account.listenTogetherEndpointUri,
      body: jsonEncode(<String, Object?>{
        'baseRevision': baseRevision,
        'deviceId': account.deviceId,
      }),
    );
    if (response.statusCode == 409) {
      throw _parseListenTogetherConflict(response.body);
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseListenTogetherMetadata(response.body);
  }

  @override
  Future<String> issueListenTogetherInvite() async {
    final response = await _execute(
      'POST',
      endpoint: account.listenTogetherInviteIssueEndpointUri,
    );
    if (response.statusCode != 201) {
      throw _requestFailure(response);
    }
    final code = _jsonObject(response.body)['inviteCode'];
    if (code is! String || !_isListenTogetherInviteCode(code)) {
      throw const FormatException('Listen-together invite code is invalid.');
    }
    return code;
  }

  @override
  Future<ListenTogetherRemoteSession> fetchListenTogetherInvite(
    String inviteCode,
  ) async {
    final normalized = inviteCode.trim();
    if (!_isListenTogetherInviteCode(normalized)) {
      throw const FormatException('Enter a valid listen-together invite code.');
    }
    final response = await _execute(
      'GET',
      endpoint: account.listenTogetherInviteEndpointUri(normalized),
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseListenTogetherSession(response.body);
  }

  @override
  Future<SharedPlaylistRemote> createSharedPlaylist({
    required String name,
    required List<String> trackIds,
  }) async {
    final document = _sharedPlaylistDocument(name, trackIds);
    final response = await _execute(
      'POST',
      endpoint: account.sharedPlaylistCollectionEndpointUri,
      body: jsonEncode(<String, Object?>{
        'baseRevision': 0,
        'deviceId': account.deviceId,
        'playlist': document,
      }),
    );
    if (response.statusCode != 201) {
      throw _requestFailure(response);
    }
    return _parseSharedPlaylist(response.body);
  }

  @override
  Future<SharedPlaylistRemote> fetchSharedPlaylist(String playlistId) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    final response = await _execute(
      'GET',
      endpoint: account.sharedPlaylistEndpointUri(normalized),
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseSharedPlaylist(response.body);
  }

  @override
  Future<List<SharedPlaylistRevision>> fetchSharedPlaylistHistory(
    String playlistId,
  ) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    final response = await _execute(
      'GET',
      endpoint: account.sharedPlaylistHistoryEndpointUri(normalized),
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    final revisions = _jsonObject(response.body)['revisions'];
    if (revisions is! List || revisions.length > 25) {
      throw const FormatException('Shared playlist history is invalid.');
    }
    final parsed = <SharedPlaylistRevision>[];
    var previousRevision = 1 << 62;
    for (final value in revisions) {
      if (value is! Map) {
        throw const FormatException('Shared playlist history is invalid.');
      }
      final revision = _parseSharedPlaylistRevision(
        Map<String, Object?>.from(value),
      );
      if (revision.revision >= previousRevision) {
        throw const FormatException('Shared playlist history is invalid.');
      }
      previousRevision = revision.revision;
      parsed.add(revision);
    }
    return List<SharedPlaylistRevision>.unmodifiable(parsed);
  }

  @override
  Future<SharedPlaylistRemote> updateSharedPlaylist({
    required String playlistId,
    required int baseRevision,
    required String name,
    required List<String> trackIds,
  }) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    if (baseRevision <= 0) {
      throw const FormatException('Shared playlist revision is invalid.');
    }
    final response = await _execute(
      'PUT',
      endpoint: account.sharedPlaylistEndpointUri(normalized),
      body: jsonEncode(<String, Object?>{
        'baseRevision': baseRevision,
        'deviceId': account.deviceId,
        'playlist': _sharedPlaylistDocument(name, trackIds),
      }),
    );
    if (response.statusCode == 409) {
      throw _parseSharedPlaylistConflict(response.body);
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseSharedPlaylist(response.body);
  }

  @override
  Future<void> deleteSharedPlaylist({
    required String playlistId,
    required int baseRevision,
  }) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    final response = await _execute(
      'DELETE',
      endpoint: account.sharedPlaylistEndpointUri(normalized),
      body: jsonEncode(<String, Object?>{
        'baseRevision': baseRevision,
        'deviceId': account.deviceId,
      }),
    );
    if (response.statusCode == 409) {
      throw _parseSharedPlaylistConflict(response.body);
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
  }

  @override
  Future<SharedPlaylistInvitation> issueSharedPlaylistInvite({
    required String playlistId,
    required SharedPlaylistAccessRole role,
  }) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    if (role == SharedPlaylistAccessRole.owner) {
      throw const FormatException('Shared playlist invites require viewer or editor access.');
    }
    final response = await _execute(
      'POST',
      endpoint: account.sharedPlaylistInviteIssueEndpointUri(normalized),
      body: jsonEncode(<String, Object?>{'role': _sharedPlaylistRoleWire(role)}),
    );
    if (response.statusCode != 201) {
      throw _requestFailure(response);
    }
    final invitation = _jsonObject(response.body);
    final code = invitation['inviteCode'];
    final returnedRole = _sharedPlaylistRoleFromWire(invitation['role']);
    final expiresAt = _optionalDate(invitation['expiresAt']);
    if (code is! String ||
        !_isSharedPlaylistInviteCode(code) ||
        returnedRole == null ||
        returnedRole != role ||
        expiresAt == null) {
      throw const FormatException('Shared playlist invite code is invalid.');
    }
    return SharedPlaylistInvitation(
      code: code,
      role: returnedRole,
      expiresAt: expiresAt,
    );
  }

  @override
  Future<int> invalidateSharedPlaylistInvites({
    required String playlistId,
  }) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    final response = await _execute(
      'DELETE',
      endpoint: account.sharedPlaylistInviteIssueEndpointUri(normalized),
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    final invalidated = _jsonObject(response.body)['invalidated'];
    if (invalidated is! int || invalidated < 0) {
      throw const FormatException('Shared playlist invite rotation is invalid.');
    }
    return invalidated;
  }

  @override
  Future<SharedPlaylistRemote> revokeSharedPlaylistCollaborator({
    required String playlistId,
    required String collaboratorId,
    required int baseRevision,
  }) async {
    final normalizedPlaylistId = _requireSharedPlaylistId(playlistId);
    final normalizedCollaboratorId = collaboratorId.trim();
    if (baseRevision <= 0 ||
        normalizedCollaboratorId.isEmpty ||
        normalizedCollaboratorId.length > 256) {
      throw const FormatException('Shared playlist collaborator is invalid.');
    }
    final response = await _execute(
      'DELETE',
      endpoint: account.sharedPlaylistCollaboratorEndpointUri(
        normalizedPlaylistId,
        normalizedCollaboratorId,
      ),
      body: jsonEncode(<String, Object?>{
        'baseRevision': baseRevision,
        'deviceId': account.deviceId,
      }),
    );
    if (response.statusCode == 409) {
      throw _parseSharedPlaylistConflict(response.body);
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseSharedPlaylist(response.body);
  }

  @override
  Future<SharedPlaylistRemote> joinSharedPlaylistInvite(String inviteCode) async {
    final normalized = inviteCode.trim();
    if (!_isSharedPlaylistInviteCode(normalized)) {
      throw const FormatException('Enter a valid shared playlist invite code.');
    }
    final response = await _execute(
      'POST',
      endpoint: account.sharedPlaylistInviteEndpointUri(normalized),
    );
    if (response.statusCode == 409) {
      throw _parseSharedPlaylistConflict(response.body);
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseSharedPlaylist(response.body);
  }

  @override
  Future<LibrarySyncRemoteSnapshot> push({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  }) async {
    final response = await _execute(
      'PUT',
      body: jsonEncode(<String, Object?>{
        'baseRevision': baseRevision,
        'deviceId': account.deviceId,
        'snapshot': snapshot,
      }),
    );
    if (response.statusCode == 409) {
      final body = _jsonObject(response.body);
      throw LibrarySyncConflictException(
        currentRevision: body['currentRevision'] as int? ?? 0,
        updatedAt: _optionalDate(body['updatedAt']),
        updatedByDevice: _optionalString(body['updatedByDevice']),
        checksum: _optionalString(body['checksum']),
      );
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    final body = _jsonObject(response.body);
    final revision = body['revision'];
    if (revision is! int || revision <= baseRevision) {
      throw const ProviderRequestException(
        'Library sync returned an invalid revision.',
      );
    }
    return LibrarySyncRemoteSnapshot(
      revision: revision,
      updatedAt: _optionalDate(body['updatedAt']),
      updatedByDevice: _optionalString(body['updatedByDevice']),
      checksum: _optionalString(body['checksum']),
    );
  }

  @override
  Future<LibrarySyncRemoteSnapshot> delete({required int baseRevision}) async {
    final response = await _execute(
      'DELETE',
      body: jsonEncode(<String, Object?>{
        'baseRevision': baseRevision,
        'deviceId': account.deviceId,
      }),
    );
    if (response.statusCode == 409) {
      final body = _jsonObject(response.body);
      throw LibrarySyncConflictException(
        currentRevision: body['currentRevision'] as int? ?? 0,
        updatedAt: _optionalDate(body['updatedAt']),
        updatedByDevice: _optionalString(body['updatedByDevice']),
        checksum: _optionalString(body['checksum']),
      );
    }
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    final body = _jsonObject(response.body);
    final revision = body['revision'];
    if (revision is! int || revision <= baseRevision) {
      throw const ProviderRequestException(
        'Library sync returned an invalid revision.',
      );
    }
    return LibrarySyncRemoteSnapshot(
      revision: revision,
      updatedAt: _optionalDate(body['updatedAt']),
      updatedByDevice: _optionalString(body['updatedByDevice']),
      checksum: _optionalString(body['checksum']),
    );
  }

  Future<LibrarySyncHttpResponse> _execute(
    String method, {
    Uri? endpoint,
    String? body,
  }) async {
    try {
      return await _httpExecutor(
        method,
        endpoint ?? account.libraryEndpointUri,
        headers: <String, String>{
          'authorization': 'Bearer $token',
          'accept': 'application/json',
          if (body != null) 'content-type': 'application/json',
        },
        body: body,
      );
    } on Object catch (error) {
      if (error is ProviderRequestException ||
          error is LibrarySyncConflictException ||
          error is SharedPlaylistConflictException) {
        rethrow;
      }
      throw ProviderRequestException(
        safeProviderErrorMessage(
          error,
          providerName: 'Library sync',
          secrets: <String>[token],
        ),
      );
    }
  }

  ProviderRequestException _requestFailure(LibrarySyncHttpResponse response) {
    String? detail;
    try {
      final body = _jsonObject(response.body);
      detail =
          _optionalString(body['message']) ?? _optionalString(body['error']);
    } on FormatException {
      detail = null;
    }
    final statusMessage = switch (response.statusCode) {
      401 => 'Authentication failed.',
      413 => 'Snapshot is larger than the server limit.',
      503 => 'Library sync is not configured on this server.',
      _ => detail ?? 'Server returned HTTP ${response.statusCode}.',
    };
    return ProviderRequestException(
      safeProviderErrorMessage(
        statusMessage,
        providerName: 'Library sync',
        secrets: <String>[token],
      ),
    );
  }
}

LibrarySyncRemoteSnapshot _parseRemoteSnapshot(String rawBody) {
  final body = _jsonObject(rawBody);
  final revision = body['revision'];
  if (revision is! int || revision < 0) {
    throw const FormatException('Library sync revision is invalid.');
  }
  final rawSnapshot = body['snapshot'];
  if (rawSnapshot == null) {
    if (body['checksum'] != null) {
      throw const FormatException('Library sync deletion metadata is invalid.');
    }
    return LibrarySyncRemoteSnapshot(
      revision: revision,
      updatedAt: _optionalDate(body['updatedAt']),
      updatedByDevice: _optionalString(body['updatedByDevice']),
    );
  }
  if (rawSnapshot is! Map) {
    throw const FormatException('Library sync snapshot is invalid.');
  }
  return LibrarySyncRemoteSnapshot(
    revision: revision,
    updatedAt: _optionalDate(body['updatedAt']),
    updatedByDevice: _optionalString(body['updatedByDevice']),
    checksum: _optionalString(body['checksum']),
    snapshot: Map<String, Object?>.from(rawSnapshot),
  );
}

LibrarySyncRemoteSnapshot _parseRemoteMetadata(String rawBody) {
  final body = _jsonObject(rawBody);
  final revision = body['revision'];
  if (revision is! int || revision < 0) {
    throw const FormatException('Library sync revision is invalid.');
  }
  return LibrarySyncRemoteSnapshot(
    revision: revision,
    updatedAt: _optionalDate(body['updatedAt']),
    updatedByDevice: _optionalString(body['updatedByDevice']),
    checksum: _optionalString(body['checksum']),
  );
}

ListenTogetherRemoteSession _parseListenTogetherSession(String rawBody) {
  final body = _jsonObject(rawBody);
  final metadata = _parseListenTogetherMetadataBody(body);
  final rawSession = body['session'];
  if (rawSession == null) {
    return metadata;
  }
  if (rawSession is! Map) {
    throw const FormatException('Listen-together session is invalid.');
  }
  return ListenTogetherRemoteSession(
    revision: metadata.revision,
    updatedAt: metadata.updatedAt,
    updatedByDevice: metadata.updatedByDevice,
    checksum: metadata.checksum,
    session: ListenTogetherSession.fromJson(
      Map<String, Object?>.from(rawSession),
    ),
  );
}

ListenTogetherRemoteSession _parseListenTogetherMetadata(String rawBody) {
  return _parseListenTogetherMetadataBody(_jsonObject(rawBody));
}

ListenTogetherRemoteSession _parseListenTogetherMetadataBody(
  Map<String, Object?> body,
) {
  final revision = body['revision'];
  if (revision is! int || revision < 0) {
    throw const FormatException('Listen-together revision is invalid.');
  }
  return ListenTogetherRemoteSession(
    revision: revision,
    updatedAt: _optionalDate(body['updatedAt']),
    updatedByDevice: _optionalString(body['updatedByDevice']),
    checksum: _optionalString(body['checksum']),
  );
}

ListenTogetherConflictException _parseListenTogetherConflict(String rawBody) {
  final body = _jsonObject(rawBody);
  return ListenTogetherConflictException(
    currentRevision: body['currentRevision'] as int? ?? 0,
    updatedAt: _optionalDate(body['updatedAt']),
    updatedByDevice: _optionalString(body['updatedByDevice']),
    checksum: _optionalString(body['checksum']),
  );
}

SharedPlaylistRemote _parseSharedPlaylist(String rawBody) {
  final body = _jsonObject(rawBody);
  final id = body['id'];
  final revision = body['revision'];
  final role = _sharedPlaylistRoleFromWire(body['role']);
  final rawPlaylist = body['playlist'];
  if (id is! String ||
      !_isSharedPlaylistId(id) ||
      revision is! int ||
      revision <= 0 ||
      role == null ||
      rawPlaylist is! Map) {
    throw const FormatException('Shared playlist response is invalid.');
  }
  final document = Map<String, Object?>.from(rawPlaylist);
  final name = document['name'];
  final rawTrackIds = document['trackIds'];
  if (document['version'] != 1 ||
      name is! String ||
      name != name.trim() ||
      name.isEmpty ||
      name.length > 160 ||
      rawTrackIds is! List ||
      rawTrackIds.length > 500) {
    throw const FormatException('Shared playlist document is invalid.');
  }
  final trackIds = <String>[];
  for (final value in rawTrackIds) {
    if (value is! String ||
        value != value.trim() ||
        value.isEmpty ||
        value.length > 256) {
      throw const FormatException('Shared playlist track IDs are invalid.');
    }
    trackIds.add(value);
  }
  final checksum = _optionalString(body['checksum']);
  final actualChecksum = sha256.convert(utf8.encode(jsonEncode(document))).toString();
  if (checksum == null || checksum != actualChecksum) {
    throw const ProviderRequestException(
      'Shared playlist response checksum does not match.',
    );
  }
  final collaborators = <String, SharedPlaylistAccessRole>{};
  final rawCollaborators = body['collaborators'];
  if (rawCollaborators != null) {
    if (role != SharedPlaylistAccessRole.owner || rawCollaborators is! Map) {
      throw const FormatException('Shared playlist collaborators are invalid.');
    }
    for (final entry in rawCollaborators.entries) {
      final collaboratorRole = _sharedPlaylistRoleFromWire(entry.value);
      if (entry.key is! String ||
          entry.key.trim().isEmpty ||
          entry.key.length > 256 ||
          collaboratorRole == null ||
          collaboratorRole == SharedPlaylistAccessRole.owner) {
        throw const FormatException('Shared playlist collaborators are invalid.');
      }
      collaborators[entry.key as String] = collaboratorRole;
    }
  }
  return SharedPlaylistRemote(
    id: id,
    revision: revision,
    role: role,
    name: name,
    trackIds: List<String>.unmodifiable(trackIds),
    updatedAt: _optionalDate(body['updatedAt']),
    updatedByDevice: _optionalString(body['updatedByDevice']),
    checksum: checksum,
    collaborators: Map<String, SharedPlaylistAccessRole>.unmodifiable(
      collaborators,
    ),
  );
}

SharedPlaylistRevision _parseSharedPlaylistRevision(
  Map<String, Object?> body,
) {
  final revision = body['revision'];
  final rawPlaylist = body['playlist'];
  final updatedAt = _optionalDate(body['updatedAt']);
  final updatedByDevice = _optionalString(body['updatedByDevice']);
  final checksum = _optionalString(body['checksum']);
  if (revision is! int ||
      revision <= 0 ||
      rawPlaylist is! Map ||
      updatedAt == null ||
      updatedByDevice == null ||
      checksum == null) {
    throw const FormatException('Shared playlist revision is invalid.');
  }
  final document = Map<String, Object?>.from(rawPlaylist);
  final name = document['name'];
  final rawTrackIds = document['trackIds'];
  if (document['version'] != 1 ||
      name is! String ||
      name != name.trim() ||
      name.isEmpty ||
      name.length > 160 ||
      rawTrackIds is! List ||
      rawTrackIds.length > 500) {
    throw const FormatException('Shared playlist revision is invalid.');
  }
  final trackIds = <String>[];
  for (final value in rawTrackIds) {
    if (value is! String ||
        value != value.trim() ||
        value.isEmpty ||
        value.length > 256) {
      throw const FormatException('Shared playlist revision is invalid.');
    }
    trackIds.add(value);
  }
  final actualChecksum = sha256
      .convert(utf8.encode(jsonEncode(document)))
      .toString();
  if (checksum != actualChecksum) {
    throw const ProviderRequestException(
      'Shared playlist revision checksum does not match.',
    );
  }
  return SharedPlaylistRevision(
    revision: revision,
    name: name,
    trackIds: List<String>.unmodifiable(trackIds),
    updatedAt: updatedAt,
    updatedByDevice: updatedByDevice,
    checksum: checksum,
  );
}

SharedPlaylistConflictException _parseSharedPlaylistConflict(String rawBody) {
  final body = _jsonObject(rawBody);
  return SharedPlaylistConflictException(
    currentRevision: body['currentRevision'] as int? ?? 0,
    updatedAt: _optionalDate(body['updatedAt']),
    updatedByDevice: _optionalString(body['updatedByDevice']),
    checksum: _optionalString(body['checksum']),
  );
}

Map<String, Object?> _sharedPlaylistDocument(
  String name,
  List<String> trackIds,
) {
  final normalizedName = name.trim();
  if (normalizedName.isEmpty || normalizedName.length > 160 || trackIds.length > 500) {
    throw const FormatException('Shared playlist document is invalid.');
  }
  final normalizedTrackIds = <String>[];
  for (final trackId in trackIds) {
    final normalized = trackId.trim();
    if (normalized.isEmpty || normalized != trackId || normalized.length > 256) {
      throw const FormatException('Shared playlist track IDs are invalid.');
    }
    normalizedTrackIds.add(normalized);
  }
  return <String, Object?>{
    'version': 1,
    'name': normalizedName,
    'trackIds': normalizedTrackIds,
  };
}

SharedPlaylistAccessRole? _sharedPlaylistRoleFromWire(Object? value) => switch (value) {
  'owner' => SharedPlaylistAccessRole.owner,
  'editor' => SharedPlaylistAccessRole.editor,
  'viewer' => SharedPlaylistAccessRole.viewer,
  _ => null,
};

String _sharedPlaylistRoleWire(SharedPlaylistAccessRole role) => switch (role) {
  SharedPlaylistAccessRole.viewer => 'viewer',
  SharedPlaylistAccessRole.editor => 'editor',
  SharedPlaylistAccessRole.owner => throw ArgumentError.value(role, 'role'),
};

String _requireSharedPlaylistId(String value) {
  final normalized = value.trim();
  if (!_isSharedPlaylistId(normalized)) {
    throw const FormatException('Shared playlist ID is invalid.');
  }
  return normalized;
}

bool _isSharedPlaylistId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);

bool _isSharedPlaylistInviteCode(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);

bool _isListenTogetherInviteCode(String value) {
  return RegExp(r'^[A-Za-z0-9_-]{24}$').hasMatch(value);
}

Map<String, Object?> _jsonObject(String rawBody) {
  final decoded = jsonDecode(rawBody);
  if (decoded is! Map) {
    throw const FormatException('Library sync response must be an object.');
  }
  return Map<String, Object?>.from(decoded);
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

Future<LibrarySyncHttpResponse> executeLibrarySyncHttpRequest(
  String method,
  Uri uri, {
  required Map<String, String> headers,
  String? body,
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > maxLibrarySyncResponseBytes) {
        throw const FormatException('Library sync response is too large.');
      }
    }
    return LibrarySyncHttpResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes),
    );
  } finally {
    client.close(force: true);
  }
}
