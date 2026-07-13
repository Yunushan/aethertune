import 'dart:convert';
import 'dart:io';

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

  test('leaves front-loaded M4A files untouched', () async {
    final file = File('${temporaryDirectory.path}/front-loaded.m4a');
    final original = _m4aFile(
      audio: <int>[1, 2, 3],
      mediaBeforeMoov: false,
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
}) {
  final items = <int>[
    if (title.isNotEmpty) ..._textItem(_titleType, title),
    if (artwork != null) ..._artworkItem(artwork),
    if (customPayload != null) ..._atom('xtra', customPayload),
  ];
  final ilst = _atom('ilst', items);
  final meta = _atom('meta', <int>[0, 0, 0, 0, ...ilst]);
  final udta = _atom('udta', meta);
  final moov = _atom('moov', udta);
  final mdat = _atom('mdat', audio);

  return <int>[
    ..._atom('ftyp', 'M4A '.codeUnits),
    if (mediaBeforeMoov) ...mdat,
    ...moov,
    if (!mediaBeforeMoov) ...mdat,
  ];
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

const _titleType = <int>[0xa9, 0x6e, 0x61, 0x6d];
