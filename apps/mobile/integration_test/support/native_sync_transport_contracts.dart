import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:aethertune/src/data/library_sync_transport.dart';
import 'package:rhttp/rhttp.dart' as native;

const nativeSyncAcceptanceHeaders = {
  'authorization': 'Bearer synthetic-acceptance-only',
};

Future<List<Map<String, Object?>>> runNativeSyncTransportContracts({
  required String certificateDirectory,
  required String evidenceDirectory,
}) async {
  final checks = await _certificates(certificateDirectory, evidenceDirectory);
  for (var attempt = 0; attempt < 3; attempt++) {
    checks.add(await _stalledHandshake(attempt));
  }
  checks.add(await _isolates());
  return checks;
}

Future<List<Map<String, Object?>>> _certificates(
  String certificateDirectory,
  String evidenceDirectory,
) async {
  final checks = <Map<String, Object?>>[];
  final context = SecurityContext()
    ..useCertificateChain('$certificateDirectory/trusted-leaf.pem')
    ..usePrivateKey('$certificateDirectory/trusted-leaf.key');
  final untrustedContext = SecurityContext()
    ..useCertificateChain('$certificateDirectory/untrusted-leaf.pem')
    ..usePrivateKey('$certificateDirectory/untrusted-leaf.key');
  final trusted = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  final untrusted = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    untrustedContext,
  );
  var acceptedRequests = 0;
  var authorized = false;
  var correctBody = false;
  var untrustedRequests = 0;
  final subscriptions = [
    trusted.listen((request) async {
      acceptedRequests++;
      authorized =
          request.headers.value('authorization') ==
          nativeSyncAcceptanceHeaders['authorization'];
      correctBody =
          request.method == 'PUT' &&
          await utf8.decoder.bind(request).join() ==
              '{"title":"\u00e7\u0131\u011f"}';
      request.response
        ..statusCode = 302
        ..headers.set('location', '/must-not-follow')
        ..write('{"result":"verified TLS"}');
      try {
        await request.response.close();
      } on Object {
        // Rejected certificate controls never reach this HTTP handler.
      }
    }, onError: (Object _) {}),
    untrusted.listen((request) async {
      untrustedRequests++;
      await request.response.close();
    }, onError: (Object _) {}),
  ];
  try {
    late LibrarySyncHttpResponse response;
    try {
      response = await executeLibrarySyncHttpRequest(
        'PUT',
        Uri.parse('https://127.0.0.1:${trusted.port}/'),
        headers: nativeSyncAcceptanceHeaders,
        body: '{"title":"\u00e7\u0131\u011f"}',
        transferTimeout: const Duration(seconds: 5),
      );
    } on Object {
      await _diagnoseCertificateFixture(
        trusted.port,
        certificateDirectory,
        evidenceDirectory,
      );
      rethrow;
    }
    _require(
      response.statusCode == 302 &&
          response.body == '{"result":"verified TLS"}' &&
          acceptedRequests == 1 &&
          authorized &&
          correctBody,
      'Trusted TLS upload, authorization or redirect contract failed',
    );
    checks.add({
      'name': 'platform-trusted-TLS-UTF8-upload-status-auth-redirect',
      'passed': true,
    });
    for (final control in [
      ('untrusted-root', 'https://127.0.0.1:${untrusted.port}/'),
      ('wrong-hostname', 'https://localhost:${trusted.port}/'),
    ]) {
      Object? failure;
      try {
        await executeLibrarySyncHttpRequest(
          'GET',
          Uri.parse(control.$2),
          headers: nativeSyncAcceptanceHeaders,
          transferTimeout: const Duration(seconds: 5),
        );
      } on Object catch (error) {
        failure = error;
      }
      _require(
        failure is HandshakeException &&
            !failure.toString().contains(control.$2) &&
            !failure.toString().contains('synthetic-acceptance-only'),
        '${control.$1} did not produce a sanitized certificate rejection',
      );
      checks.add({'name': control.$1, 'passed': true});
    }
    _require(
      acceptedRequests == 1 && untrustedRequests == 0,
      'Rejected certificate request reached HTTP application handler',
    );
    checks.add({
      'name': 'rejected-TLS-sends-no-HTTP-credentials',
      'passed': true,
    });
    return checks;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    await trusted.close(force: true);
    await untrusted.close(force: true);
  }
}

Future<void> _diagnoseCertificateFixture(
  int port,
  String certificateDirectory,
  String evidenceDirectory,
) async {
  // These extra controls only diagnose a failed synthetic fixture. They cannot
  // turn the production-executor assertion into a pass or change its trust.
  final diagnostics = <String, Object?>{};
  final ca = await File('$certificateDirectory/trusted-ca.pem').readAsString();
  for (final control in ['platform', 'explicit-fixture-root']) {
    final client = await native.RhttpClient.create(
      settings: native.ClientSettings(
        proxySettings: const native.ProxySettings.noProxy(),
        redirectSettings: const native.RedirectSettings.none(),
        tlsSettings: native.TlsSettings(
          rootCertSource: control == 'platform'
              ? native.RootCertSource.platform
              : native.RootCertSource.none,
          trustedRootCertificates: control == 'platform' ? const [] : [ca],
        ),
        timeoutSettings: const native.TimeoutSettings(
          timeout: Duration(seconds: 5),
        ),
      ),
    );
    try {
      final response = await client.getStream('https://127.0.0.1:$port/');
      await response.body.drain<void>();
      diagnostics[control] = {'statusCode': response.statusCode};
    } on Object catch (error) {
      diagnostics[control] = {'error': error.toString()};
    } finally {
      await client.cancelRunningRequests();
      client.dispose();
    }
  }
  await File('$evidenceDirectory/certificate-diagnostics.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(diagnostics),
    flush: true,
  );
}

Future<Map<String, Object?>> _stalledHandshake(int attempt) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = Completer<void>();
  final disconnected = Completer<void>();
  final sockets = <Socket>[];
  final subscription = server.listen((socket) {
    sockets.add(socket);
    if (!accepted.isCompleted) accepted.complete();
    void closed() {
      if (!disconnected.isCompleted) disconnected.complete();
    }

    unawaited(socket.done.then<void>((_) {}, onError: (Object _) => closed()));
    socket.listen((_) {}, onDone: closed, onError: (Object _) => closed());
  });
  final watch = Stopwatch()..start();
  Object? failure;
  try {
    try {
      await executeLibrarySyncHttpRequest(
        'GET',
        Uri.parse('https://127.0.0.1:${server.port}/'),
        headers: nativeSyncAcceptanceHeaders,
        transferTimeout: const Duration(milliseconds: 300),
      );
    } on Object catch (error) {
      failure = error;
    }
    final callerMs = watch.elapsedMilliseconds;
    _require(accepted.isCompleted, 'TLS negative control never connected');
    _require(failure is TimeoutException, 'TLS stall did not time out');
    await disconnected.future.timeout(const Duration(seconds: 2));
    return {
      'name': 'stalled-TLS-cleanup-$attempt',
      'passed': true,
      'callerMs': callerMs,
      'peerDisconnectedMs': watch.elapsedMilliseconds,
    };
  } finally {
    for (final socket in sockets) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
  }
}

Future<Map<String, Object?>> _isolates() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  final subscription = server.listen((request) async {
    requests++;
    request.response.write('{"isolate":"verified"}');
    await request.response.close();
  });
  final url = 'http://127.0.0.1:${server.port}/';
  try {
    final results = await Future.wait(
      List.generate(3, (_) => Isolate.run(() => _isolateRequest(url))),
    ).timeout(const Duration(seconds: 10));
    _require(
      requests == 3 && results.every((passed) => passed),
      'Independent isolate initialization or request cleanup failed',
    );
    return {'name': 'three-independent-isolate-roundtrips', 'passed': true};
  } finally {
    await subscription.cancel();
    await server.close(force: true);
  }
}

Future<bool> _isolateRequest(String url) async {
  final response = await executeLibrarySyncHttpRequest(
    'GET',
    Uri.parse(url),
    headers: nativeSyncAcceptanceHeaders,
    transferTimeout: const Duration(seconds: 5),
  );
  return response.statusCode == 200 &&
      response.body == '{"isolate":"verified"}';
}

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}
