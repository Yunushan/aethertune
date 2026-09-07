import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aethertune/src/data/offline_cache_manager.dart';
import 'package:aethertune/src/data/offline_cache_paths.dart';
import 'package:aethertune/src/data/offline_cache_resume.dart';
import 'package:aethertune/src/domain/music_source_provider.dart';
import 'package:aethertune/src/domain/offline_cache_cancellation.dart';
import 'package:aethertune/src/domain/offline_cache_entry.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late OfflineCacheManager manager;
  late File partial;
  late OfflineCacheResume resume;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aethertune-cache-resume-');
    manager = OfflineCacheManager(cacheRoot: root);
    await manager.mediaDirectory.create(recursive: true);
    partial = File(p.join(manager.mediaDirectory.path, 'entry.mp3.part'));
    resume = OfflineCacheResume(OfflineCachePaths(root), partial);
  });
  tearDown(() => root.delete(recursive: true));

  Future<Uri> serve(Future<void> Function(HttpRequest) handler) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      try {
        await handler(request);
      } on IOException {
        /* Cancellations deliberately close connections. */
      }
    });
    return Uri.parse('http://127.0.0.1:${server.port}/song.mp3');
  }

  test(
    'stable strong ETag resumes with If-Range and exact Content-Range',
    () async {
      final uri = await serve((request) async {
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=2-');
        expect(
          request.headers.value(HttpHeaders.ifRangeHeader),
          '"version-one"',
        );
        expect(
          request.headers.value(HttpHeaders.acceptEncodingHeader),
          'identity',
        );
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.etagHeader, '"version-one"');
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes 2-3/4',
        );
        request.response.add([3, 4]);
        await request.response.close();
      });
      await partial.writeAsBytes([1, 2]);
      await resume.write(uri, null, '"version-one"');
      final result = await manager.materialize(_entry(uri));
      expect(await File(result.track.localPath!).readAsBytes(), [1, 2, 3, 4]);
      expect(await resume.file.exists(), isFalse);
    },
  );

  for (final etag in [null, 'W/"weak"', 'not-an-etag']) {
    test(
      'unvalidated partial restarts instead of mixing media: $etag',
      () async {
        final uri = await serve((request) async {
          expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
          expect(request.headers.value(HttpHeaders.ifRangeHeader), isNull);
          request.response.add([8, 9, 10]);
          await request.response.close();
        });
        await partial.writeAsBytes([1, 2]);
        if (etag != null) await resume.write(uri, null, etag);
        final result = await manager.materialize(_entry(uri));
        expect(await File(result.track.localPath!).readAsBytes(), [8, 9, 10]);
      },
    );
  }

  for (final responseEtag in [null, '"changed"', 'W/"old"']) {
    test(
      'incorrect partial-response validator triggers clean retry: $responseEtag',
      () async {
        final ranges = <String?>[];
        final uri = await serve((request) async {
          ranges.add(request.headers.value(HttpHeaders.rangeHeader));
          if (ranges.length == 1) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes 2-3/4',
            );
            if (responseEtag != null) {
              request.response.headers.set(
                HttpHeaders.etagHeader,
                responseEtag,
              );
            }
            request.response.add([7, 8]);
          } else {
            request.response.add([5, 6, 7, 8]);
          }
          await request.response.close();
        });
        await partial.writeAsBytes([1, 2]);
        await resume.write(uri, null, '"old"');
        final result = await manager.materialize(_entry(uri));
        expect(ranges, ['bytes=2-', null]);
        expect(await File(result.track.localPath!).readAsBytes(), [5, 6, 7, 8]);
      },
    );
  }

  test('full response to If-Range replaces rather than appends', () async {
    final uri = await serve((request) async {
      expect(request.headers.value(HttpHeaders.ifRangeHeader), '"old"');
      request.response.headers.set(HttpHeaders.etagHeader, '"new"');
      request.response.add([9, 8, 7]);
      await request.response.close();
    });
    await partial.writeAsBytes([1, 2]);
    await resume.write(uri, null, '"old"');
    final result = await manager.materialize(_entry(uri));
    expect(await File(result.track.localPath!).readAsBytes(), [9, 8, 7]);
  });

  test('ETags are not reused for a different resource URL', () async {
    final uri = await serve((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
      request.response.add([4, 5]);
      await request.response.close();
    });
    await partial.writeAsBytes([1, 2]);
    await resume.write(uri.replace(path: '/other.mp3'), null, '"one"');
    final result = await manager.materialize(_entry(uri));
    expect(await File(result.track.localPath!).readAsBytes(), [4, 5]);
  });

  for (final metadata in ['{corrupt', 'x' * 5000]) {
    test(
      'malformed or oversized resume metadata causes a clean restart',
      () async {
        final uri = await serve((request) async {
          expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
          request.response.add([3, 4]);
          await request.response.close();
        });
        await partial.writeAsBytes([1, 2]);
        await resume.file.writeAsString(metadata);
        final result = await manager.materialize(_entry(uri));
        expect(await File(result.track.localPath!).readAsBytes(), [3, 4]);
      },
    );
  }

  test(
    'unexpected content encoding never changes range byte semantics',
    () async {
      final uri = await serve((request) async {
        request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        request.response.add(gzip.encode([1, 2, 3]));
        await request.response.close();
      });
      await expectLater(
        manager.materialize(_entry(uri)),
        throwsA(isA<HttpException>()),
      );
      expect(await partial.exists(), isFalse);
    },
  );

  test(
    'actual cancelled transfer persists identity and resumes after restart',
    () async {
      final ranges = <String?>[];
      final release = Completer<void>();
      final uri = await serve((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        ranges.add(range);
        request.response.bufferOutput = false;
        request.response.headers.set(HttpHeaders.etagHeader, '"stable"');
        if (range == null) {
          request.response.add([1, 2]);
          await request.response.flush();
          await release.future;
          request.response.add([3, 4]);
        } else {
          expect(request.headers.value(HttpHeaders.ifRangeHeader), '"stable"');
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 2-3/4',
          );
          request.response.add([3, 4]);
        }
        await request.response.close();
      });
      final token = OfflineCacheCancellationToken();
      final operation = manager.materialize(
        _entry(uri),
        cancellationToken: token,
      );
      final rejected = expectLater(
        operation,
        throwsA(isA<OfflineCacheCancelled>()),
      );
      try {
        final deadline = Stopwatch()..start();
        while (!await partial.exists() || await partial.length() < 2) {
          if (deadline.elapsed > const Duration(seconds: 5)) {
            fail('Partial bytes were not written.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        token.cancel();
        await rejected;
      } finally {
        token.cancel();
        release.complete();
      }
      final metadata = jsonDecode(await resume.file.readAsString()) as Map;
      expect(metadata['etag'], '"stable"');
      expect(metadata.values, isNot(contains(uri.toString())));
      final result = await OfflineCacheManager(
        cacheRoot: root,
      ).materialize(_entry(uri));
      expect(ranges, [null, 'bytes=2-']);
      expect(await File(result.track.localPath!).readAsBytes(), [1, 2, 3, 4]);
    },
  );
}

OfflineCacheEntry _entry(Uri uri) => OfflineCacheEntry(
  id: 'entry',
  track: Track(
    id: 'track',
    title: 'Track',
    sourceId: 'archive',
    streamUrl: uri.toString(),
  ),
  action: OfflineMediaAction.cache,
  createdAt: DateTime.utc(2026, 1, 1),
);
