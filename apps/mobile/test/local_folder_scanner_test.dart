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

  test('prefers ID3v1 title artist and album metadata for MP3 files', () async {
    final albumFolder = Directory(p.join(root.path, 'Filename Album'));
    await albumFolder.create();
    final taggedFile = File(p.join(albumFolder.path, '99 messy-name.mp3'));
    await taggedFile.writeAsBytes(
      <int>[
        1,
        2,
        3,
        ..._id3v1Tag(
          title: 'Tagged Title',
          artist: 'Tagged Artist',
          album: 'Tagged Album',
        ),
      ],
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Tagged Title');
    expect(result.tracks.single.artist, 'Tagged Artist');
    expect(result.tracks.single.album, 'Tagged Album');
  });

  test('prefers ID3v2 title artist album and genre metadata', () async {
    final albumFolder = Directory(p.join(root.path, 'Filename Album'));
    await albumFolder.create();
    final taggedFile = File(p.join(albumFolder.path, '99 messy-name.mp3'));
    await taggedFile.writeAsBytes(
      <int>[
        ..._id3v23Tag(
          title: 'ID3v2 Title',
          artist: 'ID3v2 Artist',
          album: 'ID3v2 Album',
          genre: 'Dream Pop',
        ),
        1,
        2,
        3,
        ..._id3v1Tag(
          title: 'ID3v1 Title',
          artist: 'ID3v1 Artist',
          album: 'ID3v1 Album',
        ),
      ],
    );

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'ID3v2 Title');
    expect(result.tracks.single.artist, 'ID3v2 Artist');
    expect(result.tracks.single.album, 'ID3v2 Album');
    expect(result.tracks.single.genre, 'Dream Pop');
  });

  test('merges partial UTF-16 ID3v2 tags with filename metadata', () async {
    await File(
      p.join(root.path, '06 Filename Artist - Filename Title.mp3'),
    ).writeAsBytes(<int>[
      ..._id3v23Tag(
        title: 'UTF16 Title',
        album: 'UTF16 Album',
        encoding: _id3v2EncodingUtf16,
      ),
      1,
      2,
      3,
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'UTF16 Title');
    expect(result.tracks.single.artist, 'Filename Artist');
    expect(result.tracks.single.album, 'UTF16 Album');
  });

  test('falls back to filename metadata when ID3v1 tags are empty', () async {
    await File(
      p.join(root.path, '04 Fallback Artist - Fallback Title.mp3'),
    ).writeAsBytes(<int>[1, 2, 3, ..._id3v1Tag()]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Fallback Title');
    expect(result.tracks.single.artist, 'Fallback Artist');
    expect(result.tracks.single.album, p.basename(root.path));
  });

  test('merges partial ID3v1 tags with filename metadata', () async {
    await File(
      p.join(root.path, '05 Filename Artist - Filename Title.mp3'),
    ).writeAsBytes(<int>[
      1,
      2,
      3,
      ..._id3v1Tag(album: 'Tagged Album Only'),
    ]);

    final result = await const LocalFolderScanner().scan(root.path);

    expect(result.tracks.single.title, 'Filename Title');
    expect(result.tracks.single.artist, 'Filename Artist');
    expect(result.tracks.single.album, 'Tagged Album Only');
  });

  test('rejects a missing folder path', () async {
    const scanner = LocalFolderScanner();

    expect(
      scanner.scan(p.join(root.path, 'missing')),
      throwsA(isA<FileSystemException>()),
    );
  });
}

List<int> _id3v1Tag({
  String title = '',
  String artist = '',
  String album = '',
}) {
  final bytes = List<int>.filled(128, 0);
  bytes[0] = 0x54;
  bytes[1] = 0x41;
  bytes[2] = 0x47;
  _writeFixedAscii(bytes, 3, 30, title);
  _writeFixedAscii(bytes, 33, 30, artist);
  _writeFixedAscii(bytes, 63, 30, album);
  return bytes;
}

void _writeFixedAscii(List<int> target, int offset, int length, String value) {
  final codes = value.codeUnits.take(length).toList(growable: false);
  for (var index = 0; index < codes.length; index += 1) {
    target[offset + index] = codes[index];
  }
}

List<int> _id3v23Tag({
  String title = '',
  String artist = '',
  String album = '',
  String genre = '',
  int encoding = _id3v2EncodingUtf8,
}) {
  final frames = <int>[
    if (title.isNotEmpty) ..._id3v23TextFrame('TIT2', title, encoding),
    if (artist.isNotEmpty) ..._id3v23TextFrame('TPE1', artist, encoding),
    if (album.isNotEmpty) ..._id3v23TextFrame('TALB', album, encoding),
    if (genre.isNotEmpty) ..._id3v23TextFrame('TCON', genre, encoding),
  ];

  return <int>[
    0x49,
    0x44,
    0x33,
    0x03,
    0x00,
    0x00,
    ..._id3v2SynchsafeSize(frames.length),
    ...frames,
  ];
}

List<int> _id3v23TextFrame(String id, String value, int encoding) {
  final payload = <int>[
    encoding,
    ..._id3v2EncodedText(value, encoding),
  ];

  return <int>[
    ...id.codeUnits,
    ..._uint32Size(payload.length),
    0x00,
    0x00,
    ...payload,
  ];
}

List<int> _id3v2EncodedText(String value, int encoding) {
  if (encoding == _id3v2EncodingUtf16) {
    final bytes = <int>[0xff, 0xfe];
    for (final codeUnit in value.codeUnits) {
      bytes
        ..add(codeUnit & 0xff)
        ..add((codeUnit >> 8) & 0xff);
    }

    return bytes;
  }

  return value.codeUnits;
}

List<int> _id3v2SynchsafeSize(int size) {
  return <int>[
    (size >> 21) & 0x7f,
    (size >> 14) & 0x7f,
    (size >> 7) & 0x7f,
    size & 0x7f,
  ];
}

List<int> _uint32Size(int size) {
  return <int>[
    (size >> 24) & 0xff,
    (size >> 16) & 0xff,
    (size >> 8) & 0xff,
    size & 0xff,
  ];
}

const _id3v2EncodingUtf8 = 3;
const _id3v2EncodingUtf16 = 1;
