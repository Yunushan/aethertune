import 'dart:io';
import 'dart:typed_data';

class Mp3Id3v1TagWriter {
  const Mp3Id3v1TagWriter();

  Future<void> write({
    required String path,
    required String title,
    required String artist,
    required String album,
  }) async {
    if (!path.toLowerCase().endsWith('.mp3')) {
      throw const FormatException('Only local MP3 files can be updated.');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('The MP3 file no longer exists.', path);
    }

    final access = await file.open(mode: FileMode.writeOnly);
    try {
      final length = await access.length();
      Uint8List tag = Uint8List(128);
      var tagOffset = length;
      if (length >= 128) {
        tagOffset = length - 128;
        await access.setPosition(tagOffset);
        final existing = await access.read(128);
        if (_isId3v1(existing)) {
          tag = Uint8List.fromList(existing);
        }
      }

      tag
        ..[0] = 0x54
        ..[1] = 0x41
        ..[2] = 0x47;
      _writeField(tag, 3, 30, title);
      _writeField(tag, 33, 30, artist);
      _writeField(tag, 63, 30, album);

      await access.setPosition(tagOffset);
      await access.writeFrom(tag);
      await access.flush();
    } finally {
      await access.close();
    }
  }
}

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
