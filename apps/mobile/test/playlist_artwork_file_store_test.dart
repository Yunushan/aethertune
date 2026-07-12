import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/playlist_artwork_file_store.dart';

void main() {
  late Directory temporaryDirectory;
  late PlaylistArtworkFileStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'aethertune-playlist-artwork-test-',
    );
    store = PlaylistArtworkFileStore(
      documentsDirectory: () async => temporaryDirectory,
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('stores validated image bytes privately and removes managed files',
      () async {
    final bytes = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
      0x00,
    ]);

    final uri = await store.save(bytes);
    final file = File.fromUri(uri);

    expect(uri.scheme, 'file');
    expect(file.path, endsWith('.png'));
    expect(await file.readAsBytes(), bytes);

    await store.delete(uri);
    expect(await file.exists(), isFalse);
  });

  test('rejects unsupported or oversized artwork and keeps external files',
      () async {
    await expectLater(
      store.save(Uint8List.fromList(<int>[1, 2, 3])),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      store.save(Uint8List(maxPlaylistArtworkBytes + 1)),
      throwsA(isA<FormatException>()),
    );

    final external = File('${temporaryDirectory.path}-external.txt');
    await external.writeAsString('keep');
    await store.delete(Uri.file(external.path));

    expect(await external.readAsString(), 'keep');
    await external.delete();
  });
}
