import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune_server/server.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const _playlistId = 'AAAAAAAAAAAAAAAAAAAAAAAA';
const _otherPlaylistId = 'BBBBBBBBBBBBBBBBBBBBBBBB';
const _ownerToken = 'fixture-owner-token';

void main() {
  group('shared-playlist storage failures', () {
    test(
      'existing corrupt active data cannot become missing or be overwritten',
      () async {
        final seedRoot = await _temporaryDirectory();
        final original = (await _write(
          FileSharedPlaylistStore(seedRoot),
        )).record!;
        final corruptions = <String>[
          'broken private playlist data',
          '[]',
          jsonEncode(<String, Object?>{
            ...original.toStorageJson(),
            'checksum': 'bad',
          }),
          jsonEncode(<String, Object?>{
            ...original.toStorageJson(),
            'id': _otherPlaylistId,
          }),
        ];
        for (final corruption in corruptions) {
          final root = await _temporaryDirectory();
          final store = FileSharedPlaylistStore(root);
          await _write(store);
          final file = _playlistFile(root);
          await file.writeAsString(corruption, flush: true);

          await expectLater(
            store.read(_playlistId),
            throwsA(isA<SharedPlaylistStorageException>()),
          );
          await expectLater(
            _write(store),
            throwsA(isA<SharedPlaylistStorageException>()),
          );
          await expectLater(
            store.delete(playlistId: _playlistId, baseRevision: 1),
            throwsA(isA<SharedPlaylistStorageException>()),
          );
          final handler = _handler(store);
          for (final method in <String>['GET', 'PUT', 'DELETE']) {
            await _expectStorageUnavailable(
              handler(
                _request(method, '/api/v1/shared-playlists/$_playlistId'),
              ),
            );
          }
          expect(await file.readAsString(), corruption);
        }
      },
    );

    test('unreadable active path cannot become a missing playlist', () async {
      final root = await _temporaryDirectory();
      await Directory(_playlistFile(root).path).create();
      final store = FileSharedPlaylistStore(root);

      await expectLater(
        store.read(_playlistId),
        throwsA(isA<SharedPlaylistStorageException>()),
      );
      await expectLater(
        _write(store),
        throwsA(isA<SharedPlaylistStorageException>()),
      );
      await _expectStorageUnavailable(
        _handler(store)(
          _request('GET', '/api/v1/shared-playlists/$_playlistId'),
        ),
      );
      expect(await Directory(_playlistFile(root).path).exists(), isTrue);
    });

    test(
      'missing active data retains normal creation and not-found behavior',
      () async {
        final root = await _temporaryDirectory();
        final store = FileSharedPlaylistStore(root);
        expect(await store.read(_playlistId), isNull);
        expect(
          (await _handler(store)(
            _request('GET', '/api/v1/shared-playlists/$_playlistId'),
          )).statusCode,
          404,
        );

        final created = await _write(store);
        expect(created.isConflict, isFalse);
        expect((await store.read(_playlistId))?.revision, 1);
      },
    );

    test(
      'failed invite deletion cannot report successful revocation',
      () async {
        final root = await _temporaryDirectory();
        final store = FileSharedPlaylistInviteStore(root);
        final code = await store.issue(
          playlistId: _playlistId,
          role: SharedPlaylistRole.editor,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        );
        final file = _inviteFile(root, code);
        final playlists = MemorySharedPlaylistStore();
        await _write(playlists);
        final blocked = await _blockDeletion(root, file);
        if (blocked == null) return;
        try {
          await expectLater(
            store.invalidateForPlaylist(_playlistId),
            throwsA(isA<SharedPlaylistStorageException>()),
          );
          await _expectStorageUnavailable(
            _handler(playlists, invites: store)(
              _request(
                'DELETE',
                '/api/v1/shared-playlists/$_playlistId/invites',
              ),
            ),
          );
          expect(await file.exists(), isTrue);
          expect((await store.lookup(code))?.playlistId, _playlistId);
        } finally {
          await blocked();
        }
        expect(await store.invalidateForPlaylist(_playlistId), 1);
        expect(await store.lookup(code), isNull);
      },
    );

    test(
      'concurrent invite disappearance remains a safe revocation race',
      () async {
        final root = await _temporaryDirectory();
        final original = FileSharedPlaylistInviteStore(root);
        final code = await original.issue(
          playlistId: _playlistId,
          role: SharedPlaylistRole.editor,
          expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
        );
        final raced = FileSharedPlaylistInviteStore(
          _ListedDirectory(
            root,
            _RemovedBeforeDeleteFile(_inviteFile(root, code)),
          ),
        );

        expect(await raced.invalidateForPlaylist(_playlistId), 0);
        expect(await original.lookup(code), isNull);
      },
    );

    test(
      'unreadable invitation aborts revocation instead of being skipped',
      () async {
        final root = await _temporaryDirectory();
        final unreadable = Directory(
          '${root.path}${Platform.pathSeparator}unreadable.json',
        );
        await unreadable.create();
        final store = FileSharedPlaylistInviteStore(
          _ListedDirectory(root, File(unreadable.path)),
        );

        await expectLater(
          store.invalidateForPlaylist(_playlistId),
          throwsA(isA<SharedPlaylistStorageException>()),
        );
        expect(await unreadable.exists(), isTrue);
      },
    );

    test('missing invitation directories retain safe empty behavior', () async {
      final root = await _temporaryDirectory();
      final missing = Directory('${root.path}${Platform.pathSeparator}missing');
      final store = FileSharedPlaylistInviteStore(missing);

      expect(await store.invalidateForPlaylist(_playlistId), 0);
      expect(await store.lookup('CCCCCCCCCCCCCCCCCCCCCCCC'), isNull);
    });

    test('inaccessible invitation directory is a storage failure', () async {
      final root = await _temporaryDirectory();
      final blocked = File(
        '${root.path}${Platform.pathSeparator}not-a-directory',
      );
      await blocked.writeAsString('fixture');
      final store = FileSharedPlaylistInviteStore(Directory(blocked.path));

      await expectLater(
        store.invalidateForPlaylist(_playlistId),
        throwsA(isA<SharedPlaylistStorageException>()),
      );
      expect(await blocked.readAsString(), 'fixture');
    });
  });
}

Future<Directory> _temporaryDirectory() async {
  final root = await Directory.systemTemp.createTemp(
    'aethertune-shared-storage-',
  );
  addTearDown(() => root.delete(recursive: true));
  return root;
}

File _playlistFile(Directory root) {
  final digest = sha256.convert(utf8.encode(_playlistId));
  return File('${root.path}${Platform.pathSeparator}$digest.json');
}

File _inviteFile(Directory root, String code) {
  final digest = sha256.convert(utf8.encode(code));
  return File('${root.path}${Platform.pathSeparator}$digest.json');
}

Future<SharedPlaylistWriteResult> _write(SharedPlaylistStore store) {
  return store.write(
    playlistId: _playlistId,
    ownerId: 'fixture-owner',
    baseRevision: 0,
    deviceId: 'fixture-device',
    document: <String, Object?>{
      'version': 1,
      'name': 'Original playlist',
      'trackIds': <String>['fixture-track'],
    },
    collaborators: const <String, SharedPlaylistRole>{},
    publicShareSecretHash: null,
    updatedAt: DateTime.utc(2026, 9, 30),
  );
}

Handler _handler(
  SharedPlaylistStore playlists, {
  SharedPlaylistInviteStore? invites,
}) {
  return createServerHandler(
    syncAuthenticator: StaticSyncAuthenticator(const <String, String>{
      'fixture-owner': _ownerToken,
    }),
    sharedPlaylistStore: playlists,
    sharedPlaylistInviteStore: invites,
  );
}

Request _request(String method, String path) {
  return Request(
    method,
    Uri.parse('http://localhost$path'),
    headers: <String, String>{'authorization': 'Bearer $_ownerToken'},
  );
}

Future<void> _expectStorageUnavailable(FutureOr<Response> result) async {
  final response = await result;
  expect(response.statusCode, 503);
  expect(jsonDecode(await response.readAsString()), <String, Object?>{
    'error': 'shared_playlist_storage_unavailable',
  });
}

/// Denies deletion using the host filesystem, while allowing file reads.
Future<Future<void> Function()?> _blockDeletion(
  Directory root,
  File file,
) async {
  if (Platform.isWindows) {
    await _setWindowsReadOnly(file, true);
    return () => _setWindowsReadOnly(file, false);
  }

  final marker = File('${root.path}${Platform.pathSeparator}permission-check');
  await marker.writeAsString('fixture');
  final changed = await Process.run('chmod', <String>['500', root.path]);
  expect(changed.exitCode, 0);
  try {
    await marker.delete();
  } on FileSystemException {
    return () async {
      final restored = await Process.run('chmod', <String>['700', root.path]);
      expect(restored.exitCode, 0);
    };
  }
  await Process.run('chmod', <String>['700', root.path]);
  markTestSkipped('The current POSIX identity bypasses directory permissions.');
  return null;
}

Future<void> _setWindowsReadOnly(File file, bool readOnly) async {
  final changed = await Process.run(
    'powershell',
    <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      readOnly
          ? r'[System.IO.File]::SetAttributes($env:AETHERTUNE_STORAGE_FIXTURE, ([System.IO.File]::GetAttributes($env:AETHERTUNE_STORAGE_FIXTURE) -bor [System.IO.FileAttributes]::ReadOnly))'
          : r'[System.IO.File]::SetAttributes($env:AETHERTUNE_STORAGE_FIXTURE, ([System.IO.File]::GetAttributes($env:AETHERTUNE_STORAGE_FIXTURE) -band (-bnot [System.IO.FileAttributes]::ReadOnly)))',
    ],
    environment: <String, String>{'AETHERTUNE_STORAGE_FIXTURE': file.path},
  );
  expect(changed.exitCode, 0, reason: changed.stderr.toString());
}

// Supplies a deterministic directory listing so a real file can disappear after
// its contents were read, or a listed file can fail its real filesystem read.
class _ListedDirectory implements Directory {
  _ListedDirectory(this.original, this.file);

  final Directory original;
  final File file;

  @override
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) async* {
    yield file;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RemovedBeforeDeleteFile implements File {
  _RemovedBeforeDeleteFile(this.original);

  final File original;

  @override
  String get path => original.path;

  @override
  Future<String> readAsString({Encoding encoding = utf8}) =>
      original.readAsString(encoding: encoding);

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async {
    await original.delete(recursive: recursive);
    // A concurrent operation removed it after validation but before deletion.
    return original.delete(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
