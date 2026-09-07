import 'dart:convert';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';

Request _request(String token) => Request(
  'GET',
  Uri.parse('http://localhost/api/v1/sync/library'),
  headers: {'authorization': 'Bearer $token'},
);

void main() {
  test(
    'rejects invalid tokens without granting new rate-limit buckets',
    () async {
      final handler = createServerHandler(
        syncAuthenticator: StaticSyncAuthenticator({'owner': 'valid-token'}),
        requestRateLimiter: ServerRequestRateLimiter(maximumRequests: 2),
      );
      final statuses = <int>[];
      for (var i = 0; i < 4; i++) {
        statuses.add((await handler(_request('invalid-$i'))).statusCode);
      }
      expect(statuses, [401, 401, 429, 429]);
      // Valid credentials retain their own allowance behind the same proxy.
      expect((await handler(_request('valid-token'))).statusCode, 200);
    },
  );

  test(
    'uses account identity across device tokens behind a shared proxy',
    () async {
      final handler = createServerHandler(
        syncAuthenticator: StaticSyncAuthenticator.fromJson(
          jsonEncode({
            'alice': ['alice-phone', 'alice-desktop'],
            'bob': 'bob-phone',
          }),
        ),
        requestRateLimiter: ServerRequestRateLimiter(maximumRequests: 1),
      );
      expect((await handler(_request('alice-phone'))).statusCode, 200);
      expect((await handler(_request('alice-desktop'))).statusCode, 429);
      expect((await handler(_request('bob-phone'))).statusCode, 200);
    },
  );

  test('bounds verification work before calling the authenticator', () async {
    final authenticator = _CountingAuthenticator();
    final handler = createServerHandler(
      syncAuthenticator: authenticator,
      requestRateLimiter: ServerRequestRateLimiter(
        maximumRequests: 10,
        maximumIngressRequests: 2,
      ),
    );
    for (var i = 0; i < 20; i++) {
      await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/health'),
          headers: {'authorization': 'Bearer invalid-$i'},
        ),
      );
    }
    expect(authenticator.calls, 2);
  });

  test(
    'does not evict an exhausted verified identity to admit another',
    () async {
      var now = DateTime.utc(2026, 9, 5);
      final handler = createServerHandler(
        syncAuthenticator: StaticSyncAuthenticator({
          'alice': 'one',
          'bob': 'two',
        }),
        requestRateLimiter: ServerRequestRateLimiter(
          maximumRequests: 1,
          maximumBuckets: 1,
          clock: () => now,
        ),
      );
      expect((await handler(_request('one'))).statusCode, 200);
      expect((await handler(_request('one'))).statusCode, 429);
      expect((await handler(_request('two'))).statusCode, 429);
      expect((await handler(_request('one'))).statusCode, 429);
      now = now.add(const Duration(minutes: 1));
      expect((await handler(_request('two'))).statusCode, 200);
    },
  );

  test('validates the independent ingress environment setting', () {
    expect(
      serverRequestRateLimiterFromEnvironment({
        'AETHERTUNE_RATE_LIMIT_PER_MINUTE': '4',
      }).maximumIngressRequests,
      40,
    );
    expect(
      serverRequestRateLimiterFromEnvironment({
        'AETHERTUNE_INGRESS_RATE_LIMIT_PER_MINUTE': '17',
      }).maximumIngressRequests,
      17,
    );
    for (final invalid in ['0', '-1', 'invalid']) {
      expect(
        () => serverRequestRateLimiterFromEnvironment({
          'AETHERTUNE_INGRESS_RATE_LIMIT_PER_MINUTE': invalid,
        }),
        throwsFormatException,
      );
    }
  });

  test(
    'real HTTP connections cannot rotate tokens or forwarded IP headers',
    () async {
      final server = await shelf_io.serve(
        createServerHandler(
          syncAuthenticator: StaticSyncAuthenticator({'owner': 'valid-token'}),
          requestRateLimiter: ServerRequestRateLimiter(maximumRequests: 2),
        ),
        InternetAddress.loopbackIPv4,
        0,
      );
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      final statuses = <int>[];
      for (var i = 0; i < 4; i++) {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}/api/v1/sync/library'),
        );
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer invalid-$i',
        );
        request.headers.set('x-forwarded-for', '10.0.0.${i + 1}');
        request.headers.set('forwarded', 'for=10.0.1.${i + 1}');
        final response = await request.close();
        statuses.add(response.statusCode);
        await response.drain<void>();
      }
      expect(statuses, [401, 401, 429, 429]);
    },
  );
}

final class _CountingAuthenticator implements SyncAuthenticator {
  int calls = 0;

  @override
  bool get isConfigured => true;

  @override
  String? authenticate(String token) {
    calls++;
    return null;
  }
}
