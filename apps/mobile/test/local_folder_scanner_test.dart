import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/domain/track.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'aethertune-folder-scan-test-',
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('recursively imports supported audio files with folder metadata', () async {
    final albumOne = Directory(p.join(root.path, 'Album One'));
    final discOne = Directory(p.join(albumOne.path, 'Disc 1'));
    await discOne.create(recursive: true);
    await Directory(p.join(root.path, 'Artwork')).create();
    await File(p.join(albumOne.path, '01 Alpha.MP3')).writeAsBytes(<int>[1]);
    await File(
      p.join(discOne.path, '02 Local Artist - Beta.flac'),
    ).writeAsBytes(<int>[2]);
    await File(
      p.join(root.path, 'Loose Artist - Loose Track.m4a'),
    ).writeAsBytes(<int>[3]);
    await File(p.join(root.path, 'cover.jpg')).writeAsBytes(<int>[4]);
    await File(p.join(root.path, 'notes.txt')).writeAsString('not audio');

    final result = await const LocalFolderScanner().scan(
      root.path,
      importedAt: DateTime.utc(2026, 2, 1),
    );

    expect(result.ignoredFileCount, 2);
    expect(result.inaccessibleDirectoryCount, 0);
    expect(
      result.tracks.map((track) => track.title),
      <String>['Alpha', 'Beta', 'Loose Track'],
    );
    expect(
      result.tracks.map((track) => track.album),
      <String>[
        'Album One',
        p.join('Album One', 'Disc 1'),
        p.basename(root.path),
      ],
    );
    expect(
      result.tracks.map((track) => track.artist),
      <String>['Local Folder', 'Local Artist', 'Loose Artist'],
    );
    expect(
      result.tracks.map((track) => track.addedAt).toSet(),
      <DateTime>{DateTime.utc(2026, 2, 1)},
    );
    expect(
      result.tracks.map((track) => track.sourceId).toSet(),
      <String>{'local'},
    );
    expect(
      result.tracks.first.id,
      Track.stableLocalId(p.join(albumOne.path, '01 Alpha.MP3')),
    );
  });

  test('keeps dashed song titles after parsed local artists', () async {
    await File(
      p.join(root.path, '03. Aether Artist - Movement - Live.opus'),
    ).writeAsBytes(<int>[1]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.artist, 'Aether Artist');
    expect(result.tracks.single.title, 'Movement - Live');
  });

  test('rejects a missing folder path', () async {
    const scanner = LocalFolderScanner();

    expect(
      scanner.scan(p.join(root.path, 'missing')),
      throwsA(isA<FileSystemException>()),
    );
  });
}
