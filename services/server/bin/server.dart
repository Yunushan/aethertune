import 'dart:convert';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final listenAddress = serverListenAddress(
    Platform.environment['AETHERTUNE_LISTEN_ADDRESS'],
  );
  final dataDirectory = Directory(
    Platform.environment['AETHERTUNE_DATA_DIR'] ??
        '${Directory.current.path}${Platform.pathSeparator}data',
  );
  final syncAuthenticator = StaticSyncAuthenticator.fromJson(
    Platform.environment['AETHERTUNE_SYNC_USERS'],
  );
  final managedSyncAccounts = await ManagedSyncAccountRegistry.open(
    Directory('${dataDirectory.path}${Platform.pathSeparator}authentication'),
    tokenLifetime: managedTokenLifetimeFromEnvironment(Platform.environment),
  );
  final combinedSyncAuthenticator = CompositeSyncAuthenticator(
    <SyncAuthenticator>[syncAuthenticator, managedSyncAccounts],
  );
  final operationsToken = Platform.environment['AETHERTUNE_OPS_TOKEN'];
  if (operationsToken == null || operationsToken.isEmpty) {
    throw const FormatException(
      'AETHERTUNE_OPS_TOKEN is required for server deployments.',
    );
  }
  final operationsAuthenticator = StaticOperationsAuthenticator(
    operationsToken,
  );
  final requestRateLimiter = serverRequestRateLimiterFromEnvironment(
    Platform.environment,
  );
  final server = await shelf_io.serve(
    createServerHandler(
      syncAuthenticator: combinedSyncAuthenticator,
      managedSyncAccounts: managedSyncAccounts,
      operationsAuthenticator: operationsAuthenticator,
      requestRateLimiter: requestRateLimiter,
      syncStore: FileLibrarySyncSnapshotStore(dataDirectory),
      providerConfigurationStore: FileLibrarySyncSnapshotStore(
        Directory(
          '${dataDirectory.path}${Platform.pathSeparator}provider-configurations',
        ),
      ),
      listenTogetherStore: FileLibrarySyncSnapshotStore(
        Directory(
          '${dataDirectory.path}${Platform.pathSeparator}listen-together',
        ),
      ),
      listenTogetherInviteStore: FileListenTogetherInviteStore(
        Directory(
          '${dataDirectory.path}${Platform.pathSeparator}listen-together-invites',
        ),
      ),
      sharedPlaylistStore: FileSharedPlaylistStore(
        Directory(
          '${dataDirectory.path}${Platform.pathSeparator}shared-playlists',
        ),
      ),
      sharedPlaylistInviteStore: FileSharedPlaylistInviteStore(
        Directory(
          '${dataDirectory.path}${Platform.pathSeparator}shared-playlist-invites',
        ),
      ),
      readinessCheck: () => _isDirectoryWritable(dataDirectory),
      requestLogger: (entry) => stdout.writeln(jsonEncode(entry.toJson())),
    ),
    listenAddress,
    port,
  );

  server.autoCompress = true;
  stdout.writeln(
    'AetherTune server listening on http://${server.address.host}:${server.port}',
  );
}

Future<bool> _isDirectoryWritable(Directory directory) async {
  await directory.create(recursive: true);
  final probe = File(
    '${directory.path}${Platform.pathSeparator}.readiness-${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await probe.writeAsString('ready', flush: true);
    return true;
  } finally {
    try {
      await probe.delete();
    } on FileSystemException {
      // A successful write is sufficient evidence for readiness.
    }
  }
}
