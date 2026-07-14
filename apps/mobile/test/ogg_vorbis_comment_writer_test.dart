import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/data/ogg_vorbis_comment_writer.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('aethertune-ogg-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('writes Vorbis comments, preserves custom comments, and keeps audio pages',
      () async {
    final file = File('${temporaryDirectory.path}/unicode.ogg');
    final audioPage = _oggPage(
      <List<int>>[
        <int>[0xde, 0xad, 0xbe, 0xef, 1, 2, 3],
      ],
      serial: 19,
      sequence: 2,
    );
    await file.writeAsBytes(<int>[
      ..._identificationPage(serial: 19),
      ..._commentPage(
        serial: 19,
        comments: <String>[
          'TITLE=Old title',
          'MUSICBRAINZ_TRACKID=external-id',
        ],
      ),
      ...audioPage,
    ]);

    await const OggVorbisCommentWriter().write(
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
    final track = result.tracks.single;
    expect(track.title, 'Nehir Şarkısı');
    expect(track.artist, 'Björk');
    expect(track.album, 'Canlı Kayıt');
    expect(track.genre, 'Türkçe fusion');

    final bytes = await file.readAsBytes();
    expect(_containsBytes(bytes, ascii.encode('MUSICBRAINZ_TRACKID=external-id')), isTrue);
    expect(bytes.sublist(bytes.length - audioPage.length), audioPage);
    expect(_secondPageHasValidChecksum(bytes), isTrue);
  });

  test('writes standard OpusTags comment metadata', () async {
    final file = File('${temporaryDirectory.path}/podcast.opus');
    await file.writeAsBytes(<int>[
      ..._identificationPage(serial: 23, opus: true),
      ..._commentPage(
        serial: 23,
        opus: true,
        comments: <String>['TITLE=Old episode'],
      ),
      ..._oggPage(<List<int>>[<int>[9, 8, 7]], serial: 23, sequence: 2),
    ]);

    await const OggVorbisCommentWriter().write(
      path: file.path,
      title: 'Updated episode',
      artist: 'Host',
      album: 'Season one',
      genre: 'Podcast',
    );

    final result = await const LocalFolderScanner().scan(
      temporaryDirectory.path,
      importedAt: DateTime.utc(2026, 1, 1),
    );
    final track = result.tracks.single;
    expect(track.title, 'Updated episode');
    expect(track.artist, 'Host');
    expect(track.album, 'Season one');
    expect(track.genre, 'Podcast');
  });

  test('leaves a shared-packet comment page untouched', () async {
    final file = File('${temporaryDirectory.path}/shared.ogg');
    final original = <int>[
      ..._identificationPage(serial: 31),
      ..._oggPage(
        <List<int>>[
          <int>[3, ...'vorbis'.codeUnits, ..._vorbisComments(<String>[])],
          <int>[1, 2, 3],
        ],
        serial: 31,
        sequence: 1,
      ),
    ];
    await file.writeAsBytes(original);

    await expectLater(
      const OggVorbisCommentWriter().write(
        path: file.path,
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        genre: 'Genre',
      ),
      throwsA(isA<FormatException>()),
    );

    expect(await file.readAsBytes(), original);
  });

  test('rejects non-Ogg paths', () async {
    await expectLater(
      const OggVorbisCommentWriter().write(
        path: '${temporaryDirectory.path}/song.flac',
        title: 'Title',
        artist: '',
        album: '',
        genre: '',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

List<int> _identificationPage({required int serial, bool opus = false}) {
  final packet = opus
      ? <int>[...'OpusHead'.codeUnits, 1, 2, 0, 0, 0, 0, 0, 0, 0, 0]
      : <int>[1, ...'vorbis'.codeUnits, 0, 0, 0, 0];
  return _oggPage(
    <List<int>>[packet],
    serial: serial,
    sequence: 0,
    bos: true,
  );
}

List<int> _commentPage({
  required int serial,
  required List<String> comments,
  bool opus = false,
}) {
  final packet = <int>[
    if (opus) ...'OpusTags'.codeUnits else 3,
    if (!opus) ...'vorbis'.codeUnits,
    ..._vorbisComments(comments),
  ];
  return _oggPage(<List<int>>[packet], serial: serial, sequence: 1);
}

List<int> _oggPage(
  List<List<int>> packets, {
  required int serial,
  required int sequence,
  bool bos = false,
}) {
  final lacing = <int>[];
  final body = <int>[];
  for (final packet in packets) {
    var offset = 0;
    while (packet.length - offset >= 255) {
      lacing.add(255);
      body.addAll(packet.sublist(offset, offset + 255));
      offset += 255;
    }
    lacing.add(packet.length - offset);
    body.addAll(packet.sublist(offset));
  }
  if (lacing.length > 255) {
    throw ArgumentError('Test packet layout exceeds one Ogg page.');
  }
  return <int>[
    ...'OggS'.codeUnits,
    0,
    bos ? 0x02 : 0,
    ...List<int>.filled(8, 0),
    ..._uint32Le(serial),
    ..._uint32Le(sequence),
    ...List<int>.filled(4, 0),
    lacing.length,
    ...lacing,
    ...body,
  ];
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

bool _secondPageHasValidChecksum(List<int> bytes) {
  final firstPageEnd = _pageEnd(bytes, 0);
  final secondPageEnd = _pageEnd(bytes, firstPageEnd);
  final page = List<int>.from(bytes.sublist(firstPageEnd, secondPageEnd));
  final stored = page[22] |
      (page[23] << 8) |
      (page[24] << 16) |
      (page[25] << 24);
  page[22] = 0;
  page[23] = 0;
  page[24] = 0;
  page[25] = 0;
  return _oggChecksum(page) == stored;
}

int _pageEnd(List<int> bytes, int start) {
  final segmentCount = bytes[start + 26];
  var bodyLength = 0;
  for (var index = 0; index < segmentCount; index += 1) {
    bodyLength += bytes[start + 27 + index];
  }
  return start + 27 + segmentCount + bodyLength;
}

int _oggChecksum(List<int> bytes) {
  var checksum = 0;
  for (final byte in bytes) {
    checksum ^= (byte & 0xff) << 24;
    for (var bit = 0; bit < 8; bit += 1) {
      checksum = (checksum & 0x80000000) != 0
          ? ((checksum << 1) ^ 0x04c11db7).toUnsigned(32)
          : (checksum << 1).toUnsigned(32);
    }
  }
  return checksum.toUnsigned(32);
}
