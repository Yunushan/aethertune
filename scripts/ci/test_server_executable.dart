import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart test_server_executable.dart <server-executable>');
    exitCode = 64;
    return;
  }

  final executable = File(arguments.single);
  if (!await executable.exists()) {
    stderr.writeln('Server executable does not exist: ${executable.path}');
    exitCode = 66;
    return;
  }

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
      },
    );
    unawaited(process.stdout.transform(utf8.decoder).forEach(output.write));
    unawaited(process.stderr.transform(utf8.decoder).forEach(output.write));

    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri(scheme: 'http', host: InternetAddress.loopbackIPv4.address, port: port, path: 'health'),
        );
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) {
          stdout.writeln('Server executable passed the health check on port $port.');
          return;
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
