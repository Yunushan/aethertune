import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aethertune/src/data/local_folder_scanner.dart';
import 'package:aethertune/src/data/wav_riff_info_writer.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('aethertune-wav-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('writes INFO metadata that the scanner reads', () async {
    final file = File('${temporaryDirectory.path}/metadata.wave');
    await file.writeAsBytes(_wavFile(audio: <int>[1, 2, 3]));

    await const WavRiffInfoWriter().write(
      path: file.path,
      title: 'WAV Title',
      artist: 'WAV Artist',
      album: 'WAV Album',
      year: 2024,
      trackNumber: 7,
      genre: 'Jazz Fusion',
    );

    final result = await const LocalFolderScanner().scan(
      temporaryDirectory.path,
      importedAt: DateTime.utc(2026, 1, 1),
    );

    expect(result.tracks, hasLength(1));
    expect(result.tracks.single.title, 'WAV Title');
    expect(result.tracks.single.artist, 'WAV Artist');
    expect(result.tracks.single.album, 'WAV Album');
    expect(result.tracks.single.year, 2024);
    expect(result.tracks.single.trackNumber, 7);
    expect(result.tracks.single.genre, 'Jazz Fusion');
    expect(_dataPayload(await file.readAsBytes()), <int>[1, 2, 3]);
  });

  test('preserves non-INFO chunks, custom INFO fields, and data bytes',
      () async {
    final file = File('${temporaryDirectory.path}/preserved.wav');
    final junkPayload = <int>[0xde, 0xad, 0xbe, 0xef];
    await file.writeAsBytes(
      _wavFile(
        audio: <int>[9, 8, 7],
        junkPayload: junkPayload,
        infoEntries: <_InfoEntry>[
          _InfoEntry('INAM', _latin1NullTerminated('Old title')),
          _InfoEntry('ICMT', _latin1NullTerminated('custom comment')),
        ],
      ),
    );

    await const WavRiffInfoWriter().write(
      path: file.path,
      title: 'New title',
      artist: 'Artist',
      album: 'Album',
      genre: 'Rock',
    );

    final bytes = await file.readAsBytes();
    expect(_dataPayload(bytes), <int>[9, 8, 7]);
    expect(_containsBytes(bytes, junkPayload), isTrue);
    expect(_containsBytes(bytes, ascii.encode('custom comment')), isTrue);
  });

  test('leaves malformed INFO lists untouched', () async {
    final file = File('${temporaryDirectory.path}/malformed.wav');
    final malformedInfo = <int>[
      ...ascii.encode('INFO'),
      ...ascii.encode('INAM'),
      1,
      0,
      0,
      0,
    ];
    final original = _wavFile(
      audio: <int>[1, 2, 3],
      rawInfoPayload: malformedInfo,
    );
    await file.writeAsBytes(original);

    await expectLater(
      const WavRiffInfoWriter().write(
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

  test('rejects non-WAV paths', () async {
    await expectLater(
      const WavRiffInfoWriter().write(
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

List<int> _wavFile({
  required List<int> audio,
  List<int>? junkPayload,
  List<_InfoEntry>? infoEntries,
  List<int>? rawInfoPayload,
}) {
  final chunks = <_Chunk>[
    _Chunk('fmt ', List<int>.filled(16, 0)),
    if (junkPayload != null) _Chunk('JUNK', junkPayload),
    _Chunk('data', audio),
    if (rawInfoPayload != null) _Chunk('LIST', rawInfoPayload),
    if (infoEntries != null) _Chunk('LIST', _infoPayload(infoEntries)),
  ];
  final riffSize = 4 + chunks.fold<int>(
    0,
    (total, chunk) => total + 8 + chunk.payload.length + (chunk.payload.length.isOdd ? 1 : 0),
  );
  return <int>[
    ...ascii.encode('RIFF'),
    ..._uint32Le(riffSize),
    ...ascii.encode('WAVE'),
    for (final chunk in chunks) ...<int>[
      ...ascii.encode(chunk.id),
      ..._uint32Le(chunk.payload.length),
      ...chunk.payload,
      if (chunk.payload.length.isOdd) 0,
    ],
  ];
}

class _Chunk {
  const _Chunk(this.id, this.payload);

  final String id;
  final List<int> payload;
}

class _InfoEntry {
  const _InfoEntry(this.id, this.payload);

  final String id;
  final List<int> payload;
}

List<int> _infoPayload(List<_InfoEntry> entries) {
  return <int>[
    ...ascii.encode('INFO'),
    for (final entry in entries) ...<int>[
      ...ascii.encode(entry.id),
      ..._uint32Le(entry.payload.length),
      ...entry.payload,
      if (entry.payload.length.isOdd) 0,
    ],
  ];
}

List<int> _latin1NullTerminated(String value) {
  return <int>[...latin1.encode(value), 0];
}

List<int> _uint32Le(int value) {
  return <int>[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];
}

List<int> _dataPayload(List<int> bytes) {
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = ascii.decode(bytes.sublist(offset, offset + 4));
    final length =
        bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24);
    final start = offset + 8;
    if (id == 'data') {
      return bytes.sublist(start, start + length);
    }
    offset = start + length + (length.isOdd ? 1 : 0);
  }
  throw StateError('WAV data chunk was not found.');
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
