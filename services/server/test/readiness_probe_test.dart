import 'dart:async';
import 'dart:io';

import 'package:aethertune_server/src/readiness_probe.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  final handlers = <Future<void>>[];

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  });
  tearDown(() async {
    await server.close(force: true);
    await Future.wait(handlers);
    handlers.clear();
  });

  void respond(Future<void> Function(HttpRequest) handler) {
    server.listen((request) {
      handlers.add(handler(request));
    });
  }

  test('accepts the exact unauthenticated local readiness contract', () async {
    respond((request) async {
      expect(request.method, 'GET');
      expect(request.uri.path, '/ready');
      expect(request.headers.value('authorization'), isNull);
      request.response.write(
        '{"status":"ready","service":"aethertune-server"}',
      );
      await request.response.close();
    });
    expect(await probeServerReadiness(server.port), isTrue);
  });

  for (final status in [301, 401, 503]) {
    test('rejects HTTP $status without following redirects', () async {
      var requests = 0;
      respond((request) async {
        requests++;
        request.response.statusCode = status;
        request.response.headers.set('location', '/ready');
        await request.response.close();
      });
      expect(await probeServerReadiness(server.port), isFalse);
      expect(requests, 1);
    });
  }

  for (final body in [
    '',
    'not json',
    '[]',
    '{}',
    '{"status":"ready","service":"other"}',
    '{"status":"not_ready","service":"aethertune-server"}',
    ' ' * 4097,
  ]) {
    test(
      'rejects invalid or oversized readiness body (${body.length} bytes)',
      () async {
        respond((request) async {
          request.response.write(body);
          await request.response.close();
        });
        expect(await probeServerReadiness(server.port), isFalse);
      },
    );
  }

  for (final drip in [false, true]) {
    test(
      'bounds ${drip ? 'dripping' : 'stalled'} responses by a total deadline',
      () async {
        respond((request) async {
          try {
            for (var index = 0; index < 30; index++) {
              if (drip) {
                request.response.write(' ');
                await request.response.flush();
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            await request.response.close();
          } on Exception {
            // The bounded probe closes its socket when its total deadline expires.
          }
        });
        final watch = Stopwatch()..start();
        expect(
          await probeServerReadiness(
            server.port,
            timeout: const Duration(milliseconds: 60),
          ),
          isFalse,
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
      },
    );
  }

  test('rejects closed ports and invalid configuration', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close();
    expect(await probeServerReadiness(port), isFalse);
    for (final port in [-1, 0, 65536]) {
      expect(await probeServerReadiness(port), isFalse);
    }
    expect(
      await probeServerReadiness(server.port, timeout: Duration.zero),
      isFalse,
    );
  });
}
