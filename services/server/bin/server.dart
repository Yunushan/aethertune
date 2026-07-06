import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await shelf_io.serve(
    createServerHandler(),
    InternetAddress.anyIPv4,
    port,
  );

  server.autoCompress = true;
  stdout.writeln(
    'AetherTune server listening on http://${server.address.host}:${server.port}',
  );
}
