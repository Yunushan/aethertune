import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rhttp/rhttp.dart' as native;

void main() {
  setUpAll(native.Rhttp.init);

  for (final stage in [
    'declared',
    'chunked',
    'compressed',
    'delayed-listener',
    'exact',
    'zero-empty',
    'zero-nonempty',
    'unlimited',
  ]) {
    test('native decoded stream limit: $stage', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final disconnected = Completer<void>();
      final exact = stage == 'exact';
      final limit = stage == 'unlimited'
          ? null
          : stage.startsWith('zero')
          ? 0
          : 1024;
      final payload = List<int>.filled(
        stage == 'zero-empty'
            ? 0
            : exact
            ? 1024
            : 65536,
        32,
      );
      final compressed = stage == 'compressed';
      final wire = compressed ? gzip.encode(payload) : payload;
      final chunked = stage == 'chunked' || stage == 'delayed-listener';
      final serverSubscription = server.listen((socket) {
        sockets.add(socket);
        unawaited(socket.done.then<void>((_) {}, onError: (Object _) {}));
        var sent = false;
        socket.listen(
          (_) {
            if (sent) return;
            sent = true;
            socket.write('HTTP/1.1 200 OK\r\n');
            if (compressed) socket.write('Content-Encoding: gzip\r\n');
            if (chunked) {
              socket.write('Transfer-Encoding: chunked\r\n\r\n');
              socket.write('${wire.length.toRadixString(16)}\r\n');
              socket.add(wire);
              socket.write('\r\n0\r\n\r\n');
            } else {
              socket.write('Content-Length: ${wire.length}\r\n\r\n');
              socket.add(wire);
            }
          },
          onDone: () {
            if (!disconnected.isCompleted) disconnected.complete();
          },
          onError: (Object _) {
            if (!disconnected.isCompleted) disconnected.complete();
          },
        );
      });
      addTearDown(() async {
        for (final socket in sockets) {
          socket.destroy();
        }
        await serverSubscription.cancel();
        await server.close();
      });

      final client = await native.RhttpClient.create(
        settings: native.ClientSettings(
          throwOnStatusCode: false,
          proxySettings: const native.ProxySettings.noProxy(),
          redirectSettings: const native.RedirectSettings.none(),
          timeoutSettings: const native.TimeoutSettings(
            timeout: Duration(seconds: 3),
          ),
          maxStreamResponseBytes: limit,
        ),
      );
      final token = native.CancelToken();
      var received = 0;
      Object? failure;
      try {
        final response = await client.getStream(
          'http://127.0.0.1:${server.port}/',
          cancelToken: token,
        );
        if (stage == 'delayed-listener') {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        final done = Completer<void>();
        response.body.listen(
          (bytes) {
            received += bytes.length;
          },
          onError: (Object error) {
            failure = error;
          },
          onDone: done.complete,
        );
        await done.future.timeout(const Duration(seconds: 3));
      } catch (error) {
        failure = error;
      } finally {
        await token.cancel().timeout(const Duration(seconds: 2));
        client.dispose();
      }
      if (limit == null || payload.length <= limit) {
        expect(failure, isNull);
        expect(received, payload.length);
      } else {
        expect(failure, isA<native.RhttpResponseTooLargeException>());
        expect(received, lessThanOrEqualTo(limit));
      }
      if (compressed) expect(wire.length, lessThan(limit!));
      expect(sockets, hasLength(1));
      await disconnected.future.timeout(const Duration(seconds: 2));
    });
  }

  test('stream limit configuration rejects values outside uint32', () async {
    for (final limit in [-1, 0x100000000]) {
      await expectLater(
        native.RhttpClient.create(
          settings: native.ClientSettings(maxStreamResponseBytes: limit),
        ),
        throwsArgumentError,
      );
    }
  });

  test('copyWith retains, updates and clears the native stream limit', () {
    const settings = native.ClientSettings(maxStreamResponseBytes: 1024);
    expect(settings.copyWith().maxStreamResponseBytes, 1024);
    expect(
      settings.copyWith(maxStreamResponseBytes: 0).maxStreamResponseBytes,
      0,
    );
    expect(
      settings.copyWith(maxStreamResponseBytes: null).maxStreamResponseBytes,
      isNull,
    );
  });
}
