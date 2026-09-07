import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rhttp/rhttp.dart' show Rhttp;
import 'package:rhttp/src/rust/api/client.dart' as rust_client;
import 'package:rhttp/src/rust/api/http.dart' as rust;

void main() {
  setUpAll(Rhttp.init);
  for (final stage in ['response', 'error']) {
    test('native cancellation finishes an in-flight $stage callback', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.contentLength = stage == 'error' ? 2048 : 2;
        request.response.add(
          List<int>.filled(request.response.contentLength, 32),
        );
        await request.response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await subscription.cancel();
      });
      final client = await rust.registerClient(
        settings: const rust_client.ClientSettings(
          httpVersionPref: rust.HttpVersionPref.http11,
          throwOnStatusCode: false,
          proxySettings: rust_client.ProxySettings.noProxy(),
          maxStreamResponseBytes: 1024,
        ),
      );
      addTearDown(client.dispose);
      Future<void> Function()? cancel;
      final callbackDone = Completer<void>();
      var callbackStarted = false;
      var callbackFinished = false;
      var errorCallbacks = 0;
      Future<void> finishCallback() async {
        if (callbackStarted) return;
        callbackStarted = true;
        try {
          await cancel!();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          callbackFinished = true;
        } finally {
          callbackDone.complete();
        }
      }

      final stream = rust.makeHttpRequestReceiveStream(
        client: client,
        method: const rust.HttpMethod(method: 'GET'),
        url: 'http://127.0.0.1:${server.port}/',
        onCancelToken: (token) =>
            cancel = () => rust.cancelRequest(token: token),
        cancelable: true,
        onResponse: (_) => stage == 'response' ? finishCallback() : null,
        onError: (_) async {
          errorCallbacks++;
          if (stage == 'error') await finishCallback();
        },
      );
      final done = Completer<void>();
      final streamErrors = <Object>[];
      stream.listen((_) {}, onError: streamErrors.add, onDone: done.complete);
      addTearDown(
        () => callbackDone.future.timeout(const Duration(seconds: 2)),
      );
      await done.future.timeout(const Duration(seconds: 2));
      expect(
        callbackFinished,
        isTrue,
        reason:
            'The native task must not drop a callback that is returning to Rust.',
      );
      expect(errorCallbacks, stage == 'error' ? 1 : 0);
      if (stage == 'response') {
        expect(streamErrors, hasLength(1));
        expect(streamErrors.single.toString(), contains('STREAM_CANCEL_ERROR'));
      } else {
        expect(streamErrors, isEmpty);
      }
    });
  }
}
