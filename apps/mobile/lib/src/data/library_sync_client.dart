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

Future<String> redeemLibrarySyncRecoveryCode(
  LibrarySyncAccount account,
  String recoveryCode, {
  LibrarySyncHttpExecutor? httpExecutor,
}) async {
  final normalizedCode = recoveryCode.trim();
  if (normalizedCode.isEmpty || RegExp(r'\s').hasMatch(normalizedCode)) {
    throw const FormatException('Recovery code is required.');
  }
  final executor = httpExecutor ?? executeLibrarySyncHttpRequest;
  final response = await executor(
    'POST',
    account.recoveryEndpointUri,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'accept': 'application/json',
    },
    body: jsonEncode(<String, Object?>{
      'recoveryCode': normalizedCode,
      'deviceName': account.deviceId,
    }),
  );
  if (response.statusCode != 201) {
    throw const ProviderRequestException('Recovery code was not accepted.');
  }
  final body = _jsonObject(response.body);
  final token = body['token'];
  if (token is! String || token.trim().isEmpty || RegExp(r'\s').hasMatch(token)) {
    throw const ProviderRequestException('Recovery response did not include a valid token.');
  }
  return token;
}

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

enum SharedPlaylistKind { manual, smart }

class SharedSmartPlaylistDocument {
  const SharedSmartPlaylistDocument({
    required this.name,
    required this.rule,
  });

  final String name;
  final Map<String, Object?> rule;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 2,
    'kind': 'smart',
    'name': name,
    'rule': rule,
  };
}

class LibrarySyncPublicProfile {
  const LibrarySyncPublicProfile({
    required this.id,
    required this.displayName,
    this.avatarTone,
  });

  final String id;
  final String displayName;
  final String? avatarTone;

  static LibrarySyncPublicProfile fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final displayName = json['displayName'];
    final avatarTone = json['avatarTone'];
    if (id is! String ||
        id.trim().isEmpty ||
        id.length > 128 ||
        displayName is! String ||
        displayName.trim().isEmpty ||
        displayName.length > 160 ||
        (avatarTone != null && avatarTone is! String)) {
      throw const FormatException('Public profile result is invalid.');
    }
    return LibrarySyncPublicProfile(
      id: id,
      displayName: displayName,
      avatarTone: avatarTone as String?,
    );
  }
}

/// A privacy-bounded, cross-library identity for a manual shared playlist.
///
/// It deliberately excludes device-local IDs, paths, provider IDs, stream
/// URLs, hashes, and fingerprints. Receivers resolve it only when it maps to
/// exactly one local track.
class SharedPlaylistTrackReference {
  const SharedPlaylistTrackReference({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMilliseconds,
  });

  final String title;
  final String artist;
  final String album;
  final int durationMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': durationMilliseconds,
  };
}

class SharedSmartPlaylistPublicLink {
  const SharedSmartPlaylistPublicLink({
    required this.uri,
    required this.revision,
  });

  final Uri uri;
  final int revision;
}

/// A checksum-verified smart-playlist document fetched with a public link.
///
/// Public links are bearer capabilities. They deliberately use a separate
/// client path so a configured library-sync token can never accompany them.
class PublicSharedSmartPlaylist {
  const PublicSharedSmartPlaylist({
    required this.uri,
    required this.playlistId,
    required this.revision,
    required this.playlist,
  });

  final Uri uri;
  final String playlistId;
  final int revision;
  final SharedSmartPlaylistDocument playlist;
}

Future<PublicSharedSmartPlaylist> fetchPublicSharedSmartPlaylist(
  String link, {
  LibrarySyncHttpExecutor? httpExecutor,
}) async {
  final uri = _parsePublicSharedSmartPlaylistUri(link);
  final executor = httpExecutor ?? executeLibrarySyncHttpRequest;
  try {
    final response = await executor(
      'GET',
      uri,
      headers: const <String, String>{'accept': 'application/json'},
    );
    if (response.statusCode == 404) {
      throw const ProviderRequestException('This public smart playlist is unavailable.');
    }
    if (response.statusCode != 200) {
      throw const ProviderRequestException('Could not fetch this public smart playlist.');
    }
    final body = _jsonObject(response.body);
    if (body.keys.any(
      (key) => key != 'revision' && key != 'checksum' && key != 'playlist',
    )) {
      throw const FormatException('Public smart playlist response is invalid.');
    }
    final revision = body['revision'];
    final checksum = body['checksum'];
    final rawPlaylist = body['playlist'];
    if (revision is! int ||
        revision <= 0 ||
        checksum is! String ||
        rawPlaylist is! Map) {
      throw const FormatException('Public smart playlist response is invalid.');
    }
    final document = Map<String, Object?>.from(rawPlaylist);
    final actualChecksum = sha256
        .convert(utf8.encode(jsonEncode(document)))
        .toString();
    if (checksum != actualChecksum) {
      throw const ProviderRequestException(
        'Public smart playlist response checksum does not match.',
      );
    }
    final parsedDocument = _parseSharedPlaylistDocument(document);
    final smartPlaylist = parsedDocument.smartPlaylist;
    if (parsedDocument.kind != SharedPlaylistKind.smart || smartPlaylist == null) {
      throw const FormatException('This public link is not a smart playlist.');
    }
    return PublicSharedSmartPlaylist(
      uri: uri,
      playlistId: _publicSharedSmartPlaylistIdFromUri(uri),
      revision: revision,
      playlist: smartPlaylist,
    );
  } on Object catch (error) {
    if (error is ProviderRequestException || error is FormatException) {
      rethrow;
    }
    throw const ProviderRequestException('Could not fetch this public smart playlist.');
  }
}

class SharedPlaylistRemote {
  const SharedPlaylistRemote({
    required this.id,
    required this.revision,
    required this.role,
    required this.name,
    required this.trackIds,
    this.trackReferences,
    this.kind = SharedPlaylistKind.manual,
    this.smartPlaylist,
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
  final List<SharedPlaylistTrackReference>? trackReferences;
  final SharedPlaylistKind kind;
  final SharedSmartPlaylistDocument? smartPlaylist;
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
    this.trackReferences,
    this.kind = SharedPlaylistKind.manual,
    this.smartPlaylist,
    required this.updatedAt,
    required this.updatedByDevice,
    required this.checksum,
  });

  final int revision;
  final String name;
  final List<String> trackIds;
  final List<SharedPlaylistTrackReference>? trackReferences;
  final SharedPlaylistKind kind;
  final SharedSmartPlaylistDocument? smartPlaylist;
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

/// Coordinates provider settings separately from portable library metadata.
/// Callers are responsible for allowing only credential-free documents.
abstract interface class ProviderConfigurationGateway {
  Future<LibrarySyncRemoteSnapshot> fetchProviderConfiguration();

  Future<LibrarySyncRemoteSnapshot> pushProviderConfiguration({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  });
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
    List<SharedPlaylistTrackReference>? trackReferences,
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
    List<SharedPlaylistTrackReference>? trackReferences,
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

abstract interface class SharedSmartPlaylistGateway
    extends SharedPlaylistGateway {
  Future<SharedPlaylistRemote> createSharedSmartPlaylist({
    required String name,
    required Map<String, Object?> rule,
  });

  Future<SharedPlaylistRemote> updateSharedSmartPlaylist({
    required String playlistId,
    required int baseRevision,
    required String name,
    required Map<String, Object?> rule,
  });

  Future<SharedSmartPlaylistPublicLink> issueSharedSmartPlaylistPublicLink({
    required String playlistId,
    required int baseRevision,
  });

  Future<int> revokeSharedSmartPlaylistPublicLink({
    required String playlistId,
    required int baseRevision,
  });
}

abstract interface class LibrarySyncProfileGateway {
  Future<LibrarySyncProfile?> fetchProfile();
}

abstract interface class LibrarySyncPublicProfileGateway {
  Future<List<LibrarySyncPublicProfile>> findPublicProfiles(String query);
}

abstract interface class LibrarySyncProfileEditorGateway {
  Future<LibrarySyncProfile> updateProfile({
    required String displayName,
    required String deviceName,
    LibrarySyncProfileAvatarTone? avatarTone,
    bool includeAvatarTone = false,
    bool publicProfileEnabled = false,
    bool includePublicProfileEnabled = false,
    bool publicDisplayNameEnabled = false,
    bool includePublicDisplayNameEnabled = false,
    bool publicAvatarToneEnabled = false,
    bool includePublicAvatarToneEnabled = false,
  });
}

class LibrarySyncClient
    implements
        LibrarySyncGateway,
        LibrarySyncMetadataGateway,
        ProviderConfigurationGateway,
        ListenTogetherGateway,
        SharedPlaylistGateway,
        SharedSmartPlaylistGateway,
        LibrarySyncProfileGateway,
        LibrarySyncPublicProfileGateway,
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
  Future<List<LibrarySyncPublicProfile>> findPublicProfiles(
    String query,
  ) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 80) {
      throw const FormatException('Enter at least two characters to search profiles.');
    }
    final response = await _httpExecutor(
      'GET',
      account.publicProfileDiscoveryEndpointUri(normalized),
      headers: const <String, String>{'accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    final profiles = _jsonObject(response.body)['profiles'];
    if (profiles is! List || profiles.length > 20) {
      throw const FormatException('Public profile results are invalid.');
    }
    return List<LibrarySyncPublicProfile>.unmodifiable(
      profiles.map((item) {
        if (item is! Map) {
          throw const FormatException('Public profile result is invalid.');
        }
        return LibrarySyncPublicProfile.fromJson(
          Map<String, Object?>.from(item),
        );
      }),
    );
  }

  @override
  Future<LibrarySyncProfile> updateProfile({
    required String displayName,
    required String deviceName,
    LibrarySyncProfileAvatarTone? avatarTone,
    bool includeAvatarTone = false,
    bool publicProfileEnabled = false,
    bool includePublicProfileEnabled = false,
    bool publicDisplayNameEnabled = false,
    bool includePublicDisplayNameEnabled = false,
    bool publicAvatarToneEnabled = false,
    bool includePublicAvatarToneEnabled = false,
  }) async {
    final response = await _execute(
      'PATCH',
      endpoint: account.profileEndpointUri,
      body: jsonEncode(<String, Object?>{
        'displayName': normalizeLibrarySyncProfileDisplayName(displayName),
        'deviceName': normalizeLibrarySyncProfileDeviceName(deviceName),
        if (includeAvatarTone) 'avatarTone': avatarTone?.wireValue,
        if (includePublicProfileEnabled)
          'publicProfileEnabled': publicProfileEnabled,
        if (includePublicDisplayNameEnabled)
          'publicDisplayNameEnabled': publicDisplayNameEnabled,
        if (includePublicAvatarToneEnabled)
          'publicAvatarToneEnabled': publicAvatarToneEnabled,
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
  Future<LibrarySyncRemoteSnapshot> fetchProviderConfiguration() async {
    final response = await _execute(
      'GET',
      endpoint: account.providerConfigurationEndpointUri,
    );
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
          'Provider configuration checksum does not match.',
        );
      }
    }
    return result;
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
    List<SharedPlaylistTrackReference>? trackReferences,
  }) async {
    return _createSharedPlaylistDocument(
      _sharedPlaylistDocument(
        name,
        trackIds,
        trackReferences: trackReferences,
      ),
    );
  }

  /// Creates a private shared rule definition. Each device evaluates the rules
  /// locally, so no library records or playback history leave the device.
  @override
  Future<SharedPlaylistRemote> createSharedSmartPlaylist({
    required String name,
    required Map<String, Object?> rule,
  }) async {
    return _createSharedPlaylistDocument(
      _sharedSmartPlaylistDocument(name, rule),
    );
  }

  Future<SharedPlaylistRemote> _createSharedPlaylistDocument(
    Map<String, Object?> document,
  ) async {
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
    List<SharedPlaylistTrackReference>? trackReferences,
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
        'playlist': _sharedPlaylistDocument(
          name,
          trackIds,
          trackReferences: trackReferences,
        ),
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
  Future<SharedPlaylistRemote> updateSharedSmartPlaylist({
    required String playlistId,
    required int baseRevision,
    required String name,
    required Map<String, Object?> rule,
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
        'playlist': _sharedSmartPlaylistDocument(name, rule),
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
  Future<SharedSmartPlaylistPublicLink> issueSharedSmartPlaylistPublicLink({
    required String playlistId,
    required int baseRevision,
  }) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    if (baseRevision <= 0) {
      throw const FormatException('Shared playlist revision is invalid.');
    }
    final response = await _execute(
      'POST',
      endpoint: account.sharedPlaylistPublicLinkEndpointUri(normalized),
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
    final body = _jsonObject(response.body);
    final secret = body['secret'];
    final revision = body['revision'];
    if (secret is! String ||
        !_isSharedPlaylistInviteCode(secret) ||
        revision is! int ||
        revision <= baseRevision) {
      throw const FormatException('Shared smart-playlist public link is invalid.');
    }
    return SharedSmartPlaylistPublicLink(
      uri: account.publicSmartPlaylistEndpointUri(normalized, secret),
      revision: revision,
    );
  }

  @override
  Future<int> revokeSharedSmartPlaylistPublicLink({
    required String playlistId,
    required int baseRevision,
  }) async {
    final normalized = _requireSharedPlaylistId(playlistId);
    if (baseRevision <= 0) {
      throw const FormatException('Shared playlist revision is invalid.');
    }
    final response = await _execute(
      'DELETE',
      endpoint: account.sharedPlaylistPublicLinkEndpointUri(normalized),
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
    final body = _jsonObject(response.body);
    final revision = body['revision'];
    if (body['revoked'] != true || revision is! int || revision <= baseRevision) {
      throw const FormatException('Shared smart-playlist public-link revocation is invalid.');
    }
    return revision;
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

  @override
  Future<LibrarySyncRemoteSnapshot> pushProviderConfiguration({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  }) async {
    final response = await _execute(
      'PUT',
      endpoint: account.providerConfigurationEndpointUri,
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
        'Provider configuration returned an invalid revision.',
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
  final parsedDocument = _parseSharedPlaylistDocument(document);
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
    name: parsedDocument.name,
    trackIds: parsedDocument.trackIds,
    trackReferences: parsedDocument.trackReferences,
    kind: parsedDocument.kind,
    smartPlaylist: parsedDocument.smartPlaylist,
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
  final parsedDocument = _parseSharedPlaylistDocument(document);
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
    name: parsedDocument.name,
    trackIds: parsedDocument.trackIds,
    trackReferences: parsedDocument.trackReferences,
    kind: parsedDocument.kind,
    smartPlaylist: parsedDocument.smartPlaylist,
    updatedAt: updatedAt,
    updatedByDevice: updatedByDevice,
    checksum: checksum,
  );
}

class _ParsedSharedPlaylistDocument {
  const _ParsedSharedPlaylistDocument({
    required this.name,
    required this.trackIds,
    required this.kind,
    this.trackReferences,
    this.smartPlaylist,
  });

  final String name;
  final List<String> trackIds;
  final SharedPlaylistKind kind;
  final List<SharedPlaylistTrackReference>? trackReferences;
  final SharedSmartPlaylistDocument? smartPlaylist;
}

_ParsedSharedPlaylistDocument _parseSharedPlaylistDocument(
  Map<String, Object?> document,
) {
  final name = document['name'];
  if (name is! String ||
      name != name.trim() ||
      name.isEmpty ||
      name.length > 160) {
    throw const FormatException('Shared playlist document is invalid.');
  }
  if (document['version'] == 1) {
    if (document.keys.any((key) => key != 'version' && key != 'name' && key != 'trackIds')) {
      throw const FormatException('Shared playlist document is invalid.');
    }
    final rawTrackIds = document['trackIds'];
    if (rawTrackIds is! List || rawTrackIds.length > 500) {
      throw const FormatException('Shared playlist track IDs are invalid.');
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
    return _ParsedSharedPlaylistDocument(
      name: name,
      trackIds: List<String>.unmodifiable(trackIds),
      kind: SharedPlaylistKind.manual,
    );
  }
  if (document['version'] == 3) {
    if (document.keys.any((key) => key != 'version' && key != 'name' && key != 'tracks')) {
      throw const FormatException('Shared playlist document is invalid.');
    }
    final rawTracks = document['tracks'];
    if (rawTracks is! List || rawTracks.length > 200) {
      throw const FormatException('Shared playlist track references are invalid.');
    }
    final trackReferences = <SharedPlaylistTrackReference>[];
    for (final value in rawTracks) {
      if (value is! Map) {
        throw const FormatException('Shared playlist track references are invalid.');
      }
      trackReferences.add(
        _parseSharedPlaylistTrackReference(Map<String, Object?>.from(value)),
      );
    }
    return _ParsedSharedPlaylistDocument(
      name: name,
      trackIds: const <String>[],
      trackReferences: List<SharedPlaylistTrackReference>.unmodifiable(
        trackReferences,
      ),
      kind: SharedPlaylistKind.manual,
    );
  }
  if (document['version'] != 2 ||
      document['kind'] != 'smart' ||
      document.keys.any(
        (key) => key != 'version' && key != 'kind' && key != 'name' && key != 'rule',
      ) ||
      document['rule'] is! Map) {
    throw const FormatException('Shared smart playlist document is invalid.');
  }
  final rule = _parseSharedSmartPlaylistRule(
    Map<String, Object?>.from(document['rule'] as Map),
  );
  return _ParsedSharedPlaylistDocument(
    name: name,
    trackIds: const <String>[],
    kind: SharedPlaylistKind.smart,
    smartPlaylist: SharedSmartPlaylistDocument(name: name, rule: rule),
  );
}

SharedPlaylistTrackReference _parseSharedPlaylistTrackReference(
  Map<String, Object?> reference,
) {
  const allowed = <String>{'title', 'artist', 'album', 'durationMs'};
  if (reference.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Shared playlist track references are invalid.');
  }
  String text(String key) {
    final value = reference[key];
    if (value is! String ||
        value != value.trim() ||
        value.isEmpty ||
        value.length > 160) {
      throw const FormatException('Shared playlist track references are invalid.');
    }
    return value;
  }

  final durationMilliseconds = reference['durationMs'];
  if (durationMilliseconds is! int ||
      durationMilliseconds < 0 ||
      durationMilliseconds > 86400000) {
    throw const FormatException('Shared playlist track references are invalid.');
  }
  return SharedPlaylistTrackReference(
    title: text('title'),
    artist: text('artist'),
    album: text('album'),
    durationMilliseconds: durationMilliseconds,
  );
}

Map<String, Object?> _parseSharedSmartPlaylistRule(
  Map<String, Object?> rule,
) {
  const allowed = <String>{
    'query', 'sourceId', 'artist', 'album', 'genre',
    'minimumDurationSeconds', 'maximumDurationSeconds', 'favoritesOnly',
    'minimumPlayCount', 'minimumDaysSinceLastPlayed', 'matchMode',
    'ruleGroups', 'sortMode', 'limit',
  };
  if (rule.keys.any((key) => !allowed.contains(key))) {
    throw const FormatException('Shared smart playlist rule is invalid.');
  }
  final normalized = <String, Object?>{};
  for (final key in <String>['query', 'sourceId', 'artist', 'album', 'genre']) {
    final value = rule[key] ?? '';
    if (value is! String || value != value.trim() || value.length > 512) {
      throw const FormatException('Shared smart playlist text rule is invalid.');
    }
    normalized[key] = value;
  }
  for (final key in <String>[
    'minimumDurationSeconds', 'maximumDurationSeconds',
    'minimumPlayCount', 'minimumDaysSinceLastPlayed',
  ]) {
    final value = rule[key] ?? 0;
    if (value is! int || value < 0 || value > 315360000) {
      throw const FormatException('Shared smart playlist numeric rule is invalid.');
    }
    normalized[key] = value;
  }
  final favoritesOnly = rule['favoritesOnly'] ?? false;
  final matchMode = rule['matchMode'] ?? 'all';
  final sortMode = rule['sortMode'] ?? 'recentlyAdded';
  final limit = rule['limit'] ?? 50;
  if (favoritesOnly is! bool ||
      (matchMode != 'all' && matchMode != 'any') ||
      !const <String>{'recentlyAdded', 'title', 'artist', 'album', 'recentlyPlayed', 'mostPlayed'}.contains(sortMode) ||
      limit is! int || limit < 1 || limit > 500) {
    throw const FormatException('Shared smart playlist options are invalid.');
  }
  final rawGroups = rule['ruleGroups'] ?? const <Object?>[];
  if (rawGroups is! List || rawGroups.length > 25) {
    throw const FormatException('Shared smart playlist groups are invalid.');
  }
  normalized['favoritesOnly'] = favoritesOnly;
  normalized['matchMode'] = matchMode;
  normalized['sortMode'] = sortMode;
  normalized['limit'] = limit;
  normalized['ruleGroups'] = rawGroups
      .map((group) => _parseSharedSmartPlaylistGroup(group, depth: 0))
      .toList(growable: false);
  return Map<String, Object?>.unmodifiable(normalized);
}

Map<String, Object?> _parseSharedSmartPlaylistGroup(
  Object? raw, {
  required int depth,
}) {
  if (raw is! Map || depth >= 8) {
    throw const FormatException('Shared smart playlist group is invalid.');
  }
  final group = Map<String, Object?>.from(raw);
  if (group.keys.any((key) => key != 'matchMode' && key != 'rules' && key != 'groups') ||
      (group['matchMode'] != 'all' && group['matchMode'] != 'any')) {
    throw const FormatException('Shared smart playlist group is invalid.');
  }
  final rules = group['rules'];
  final groups = group['groups'];
  if (rules is! List || groups is! List || rules.length > 50 || groups.length > 25) {
    throw const FormatException('Shared smart playlist group is invalid.');
  }
  if (rules.isEmpty && groups.isEmpty) {
    throw const FormatException('Shared smart playlist group is empty.');
  }
  const allowedFields = <String>{
    'searchText', 'sourceId', 'artist', 'album', 'genre',
    'minimumDurationSeconds', 'maximumDurationSeconds', 'favoritesOnly',
    'minimumRating', 'minimumPlayCount', 'minimumDaysSinceLastPlayed',
  };
  final normalizedRules = <Map<String, Object?>>[];
  for (final rawRule in rules) {
    if (rawRule is! Map) {
      throw const FormatException('Shared smart playlist group rule is invalid.');
    }
    final item = Map<String, Object?>.from(rawRule);
    final field = item['field'];
    final value = item['value'];
    if (item.keys.any((key) => key != 'field' && key != 'value') ||
        field is! String || !allowedFields.contains(field) ||
        value is! String || value != value.trim() || value.length > 512) {
      throw const FormatException('Shared smart playlist group rule is invalid.');
    }
    normalizedRules.add(<String, Object?>{'field': field, 'value': value});
  }
  return <String, Object?>{
    'matchMode': group['matchMode'],
    'rules': normalizedRules,
    'groups': groups
        .map((child) => _parseSharedSmartPlaylistGroup(child, depth: depth + 1))
        .toList(growable: false),
  };
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
  {List<SharedPlaylistTrackReference>? trackReferences,}
) {
  if (trackReferences != null) {
    final candidate = <String, Object?>{
      'version': 3,
      'name': name.trim(),
      'tracks': trackReferences.map((reference) => reference.toJson()).toList(),
    };
    final parsed = _parseSharedPlaylistDocument(candidate);
    return <String, Object?>{
      'version': 3,
      'name': parsed.name,
      'tracks': parsed.trackReferences!
          .map((reference) => reference.toJson())
          .toList(growable: false),
    };
  }
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

Map<String, Object?> _sharedSmartPlaylistDocument(
  String name,
  Map<String, Object?> rule,
) {
  final candidate = <String, Object?>{
    'version': 2,
    'kind': 'smart',
    'name': name.trim(),
    'rule': Map<String, Object?>.from(rule),
  };
  final parsed = _parseSharedPlaylistDocument(candidate);
  final smart = parsed.smartPlaylist;
  if (parsed.kind != SharedPlaylistKind.smart || smart == null) {
    throw const FormatException('Shared smart playlist document is invalid.');
  }
  return smart.toJson();
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

Uri _parsePublicSharedSmartPlaylistUri(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw const FormatException(
      'Enter a valid HTTPS public smart-playlist link.',
    );
  }
  final segments = uri.pathSegments;
  if (segments.length < 5 || segments.any((segment) => segment.isEmpty)) {
    throw const FormatException(
      'Enter a valid HTTPS public smart-playlist link.',
    );
  }
  final tail = segments.sublist(segments.length - 5);
  if (tail[0] != 'api' ||
      tail[1] != 'v1' ||
      tail[2] != 'public-smart-playlists' ||
      !_isSharedPlaylistId(tail[3]) ||
      !_isSharedPlaylistInviteCode(tail[4])) {
    throw const FormatException(
      'Enter a valid HTTPS public smart-playlist link.',
    );
  }
  return uri;
}

String _publicSharedSmartPlaylistIdFromUri(Uri uri) =>
    uri.pathSegments[uri.pathSegments.length - 2];

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
    request.followRedirects = false;
    request.maxRedirects = 0;
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
