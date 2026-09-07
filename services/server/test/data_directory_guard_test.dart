import 'dart:async';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('aethertune-guard-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test('rejects duplicate ownership and can reopen after close', () async {
    final guard = await ServerDataDirectoryGuard.open(root);
    await expectLater(
      ServerDataDirectoryGuard.open(root),
      throwsA(isA<FileSystemException>()),
    );
    await guard.close();
    await (await ServerDataDirectoryGuard.open(root)).close();
  });

  test(
    'close drains admitted requests and refuses new data requests',
    () async {
      final guard = await ServerDataDirectoryGuard.open(root);
      await guard.initializationComplete();
      final entered = Completer<void>();
      final release = Completer<void>();
      final handler = guard.middleware((request) async {
        if (request.url.path == 'health') return Response.ok('ok');
        entered.complete();
        await release.future;
        return Response.ok('committed');
      });
      final inFlight = handler(
        Request('GET', Uri.parse('http://localhost/data')),
      );
      await entered.future;
      var closed = false;
      final closing = guard.close().then((_) => closed = true);
      final refused = await handler(
        Request('GET', Uri.parse('http://localhost/data')),
      );
      expect(refused.statusCode, 503);
      expect(closed, isFalse);
      expect(
        (await handler(
          Request('GET', Uri.parse('http://localhost/health')),
        )).statusCode,
        200,
      );
      release.complete();
      expect((await inFlight).statusCode, 200);
      await closing;
      await (await ServerDataDirectoryGuard.open(root)).close();
    },
  );

  test('handler failure still releases its snapshot admission', () async {
    final guard = await ServerDataDirectoryGuard.open(root);
    await guard.initializationComplete();
    final handler = guard.middleware((_) => throw StateError('failed write'));
    await expectLater(
      handler(Request('PUT', Uri.parse('http://localhost/data'))),
      throwsStateError,
    );
    await guard.close().timeout(const Duration(seconds: 2));
    await (await ServerDataDirectoryGuard.open(root)).close();
  });
}
