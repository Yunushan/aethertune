import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/provider_artwork_file_cache.dart';

void main() {
  late Directory cacheRoot;

  setUp(() async {
    cacheRoot = await Directory.systemTemp.createTemp(
      'aethertune-artwork-cache-test-',
    );
  });

  tearDown(() async {
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }
  });

  test('writes format-aware private files and reuses matching artwork',
      () async {
    var rootLoads = 0;
    final cache = ProviderArtworkFileCache(
      cacheRootLoader: () async {
        rootLoads += 1;
        return cacheRoot;
      },
    );
    final bytes = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      1,
      2,
      3,
    ]);

    final first = await cache.materialize(
      sourceId: 'provider-1',
      artworkId: 'cover-1',
      version: 'v1',
      bytes: bytes,
    );
    final stalePartial = File('${File.fromUri(first).path}.stale.part');
    await stalePartial.writeAsBytes(<int>[9]);
    final second = await cache.materialize(
      sourceId: 'provider-1',
      artworkId: 'cover-1',
      version: 'v1',
      bytes: bytes,
    );

    expect(first, second);
    expect(first.scheme, 'file');
    expect(first.path, endsWith('.png'));
    expect(await File.fromUri(first).readAsBytes(), bytes);
    expect(first.toString(), isNot(contains('provider-1')));
    expect(first.toString(), isNot(contains('cover-1')));
    expect(await stalePartial.exists(), isFalse);
    expect(rootLoads, 1);
  });

  test('bounds file count while retaining the newly written file', () async {
    final cache = ProviderArtworkFileCache(
      cacheRootLoader: () async => cacheRoot,
      maxFileCount: 2,
      maxTotalBytes: 1024,
    );

    for (var index = 0; index < 3; index += 1) {
      await cache.materialize(
        sourceId: 'provider-1',
        artworkId: 'cover-$index',
        bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, index]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }

    final files = await cacheRoot
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && !entity.path.endsWith('.part'))
        .toList();
    expect(files, hasLength(2));
  });

  test('removes only the selected provider directory', () async {
    final cache = ProviderArtworkFileCache(
      cacheRootLoader: () async => cacheRoot,
    );
    final first = await cache.materialize(
      sourceId: 'provider-1',
      artworkId: 'cover-1',
      bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 1]),
    );
    final second = await cache.materialize(
      sourceId: 'provider-2',
      artworkId: 'cover-2',
      bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 2]),
    );

    await cache.removeProvider('provider-1');

    expect(await File.fromUri(first).exists(), isFalse);
    expect(await File.fromUri(second).exists(), isTrue);
  });
}
