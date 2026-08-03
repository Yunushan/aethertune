import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'Usage: dart test_server_executable.dart <server-executable>',
    );
    exitCode = 64;
    return;
  }

  final executable = File(arguments.single);
  if (!await executable.exists()) {
    stderr.writeln('Server executable does not exist: ${executable.path}');
    exitCode = 66;
    return;
  }

  await _assertMissingOperationsTokenRejected(executable);

  final reservation = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = reservation.port;
  await reservation.close();
  final dataDirectory = await Directory.systemTemp.createTemp(
    'aethertune-server-smoke-',
  );
  Process? process;
  final output = StringBuffer();

  try {
    process = await Process.start(
      executable.path,
      const <String>[],
      environment: <String, String>{
        ...Platform.environment,
        'AETHERTUNE_DATA_DIR': dataDirectory.path,
        'AETHERTUNE_LISTEN_ADDRESS': InternetAddress.loopbackIPv4.address,
        'PORT': '$port',
        'AETHERTUNE_OPS_TOKEN': 'ci-only-executable-metrics-token',
      },
    );
    unawaited(process.stdout.transform(utf8.decoder).forEach(output.write));
    unawaited(process.stderr.transform(utf8.decoder).forEach(output.write));

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri(
            scheme: 'http',
            host: InternetAddress.loopbackIPv4.address,
            port: port,
            path: 'health',
          ),
        );
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) {
          final readyRequest = await client.getUrl(
            Uri(
              scheme: 'http',
              host: InternetAddress.loopbackIPv4.address,
              port: port,
              path: 'ready',
            ),
          );
          final readyResponse = await readyRequest.close();
          await readyResponse.drain<void>();
          if (readyResponse.statusCode == HttpStatus.ok) {
            final unauthorizedMetricsRequest = await client.getUrl(
              Uri(
                scheme: 'http',
                host: InternetAddress.loopbackIPv4.address,
                port: port,
                path: 'api/v1/metrics',
              ),
            );
            final unauthorizedMetricsResponse =
                await unauthorizedMetricsRequest.close();
            await unauthorizedMetricsResponse.drain<void>();
            if (unauthorizedMetricsResponse.statusCode !=
                HttpStatus.unauthorized) {
              throw StateError(
                'Metrics endpoint accepted an unauthenticated request: '
                '${unauthorizedMetricsResponse.statusCode}',
              );
            }

            final metricsRequest = await client.getUrl(
              Uri(
                scheme: 'http',
                host: InternetAddress.loopbackIPv4.address,
                port: port,
                path: 'api/v1/metrics',
              ),
            );
            metricsRequest.headers.set(
              HttpHeaders.authorizationHeader,
              'Bearer ci-only-executable-metrics-token',
            );
            final metricsResponse = await metricsRequest.close();
            final metricsBody = await metricsResponse
                .transform(utf8.decoder)
                .join();
            if (metricsResponse.statusCode != HttpStatus.ok) {
              throw StateError(
                'Metrics endpoint returned ${metricsResponse.statusCode}: '
                '$metricsBody',
              );
            }
            final metrics = jsonDecode(metricsBody);
            if (metrics is! Map<String, dynamic> ||
                metrics['requestsTotal'] is! int ||
                metrics['responses2xx'] is! int ||
                metrics['responses4xx'] is! int ||
                metrics['responses5xx'] is! int ||
                metrics['requestDurationMillisecondsTotal'] is! int) {
              throw StateError(
                'Metrics endpoint returned an invalid aggregate payload.',
              );
            }
            final loadFailures = <String>[];
            await Future.wait(
              List<Future<void>>.generate(30, (_) async {
                final loadClient = HttpClient();
                try {
                  for (final path in const <String>[
                    'health',
                    'ready',
                    'api/v1/info',
                  ]) {
                    final loadRequest = await loadClient.getUrl(
                      Uri(
                        scheme: 'http',
                        host: InternetAddress.loopbackIPv4.address,
                        port: port,
                        path: path,
                      ),
                    );
                    final loadResponse = await loadRequest.close();
                    await loadResponse.drain<void>();
                    if (loadResponse.statusCode != HttpStatus.ok) {
                      loadFailures.add(
                        '$path returned ${loadResponse.statusCode}',
                      );
                    }
                  }
                } on Object catch (error) {
                  loadFailures.add('request failed: $error');
                } finally {
                  loadClient.close(force: true);
                }
              }),
            );
            if (loadFailures.isNotEmpty) {
              throw StateError(
                'Server load probes failed: ${loadFailures.join('; ')}',
              );
            }
            stdout.writeln(
              'Server executable passed health, readiness, metrics, and 90 concurrent load probes on port $port.',
            );
            return;
          }
        }
      } on SocketException {
        // The process may still be binding its loopback socket.
      } finally {
        client.close(force: true);
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    throw StateError(
      'Server executable did not pass its health check within 15 seconds.\n$output',
    );
  } finally {
    if (process != null) {
      process.kill();
      await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
    await dataDirectory.delete(recursive: true);
  }
}

Future<void> _assertMissingOperationsTokenRejected(File executable) async {
  final dataDirectory = await Directory.systemTemp.createTemp(
    'aethertune-server-missing-ops-token-',
  );
  try {
    final result = await Process.run(
      executable.path,
      const <String>[],
      environment: <String, String>{
        ...Platform.environment,
        'AETHERTUNE_DATA_DIR': dataDirectory.path,
        'AETHERTUNE_LISTEN_ADDRESS': InternetAddress.loopbackIPv4.address,
        'AETHERTUNE_OPS_TOKEN': '',
        'AETHERTUNE_SYNC_USERS': '{}',
        'PORT': '0',
      },
    );
    final output = '${result.stdout}\n${result.stderr}';
    if (result.exitCode == 0 ||
        !output.contains('AETHERTUNE_OPS_TOKEN is required')) {
      throw StateError(
        'Server executable did not reject a missing operations token.\n$output',
      );
    }
  } finally {
    await dataDirectory.delete(recursive: true);
  }
}
