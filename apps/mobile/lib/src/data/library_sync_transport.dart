import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:rhttp/rhttp.dart' as native;

const maxLibrarySyncResponseBytes = 9 * 1024 * 1024;
const _cleanupTimeout = Duration(seconds: 2);

typedef LibrarySyncHttpExecutor =
    Future<LibrarySyncHttpResponse> Function(
      String method,
      Uri uri, {
      required Map<String, String> headers,
      String? body,
    });

class LibrarySyncHttpResponse {
  const LibrarySyncHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

// Lazy and shared per isolate, including failure: a partially initialized FFI
// bridge must not be initialized twice by concurrent requests or retries.
final Future<void> _nativeTransportReady = native.Rhttp.init();

Future<LibrarySyncHttpResponse> executeLibrarySyncHttpRequest(
  String method,
  Uri uri, {
  required Map<String, String> headers,
  String? body,
  Duration requestTimeout = const Duration(seconds: 30),
  Duration idleTimeout = const Duration(seconds: 30),
  Duration transferTimeout = const Duration(minutes: 2),
}) async {
  if (requestTimeout <= Duration.zero ||
      idleTimeout <= Duration.zero ||
      transferTimeout <= Duration.zero) {
    throw ArgumentError('Library sync timeouts must be positive.');
  }
  final result = Completer<LibrarySyncHttpResponse>();
  native.RhttpClient? client;
  StreamSubscription<List<int>>? subscription;
  Completer<void>? streamDone;
  Timer? phaseDeadline;

  void fail(Object error, [StackTrace? stack]) {
    if (!result.isCompleted) {
      result.completeError(_publicTransportError(error), stack);
    }
  }

  void deadline(Duration duration, String message) {
    phaseDeadline?.cancel();
    phaseDeadline = Timer(duration, () => fail(TimeoutException(message)));
  }

  final totalDeadline = Timer(
    transferTimeout,
    () => fail(TimeoutException('Library sync transfer timed out.')),
  );

  Future<void> receive() async {
    await _nativeTransportReady;
    if (result.isCompleted) return;
    final created = await native.RhttpClient.create(
      settings: native.ClientSettings(
        throwOnStatusCode: false,
        cookieSettings: const native.CookieSettings.none(),
        proxySettings: const native.ProxySettings.noProxy(),
        redirectSettings: const native.RedirectSettings.none(),
        // rhttp otherwise selects bundled WebPKI roots, omitting certificates
        // intentionally trusted by the user's operating system.
        tlsSettings: const native.TlsSettings(
          rootCertSource: native.RootCertSource.platform,
        ),
        maxStreamResponseBytes: maxLibrarySyncResponseBytes,
        timeoutSettings: native.TimeoutSettings(
          timeout: transferTimeout,
          connectTimeout: const Duration(seconds: 15),
        ),
      ),
    );
    if (result.isCompleted) {
      created.dispose();
      return;
    }
    client = created;
    deadline(requestTimeout, 'Library sync request timed out.');
    final response = await created.requestStream(
      method: native.HttpMethod(method),
      url: uri.toString(),
      headers: native.HttpHeaders.rawMap(headers),
      body: body == null
          ? null
          : native.HttpBody.bytes(Uint8List.fromList(utf8.encode(body))),
    );
    final bytes = BytesBuilder(copy: false);
    streamDone = Completer<void>();
    if (!result.isCompleted) {
      deadline(idleTimeout, 'Library sync response stopped sending data.');
    }
    // Always observe a late response. Keep this listener attached until native
    // cancellation ends the stream, including errors sent after a Dart deadline.
    subscription = response.body.listen(
      (chunk) {
        if (result.isCompleted) return;
        deadline(idleTimeout, 'Library sync response stopped sending data.');
        if (chunk.length > maxLibrarySyncResponseBytes - bytes.length) {
          fail(const FormatException('Library sync response is too large.'));
          return;
        }
        bytes.add(chunk);
      },
      onError: fail,
      onDone: () {
        streamDone!.complete();
        if (result.isCompleted) return;
        try {
          result.complete(
            LibrarySyncHttpResponse(
              statusCode: response.statusCode,
              body: utf8.decode(bytes.takeBytes()),
            ),
          );
        } on Object catch (error, stack) {
          fail(error, stack);
        }
      },
    );
  }

  final receiving = receive().catchError(fail);
  try {
    return await result.future;
  } finally {
    totalDeadline.cancel();
    phaseDeadline?.cancel();
    final activeClient = client;
    if (activeClient != null) {
      try {
        await (() async {
          await activeClient.cancelRunningRequests();
          await receiving;
          await streamDone?.future;
          await subscription?.cancel();
        })().timeout(_cleanupTimeout);
      } on Object {
        throw TimeoutException(
          'Library sync transport cleanup did not finish.',
        );
      } finally {
        activeClient.dispose();
      }
    }
  }
}

Object _publicTransportError(Object error) => switch (error) {
  native.RhttpTimeoutException() => TimeoutException('Library sync timed out.'),
  native.RhttpResponseTooLargeException() => const FormatException(
    'Library sync response is too large.',
  ),
  native.RhttpInvalidCertificateException() => const HandshakeException(
    'Library sync certificate validation failed.',
  ),
  native.RhttpException() => const HttpException(
    'Library sync request failed.',
  ),
  TimeoutException() || FormatException() || ArgumentError() => error,
  _ => StateError('Library sync transport is unavailable.'),
};
