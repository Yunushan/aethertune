import 'dart:convert';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('AetherTune server', () {
    test('health endpoint reports ok', () async {
      final handler = createServerHandler(
        clock: () => DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final response = await handler(_get('/health'));
      final body = await _json(response);

      expect(response.statusCode, 200);
      expect(body['status'], 'ok');
      expect(body['service'], 'aethertune-server');
      expect(body['timestamp'], '2026-01-02T03:04:05.000Z');
    });

    test('info endpoint lists mobile and desktop clients', () async {
      final response = await createServerHandler()(_get('/api/v1/info'));
      final body = await _json(response);

      expect(response.statusCode, 200);
      expect(body['name'], 'AetherTune');
      expect(
        body['supportedClients'],
        containsAll(<String>['android', 'ios', 'linux', 'macos', 'windows']),
      );
    });

    test('tracks endpoint filters catalog entries', () async {
      final response = await createServerHandler()(
        _get('/api/v1/tracks?q=radio'),
      );
      final body = await _json(response);
      final tracks = body['tracks'] as List<dynamic>;

      expect(response.statusCode, 200);
      expect(tracks, hasLength(1));
      expect((tracks.single as Map<String, dynamic>)['id'], 'open-catalogs');
    });

    test('unsupported paths return JSON 404', () async {
      final response = await createServerHandler()(_get('/missing'));
      final body = await _json(response);

      expect(response.statusCode, 404);
      expect(body['error'], 'not_found');
      expect(body['path'], '/missing');
    });
  });
}

Request _get(String path) {
  return Request('GET', Uri.parse('http://localhost$path'));
}

Future<Map<String, dynamic>> _json(Response response) async {
  return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
}
