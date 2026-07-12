import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class Mp3Id3v1TagWriter {
  const Mp3Id3v1TagWriter();

  Future<void> write({
    required String path,
    required String title,
    required String artist,
    required String album,
    required String genre,
  }) async {
    if (!path.toLowerCase().endsWith('.mp3')) {
      throw const FormatException('Only local MP3 files can be updated.');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('The MP3 file no longer exists.', path);
    }

    final access = await file.open(mode: FileMode.read);
    late _Mp3TagWritePlan plan;
    try {
      final length = await access.length();
      final id3v2 = await _readEditableId3v2Tag(access, length);
      final id3v1 = await _readId3v1Tag(access, length);
      final sourceStart = id3v2?.totalLength ?? 0;
      final sourceEnd = length - (id3v1.hadExistingTag ? 128 : 0);

      plan = _Mp3TagWritePlan(
        sourceStart: sourceStart,
        sourceLength: sourceEnd - sourceStart,
        leadingTag: _updatedId3v2Tag(
          existing: id3v2,
          title: title,
          artist: artist,
          album: album,
          genre: genre,
        ),
        trailingTag: _updatedId3v1Tag(
          id3v1.bytes,
          title: title,
          artist: artist,
          album: album,
          genre: genre,
        ),
      );
    } finally {
      await access.close();
    }

    await _replaceWithTaggedCopy(file, plan);
  }
}

class _Mp3TagWritePlan {
  const _Mp3TagWritePlan({
    required this.sourceStart,
    required this.sourceLength,
    required this.leadingTag,
    required this.trailingTag,
  });

  final int sourceStart;
  final int sourceLength;
  final Uint8List leadingTag;
  final Uint8List trailingTag;
}

class _Id3v1Tag {
  const _Id3v1Tag({required this.bytes, required this.hadExistingTag});

  final Uint8List bytes;
  final bool hadExistingTag;
}

class _EditableId3v2Tag {
  const _EditableId3v2Tag({
    required this.majorVersion,
    required this.totalLength,
    required this.preservedFrames,
  });

  final int majorVersion;
  final int totalLength;
  final List<Uint8List> preservedFrames;
}

Future<_Id3v1Tag> _readId3v1Tag(
  RandomAccessFile access,
  int length,
) async {
  if (length < 128) {
    return _Id3v1Tag(bytes: Uint8List(128), hadExistingTag: false);
  }

  await access.setPosition(length - 128);
  final existing = await access.read(128);
  if (_isId3v1(existing)) {
    return _Id3v1Tag(
      bytes: Uint8List.fromList(existing),
      hadExistingTag: true,
    );
  }
  return _Id3v1Tag(bytes: Uint8List(128), hadExistingTag: false);
}

Future<_EditableId3v2Tag?> _readEditableId3v2Tag(
  RandomAccessFile access,
  int length,
) async {
  if (length < 3) {
    return null;
  }

  await access.setPosition(0);
  final signature = await access.read(length < 10 ? length : 10);
  if (!_hasId3v2Signature(signature)) {
    return null;
  }
  if (signature.length != 10) {
    throw const FormatException('MP3 has an incomplete ID3v2 header.');
  }

  final majorVersion = signature[3];
  final flags = signature[5];
  if (majorVersion != 3 && majorVersion != 4) {
    throw FormatException(
      'ID3v2.$majorVersion tags cannot be safely updated.',
    );
  }
  if ((flags & 0xc0) != 0 || (majorVersion == 4 && (flags & 0x10) != 0)) {
    throw const FormatException(
      'This MP3 uses an ID3v2 layout that cannot be safely updated.',
    );
  }

  final tagSize = _synchsafeInt(signature, 6);
  final totalLength = 10 + tagSize;
  if (totalLength > length) {
    throw const FormatException('MP3 ID3v2 tag exceeds the file length.');
  }
  await access.setPosition(10);
  final payload = await access.read(tagSize);
  if (payload.length != tagSize) {
    throw const FormatException('MP3 ID3v2 tag could not be read completely.');
  }

  return _EditableId3v2Tag(
    majorVersion: majorVersion,
    totalLength: totalLength,
    preservedFrames: _preservedId3v2Frames(payload, majorVersion),
  );
}

List<Uint8List> _preservedId3v2Frames(List<int> payload, int majorVersion) {
  final preserved = <Uint8List>[];
  var offset = 0;
  while (offset < payload.length) {
    if (_isPadding(payload, offset)) {
      return preserved;
    }
    if (offset + 10 > payload.length) {
      throw const FormatException('MP3 ID3v2 tag has a truncated frame header.');
    }

    final frameId = ascii.decode(payload.sublist(offset, offset + 4));
    if (!_isId3v2FrameId(frameId)) {
      throw const FormatException('MP3 ID3v2 tag has an invalid frame identifier.');
    }
    final frameSize = majorVersion == 4
        ? _synchsafeInt(payload, offset + 4)
        : _uint32(payload, offset + 4);
    final frameEnd = offset + 10 + frameSize;
    if (frameSize < 0 || frameEnd > payload.length) {
      throw const FormatException('MP3 ID3v2 tag has an invalid frame length.');
    }

    if (!_editableFrameIds.contains(frameId)) {
      preserved.add(Uint8List.fromList(payload.sublist(offset, frameEnd)));
    }
    offset = frameEnd;
  }
  return preserved;
}

Uint8List _updatedId3v2Tag({
  required _EditableId3v2Tag? existing,
  required String title,
  required String artist,
  required String album,
  required String genre,
}) {
  final majorVersion = existing?.majorVersion ?? 3;
  final frames = BytesBuilder(copy: false);
  for (final frame in existing?.preservedFrames ?? const <Uint8List>[]) {
    frames.add(frame);
  }
  frames
    ..add(_id3v2TextFrame(majorVersion, 'TIT2', title))
    ..add(_id3v2TextFrame(majorVersion, 'TPE1', artist))
    ..add(_id3v2TextFrame(majorVersion, 'TALB', album))
    ..add(_id3v2TextFrame(majorVersion, 'TCON', genre));

  final payload = frames.takeBytes();
  final header = BytesBuilder(copy: false)
    ..add(const <int>[0x49, 0x44, 0x33])
    ..add(<int>[majorVersion, 0, 0])
    ..add(_synchsafeBytes(payload.length));
  header.add(payload);
  return header.takeBytes();
}

Uint8List _id3v2TextFrame(int majorVersion, String frameId, String value) {
  final payload = majorVersion == 3
      ? _utf16LePayload(value)
      : Uint8List.fromList(<int>[3, ...utf8.encode(value.trim())]);
  final frame = BytesBuilder(copy: false)
    ..add(ascii.encode(frameId))
    ..add(
      majorVersion == 3
          ? _uint32Bytes(payload.length)
          : _synchsafeBytes(payload.length),
    )
    ..add(const <int>[0, 0])
    ..add(payload);
  return frame.takeBytes();
}

Uint8List _utf16LePayload(String value) {
  final bytes = BytesBuilder(copy: false)..add(const <int>[1, 0xff, 0xfe]);
  for (final codeUnit in value.trim().codeUnits) {
    bytes.add(<int>[codeUnit & 0xff, codeUnit >> 8]);
  }
  return bytes.takeBytes();
}

Uint8List _updatedId3v1Tag(
  Uint8List tag, {
  required String title,
  required String artist,
  required String album,
  required String genre,
}) {
  final updated = Uint8List.fromList(tag)
    ..[0] = 0x54
    ..[1] = 0x41
    ..[2] = 0x47;
  _writeField(updated, 3, 30, title);
  _writeField(updated, 33, 30, artist);
  _writeField(updated, 63, 30, album);
  updated[127] = _id3v1GenreIndex(genre) ?? 255;
  return updated;
}

Future<void> _replaceWithTaggedCopy(File file, _Mp3TagWritePlan plan) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temporary = File('${file.path}.aethertune-$suffix.part');
  final backup = File('${file.path}.aethertune-$suffix.backup');
  final source = await file.open(mode: FileMode.read);
  final output = await temporary.open(mode: FileMode.write);
  try {
    await output.writeFrom(plan.leadingTag);
    await source.setPosition(plan.sourceStart);
    var remaining = plan.sourceLength;
    while (remaining > 0) {
      final chunk = await source.read(remaining > 64 * 1024 ? 64 * 1024 : remaining);
      if (chunk.isEmpty) {
        throw const FileSystemException(
          'MP3 file ended unexpectedly while copying.',
        );
      }
      await output.writeFrom(chunk);
      remaining -= chunk.length;
    }
    await output.writeFrom(plan.trailingTag);
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

bool _hasId3v2Signature(List<int> bytes) {
  return bytes.length >= 3 &&
      bytes[0] == 0x49 &&
      bytes[1] == 0x44 &&
      bytes[2] == 0x33;
}

bool _isId3v1(List<int> bytes) {
  return bytes.length == 128 &&
      bytes[0] == 0x54 &&
      bytes[1] == 0x41 &&
      bytes[2] == 0x47;
}

bool _isPadding(List<int> bytes, int offset) {
  for (var index = offset; index < bytes.length; index += 1) {
    if (bytes[index] != 0) {
      return false;
    }
  }
  return true;
}

bool _isId3v2FrameId(String value) {
  if (value.length != 4) {
    return false;
  }
  for (final codeUnit in value.codeUnits) {
    if ((codeUnit < 0x30 || codeUnit > 0x39) &&
        (codeUnit < 0x41 || codeUnit > 0x5a)) {
      return false;
    }
  }
  return true;
}

int _synchsafeInt(List<int> bytes, int offset) {
  if (offset + 4 > bytes.length ||
      bytes.sublist(offset, offset + 4).any((byte) => byte > 0x7f)) {
    throw const FormatException('MP3 ID3v2 tag has an invalid size.');
  }
  return (bytes[offset] << 21) |
      (bytes[offset + 1] << 14) |
      (bytes[offset + 2] << 7) |
      bytes[offset + 3];
}

Uint8List _synchsafeBytes(int value) {
  if (value < 0 || value > 0x0fffffff) {
    throw ArgumentError.value(value, 'value', 'ID3v2 tag is too large.');
  }
  return Uint8List.fromList(<int>[
    (value >> 21) & 0x7f,
    (value >> 14) & 0x7f,
    (value >> 7) & 0x7f,
    value & 0x7f,
  ]);
}

int _uint32(List<int> bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

Uint8List _uint32Bytes(int value) {
  return Uint8List.fromList(<int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);
}

int? _id3v1GenreIndex(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  return _id3v1Genres[normalized];
}

void _writeField(Uint8List tag, int start, int length, String value) {
  for (var index = 0; index < length; index += 1) {
    tag[start + index] = 0;
  }
  final codeUnits = value.trim().codeUnits;
  for (var index = 0; index < codeUnits.length && index < length; index += 1) {
    final codeUnit = codeUnits[index];
    tag[start + index] = codeUnit <= 0xff ? codeUnit : 0x3f;
  }
}

const _editableFrameIds = <String>{'TIT2', 'TPE1', 'TALB', 'TCON'};

const _id3v1Genres = <String, int>{
  'blues': 0,
  'classic rock': 1,
  'country': 2,
  'dance': 3,
  'disco': 4,
  'funk': 5,
  'grunge': 6,
  'hip-hop': 7,
  'jazz': 8,
  'metal': 9,
  'new age': 10,
  'oldies': 11,
  'other': 12,
  'pop': 13,
  'r&b': 14,
  'rap': 15,
  'reggae': 16,
  'rock': 17,
  'techno': 18,
  'industrial': 19,
  'alternative': 20,
  'ska': 21,
  'death metal': 22,
  'soundtrack': 24,
  'ambient': 26,
  'trip-hop': 27,
  'trance': 31,
  'classical': 32,
  'instrumental': 33,
  'house': 35,
  'gospel': 38,
  'soul': 42,
  'punk': 43,
  'electronic': 52,
  'eurodance': 54,
  'southern rock': 56,
  'new wave': 66,
  'rave': 68,
  'lo-fi': 71,
  'acid jazz': 74,
  'polka': 75,
  'retro': 76,
  'rock & roll': 78,
  'hard rock': 79,
};
