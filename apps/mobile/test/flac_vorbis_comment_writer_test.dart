import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/flac_vorbis_comment_writer.dart';
import 'package:aethertune/src/data/local_folder_scanner.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('aethertune-flac-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('writes Unicode comments that the scanner reads', () async {
    final file = File('${temporaryDirectory.path}/unicode.flac');
    await file.writeAsBytes(_flacFile(audio: <int>[1, 2, 3]));

    await const FlacVorbisCommentWriter().write(
      path: file.path,
      title: 'Nehir Şarkısı',
      artist: 'Björk',
      album: 'Canlı Kayıt',
      albumArtist: 'Björk Ensemble',
      year: 2024,
      trackNumber: 7,
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
    expect(result.tracks.single.albumArtist, 'Björk Ensemble');
    expect(result.tracks.single.year, 2024);
    expect(result.tracks.single.trackNumber, 7);
    expect(result.tracks.single.genre, 'Türkçe fusion');
    expect(_audioPayload(await file.readAsBytes()), <int>[1, 2, 3]);
  });

  test('preserves non-comment metadata blocks and custom comments', () async {
    final file = File('${temporaryDirectory.path}/preserved.flac');
    final pictureMarker = <int>[0xde, 0xad, 0xbe, 0xef];
    await file.writeAsBytes(
      _flacFile(
        comments: <String>[
          'TITLE=Old title',
          'MUSICBRAINZ_TRACKID=external-id',
        ],
        picturePayload: pictureMarker,
        audio: <int>[9, 8, 7],
      ),
    );

    await const FlacVorbisCommentWriter().write(
      path: file.path,
      title: 'New title',
      artist: 'Artist',
      album: 'Album',
      genre: 'Rock',
    );

    final bytes = await file.readAsBytes();
    expect(_audioPayload(bytes), <int>[9, 8, 7]);
    expect(
      _containsBytes(bytes, ascii.encode('MUSICBRAINZ_TRACKID=external-id')),
      isTrue,
    );
    expect(_containsBytes(bytes, pictureMarker), isTrue);
  });

  test('leaves malformed Vorbis comments untouched', () async {
    final file = File('${temporaryDirectory.path}/malformed.flac');
    final original = <int>[
      0x66,
      0x4c,
      0x61,
      0x43,
      0x84,
      0,
      0,
      1,
      0,
      1,
      2,
      3,
    ];
    await file.writeAsBytes(original);

    await expectLater(
      const FlacVorbisCommentWriter().write(
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

  test('rejects non-FLAC paths', () async {
    await expectLater(
      const FlacVorbisCommentWriter().write(
        path: '${Directory.systemTemp.path}/song.mp3',
        title: 'Title',
        artist: '',
        album: '',
        genre: '',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

List<int> _flacFile({
  List<String> comments = const <String>[],
  List<int>? picturePayload,
  required List<int> audio,
}) {
  final blocks = <_Block>[
    _Block(0, List<int>.filled(34, 0)),
    if (comments.isNotEmpty) _Block(4, _vorbisComments(comments)),
    if (picturePayload != null) _Block(6, picturePayload),
  ];
  return <int>[
    0x66,
    0x4c,
    0x61,
    0x43,
    for (var index = 0; index < blocks.length; index += 1) ...<int>[
      (index == blocks.length - 1 ? 0x80 : 0) | blocks[index].type,
      (blocks[index].payload.length >> 16) & 0xff,
      (blocks[index].payload.length >> 8) & 0xff,
      blocks[index].payload.length & 0xff,
      ...blocks[index].payload,
    ],
    ...audio,
  ];
}

class _Block {
  const _Block(this.type, this.payload);

  final int type;
  final List<int> payload;
}

List<int> _vorbisComments(List<String> comments) {
  const vendor = 'AetherTune test';
  final vendorBytes = utf8.encode(vendor);
  return <int>[
    ..._uint32Le(vendorBytes.length),
    ...vendorBytes,
    ..._uint32Le(comments.length),
    for (final comment in comments) ...<int>[
      ..._uint32Le(utf8.encode(comment).length),
      ...utf8.encode(comment),
    ],
  ];
}

List<int> _uint32Le(int value) {
  return <int>[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];
}

List<int> _audioPayload(List<int> bytes) {
  var offset = 4;
  while (true) {
    final isLast = (bytes[offset] & 0x80) != 0;
    final length =
        (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
    offset += 4 + length;
    if (isLast) {
      return bytes.sublist(offset);
    }
  }
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
