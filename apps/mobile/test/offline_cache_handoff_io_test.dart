import 'dart:async';
import 'dart:io';

import 'package:aethertune/src/data/library_storage.dart';
import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/offline_cache_background_session.dart';
import 'package:aethertune/src/data/offline_cache_paths.dart';
import 'package:aethertune/src/data/offline_cache_queue_worker.dart';
import 'package:aethertune/src/data/offline_media_integrity.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  _IoTestBinding();
  late Directory root;
  late FileLibraryStorage storage;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('aethertune-cache-handoff-');
    storage = FileLibraryStorage(
      directory: () async => Directory(p.join(root.path, 'library')),
    );
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'native stop reply waits for resolver file writes and saved requeue',
    () async {
      const channel = MethodChannel('aethertune/test-io-stop');
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        channel.setMethodCallHandler(null);
      });
      final library = LibraryStore(storage: storage);
      addTearDown(library.dispose);
      await library.load();
      await _queue(library, 'first');
      await _queue(library, 'second');
      final started = Completer<void>();
      final release = Completer<void>();
      final artwork = File(p.join(root.path, 'provider-artwork.bin'));
      var requests = 0;
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (track) async {
          requests++;
          started.complete();
          await release.future;
          await artwork.writeAsBytes([1, 2, 3, 4], flush: true);
          return track;
        },
      );
      final session = OfflineCacheBackgroundSession(channel: channel);
      final pass = session.run((signal) async {
        signal.cancelCurrentWith(worker.stop);
        await worker.processPending(library);
        await library.requeueProcessingOfflineCacheEntriesForBackground();
      });
      await started.future;
      final stop = Completer<Object?>();
      ServicesBinding.instance.channelBuffers.push(
        channel.name,
        codec.encodeMethodCall(const MethodCall('stop')),
        (bytes) {
          stop.complete(codec.decodeEnvelope(bytes!));
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(stop.isCompleted, isFalse);
      expect(worker.busy, isTrue);
      expect(await artwork.exists(), isFalse);
      release.complete();
      expect(await stop.future.timeout(const Duration(seconds: 3)), isTrue);
      await pass;
      expect(requests, 1);
      expect(await artwork.readAsBytes(), [1, 2, 3, 4]);
      final reopened = LibraryStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(
        reopened.offlineCacheQueue.map((entry) => entry.status),
        everyElement(OfflineCacheEntryStatus.queued),
      );
      expect(reopened.saveError, isNull);
    },
  );

  test(
    'real HTTP transfer drains, resumes with Range, and fences stale state',
    () async {
      final bytes = List.generate(65536, (index) => index % 251);
      final checksum = OfflineMediaChecksum()..add(bytes);
      const prefixLength = 16384;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final firstSent = Completer<void>();
      final finishFirstResponse = Completer<void>();
      final firstHandlerDone = Completer<void>();
      final ranges = <String?>[];
      addTearDown(() async {
        if (!finishFirstResponse.isCompleted) finishFirstResponse.complete();
        await server.close(force: true);
      });
      server.listen((request) async {
        final initial = ranges.isEmpty;
        try {
          ranges.add(request.headers.value(HttpHeaders.rangeHeader));
          request.response.headers.set(HttpHeaders.etagHeader, '"fixture-v1"');
          request.response.bufferOutput = false;
          if (initial) {
            request.response.contentLength = bytes.length;
            request.response.add(bytes.sublist(0, prefixLength));
            await request.response.flush();
            firstSent.complete();
            await finishFirstResponse.future;
          } else {
            expect(ranges.last, 'bytes=$prefixLength-');
            expect(
              request.headers.value(HttpHeaders.ifRangeHeader),
              '"fixture-v1"',
            );
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $prefixLength-${bytes.length - 1}/${bytes.length}',
            );
            request.response.contentLength = bytes.length - prefixLength;
          }
          request.response.add(bytes.sublist(prefixLength));
          await request.response.close();
        } on IOException {
          // The initial connection is deliberately closed by cancellation.
        } finally {
          if (initial) firstHandlerDone.complete();
        }
      });
      final uri = Uri.parse('http://127.0.0.1:${server.port}/fixture.mp3');
      final foreground = LibraryStore(storage: storage);
      addTearDown(foreground.dispose);
      await foreground.load();
      final entry = await _queue(foreground, 'resume');
      Track resolve(Track track) => track.copyWith(
        localPath: '',
        streamUrl: uri.toString(),
        expectedMediaChecksum: 'sha256:${sha256.convert(bytes)}',
      );
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (track) async => resolve(track),
      );
      final pass = worker.processPending(foreground);
      await firstSent.future.timeout(const Duration(seconds: 5));
      final partial = File(
        p.join(
          OfflineCachePaths(root).mediaDirectory.path,
          '${OfflineCachePaths.fileStem(entry.id)}.mp3.part',
        ),
      );
      final deadline = Stopwatch()..start();
      while (!await partial.exists() ||
          await partial.length() != prefixLength) {
        if (deadline.elapsed > const Duration(seconds: 5)) {
          fail('The initial transfer did not persist its expected prefix.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      worker.stop();
      await pass.timeout(const Duration(seconds: 5));
      expect(worker.busy, isFalse);
      expect(ranges, [null]);
      expect(await partial.readAsBytes(), bytes.sublist(0, prefixLength));
      await foreground.requeueProcessingOfflineCacheEntriesForBackground();
      finishFirstResponse.complete();
      await firstHandlerDone.future.timeout(const Duration(seconds: 5));

      final background = LibraryStore(storage: storage);
      addTearDown(background.dispose);
      await background.load();
      expect(
        background.offlineCacheQueue.single.status,
        OfflineCacheEntryStatus.queued,
      );
      final backgroundWorker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (track) async => resolve(track),
      );
      final completed = await backgroundWorker.processNext(background);
      expect(
        completed!.status,
        OfflineCacheEntryStatus.cached,
        reason: completed.reason,
      );
      expect(completed.cachedMediaChecksum, checksum.value);
      expect(completed.reason, contains('provider checksum verified'));
      expect(await File(completed.track.localPath!).readAsBytes(), bytes);
      expect(await partial.exists(), isFalse);
      expect(ranges, [null, 'bytes=$prefixLength-']);

      await expectLater(
        foreground.setOfflineModeEnabled(true),
        throwsA(isA<LibraryStorageConflict>()),
      );
      expect(foreground.saveError, isNotNull);
      await foreground.reloadSavedLibrary();
      expect(
        foreground.offlineCacheQueue.single.status,
        OfflineCacheEntryStatus.cached,
      );
      await foreground.setOfflineModeEnabled(true);
      expect(foreground.saveError, isNull);
      final reopened = LibraryStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.offlineModeEnabled, isTrue);
      expect(
        reopened.offlineCacheQueue.single.cachedMediaChecksum,
        checksum.value,
      );
    },
  );

  test('a rejected processing commit prevents media resolution', () async {
    var reject = false;
    final failing = FileLibraryStorage(
      directory: () async => Directory(p.join(root.path, 'library')),
      beforeCommit: (_) async {
        if (reject) throw const FileSystemException('fixture disk full');
      },
    );
    final library = LibraryStore(storage: failing);
    addTearDown(library.dispose);
    await library.load();
    await _queue(library, 'rejected');
    var resolutions = 0;
    final worker = OfflineCacheQueueWorker(
      cacheRoot: root,
      resolveTrack: (track) async {
        resolutions++;
        return track;
      },
    );
    reject = true;
    await expectLater(
      worker.processPending(library),
      throwsA(isA<FileSystemException>()),
    );
    expect(resolutions, 0);
    expect(worker.busy, isFalse);
    expect(library.saveError, isNotNull);
    expect(
      library.offlineCacheQueue.single.status,
      OfflineCacheEntryStatus.queued,
    );
    expect(await worker.processPending(library), isEmpty);
    expect(resolutions, 0);
    final reopened = LibraryStore(storage: storage);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(
      reopened.offlineCacheQueue.single.status,
      OfflineCacheEntryStatus.queued,
    );
  });

  test(
    'failed cached-index save preserves its original storage error',
    () async {
      var reject = false;
      const failure = FileSystemException('fixture index save failed');
      final failing = FileLibraryStorage(
        directory: () async => Directory(p.join(root.path, 'library')),
        beforeCommit: (_) async {
          if (reject) throw failure;
        },
      );
      final library = LibraryStore(storage: failing);
      addTearDown(library.dispose);
      await library.load();
      await _queue(library, 'index-failure');
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: (track) async {
          reject = true;
          return track;
        },
      );
      await expectLater(worker.processPending(library), throwsA(same(failure)));
      expect(library.saveError, isNotNull);
      expect(
        library.offlineCacheQueue.single.status,
        OfflineCacheEntryStatus.processing,
      );
      expect(worker.busy, isFalse);
      final reopened = LibraryStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(
        reopened.offlineCacheQueue.single.status,
        OfflineCacheEntryStatus.queued,
      );
    },
  );
}

// These tests combine platform messages with real file and loopback HTTP I/O.
class _IoTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

Future<OfflineCacheEntry> _queue(LibraryStore library, String id) {
  final track = Track(id: id, title: id, localPath: '/fixture/$id.mp3');
  return library.queueOfflineCache(
    track,
    OfflineMediaAction.cache,
    const OfflineMediaPolicy(
      <MusicSourceProvider>[],
    ).evaluate(track, OfflineMediaAction.cache),
  );
}
