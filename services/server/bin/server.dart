import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final port = serverPort(Platform.environment['PORT']);
  final listenAddress = serverListenAddress(
    Platform.environment['AETHERTUNE_LISTEN_ADDRESS'],
  );
  final dataDirectory = Directory(
    Platform.environment['AETHERTUNE_DATA_DIR'] ??
        '${Directory.current.path}${Platform.pathSeparator}data',
  );
  final dataDirectoryLock = await _acquireDataDirectoryLock(dataDirectory);
  if (dataDirectoryLock == null) {
    stderr.writeln(
      'Another AetherTune server instance appears to be using the same '
      'data directory (${dataDirectory.path}). Refusing to start to avoid '
      'concurrent writes.',
    );
    exitCode = 1;
    return;
  }
  try {
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
    var draining = false;
    final server = await shelf_io.serve(
      dataDirectoryLock.middleware(
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
          readinessCheck: () => draining
              ? Future.value(false)
              : _isDirectoryWritable(dataDirectory),
          requestLogger: (entry) => stdout.writeln(jsonEncode(entry.toJson())),
        ),
      ),
      listenAddress,
      port,
    );

    server.autoCompress = true;
    server.idleTimeout = serverIdleTimeout;
    await dataDirectoryLock.initializationComplete();
    stdout.writeln(
      'AetherTune server listening on http://${server.address.host}:${server.port}',
    );
    await _shutdownWhenSignaled(server, onDraining: () => draining = true);
  } finally {
    await dataDirectoryLock.close();
  }
}

const _shutdownDrainTimeout = Duration(seconds: 25);

Future<void> _shutdownWhenSignaled(
  HttpServer server, {
  required void Function() onDraining,
}) async {
  final signaled = Completer<void>();
  final subscriptions = <StreamSubscription<void>>[];
  for (final signal in <ProcessSignal>[
    ProcessSignal.sigint,
    ProcessSignal.sigterm,
  ]) {
    try {
      subscriptions.add(
        signal.watch().listen(
          (_) {
            onDraining();
            if (!signaled.isCompleted) signaled.complete();
          },
          onError: (Object _) {
            // The signal cannot be delivered on this platform (e.g. SIGTERM
            // on Windows); the remaining supported signal still applies.
          },
          cancelOnError: true,
        ),
      );
    } on Object {
      // Some platforms reject watching a signal synchronously; the
      // remaining supported signal still applies.
    }
  }
  await signaled.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  stdout.writeln(
    'Shutdown signal received; draining in-flight requests for up to '
    '${_shutdownDrainTimeout.inSeconds}s.',
  );
  try {
    await server.close(force: false).timeout(_shutdownDrainTimeout);
  } on TimeoutException {
    stdout.writeln('Drain timed out; closing remaining connections.');
    await server.close(force: true);
  }
  stdout.writeln('AetherTune server stopped.');
}

Future<ServerDataDirectoryGuard?> _acquireDataDirectoryLock(
  Directory dataDirectory,
) async {
  try {
    return await ServerDataDirectoryGuard.open(dataDirectory);
  } on FileSystemException {
    return null;
  }
}

Future<bool> _isDirectoryWritable(Directory directory) async {
  await directory.create(recursive: true);
  final probeId =
      '${DateTime.now().microsecondsSinceEpoch}-$pid-'
      '${_readinessProbeSequence++}';
  final probe = File(
    '${directory.path}${Platform.pathSeparator}.readiness-$probeId.tmp',
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

var _readinessProbeSequence = 0;
