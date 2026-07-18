import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/data/m4a_metadata_writer.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('aethertune-m4a-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('writes Unicode M4A metadata that the scanner reads', () async {
    final file = File('${temporaryDirectory.path}/unicode.m4a');
    await file.writeAsBytes(_m4aFile(audio: <int>[1, 2, 3]));

    await const M4aMetadataWriter().write(
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
    expect(_mdatPayload(await file.readAsBytes()), <int>[1, 2, 3]);
  });

  test('writes M4B metadata that the scanner reads', () async {
    final file = File('${temporaryDirectory.path}/audiobook.m4b');
    await file.writeAsBytes(_m4aFile(audio: <int>[1, 2, 3]));

    await const M4aMetadataWriter().write(
      path: file.path,
      title: 'Chapter One',
      artist: 'Narrator',
      album: 'Audiobook',
      genre: 'Audiobook',
    );

    final result = await const LocalFolderScanner().scan(
      temporaryDirectory.path,
      importedAt: DateTime.utc(2026, 1, 1),
    );

    expect(result.tracks, hasLength(1));
    expect(result.tracks.single.title, 'Chapter One');
    expect(result.tracks.single.artist, 'Narrator');
    expect(result.tracks.single.album, 'Audiobook');
    expect(result.tracks.single.genre, 'Audiobook');
    expect(_mdatPayload(await file.readAsBytes()), <int>[1, 2, 3]);
  });

  test('preserves artwork and custom M4A metadata atoms', () async {
    final file = File('${temporaryDirectory.path}/preserved.m4a');
    final artwork = <int>[0x89, 0x50, 0x4e, 0x47];
    final customPayload = <int>[0xca, 0xfe, 0xba, 0xbe];
    await file.writeAsBytes(
      _m4aFile(
        audio: <int>[9, 8, 7],
        title: 'Old title',
        artwork: artwork,
        customPayload: customPayload,
      ),
    );

    await const M4aMetadataWriter().write(
      path: file.path,
      title: 'New title',
      artist: 'Artist',
      album: 'Album',
      genre: 'Rock',
    );

    final bytes = await file.readAsBytes();
    expect(_mdatPayload(bytes), <int>[9, 8, 7]);
    expect(_containsBytes(bytes, artwork), isTrue);
    expect(_containsBytes(bytes, customPayload), isTrue);
  });

  test('clears optional M4A album fields without touching media bytes',
      () async {
    final file = File('${temporaryDirectory.path}/clear-fields.m4a');
    await file.writeAsBytes(_m4aFile(audio: <int>[8, 7, 6]));
    const writer = M4aMetadataWriter();
    await writer.write(
      path: file.path,
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      albumArtist: 'Album Artist',
      year: 2024,
      trackNumber: 3,
      genre: 'Genre',
    );

    await writer.write(
      path: file.path,
      title: 'Track',
      artist: 'Artist',
      album: 'Album',
      albumArtist: '',
      year: 0,
      trackNumber: 0,
      genre: 'Genre',
    );

    final result = await const LocalFolderScanner().scan(
      temporaryDirectory.path,
      importedAt: DateTime.utc(2026, 1, 1),
    );
    final track = result.tracks.single;
    expect(track.albumArtist, isNull);
    expect(track.year, isNull);
    expect(track.trackNumber, isNull);
    expect(_mdatPayload(await file.readAsBytes()), <int>[8, 7, 6]);
  });

  test('replaces embedded M4A artwork and preserves text, audio, and custom metadata', () async {
    final file = File('${temporaryDirectory.path}/cover.m4a');
    final originalArtwork = <int>[0x89, 0x50, 0x4e, 0x47, 1];
    final replacementArtwork = <int>[0xff, 0xd8, 0xff, 0xe0, 2];
    final customPayload = <int>[0xca, 0xfe, 0xba, 0xbe];
    await file.writeAsBytes(
      _m4aFile(
        audio: <int>[3, 4, 5],
        title: 'Existing title',
        artwork: originalArtwork,
        customPayload: customPayload,
      ),
    );

    await const M4aMetadataWriter().writeArtwork(
      path: file.path,
      artwork: Uint8List.fromList(replacementArtwork),
    );

    final bytes = await file.readAsBytes();
    expect(_mdatPayload(bytes), <int>[3, 4, 5]);
    expect(_containsBytes(bytes, originalArtwork), isFalse);
    expect(_containsBytes(bytes, replacementArtwork), isTrue);
    expect(_containsBytes(bytes, utf8.encode('Existing title')), isTrue);
    expect(_containsBytes(bytes, customPayload), isTrue);

    final result = await const LocalFolderScanner().scan(
      temporaryDirectory.path,
      importedAt: DateTime.utc(2026, 1, 1),
    );
    expect(result.tracks.single.artworkUri?.scheme, 'data');
    expect(result.tracks.single.artworkUri.toString(), contains('image/jpeg'));
  });

  test('rejects unsupported or oversized M4A artwork without touching the file', () async {
    final file = File('${temporaryDirectory.path}/invalid-cover.m4a');
    final original = _m4aFile(audio: <int>[4, 5, 6]);
    await file.writeAsBytes(original);

    await expectLater(
      const M4aMetadataWriter().writeArtwork(
        path: file.path,
        artwork: Uint8List.fromList(<int>[0x47, 0x49, 0x46, 0x38]),
      ),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      const M4aMetadataWriter().writeArtwork(
        path: file.path,
        artwork: Uint8List(maxM4aEmbeddedArtworkBytes + 1),
      ),
      throwsA(isA<FormatException>()),
    );

    expect(await file.readAsBytes(), original);
  });

  test('repairs front-loaded M4A stco and co64 offsets after a metadata rewrite', () async {
    for (final useCo64 in <bool>[false, true]) {
      final preliminary = _frontLoadedM4aFile(
        audio: <int>[1, 2, 3],
        chunkOffset: 0,
        useCo64: useCo64,
      );
      final original = _frontLoadedM4aFile(
        audio: <int>[1, 2, 3],
        chunkOffset: _mdatPayloadStart(preliminary),
        useCo64: useCo64,
      );
      final file = File(
        '${temporaryDirectory.path}/${useCo64 ? 'co64' : 'stco'}-front-loaded.m4a',
      );
      await file.writeAsBytes(original);

      await const M4aMetadataWriter().write(
        path: file.path,
        title: 'Front-loaded title',
        artist: 'Artist',
        album: 'Album',
        genre: 'Rock',
      );

      final bytes = await file.readAsBytes();
      expect(_mdatPayload(bytes), <int>[1, 2, 3]);
      expect(
        _chunkOffset(bytes, useCo64: useCo64),
        _mdatPayloadStart(bytes),
      );

      final result = await const LocalFolderScanner().scan(
        temporaryDirectory.path,
        importedAt: DateTime.utc(2026, 1, 1),
      );
      expect(
        result.tracks.any(
          (track) => track.title == 'Front-loaded title',
        ),
        isTrue,
      );
    }
  });

  test('leaves front-loaded M4A files with malformed chunk offsets untouched', () async {
    final file = File('${temporaryDirectory.path}/malformed-front-loaded.m4a');
    final original = _m4aFile(
      audio: <int>[1, 2, 3],
      mediaBeforeMoov: false,
      extraMoovChildren: <int>[
        ..._atom(
          'trak',
          _atom(
            'mdia',
            _atom(
              'minf',
              _atom(
                'stbl',
                _atom('stco', <int>[0, 0, 0, 0, 0, 0, 0, 1]),
              ),
            ),
          ),
        ),
      ],
    );
    await file.writeAsBytes(original);

    await expectLater(
      const M4aMetadataWriter().write(
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

  test('leaves fragmented front-loaded M4A files untouched', () async {
    final file = File('${temporaryDirectory.path}/fragmented-front-loaded.m4a');
    final original = <int>[
      ..._m4aFile(audio: <int>[1, 2, 3], mediaBeforeMoov: false),
      ..._atom('moof', const <int>[]),
    ];
    await file.writeAsBytes(original);

    await expectLater(
      const M4aMetadataWriter().write(
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

  test('leaves front-loaded M4A files with unsupported co64 offsets untouched', () async {
    final file = File('${temporaryDirectory.path}/large-co64-front-loaded.m4a');
    final original = _m4aFile(
      audio: <int>[1, 2, 3],
      mediaBeforeMoov: false,
      extraMoovChildren: <int>[
        ..._atom(
          'trak',
          _atom(
            'mdia',
            _atom(
              'minf',
              _atom(
                'stbl',
                _atom(
                  'co64',
                  <int>[
                    0,
                    0,
                    0,
                    0,
                    ..._uint32Bytes(1),
                    0x80,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
    await file.writeAsBytes(original);

    await expectLater(
      const M4aMetadataWriter().write(
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

  test('leaves malformed M4A metadata untouched', () async {
    final file = File('${temporaryDirectory.path}/malformed.m4a');
    final original = <int>[
      ..._atom('ftyp', 'M4A '.codeUnits),
      ..._atom('mdat', <int>[1, 2, 3]),
      ..._atom('moov', <int>[0, 0, 0, 32, ...'udta'.codeUnits]),
    ];
    await file.writeAsBytes(original);

    await expectLater(
      const M4aMetadataWriter().write(
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

  test('rejects non-M4A paths', () async {
    await expectLater(
      const M4aMetadataWriter().write(
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

List<int> _m4aFile({
  required List<int> audio,
  bool mediaBeforeMoov = true,
  String title = '',
  List<int>? artwork,
  List<int>? customPayload,
  List<int> extraMoovChildren = const <int>[],
}) {
  final items = <int>[
    if (title.isNotEmpty) ..._textItem(_titleType, title),
    if (artwork != null) ..._artworkItem(artwork),
    if (customPayload != null) ..._atom('xtra', customPayload),
  ];
  final ilst = _atom('ilst', items);
  final meta = _atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final udta = _atom('udta', meta);
  final moov = _atom('moov', <int>[...udta, ...extraMoovChildren]);
  final mdat = _atom('mdat', audio);

  return <int>[
    ..._atom('ftyp', 'M4A '.codeUnits),
    if (mediaBeforeMoov) ...mdat,
    ...moov,
    if (!mediaBeforeMoov) ...mdat,
  ];
}

List<int> _frontLoadedM4aFile({
  required List<int> audio,
  required int chunkOffset,
  required bool useCo64,
}) {
  final chunkOffsetTable = useCo64
      ? _atom(
          'co64',
          <int>[0, 0, 0, 0, ..._uint32Bytes(1), ..._uint64Bytes(chunkOffset)],
        )
      : _atom(
          'stco',
          <int>[0, 0, 0, 0, ..._uint32Bytes(1), ..._uint32Bytes(chunkOffset)],
        );
  return _m4aFile(
    audio: audio,
    mediaBeforeMoov: false,
    extraMoovChildren: <int>[
      ..._atom(
        'trak',
        _atom('mdia', _atom('minf', _atom('stbl', chunkOffsetTable))),
      ),
    ],
  );
}

List<int> _textItem(List<int> type, String value) {
  return _atomBytes(
    type,
    _atom('data', <int>[..._uint32Bytes(1), 0, 0, 0, 0, ...utf8.encode(value)]),
  );
}

List<int> _artworkItem(List<int> value) {
  return _atom(
    'covr',
    _atom('data', <int>[..._uint32Bytes(14), 0, 0, 0, 0, ...value]),
  );
}

List<int> _atom(String type, List<int> payload) {
  return _atomBytes(type.codeUnits, payload);
}

List<int> _atomBytes(List<int> type, List<int> payload) {
  return <int>[..._uint32Bytes(payload.length + 8), ...type, ...payload];
}

List<int> _uint32Bytes(int value) {
  return <int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ];
}

List<int> _uint64Bytes(int value) {
  return List<int>.generate(
    8,
    (index) => (value >> ((7 - index) * 8)) & 0xff,
  );
}

List<int> _mdatPayload(List<int> bytes) {
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    final size = (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
    final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    if (type == 'mdat') {
      return bytes.sublist(offset + 8, offset + size);
    }
    offset += size;
  }
  throw StateError('M4A media atom was not found.');
}

int _mdatPayloadStart(List<int> bytes) {
  var offset = 0;
  while (offset + 8 <= bytes.length) {
    final size = _uint32(bytes, offset);
    final type = ascii.decode(bytes.sublist(offset + 4, offset + 8));
    if (type == 'mdat') {
      return offset + 8;
    }
    offset += size;
  }
  throw StateError('M4A media atom was not found.');
}

int _chunkOffset(List<int> bytes, {required bool useCo64}) {
  final type = useCo64 ? 'co64' : 'stco';
  for (var offset = 4; offset + 16 <= bytes.length; offset += 1) {
    if (ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true) != type) {
      continue;
    }
    return useCo64 ? _uint64(bytes, offset + 12) : _uint32(bytes, offset + 12);
  }
  throw StateError('M4A $type atom was not found.');
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

int _uint32(List<int> bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _uint64(List<int> bytes, int offset) {
  var value = 0;
  for (var index = 0; index < 8; index += 1) {
    value = (value << 8) | bytes[offset + index];
  }
  return value;
}

const _titleType = <int>[0xa9, 0x6e, 0x61, 0x6d];
