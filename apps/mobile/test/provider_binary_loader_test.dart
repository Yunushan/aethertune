import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/provider_binary_loader.dart';
import 'package:aethertune/src/data/provider_error.dart';

void main() {
  test('loads bounded image bytes and applies private request headers',
      () async {
    final capturedHeader = Completer<String?>();
    final server = await _server((request) async {
      capturedHeader.complete(request.headers.value('X-Test-Token'));
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(<int>[1, 2, 3]);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final bytes = await loadProviderImageBytes(
      _uri(server),
      const <String, String>{'X-Test-Token': 'private-token'},
    );

    expect(bytes, <int>[1, 2, 3]);
    expect(await capturedHeader.future, 'private-token');
  });

  test('rejects non-image responses', () async {
    final server = await _server((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"error":"not an image"}');
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      loadProviderImageBytes(_uri(server), const <String, String>{}),
      throwsA(
        isA<ProviderRequestException>().having(
          (error) => error.message,
          'message',
          contains('did not contain an image'),
        ),
      ),
    );
  });

  test('rejects artwork larger than the configured safety limit', () async {
    final server = await _server((request) async {
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(<int>[1, 2, 3, 4, 5]);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    await expectLater(
      loadProviderImageBytes(
        _uri(server),
        const <String, String>{},
        maxBytes: 4,
      ),
      throwsA(
        isA<ProviderRequestException>().having(
          (error) => error.message,
          'message',
          contains('4 byte safety limit'),
        ),
      ),
    );
  });
}

Future<HttpServer> _server(
  Future<void> Function(HttpRequest request) handler,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(handler);
  return server;
}

Uri _uri(HttpServer server) {
  return Uri(
    scheme: 'http',
    host: server.address.address,
    port: server.port,
    path: '/artwork',
  );
}
