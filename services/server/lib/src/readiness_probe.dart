import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Checks this container's loopback readiness without a shell, proxy, or token.
Future<bool> probeServerReadiness(
  int port, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (port < 1 || port > 65535 || timeout <= Duration.zero) return false;
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..findProxy = (_) => 'DIRECT';
  try {
    return await (() async {
      final request = await client.getUrl(
        Uri(scheme: 'http', host: '127.0.0.1', port: port, path: '/ready'),
      );
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return false;
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 4096) return false;
        bytes.addAll(chunk);
      }
      final body = jsonDecode(utf8.decode(bytes));
      return body is Map<String, dynamic> &&
          body['status'] == 'ready' &&
          body['service'] == 'aethertune-server';
    })().timeout(timeout);
  } on Exception {
    return false;
  } finally {
    client.close(force: true);
  }
}
