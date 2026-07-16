import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/library_sync_account.dart';
import '../domain/library_sync_profile.dart';
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

abstract interface class LibrarySyncGateway {
  Future<LibrarySyncRemoteSnapshot> fetch();

  Future<LibrarySyncRemoteSnapshot> push({
    required int baseRevision,
    required Map<String, Object?> snapshot,
  });

  Future<LibrarySyncRemoteSnapshot> delete({required int baseRevision});
}

abstract interface class LibrarySyncMetadataGateway {
  Future<LibrarySyncRemoteSnapshot> fetchMetadata();
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
  Future<LibrarySyncRemoteSnapshot> fetchMetadata() async {
    final response = await _execute(
      'GET',
      endpoint: account.libraryMetadataEndpointUri,
    );
    if (response.statusCode != 200) {
      throw _requestFailure(response);
    }
    return _parseRemoteMetadata(response.body);
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
          error is LibrarySyncConflictException) {
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
