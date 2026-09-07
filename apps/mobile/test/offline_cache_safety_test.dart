import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/offline_cache_manager.dart';
import 'package:aethertune/src/data/offline_cache_pressure_enforcer.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

OfflineCacheEntry _entry({
  String id = 'safe-entry',
  String url = 'https://example.invalid/song.mp3',
  String? checksum,
}) => OfflineCacheEntry(
  id: id,
  track: Track(
    id: 'track',
    title: 'Track',
    sourceId: 'podcast',
    streamUrl: url,
    expectedMediaChecksum: checksum,
  ),
  action: OfflineMediaAction.cache,
  createdAt: DateTime.utc(2026, 9, 5),
);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('aethertune-cache-safety-');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() async => root.delete(recursive: true));

  for (final id in [
    '',
    '../sentinel',
    r'..\sentinel',
    '/tmp/sentinel',
    r'C:\sentinel',
    r'\\server\share',
    'safe/../../sentinel',
    'entry:stream',
    '.',
    '..',
    'safe\n',
    'safe\u0000',
  ]) {
    test('rejects unsafe cache ID ${jsonEncode(id)} before I/O', () async {
      var downloaded = false;
      final manager = OfflineCacheManager(
        cacheRoot: root,
        downloader: (_) async {
          downloaded = true;
          return [1];
        },
      );
      final sentinel = File(p.join(root.path, 'sentinel.mp3'));
      await sentinel.writeAsString('original');
      expect(
        () => OfflineCacheEntry.fromJson(_entry(id: id).toJson()),
        throwsFormatException,
      );
      await expectLater(
        manager.materialize(_entry(id: id)),
        throwsFormatException,
      );
      expect(downloaded, isFalse);
      expect(await sentinel.readAsString(), 'original');
      expect(await manager.mediaDirectory.exists(), isFalse);
    });
  }

  test('rejects crafted backup without changing the current library', () async {
    final library = LibraryStore(clock: () => DateTime.utc(2026, 9, 5));
    addTearDown(library.dispose);
    await library.load();
    await library.addTracks([Track(id: 'existing', title: 'Existing')]);
    final before = library.exportBackupJson();
    final document = jsonDecode(before) as Map<String, dynamic>;
    document['offlineCacheQueue'] = [_entry(id: '../sentinel').toJson()];
    await expectLater(
      library.restoreBackupJson(jsonEncode(document)),
      throwsFormatException,
    );
    expect(library.exportBackupJson(), before);
  });

  for (final id in ['CON', 'NUL', 'COM1', 'a' * 2000]) {
    test(
      'uses a portable bounded filename for ${id.substring(0, 3)}',
      () async {
        final manager = OfflineCacheManager(
          cacheRoot: root,
          downloader: (_) async => [1, 2, 3],
        );
        final result = await manager.materialize(_entry(id: id));
        expect(p.basename(result.track.localPath!).length, lessThan(100));
        expect(await File(result.track.localPath!).readAsBytes(), [1, 2, 3]);
      },
    );
  }

  for (final name in ['safe-entry.mp3', 'safe-entry.mp3.part']) {
    test('rejects a linked $name and preserves its target', () async {
      final manager = OfflineCacheManager(
        cacheRoot: root,
        downloader: (_) async => [9, 9],
      );
      await manager.mediaDirectory.create(recursive: true);
      final sentinel = File(p.join(root.path, 'sentinel'));
      await sentinel.writeAsString('original');
      final link = Link(p.join(manager.mediaDirectory.path, name));
      if (!await _createLink(link, sentinel.path)) return;
      await expectLater(manager.materialize(_entry()), throwsStateError);
      expect(await sentinel.readAsString(), 'original');
      final cached = _entry().copyWith(
        status: OfflineCacheEntryStatus.cached,
        track: _entry().track.copyWith(localPath: link.path),
      );
      expect((await manager.usage([cached])).byteCount, 0);
      expect(
        (await manager.evictToSize(
          entries: [cached],
          maxBytes: 0,
        )).evictedEntryIds,
        isEmpty,
      );
      await expectLater(
        manager.verifyCachedMedia(entry: cached),
        throwsStateError,
      );
      expect(await sentinel.readAsString(), 'original');
    });
  }

  for (final linkedDirectory in ['aethertune', 'offline_media']) {
    test('rejects linked cache directory $linkedDirectory', () async {
      final manager = OfflineCacheManager(
        cacheRoot: root,
        downloader: (_) async => [9],
      );
      final outside = await Directory(p.join(root.path, 'outside')).create();
      final sentinel = File(p.join(outside.path, 'safe-entry.mp3'));
      await sentinel.writeAsString('original');
      final parent = linkedDirectory == 'aethertune'
          ? root
          : await Directory(p.join(root.path, 'aethertune')).create();
      if (!await _createLink(
        Link(p.join(parent.path, linkedDirectory)),
        outside.path,
      )) {
        return;
      }
      await expectLater(manager.materialize(_entry()), throwsStateError);
      expect(await sentinel.readAsString(), 'original');
    });
  }

  test('preserves existing media when replacement checksum fails', () async {
    final manager = OfflineCacheManager(
      cacheRoot: root,
      downloader: (_) async => [9, 9],
    );
    await manager.mediaDirectory.create(recursive: true);
    final original = File(
      p.join(manager.mediaDirectory.path, 'safe-entry.mp3'),
    );
    await original.writeAsBytes([1, 2, 3]);
    await expectLater(
      manager.materialize(_entry(checksum: 'sha256:${'0' * 64}')),
      throwsStateError,
    );
    expect(await original.readAsBytes(), [1, 2, 3]);
    expect(await File('${original.path}.part').exists(), isFalse);
  });

  for (final (name, algorithm) in [
    ('md5', md5),
    ('sha1', sha1),
    ('sha256', sha256),
  ]) {
    test('streams $name verification over multiple file chunks', () async {
      final bytes = List<int>.generate(200000, (i) => i % 256);
      final manager = OfflineCacheManager(
        cacheRoot: root,
        downloader: (_) async => bytes,
      );
      final result = await manager.materialize(
        _entry(checksum: '$name:${algorithm.convert(bytes)}'),
      );
      expect(result.byteCount, bytes.length);
      expect(result.expectedMediaChecksumVerified, isTrue);
      expect(result.checksum, offlineMediaChecksum(bytes));
      final exported = await manager.exportCachedMedia(
        entry: _entry().copyWith(
          track: result.track,
          status: OfflineCacheEntryStatus.cached,
          cachedByteCount: result.byteCount,
          cachedMediaChecksum: result.checksum,
        ),
        destinationDirectory: Directory(p.join(root.path, 'export')),
      );
      expect(await exported.file.readAsBytes(), bytes);
    });
  }

  test('enforces injected transfer size before writing', () async {
    final manager = OfflineCacheManager(
      cacheRoot: root,
      downloader: (_) async => [1, 2, 3, 4],
    );
    await expectLater(
      manager.materialize(_entry(), maxBytes: 3),
      throwsA(isA<OfflineMediaSizeLimitExceeded>()),
    );
    expect(await manager.mediaDirectory.list().toList(), isEmpty);
  });

  test('uses the smaller app or provider transfer budget', () async {
    final library = LibraryStore();
    addTearDown(library.dispose);
    await library.load();
    final appLimit = library.offlineCacheLimitBytes;
    expect(offlineCacheTransferLimitBytes(library, 'podcast'), appLimit);
    await library.setOfflineCacheProviderLimitMegabytes('podcast', 100);
    expect(
      offlineCacheTransferLimitBytes(library, 'podcast'),
      100 * 1024 * 1024,
    );
    await library.setOfflineCacheProviderLimitMegabytes('podcast', 1000);
    expect(offlineCacheTransferLimitBytes(library, 'podcast'), appLimit);
  });

  for (final declaredLength in [true, false]) {
    test('bounds HTTP bytes with declared length $declaredLength', () async {
      final server = await _server((request) async {
        if (declaredLength) request.response.contentLength = 20;
        request.response.add(List.filled(20, 1));
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final manager = OfflineCacheManager(cacheRoot: root);
      await expectLater(
        manager.materialize(
          _entry(url: 'http://127.0.0.1:${server.port}/song.mp3'),
          maxBytes: 10,
        ),
        throwsA(isA<OfflineMediaSizeLimitExceeded>()),
      );
      expect(await manager.mediaDirectory.list().toList(), isEmpty);
    });
  }

  test('does not append a response with an incorrect Content-Range', () async {
    final server = await _server((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=2-');
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes 0-1/2',
      );
      request.response.add([9, 9]);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final manager = OfflineCacheManager(cacheRoot: root);
    await manager.mediaDirectory.create(recursive: true);
    final partial = File(
      p.join(manager.mediaDirectory.path, 'safe-entry.mp3.part'),
    );
    await partial.writeAsBytes([1, 2]);
    await expectLater(
      manager.materialize(
        _entry(
          url: 'http://127.0.0.1:${server.port}/song.mp3',
          checksum: 'sha256:${sha256.convert([1, 2, 3, 4])}',
        ),
      ),
      throwsA(isA<HttpException>()),
    );
    expect(await partial.readAsBytes(), [1, 2]);
  });

  for (final stage in ['headers', 'idle', 'total']) {
    test('times out a stalled $stage transfer', () async {
      final server = await _server((request) async {
        if (stage == 'headers') {
          await Future<void>.delayed(const Duration(seconds: 1));
        } else {
          request.response.add([1]);
          await request.response.flush();
          if (stage == 'idle') {
            await Future<void>.delayed(const Duration(seconds: 1));
          } else {
            for (var i = 0; i < 50; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 20));
              request.response.add([1]);
              await request.response.flush();
            }
          }
        }
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final manager = OfflineCacheManager(
        cacheRoot: root,
        requestTimeout: Duration(milliseconds: stage == 'headers' ? 100 : 2000),
        idleTimeout: Duration(milliseconds: stage == 'idle' ? 100 : 2000),
        transferTimeout: Duration(milliseconds: stage == 'total' ? 200 : 3000),
      );
      await expectLater(
        manager.materialize(
          _entry(url: 'http://127.0.0.1:${server.port}/song.mp3'),
        ),
        throwsA(isA<TimeoutException>()),
      );
      expect(
        await File(
          p.join(manager.mediaDirectory.path, 'safe-entry.mp3'),
        ).exists(),
        isFalse,
      );
    });
  }
}

Future<HttpServer> _server(Future<void> Function(HttpRequest) handle) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handle(request);
    } on IOException {
      // Clients intentionally disconnect when a transfer bound is exceeded.
    }
  });
  return server;
}

Future<bool> _createLink(Link link, String target) async {
  try {
    await link.create(target);
    return true;
  } on FileSystemException {
    if (!Platform.isWindows) rethrow;
    markTestSkipped('Windows symlink creation requires Developer Mode.');
    return false;
  }
}
