import 'dart:io';
import 'dart:typed_data';

class WavRiffInfoWriter {
  const WavRiffInfoWriter();

  Future<void> write({
    required String path,
    required String title,
    required String artist,
    required String album,
    required String genre,
    int? year,
    int? trackNumber,
  }) async {
    if (!path.toLowerCase().endsWith('.wav')) {
      throw const FormatException('Only local WAV files can be updated.');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('The WAV file no longer exists.', path);
    }

    final access = await file.open(mode: FileMode.read);
    late _WavWritePlan plan;
    try {
      plan = await _buildWritePlan(
        access,
        await access.length(),
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        year: year,
        trackNumber: trackNumber,
      );
    } finally {
      await access.close();
    }

    await _replaceWithTaggedCopy(file, plan);
  }
}

class _WavWritePlan {
  const _WavWritePlan({required this.chunks, required this.riffSize});

  final List<_WavOutputChunk> chunks;
  final int riffSize;
}

class _WavInputChunk {
  const _WavInputChunk({
    required this.id,
    required this.payloadOffset,
    required this.length,
  });

  final String id;
  final int payloadOffset;
  final int length;
}

class _WavOutputChunk {
  _WavOutputChunk.source(_WavInputChunk source)
      : id = source.id,
        source = source,
        payload = null;

  _WavOutputChunk.generated({required this.id, required this.payload})
      : source = null;

  final String id;
  final _WavInputChunk? source;
  final Uint8List? payload;

  int get length => source?.length ?? payload!.length;
}

class _InfoEntry {
  const _InfoEntry({required this.id, required this.payload});

  final String id;
  final Uint8List payload;
}

Future<_WavWritePlan> _buildWritePlan(
  RandomAccessFile access,
  int fileLength, {
  required String title,
  required String artist,
  required String album,
  required String genre,
  required int? year,
  required int? trackNumber,
}) async {
  if (fileLength < 12) {
    throw const FormatException('WAV file is too short to contain RIFF data.');
  }
  await access.setPosition(0);
  final header = await access.read(12);
  if (!_matchesAscii(header, 0, 'RIFF') || !_matchesAscii(header, 8, 'WAVE')) {
    throw const FormatException('File does not have a RIFF/WAVE header.');
  }

  final chunks = <_WavInputChunk>[];
  final retainedInfoEntries = <_InfoEntry>[];
  var offset = 12;
  while (offset < fileLength) {
    if (offset + 8 > fileLength) {
      throw const FormatException('WAV chunk header is incomplete.');
    }
    await access.setPosition(offset);
    final chunkHeader = await access.read(8);
    if (chunkHeader.length != 8) {
      throw const FormatException('WAV chunk header could not be read.');
    }
    final id = String.fromCharCodes(chunkHeader.sublist(0, 4));
    final length = _uint32Le(chunkHeader, 4);
    final payloadOffset = offset + 8;
    final payloadEnd = payloadOffset + length;
    if (payloadEnd > fileLength) {
      throw const FormatException('WAV chunk exceeds the file length.');
    }

    final chunk = _WavInputChunk(
      id: id,
      payloadOffset: payloadOffset,
      length: length,
    );
    if (id == 'LIST' && length >= 4) {
      await access.setPosition(payloadOffset);
      final payload = await access.read(length);
      if (payload.length != length) {
        throw const FormatException('WAV LIST chunk could not be read.');
      }
      if (_matchesAscii(payload, 0, 'INFO')) {
        retainedInfoEntries.addAll(_retainedInfoEntries(payload));
      } else {
        chunks.add(chunk);
      }
    } else {
      chunks.add(chunk);
    }

    offset = payloadEnd + (length.isOdd ? 1 : 0);
    if (offset > fileLength) {
      throw const FormatException('WAV chunk padding exceeds the file length.');
    }
  }

  final outputChunks = <_WavOutputChunk>[
    for (final chunk in chunks) _WavOutputChunk.source(chunk),
    _WavOutputChunk.generated(
      id: 'LIST',
      payload: _updatedInfoList(
        retainedEntries: retainedInfoEntries,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        year: year,
        trackNumber: trackNumber,
      ),
    ),
  ];
  final riffSize = 4 + outputChunks.fold<int>(
    0,
    (total, chunk) => total + 8 + chunk.length + (chunk.length.isOdd ? 1 : 0),
  );
  if (riffSize > 0xffffffff) {
    throw const FormatException('Updated WAV file exceeds the RIFF size limit.');
  }
  return _WavWritePlan(chunks: outputChunks, riffSize: riffSize);
}

List<_InfoEntry> _retainedInfoEntries(List<int> payload) {
  if (payload.length < 4 || !_matchesAscii(payload, 0, 'INFO')) {
    throw const FormatException('WAV INFO list is invalid.');
  }
  final entries = <_InfoEntry>[];
  var offset = 4;
  while (offset < payload.length) {
    if (_isPadding(payload, offset)) {
      return entries;
    }
    if (offset + 8 > payload.length) {
      throw const FormatException('WAV INFO entry header is incomplete.');
    }
    final id = String.fromCharCodes(payload.sublist(offset, offset + 4));
    final length = _uint32Le(payload, offset + 4);
    final valueStart = offset + 8;
    final valueEnd = valueStart + length;
    if (valueEnd > payload.length) {
      throw const FormatException('WAV INFO entry exceeds the list length.');
    }
    if (!_editableInfoIds.contains(id)) {
      entries.add(
        _InfoEntry(
          id: id,
          payload: Uint8List.fromList(payload.sublist(valueStart, valueEnd)),
        ),
      );
    }
    offset = valueEnd + (length.isOdd ? 1 : 0);
    if (offset > payload.length) {
      throw const FormatException('WAV INFO entry padding is incomplete.');
    }
  }
  return entries;
}

Uint8List _updatedInfoList({
  required List<_InfoEntry> retainedEntries,
  required String title,
  required String artist,
  required String album,
  required String genre,
  required int? year,
  required int? trackNumber,
}) {
  final output = BytesBuilder(copy: false)..add(const <int>[0x49, 0x4e, 0x46, 0x4f]);
  for (final entry in retainedEntries) {
    _writeInfoEntry(output, entry.id, entry.payload);
  }
  _writeEditableInfoEntry(output, 'INAM', title);
  _writeEditableInfoEntry(output, 'IART', artist);
  _writeEditableInfoEntry(output, 'IPRD', album);
  _writeEditableInfoEntry(output, 'ICRD', year?.toString() ?? '');
  _writeEditableInfoEntry(output, 'ITRK', trackNumber?.toString() ?? '');
  _writeEditableInfoEntry(output, 'IGNR', genre);
  return output.takeBytes();
}

void _writeEditableInfoEntry(BytesBuilder output, String id, String value) {
  if (value.trim().isEmpty) {
    return;
  }
  final payload = Uint8List.fromList(<int>[
    for (final codeUnit in value.trim().codeUnits)
      codeUnit <= 0xff ? codeUnit : 0x3f,
    0,
  ]);
  _writeInfoEntry(output, id, payload);
}

void _writeInfoEntry(BytesBuilder output, String id, List<int> payload) {
  output
    ..add(id.codeUnits)
    ..add(_uint32LeBytes(payload.length))
    ..add(payload);
  if (payload.length.isOdd) {
    output.addByte(0);
  }
}

Future<void> _replaceWithTaggedCopy(File file, _WavWritePlan plan) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temporary = File('${file.path}.aethertune-$suffix.part');
  final backup = File('${file.path}.aethertune-$suffix.backup');
  final source = await file.open(mode: FileMode.read);
  final output = await temporary.open(mode: FileMode.write);
  try {
    await output.writeFrom(const <int>[0x52, 0x49, 0x46, 0x46]);
    await output.writeFrom(_uint32LeBytes(plan.riffSize));
    await output.writeFrom(const <int>[0x57, 0x41, 0x56, 0x45]);
    for (final chunk in plan.chunks) {
      await output.writeFrom(chunk.id.codeUnits);
      await output.writeFrom(_uint32LeBytes(chunk.length));
      if (chunk.source case final sourceChunk?) {
        await _copyRange(
          source,
          output,
          start: sourceChunk.payloadOffset,
          length: sourceChunk.length,
        );
      } else {
        await output.writeFrom(chunk.payload!);
      }
      if (chunk.length.isOdd) {
        await output.writeFrom(const <int>[0]);
      }
    }
    await output.flush();
  } finally {
    await source.close();
    await output.close();
  }

  await file.rename(backup.path);
  try {
    await temporary.rename(file.path);
    await backup.delete();
  } on Object {
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    rethrow;
  } finally {
    if (await temporary.exists()) {
      await temporary.delete();
    }
  }
}

Future<void> _copyRange(
  RandomAccessFile source,
  RandomAccessFile output, {
  required int start,
  required int length,
}) async {
  await source.setPosition(start);
  var remaining = length;
  while (remaining > 0) {
    final chunk = await source.read(remaining > 64 * 1024 ? 64 * 1024 : remaining);
    if (chunk.isEmpty) {
      throw const FileSystemException('WAV file ended unexpectedly while copying.');
    }
    await output.writeFrom(chunk);
    remaining -= chunk.length;
  }
}

bool _matchesAscii(List<int> bytes, int offset, String value) {
  if (offset + value.length > bytes.length) {
    return false;
  }
  for (var index = 0; index < value.length; index += 1) {
    if (bytes[offset + index] != value.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

bool _isPadding(List<int> bytes, int offset) {
  for (var index = offset; index < bytes.length; index += 1) {
    if (bytes[index] != 0) {
      return false;
    }
  }
  return true;
}

int _uint32Le(List<int> bytes, int offset) {
  if (offset + 4 > bytes.length) {
    throw const FormatException('WAV field is truncated.');
  }
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}

Uint8List _uint32LeBytes(int value) {
  return Uint8List.fromList(<int>[
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ]);
}

const _editableInfoIds = <String>{
  'INAM',
  'IART',
  'IPRD',
  'ICRD',
  'ITRK',
  'IGNR',
};
