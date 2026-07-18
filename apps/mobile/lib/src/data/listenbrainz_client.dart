import 'dart:convert';
import 'dart:io';

import '../domain/track.dart';

final class ListenBrainzResponse {
  const ListenBrainzResponse({required this.statusCode, this.body = ''});

  final int statusCode;
  final String body;
}

typedef ListenBrainzRequestSender = Future<ListenBrainzResponse> Function(
  Uri uri, {
  required String method,
  required Map<String, String> headers,
  String? body,
});

final class ListenBrainzHistoryEntry {
  const ListenBrainzHistoryEntry({
    required this.title,
    required this.artist,
    required this.listenedAt,
    this.album,
  });

  final String title;
  final String artist;
  final String? album;
  final DateTime listenedAt;
}

/// Minimal client for the user-authorized ListenBrainz listen-submission API.
class ListenBrainzClient {
  ListenBrainzClient({
    required String token,
    ListenBrainzRequestSender? requestSender,
  }) : _token = _normalizeToken(token),
       _requestSender = requestSender ?? _sendRequest;

  static final Uri _baseUri = Uri.https('api.listenbrainz.org', '/1/');

  final String _token;
  final ListenBrainzRequestSender _requestSender;

  Future<String?> validateToken() async {
    final response = await _requestSender(
      _baseUri.resolve('validate-token'),
      method: 'GET',
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('ListenBrainz rejected the token.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('ListenBrainz returned an invalid token response.');
    }
    final result = Map<String, Object?>.from(decoded);
    if (result['valid'] != true) {
      throw StateError('ListenBrainz rejected the token.');
    }
    final userName = result['user_name'] as String?;
    return userName?.trim().isEmpty == true ? null : userName?.trim();
  }

  Future<void> submitListen({
    required Track track,
    required DateTime startedAt,
  }) async {
    final metadata = <String, Object?>{
      'artist_name': _metadataText(track.artist, fallback: 'Unknown Artist'),
      'track_name': _metadataText(track.title, fallback: 'Untitled'),
    };
    final album = track.album.trim();
    if (album.isNotEmpty && album != 'Unknown Album') {
      metadata['release_name'] = album;
    }
    metadata['additional_info'] = <String, Object?>{
      'media_player': 'AetherTune',
      'submission_client': 'AetherTune',
      if (track.duration > Duration.zero)
        'duration_ms': track.duration.inMilliseconds,
    };

    final response = await _requestSender(
      _baseUri.resolve('submit-listens'),
      method: 'POST',
      headers: _headers,
      body: jsonEncode(<String, Object?>{
        'listen_type': 'single',
        'payload': <Object?>[
          <String, Object?>{
            'listened_at': startedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
            'track_metadata': metadata,
          },
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('ListenBrainz did not accept this listen.');
    }
  }

  Future<List<ListenBrainzHistoryEntry>> fetchListenHistory({
    required String userName,
    int count = 100,
    DateTime? before,
  }) async {
    final normalizedUserName = userName.trim();
    if (normalizedUserName.isEmpty) {
      throw const FormatException('ListenBrainz user name is required.');
    }
    if (count < 1 || count > 1000) {
      throw RangeError.range(count, 1, 1000, 'count');
    }
    final query = <String, String>{'count': '$count'};
    if (before != null) {
      query['max_ts'] = '${before.toUtc().millisecondsSinceEpoch ~/ 1000}';
    }
    final response = await _requestSender(
      _baseUri.replace(
        path: '/1/user/${Uri.encodeComponent(normalizedUserName)}/listens',
        queryParameters: query,
      ),
      method: 'GET',
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Could not fetch ListenBrainz history.');
    }
    final decoded = jsonDecode(response.body);
    final payload = decoded is Map ? decoded['payload'] : null;
    final listens = payload is Map ? payload['listens'] : null;
    if (listens is! List) {
      throw const FormatException('ListenBrainz returned invalid history.');
    }
    final entries = <ListenBrainzHistoryEntry>[];
    for (final value in listens.take(count)) {
      if (value is! Map) continue;
      final metadata = value['track_metadata'];
      final listenedAt = value['listened_at'];
      if (metadata is! Map || listenedAt is! num || listenedAt <= 0) continue;
      final title = _nonEmpty(metadata['track_name']);
      final artist = _nonEmpty(metadata['artist_name']);
      if (title == null || artist == null) continue;
      entries.add(
        ListenBrainzHistoryEntry(
          title: title,
          artist: artist,
          album: _nonEmpty(metadata['release_name']),
          listenedAt: DateTime.fromMillisecondsSinceEpoch(
            listenedAt.toInt() * 1000,
            isUtc: true,
          ),
        ),
      );
    }
    return entries;
  }

  Map<String, String> get _headers => <String, String>{
    HttpHeaders.authorizationHeader: 'Token $_token',
    HttpHeaders.contentTypeHeader: ContentType.json.mimeType,
    HttpHeaders.acceptHeader: ContentType.json.mimeType,
  };

  static String _normalizeToken(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw const FormatException('Enter a ListenBrainz user token.');
    }
    return normalized;
  }

  static String _metadataText(String value, {required String fallback}) {
    final normalized = value.trim();
    return normalized.isEmpty ? fallback : normalized;
  }

  static String? _nonEmpty(Object? value) {
    if (value is! String || value.trim().isEmpty) return null;
    return value.trim();
  }

  static Future<ListenBrainzResponse> _sendRequest(
    Uri uri, {
    required String method,
    required Map<String, String> headers,
    String? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri);
      headers.forEach((name, value) => request.headers.set(name, value));
      if (body != null) {
        request.write(body);
      }
      final response = await request.close();
      final responseBody = await utf8.decodeStream(response);
      return ListenBrainzResponse(
        statusCode: response.statusCode,
        body: responseBody,
      );
    } finally {
      client.close(force: true);
    }
  }
}
