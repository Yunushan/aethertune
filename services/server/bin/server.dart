import 'dart:convert';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final dataDirectory = Directory(
    Platform.environment['AETHERTUNE_DATA_DIR'] ??
        '${Directory.current.path}${Platform.pathSeparator}data',
  );
  final syncAuthenticator = StaticSyncAuthenticator.fromJson(
    Platform.environment['AETHERTUNE_SYNC_USERS'],
  );
  final server = await shelf_io.serve(
    createServerHandler(
      syncAuthenticator: syncAuthenticator,
      syncStore: FileLibrarySyncSnapshotStore(dataDirectory),
      requestLogger: (entry) => stdout.writeln(jsonEncode(entry.toJson())),
    ),
    InternetAddress.anyIPv4,
    port,
  );

  server.autoCompress = true;
  stdout.writeln(
    'AetherTune server listening on http://${server.address.host}:${server.port}',
  );
}
