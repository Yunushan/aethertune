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
