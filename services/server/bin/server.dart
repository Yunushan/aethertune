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
    Directory(
      '${dataDirectory.path}${Platform.pathSeparator}authentication',
    ),
    tokenLifetime: managedTokenLifetimeFromEnvironment(Platform.environment),
  );
  final combinedSyncAuthenticator = CompositeSyncAuthenticator(
    <SyncAuthenticator>[syncAuthenticator, managedSyncAccounts],
  );
  final operationsToken = Platform.environment['AETHERTUNE_OPS_TOKEN'];
  final operationsAuthenticator =
      operationsToken == null || operationsToken.isEmpty
          ? const DisabledOperationsAuthenticator()
          : StaticOperationsAuthenticator(operationsToken);
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
