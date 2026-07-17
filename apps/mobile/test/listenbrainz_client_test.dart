import 'dart:convert';

import 'package:aethertune/src/data/listenbrainz_client.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('submits the completed listen with the documented metadata payload', () async {
    Uri? requestedUri;
    String? requestedMethod;
    Map<String, String>? requestedHeaders;
    String? requestBody;
    final client = ListenBrainzClient(
      token: ' user-token ',
      requestSender: (
        uri, {
        required method,
        required headers,
        body,
      }) async {
        requestedUri = uri;
        requestedMethod = method;
        requestedHeaders = headers;
        requestBody = body;
        return const ListenBrainzResponse(statusCode: 200, body: '{}');
      },
    );

    await client.submitListen(
      track: Track(
        id: 'track-1',
        title: 'Satellite',
        artist: 'Aether',
        album: 'Signals',
        duration: const Duration(minutes: 3, seconds: 42),
      ),
      startedAt: DateTime.utc(2026, 7, 17, 12),
    );

    expect(requestedUri, Uri.parse('https://api.listenbrainz.org/1/submit-listens'));
    expect(requestedMethod, 'POST');
    expect(requestedHeaders!['authorization'], 'Token user-token');
    final document = jsonDecode(requestBody!) as Map<String, dynamic>;
    expect(document['listen_type'], 'single');
    final listen = (document['payload'] as List<dynamic>).single as Map<String, dynamic>;
    expect(listen['listened_at'], 1784289600);
    final metadata = listen['track_metadata'] as Map<String, dynamic>;
    expect(metadata['artist_name'], 'Aether');
    expect(metadata['track_name'], 'Satellite');
    expect(metadata['release_name'], 'Signals');
    expect(
      (metadata['additional_info'] as Map<String, dynamic>)['duration_ms'],
      const Duration(minutes: 3, seconds: 42).inMilliseconds,
    );
  });

  test('validates a configured user token without placing it in a URL', () async {
    Uri? requestedUri;
    Map<String, String>? requestedHeaders;
    final client = ListenBrainzClient(
      token: 'secret-token',
      requestSender: (
        uri, {
        required method,
        required headers,
        body,
      }) async {
        requestedUri = uri;
        requestedHeaders = headers;
        return const ListenBrainzResponse(
          statusCode: 200,
          body: '{"valid": true, "user_name": "yunus"}',
        );
      },
    );

    expect(await client.validateToken(), 'yunus');
    expect(requestedUri, Uri.parse('https://api.listenbrainz.org/1/validate-token'));
    expect(requestedUri!.query, isEmpty);
    expect(requestedHeaders!['authorization'], 'Token secret-token');
  });
}
