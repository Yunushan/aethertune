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
    late Uint8List tag;
    late int audioLength;
    try {
      final length = await access.length();
      tag = Uint8List(128);
      audioLength = length;
      if (length >= 128) {
        await access.setPosition(length - 128);
        final existing = await access.read(128);
        if (_isId3v1(existing)) {
          tag = Uint8List.fromList(existing);
          audioLength = length - 128;
        }
      }

      tag
        ..[0] = 0x54
        ..[1] = 0x41
        ..[2] = 0x47;
      _writeField(tag, 3, 30, title);
      _writeField(tag, 33, 30, artist);
      _writeField(tag, 63, 30, album);
      final genreIndex = _id3v1GenreIndex(genre);
      if (genreIndex != null) {
        tag[127] = genreIndex;
      }

    } finally {
      await access.close();
    }
    await _replaceWithTaggedCopy(file, audioLength, tag);
  }
}

Future<void> _replaceWithTaggedCopy(
  File file,
  int audioLength,
  Uint8List tag,
) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temporary = File('${file.path}.aethertune-$suffix.part');
  final backup = File('${file.path}.aethertune-$suffix.backup');
  final source = await file.open(mode: FileMode.read);
  final output = await temporary.open(mode: FileMode.write);
  try {
    var remaining = audioLength;
    while (remaining > 0) {
      final chunk = await source.read(remaining > 64 * 1024 ? 64 * 1024 : remaining);
      if (chunk.isEmpty) {
        throw const FileSystemException('MP3 file ended unexpectedly while copying.');
      }
      await output.writeFrom(chunk);
      remaining -= chunk.length;
    }
    await output.writeFrom(tag);
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

int? _id3v1GenreIndex(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  return _id3v1Genres[normalized];
}

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

bool _isId3v1(List<int> bytes) {
  return bytes.length == 128 &&
      bytes[0] == 0x54 &&
      bytes[1] == 0x41 &&
      bytes[2] == 0x47;
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
