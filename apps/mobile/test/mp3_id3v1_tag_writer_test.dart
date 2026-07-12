import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/mp3_id3v1_tag_writer.dart';
import 'package:aethertune/src/data/local_folder_scanner.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('aethertune-id3-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('appends and replaces ID3v1 title artist and album fields', () async {
    final file = File('${temporaryDirectory.path}/song.mp3');
    await file.writeAsBytes(<int>[1, 2, 3]);
    const writer = Mp3Id3v1TagWriter();

    await writer.write(
      path: file.path,
      title: 'A title',
      artist: 'An artist',
      album: 'An album',
      genre: 'Rock',
    );

    var bytes = await file.readAsBytes();
    expect(_audioPayload(bytes), <int>[1, 2, 3]);
    expect(String.fromCharCodes(bytes.sublist(bytes.length - 128, bytes.length - 125)), 'TAG');
    expect(_field(bytes, 3, 30), 'A title');
    expect(_field(bytes, 33, 30), 'An artist');
    expect(_field(bytes, 63, 30), 'An album');
    expect(bytes.last, 17);

    await writer.write(
      path: file.path,
      title: 'Updated',
      artist: 'Unicode ?',
      album: '',
      genre: 'Custom genre',
    );
    bytes = await file.readAsBytes();
    expect(_audioPayload(bytes), <int>[1, 2, 3]);
    expect(_field(bytes, 3, 30), 'Updated');
    expect(_field(bytes, 33, 30), 'Unicode ?');
    expect(_field(bytes, 63, 30), isEmpty);
    expect(bytes.last, 255);
  });

  test('writes Unicode ID3v2 metadata that the scanner reads', () async {
    final file = File('${temporaryDirectory.path}/unicode.mp3');
    await file.writeAsBytes(<int>[4, 5, 6]);

    await const Mp3Id3v1TagWriter().write(
      path: file.path,
      title: 'Nehir Şarkısı',
      artist: 'Björk',
      album: 'Canlı Kayıt',
      genre: 'Türkçe fusion',
    );

    final result = await const LocalFolderScanner().scan(
      temporaryDirectory.path,
      importedAt: DateTime.utc(2026, 1, 1),
    );

    expect(result.tracks, hasLength(1));
    expect(result.tracks.single.title, 'Nehir Şarkısı');
    expect(result.tracks.single.artist, 'Björk');
    expect(result.tracks.single.album, 'Canlı Kayıt');
    expect(result.tracks.single.genre, 'Türkçe fusion');
  });

  test('preserves non-editable ID3v2 frames and audio bytes', () async {
    final file = File('${temporaryDirectory.path}/preserved.mp3');
    final existingFrames = <int>[
      ..._id3v23Frame('TIT2', <int>[3, ...utf8.encode('Old title')]),
      ..._id3v23Frame('TXXX', <int>[3, ...utf8.encode('CUSTOM-FRAME')]),
      ..._id3v23Frame(
        'APIC',
        <int>[3, ...ascii.encode('image/jpeg'), 0, 3, 0, 0xda, 0x7a],
      ),
    ];
    await file.writeAsBytes(<int>[
      ..._id3v23Tag(existingFrames),
      9,
      8,
      7,
    ]);

    await const Mp3Id3v1TagWriter().write(
      path: file.path,
      title: 'New title',
      artist: 'Artist',
      album: 'Album',
      genre: 'Rock',
    );

    final bytes = await file.readAsBytes();
    expect(_audioPayload(bytes), <int>[9, 8, 7]);
    expect(_containsBytes(bytes, ascii.encode('CUSTOM-FRAME')), isTrue);
    expect(_containsBytes(bytes, <int>[0xda, 0x7a]), isTrue);
  });

  test('updates supported ID3v2.4 tags without dropping custom frames',
      () async {
    final file = File('${temporaryDirectory.path}/v24.mp3');
    final frames = <int>[
      ..._id3v24Frame('TIT2', <int>[3, ...utf8.encode('Old title')]),
      ..._id3v24Frame('TXXX', <int>[3, ...utf8.encode('V24-CUSTOM')]),
    ];
    await file.writeAsBytes(<int>[..._id3v24Tag(frames), 6, 5, 4]);

    await const Mp3Id3v1TagWriter().write(
      path: file.path,
      title: 'Updated v2.4',
      artist: 'Artist',
      album: 'Album',
      genre: 'Electronic',
    );

    final bytes = await file.readAsBytes();
    expect(bytes[3], 4);
    expect(_audioPayload(bytes), <int>[6, 5, 4]);
    expect(_containsBytes(bytes, ascii.encode('V24-CUSTOM')), isTrue);
  });

  test('leaves unsupported ID3v2 layouts untouched', () async {
    final file = File('${temporaryDirectory.path}/unsupported.mp3');
    final original = <int>[
      0x49,
      0x44,
      0x33,
      3,
      0,
      0x80,
      0,
      0,
      0,
      0,
      1,
      2,
      3,
    ];
    await file.writeAsBytes(original);

    await expectLater(
      const Mp3Id3v1TagWriter().write(
        path: file.path,
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        genre: 'Rock',
      ),
      throwsA(isA<FormatException>()),
    );

    expect(await file.readAsBytes(), original);
  });

  test('rejects non-MP3 paths', () async {
    await expectLater(
      const Mp3Id3v1TagWriter().write(
        path: '${Directory.systemTemp.path}/song.flac',
        title: 'Title',
        artist: '',
        album: '',
        genre: '',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

String _field(List<int> bytes, int offset, int length) {
  final tagStart = bytes.length - 128;
  return String.fromCharCodes(bytes.sublist(tagStart + offset, tagStart + offset + length))
      .replaceAll(RegExp(r'\x00+$'), '');
}

List<int> _audioPayload(List<int> bytes) {
  final tagSize = (bytes[6] << 21) |
      (bytes[7] << 14) |
      (bytes[8] << 7) |
      bytes[9];
  return bytes.sublist(10 + tagSize, bytes.length - 128);
}

List<int> _id3v23Tag(List<int> frames) {
  return <int>[
    0x49,
    0x44,
    0x33,
    3,
    0,
    0,
    ..._synchsafeBytes(frames.length),
    ...frames,
  ];
}

List<int> _id3v23Frame(String id, List<int> payload) {
  return <int>[
    ...ascii.encode(id),
    (payload.length >> 24) & 0xff,
    (payload.length >> 16) & 0xff,
    (payload.length >> 8) & 0xff,
    payload.length & 0xff,
    0,
    0,
    ...payload,
  ];
}

List<int> _id3v24Tag(List<int> frames) {
  return <int>[
    0x49,
    0x44,
    0x33,
    4,
    0,
    0,
    ..._synchsafeBytes(frames.length),
    ...frames,
  ];
}

List<int> _id3v24Frame(String id, List<int> payload) {
  return <int>[
    ...ascii.encode(id),
    ..._synchsafeBytes(payload.length),
    0,
    0,
    ...payload,
  ];
}

List<int> _synchsafeBytes(int value) {
  return <int>[
    (value >> 21) & 0x7f,
    (value >> 14) & 0x7f,
    (value >> 7) & 0x7f,
    value & 0x7f,
  ];
}

bool _containsBytes(List<int> bytes, List<int> needle) {
  for (var start = 0; start + needle.length <= bytes.length; start += 1) {
    var matches = true;
    for (var index = 0; index < needle.length; index += 1) {
      if (bytes[start + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}
