import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class OggVorbisCommentWriter {
  const OggVorbisCommentWriter();

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
    if (!_isSupportedPath(path)) {
      throw const FormatException(
        'Only local Ogg Vorbis or Opus files can be updated.',
      );
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('The Ogg file no longer exists.', path);
    }

    final access = await file.open(mode: FileMode.read);
    late _OggWritePlan plan;
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

class _OggWritePlan {
  const _OggWritePlan({
    required this.commentPageStart,
    required this.commentPageEnd,
    required this.updatedCommentPage,
  });

  final int commentPageStart;
  final int commentPageEnd;
  final Uint8List updatedCommentPage;
}

class _OggPage {
  const _OggPage({
    required this.start,
    required this.end,
    required this.header,
    required this.lacing,
    required this.body,
  });

  final int start;
  final int end;
  final Uint8List header;
  final Uint8List lacing;
  final Uint8List body;

  int get headerType => header[5];
  int get serial => _uint32Le(header, 14);

  bool get beginsWithContinuedPacket => (headerType & 0x01) != 0;
  bool get isBeginningOfStream => (headerType & 0x02) != 0;

  bool get containsExactlyOneCompletePacket {
    if (lacing.isEmpty) {
      return false;
    }
    var completePackets = 0;
    for (final segment in lacing) {
      if (segment < 255) {
        completePackets += 1;
      }
    }
    return completePackets == 1 && lacing.last < 255;
  }
}

class _VorbisCommentData {
  const _VorbisCommentData({
    required this.vendor,
    required this.nonEditableComments,
  });

  final String vendor;
  final List<String> nonEditableComments;
}

Future<_OggWritePlan> _buildWritePlan(
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
  final identificationPage = await _readOggPage(access, fileLength, 0);
  if (!identificationPage.isBeginningOfStream ||
      identificationPage.beginsWithContinuedPacket ||
      !identificationPage.containsExactlyOneCompletePacket) {
    throw const FormatException(
      'Only standard single-page Ogg/Opus headers can be updated.',
    );
  }

  final codec = _codecForIdentificationPacket(identificationPage.body);
  if (codec == null) {
    throw const FormatException('File is not an Ogg Vorbis or Opus stream.');
  }

  final commentPage = await _readOggPage(
    access,
    fileLength,
    identificationPage.end,
  );
  if (commentPage.serial != identificationPage.serial ||
      commentPage.isBeginningOfStream ||
      commentPage.beginsWithContinuedPacket ||
      !commentPage.containsExactlyOneCompletePacket) {
    throw const FormatException(
      'Only an isolated Ogg/Opus comment page can be updated safely.',
    );
  }

  final prefix = codec == _OggCodec.vorbis
      ? const <int>[3, 0x76, 0x6f, 0x72, 0x62, 0x69, 0x73]
      : const <int>[0x4f, 0x70, 0x75, 0x73, 0x54, 0x61, 0x67, 0x73];
  if (!_startsWithBytes(commentPage.body, prefix)) {
    throw const FormatException('Ogg/Opus comment packet is missing.');
  }

  final comments = _parseVorbisComments(commentPage.body.sublist(prefix.length));
  final updatedPacket = Uint8List.fromList(<int>[
    ...prefix,
    ..._updatedVorbisComments(
      vendor: comments.vendor,
      retainedComments: comments.nonEditableComments,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      albumArtist: albumArtist,
      year: year,
      trackNumber: trackNumber,
    ),
  ]);
  final lacing = _packetLacing(updatedPacket.length);
  if (lacing.length > 255) {
    throw const FormatException('Updated Ogg/Opus comment packet is too large.');
  }

  return _OggWritePlan(
    commentPageStart: commentPage.start,
    commentPageEnd: commentPage.end,
    updatedCommentPage: _updatedPage(commentPage, lacing, updatedPacket),
  );
}

Future<_OggPage> _readOggPage(
  RandomAccessFile access,
  int fileLength,
  int start,
) async {
  if (start + 27 > fileLength) {
    throw const FormatException('Ogg page header is incomplete.');
  }
  await access.setPosition(start);
  final header = Uint8List.fromList(await access.read(27));
  if (header.length != 27 ||
      !_startsWithBytes(header, const <int>[0x4f, 0x67, 0x67, 0x53]) ||
      header[4] != 0) {
    throw const FormatException('File does not contain a supported Ogg page.');
  }

  final lacing = Uint8List.fromList(await access.read(header[26]));
  if (lacing.length != header[26]) {
    throw const FormatException('Ogg page lacing values are incomplete.');
  }
  final bodyLength = lacing.fold<int>(0, (total, length) => total + length);
  final bodyStart = start + 27 + lacing.length;
  final end = bodyStart + bodyLength;
  if (end > fileLength) {
    throw const FormatException('Ogg page body exceeds the file length.');
  }
  final body = Uint8List.fromList(await access.read(bodyLength));
  if (body.length != bodyLength) {
    throw const FormatException('Ogg page body could not be read.');
  }

  return _OggPage(
    start: start,
    end: end,
    header: header,
    lacing: lacing,
    body: body,
  );
}

_OggCodec? _codecForIdentificationPacket(List<int> packet) {
  if (_startsWithBytes(packet, const <int>[1, 0x76, 0x6f, 0x72, 0x62, 0x69, 0x73])) {
    return _OggCodec.vorbis;
  }
  if (_startsWithBytes(packet, const <int>[0x4f, 0x70, 0x75, 0x73, 0x48, 0x65, 0x61, 0x64])) {
    return _OggCodec.opus;
  }
  return null;
}

enum _OggCodec { vorbis, opus }

_VorbisCommentData _parseVorbisComments(List<int> bytes) {
  var offset = 0;
  final vendorLength = _uint32Le(bytes, offset);
  offset += 4;
  if (offset + vendorLength > bytes.length) {
    throw const FormatException('Ogg/Opus Vorbis vendor field is invalid.');
  }
  final vendor = utf8.decode(bytes.sublist(offset, offset + vendorLength));
  offset += vendorLength;

  final count = _uint32Le(bytes, offset);
  offset += 4;
  final retained = <String>[];
  for (var index = 0; index < count; index += 1) {
    final length = _uint32Le(bytes, offset);
    offset += 4;
    if (offset + length > bytes.length) {
      throw const FormatException('Ogg/Opus Vorbis comment field is invalid.');
    }
    final comment = utf8.decode(bytes.sublist(offset, offset + length));
    offset += length;
    if (!_isEditableComment(comment)) {
      retained.add(comment);
    }
  }
  if (offset != bytes.length) {
    throw const FormatException('Ogg/Opus comments have trailing data.');
  }
  return _VorbisCommentData(vendor: vendor, nonEditableComments: retained);
}

Uint8List _updatedVorbisComments({
  required String vendor,
  required List<String> retainedComments,
  required String title,
  required String artist,
  required String album,
  required String genre,
  required String? albumArtist,
  required int? year,
  required int? trackNumber,
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
  return output.takeBytes();
}

Uint8List _updatedPage(
  _OggPage original,
  List<int> lacing,
  List<int> body,
) {
  final bytes = BytesBuilder(copy: false)
    ..add(original.header.sublist(0, 22))
    ..add(const <int>[0, 0, 0, 0])
    ..addByte(lacing.length)
    ..add(lacing)
    ..add(body);
  final page = bytes.takeBytes();
  final checksum = _oggChecksum(page);
  page[22] = checksum & 0xff;
  page[23] = (checksum >> 8) & 0xff;
  page[24] = (checksum >> 16) & 0xff;
  page[25] = (checksum >> 24) & 0xff;
  return page;
}

List<int> _packetLacing(int length) {
  if (length < 0) {
    throw const FormatException('Ogg/Opus packet length is invalid.');
  }
  final lacing = <int>[];
  var remaining = length;
  while (remaining >= 255) {
    lacing.add(255);
    remaining -= 255;
  }
  lacing.add(remaining);
  return lacing;
}

Future<void> _replaceWithTaggedCopy(File file, _OggWritePlan plan) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temporary = File('${file.path}.aethertune-$suffix.part');
  final backup = File('${file.path}.aethertune-$suffix.backup');
  final source = await file.open(mode: FileMode.read);
  final output = await temporary.open(mode: FileMode.write);
  try {
    await _copyRange(source, output, start: 0, length: plan.commentPageStart);
    await output.writeFrom(plan.updatedCommentPage);
    final sourceLength = await source.length();
    await _copyRange(
      source,
      output,
      start: plan.commentPageEnd,
      length: sourceLength - plan.commentPageEnd,
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
      throw const FileSystemException('Ogg file ended unexpectedly while copying.');
    }
    await output.writeFrom(chunk);
    remaining -= chunk.length;
  }
}

bool _isSupportedPath(String path) {
  final normalized = path.toLowerCase();
  return normalized.endsWith('.ogg') ||
      normalized.endsWith('.oga') ||
      normalized.endsWith('.opus');
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

bool _startsWithBytes(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index += 1) {
    if (bytes[index] != prefix[index]) {
      return false;
    }
  }
  return true;
}

int _uint32Le(List<int> bytes, int offset) {
  if (offset + 4 > bytes.length) {
    throw const FormatException('Ogg/Opus field is truncated.');
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
