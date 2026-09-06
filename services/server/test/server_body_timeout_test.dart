import 'dart:async';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  for (final drip in [false, true]) {
    test(
      'bounds ${drip ? 'dripping' : 'stalled'} request body lifetime',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final timer = drip
            ? Timer.periodic(
                const Duration(milliseconds: 5),
                (_) => body.add([32]),
              )
            : null;
        final handler = createServerHandler(
          syncAuthenticator: StaticSyncAuthenticator({'primary': 'test-token'}),
          bodyReadTimeout: const Duration(milliseconds: 60),
        );
        final watch = Stopwatch()..start();
        try {
          final response = await Future<Response>.value(
            handler(
              Request(
                'PUT',
                Uri.parse('http://localhost/api/v1/sync/library'),
                headers: {'authorization': 'Bearer test-token'},
                body: body.stream,
              ),
            ),
          ).timeout(const Duration(seconds: 2));
          expect(response.statusCode, 408);
          expect(response.headers['connection'], 'close');
          expect(
            await response.readAsString(),
            contains('request_body_timeout'),
          );
          expect(cancelled, isTrue);
          expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
        } finally {
          timer?.cancel();
          await body.close();
        }
      },
    );
  }

  test('rejects invalid deadline configuration', () {
    expect(
      () => createServerHandler(bodyReadTimeout: Duration.zero),
      throwsArgumentError,
    );
  });
}
