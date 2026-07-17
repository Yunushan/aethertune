import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class FlacVorbisCommentWriter {
  const FlacVorbisCommentWriter();

  Future<void> write({
    required String path,
    required String title,
    required String artist,
    required String album,
    required String genre,
    String? albumArtist,
    int? year,
    int? trackNumber,
  }) async {
    if (!path.toLowerCase().endsWith('.flac')) {
      throw const FormatException('Only local FLAC files can be updated.');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('The FLAC file no longer exists.', path);
    }

    final access = await file.open(mode: FileMode.read);
    late _FlacWritePlan plan;
    try {
      plan = await _buildWritePlan(
        access,
        await access.length(),
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        albumArtist: albumArtist,
        year: year,
        trackNumber: trackNumber,
      );
    } finally {
      await access.close();
    }

    await _replaceWithTaggedCopy(file, plan);
  }
}

class _FlacWritePlan {
  const _FlacWritePlan({
    required this.blocks,
    required this.audioStart,
    required this.audioLength,
  });

  final List<_FlacOutputBlock> blocks;
  final int audioStart;
  final int audioLength;
}

class _FlacInputBlock {
  const _FlacInputBlock({
    required this.type,
    required this.payloadOffset,
    required this.length,
  });

  final int type;
  final int payloadOffset;
  final int length;
}

class _FlacOutputBlock {
  _FlacOutputBlock.source(_FlacInputBlock source)
      : type = source.type,
        source = source,
        payload = null;

  _FlacOutputBlock.generated({
    required this.type,
    required this.payload,
  }) : source = null;

  final int type;
  final _FlacInputBlock? source;
  final Uint8List? payload;

  int get length => source?.length ?? payload!.length;
}

class _VorbisCommentData {
  const _VorbisCommentData({
    required this.vendor,
    required this.nonEditableComments,
  });

  final String vendor;
  final List<String> nonEditableComments;
}

Future<_FlacWritePlan> _buildWritePlan(
  RandomAccessFile access,
  int fileLength, {
  required String title,
  required String artist,
  required String album,
  required String genre,
  required String? albumArtist,
  required int? year,
  required int? trackNumber,
}) async {
  if (fileLength < 8) {
    throw const FormatException('FLAC file is too short to contain metadata.');
  }
  await access.setPosition(0);
  final marker = await access.read(4);
  if (!_matchesFlacMarker(marker)) {
    throw const FormatException('File does not have a FLAC metadata marker.');
  }

  final blocks = <_FlacInputBlock>[];
  final comments = <_VorbisCommentData>[];
  var offset = 4;
  var lastBlockFound = false;
  while (!lastBlockFound) {
    if (offset + 4 > fileLength) {
      throw const FormatException('FLAC metadata is incomplete.');
    }
    await access.setPosition(offset);
    final header = await access.read(4);
    if (header.length != 4) {
      throw const FormatException('FLAC metadata block header is incomplete.');
    }

    final isLastBlock = (header[0] & 0x80) != 0;
    final type = header[0] & 0x7f;
    final length = _uint24(header, 1);
    final payloadOffset = offset + 4;
    if (payloadOffset + length > fileLength) {
      throw const FormatException('FLAC metadata block exceeds the file length.');
    }

    final block = _FlacInputBlock(
      type: type,
      payloadOffset: payloadOffset,
      length: length,
    );
    blocks.add(block);
    if (type == _vorbisCommentBlockType) {
      await access.setPosition(payloadOffset);
      final payload = await access.read(length);
      if (payload.length != length) {
        throw const FormatException('FLAC Vorbis comments could not be read.');
      }
      comments.add(_parseVorbisComments(payload));
    }

    offset = payloadOffset + length;
    lastBlockFound = isLastBlock;
  }

  if (blocks.isEmpty) {
    throw const FormatException('FLAC does not contain metadata blocks.');
  }
  final vendor = comments.isEmpty ? 'AetherTune' : comments.first.vendor;
  final retainedComments = <String>[];
  for (final comment in comments) {
    retainedComments.addAll(comment.nonEditableComments);
  }
  final outputBlocks = <_FlacOutputBlock>[
    for (final block in blocks)
      if (block.type != _vorbisCommentBlockType) _FlacOutputBlock.source(block),
    _FlacOutputBlock.generated(
      type: _vorbisCommentBlockType,
      payload: _updatedVorbisCommentBlock(
        vendor: vendor,
        retainedComments: retainedComments,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
      ),
    ),
  ];

  return _FlacWritePlan(
    blocks: outputBlocks,
    audioStart: offset,
    audioLength: fileLength - offset,
  );
}

_VorbisCommentData _parseVorbisComments(List<int> bytes) {
  var offset = 0;
  final vendorLength = _uint32Le(bytes, offset);
  offset += 4;
  if (vendorLength < 0 || offset + vendorLength > bytes.length) {
    throw const FormatException('FLAC Vorbis vendor field is invalid.');
  }
  final vendor = utf8.decode(bytes.sublist(offset, offset + vendorLength));
  offset += vendorLength;

  final count = _uint32Le(bytes, offset);
  offset += 4;
  final retained = <String>[];
  for (var index = 0; index < count; index += 1) {
    final length = _uint32Le(bytes, offset);
    offset += 4;
    if (length < 0 || offset + length > bytes.length) {
      throw const FormatException('FLAC Vorbis comment field is invalid.');
    }
    final comment = utf8.decode(bytes.sublist(offset, offset + length));
    offset += length;
    if (!_isEditableComment(comment)) {
      retained.add(comment);
    }
  }
  if (offset != bytes.length) {
    throw const FormatException('FLAC Vorbis comments have trailing data.');
  }
  return _VorbisCommentData(vendor: vendor, nonEditableComments: retained);
}

Uint8List _updatedVorbisCommentBlock({
  required String vendor,
  required List<String> retainedComments,
  required String title,
  required String artist,
  required String album,
  required String genre,
}) {
  final comments = <String>[
    ...retainedComments,
    if (title.trim().isNotEmpty) 'TITLE=${title.trim()}',
    if (artist.trim().isNotEmpty) 'ARTIST=${artist.trim()}',
    if (album.trim().isNotEmpty) 'ALBUM=${album.trim()}',
    if (albumArtist?.trim().isNotEmpty == true)
      'ALBUMARTIST=${albumArtist!.trim()}',
    if (year != null) 'DATE=$year',
    if (trackNumber != null) 'TRACKNUMBER=$trackNumber',
    if (genre.trim().isNotEmpty) 'GENRE=${genre.trim()}',
  ];
  final vendorBytes = utf8.encode(vendor);
  final output = BytesBuilder(copy: false)
    ..add(_uint32LeBytes(vendorBytes.length))
    ..add(vendorBytes)
    ..add(_uint32LeBytes(comments.length));
  for (final comment in comments) {
    final bytes = utf8.encode(comment);
    output
      ..add(_uint32LeBytes(bytes.length))
      ..add(bytes);
  }
  final payload = output.takeBytes();
  if (payload.length > 0x00ffffff) {
    throw const FormatException('FLAC Vorbis comments exceed the block limit.');
  }
  return payload;
}

Future<void> _replaceWithTaggedCopy(File file, _FlacWritePlan plan) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temporary = File('${file.path}.aethertune-$suffix.part');
  final backup = File('${file.path}.aethertune-$suffix.backup');
  final source = await file.open(mode: FileMode.read);
  final output = await temporary.open(mode: FileMode.write);
  try {
    await output.writeFrom(const <int>[0x66, 0x4c, 0x61, 0x43]);
    for (var index = 0; index < plan.blocks.length; index += 1) {
      final block = plan.blocks[index];
      final isLast = index == plan.blocks.length - 1;
      await output.writeFrom(<int>[
        (isLast ? 0x80 : 0) | block.type,
        (block.length >> 16) & 0xff,
        (block.length >> 8) & 0xff,
        block.length & 0xff,
      ]);
      if (block.source case final sourceBlock?) {
        await _copyRange(
          source,
          output,
          start: sourceBlock.payloadOffset,
          length: sourceBlock.length,
        );
      } else {
        await output.writeFrom(block.payload!);
      }
    }
    await _copyRange(
      source,
      output,
      start: plan.audioStart,
      length: plan.audioLength,
    );
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
      throw const FileSystemException('FLAC file ended unexpectedly while copying.');
    }
    await output.writeFrom(chunk);
    remaining -= chunk.length;
  }
}

bool _matchesFlacMarker(List<int> bytes) {
  return bytes.length == 4 &&
      bytes[0] == 0x66 &&
      bytes[1] == 0x4c &&
      bytes[2] == 0x61 &&
      bytes[3] == 0x43;
}

bool _isEditableComment(String comment) {
  final separator = comment.indexOf('=');
  if (separator <= 0) {
    return false;
  }
  return _editableCommentKeys.contains(
    comment.substring(0, separator).toUpperCase(),
  );
}

int _uint24(List<int> bytes, int offset) {
  return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
}

int _uint32Le(List<int> bytes, int offset) {
  if (offset + 4 > bytes.length) {
    throw const FormatException('FLAC Vorbis comment field is truncated.');
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

const _vorbisCommentBlockType = 4;
const _editableCommentKeys = <String>{
  'TITLE',
  'ARTIST',
  'ALBUM',
  'ALBUMARTIST',
  'DATE',
  'YEAR',
  'TRACKNUMBER',
  'GENRE',
};
