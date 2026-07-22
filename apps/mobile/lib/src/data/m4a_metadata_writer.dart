import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/track_chapter.dart';

class M4aMetadataWriter {
  const M4aMetadataWriter();

  Future<void> write({
    required String path,
    required String title,
    required String artist,
    required String album,
    required String genre,
    String? albumArtist,
    int? year,
    int? trackNumber,
    List<TrackChapter>? chapters,
  }) async {
    if (!_isSupportedM4aContainerPath(path)) {
      throw const FormatException(
        'Only local M4A, M4B, or ALAC files can be updated.',
      );
    }
    final file = File(path);
    await _recoverInterruptedReplacement(file);
    if (!await file.exists()) {
      throw FileSystemException(
        'The M4A, M4B, or ALAC file no longer exists.',
        path,
      );
    }

    final plan = await _buildWritePlan(
      file,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      albumArtist: albumArtist,
      year: year,
      trackNumber: trackNumber,
      chapters: _normalizedChapters(chapters),
    );
    await _replaceWithTaggedCopy(file, plan);
  }

  Future<void> writeArtwork({
    required String path,
    required Uint8List artwork,
  }) async {
    if (!_isSupportedM4aContainerPath(path)) {
      throw const FormatException(
        'Only local M4A, M4B, or ALAC files can be updated.',
      );
    }
    if (artwork.isEmpty || artwork.lengthInBytes > maxM4aEmbeddedArtworkBytes) {
      throw const FormatException(
        'M4A, M4B, or ALAC artwork must be a PNG or JPEG smaller than 512 KiB.',
      );
    }
    if (_m4aArtworkDataType(artwork) == null) {
      throw const FormatException(
        'M4A, M4B, or ALAC artwork must be a PNG or JPEG image.',
      );
    }

    final file = File(path);
    await _recoverInterruptedReplacement(file);
    if (!await file.exists()) {
      throw FileSystemException(
        'The M4A, M4B, or ALAC file no longer exists.',
        path,
      );
    }

    final plan = await _buildWritePlan(file, artwork: artwork);
    await _replaceWithTaggedCopy(file, plan);
  }
}

bool _isSupportedM4aContainerPath(String path) {
  final normalized = path.trim().toLowerCase();
  return normalized.endsWith('.m4a') ||
      normalized.endsWith('.m4b') ||
      normalized.endsWith('.m4r') ||
      normalized.endsWith('.alac');
}

class _M4aWritePlan {
  const _M4aWritePlan({required this.atoms, required this.moov});

  final List<_M4aAtom> atoms;
  final Uint8List moov;
}

class _M4aAtom {
  const _M4aAtom({
    required this.start,
    required this.end,
    required this.payloadStart,
    required this.type,
  });

  final int start;
  final int end;
  final int payloadStart;
  final Uint8List type;

  int get length => end - start;
}

Future<_M4aWritePlan> _buildWritePlan(
  File file, {
  String? title,
  String? artist,
  String? album,
  String? genre,
  String? albumArtist,
  int? year,
  int? trackNumber,
  Uint8List? artwork,
  List<TrackChapter>? chapters,
}) async {
  final access = await file.open(mode: FileMode.read);
  try {
    final fileLength = await access.length();
    final atoms = await _readTopLevelAtoms(access, fileLength);
    final moovAtoms = atoms.where((atom) => _hasAsciiType(atom, 'moov')).toList();
    if (moovAtoms.length != 1) {
      throw const FormatException('M4A must contain exactly one editable moov atom.');
    }
    final moov = moovAtoms.single;
    final mediaAtoms = atoms.where((atom) => _hasAsciiType(atom, 'mdat')).toList();
    if (mediaAtoms.isEmpty) {
      throw const FormatException('M4A must contain media data before it can be updated.');
    }

    final payloadLength = moov.end - moov.payloadStart;
    if (payloadLength > _maxMoovBytes) {
      throw const FormatException('M4A moov metadata is too large to update safely.');
    }
    await access.setPosition(moov.payloadStart);
    final payload = await access.read(payloadLength);
    if (payload.length != payloadLength) {
      throw const FormatException('M4A moov metadata could not be read completely.');
    }

    var updatedMoov = _updatedMoov(
      Uint8List.fromList(payload),
      title: title,
      artist: artist,
      album: album,
      genre: genre,
      albumArtist: albumArtist,
      year: year,
      trackNumber: trackNumber,
      artwork: artwork,
      chapters: chapters,
    );
    final movedMediaAtoms = mediaAtoms
        .where((atom) => atom.start > moov.start)
        .toList(growable: false);
    final offsetDelta = updatedMoov.length - moov.length;
    if (movedMediaAtoms.isNotEmpty && offsetDelta != 0) {
      if (atoms.any((atom) => _hasAsciiType(atom, 'moof'))) {
        throw const FormatException(
          'Fragmented M4A layouts cannot be updated safely.',
        );
      }
      updatedMoov = _shiftMdatChunkOffsets(
        updatedMoov,
        offsetDelta: offsetDelta,
        movedMediaAtoms: movedMediaAtoms,
      );
    }

    return _M4aWritePlan(
      atoms: atoms,
      moov: updatedMoov,
    );
  } finally {
    await access.close();
  }
}

Future<List<_M4aAtom>> _readTopLevelAtoms(
  RandomAccessFile access,
  int fileLength,
) async {
  final atoms = <_M4aAtom>[];
  var offset = 0;
  while (offset < fileLength) {
    if (offset + 8 > fileLength || atoms.length >= _maxTopLevelAtoms) {
      throw const FormatException('M4A top-level atom layout is invalid.');
    }
    await access.setPosition(offset);
    final header = await access.read(8);
    if (header.length != 8) {
      throw const FormatException('M4A atom header could not be read completely.');
    }
    final declaredSize = _uint32(header, 0);
    if (declaredSize == 1) {
      throw const FormatException('M4A uses an unsupported top-level atom size.');
    }
    // ISO BMFF permits a zero size only for the final atom, where it means
    // that atom extends to end of file. Retaining that header is safe because
    // the tagged copy preserves the atom as the final top-level atom.
    final size = declaredSize == 0 ? fileLength - offset : declaredSize;
    if (size < 8 || offset + size > fileLength) {
      throw const FormatException('M4A top-level atom layout is invalid.');
    }
    atoms.add(
      _M4aAtom(
        start: offset,
        end: offset + size,
        payloadStart: offset + 8,
        type: Uint8List.fromList(header.sublist(4, 8)),
      ),
    );
    offset += size;
  }
  return atoms;
}

Uint8List _updatedMoov(
  Uint8List payload, {
  String? title,
  String? artist,
  String? album,
  String? genre,
  String? albumArtist,
  int? year,
  int? trackNumber,
  Uint8List? artwork,
  List<TrackChapter>? chapters,
}) {
  final moovChildren = _childAtoms(payload);
  final udtaAtoms = moovChildren.where((atom) => _hasAsciiType(atom, 'udta')).toList();
  if (udtaAtoms.length > 1) {
    throw const FormatException('M4A contains multiple udta metadata atoms.');
  }
  final udtaPayload = udtaAtoms.isEmpty
      ? Uint8List(0)
      : Uint8List.fromList(payload.sublist(udtaAtoms.single.payloadStart, udtaAtoms.single.end));
  final updatedUdta = _updatedUdta(
    udtaPayload,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    albumArtist: albumArtist,
    year: year,
    trackNumber: trackNumber,
    artwork: artwork,
    chapters: chapters,
  );

  final output = BytesBuilder(copy: false);
  for (final child in moovChildren) {
    if (!_hasAsciiType(child, 'udta')) {
      output.add(payload.sublist(child.start, child.end));
    }
  }
  output.add(updatedUdta);
  return _atom('moov', output.takeBytes());
}

Uint8List _updatedUdta(
  Uint8List payload, {
  String? title,
  String? artist,
  String? album,
  String? genre,
  String? albumArtist,
  int? year,
  int? trackNumber,
  Uint8List? artwork,
  List<TrackChapter>? chapters,
}) {
  final children = _childAtoms(payload);
  final metaAtoms = children.where((atom) => _hasAsciiType(atom, 'meta')).toList();
  if (metaAtoms.length > 1) {
    throw const FormatException('M4A contains multiple meta metadata atoms.');
  }
  final metaPayload = metaAtoms.isEmpty
      ? Uint8List(0)
      : Uint8List.fromList(payload.sublist(metaAtoms.single.payloadStart, metaAtoms.single.end));
  final updatedMeta = _updatedMeta(
    metaPayload,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    albumArtist: albumArtist,
    year: year,
    trackNumber: trackNumber,
    artwork: artwork,
  );

  final output = BytesBuilder(copy: false);
  for (final child in children) {
    if (!_hasAsciiType(child, 'meta') &&
        !(chapters != null && _hasAsciiType(child, 'chpl'))) {
      output.add(payload.sublist(child.start, child.end));
    }
  }
  output.add(updatedMeta);
  if (chapters != null && chapters.isNotEmpty) {
    output.add(_chapterListAtom(chapters));
  }
  return _atom('udta', output.takeBytes());
}

Uint8List _updatedMeta(
  Uint8List payload, {
  String? title,
  String? artist,
  String? album,
  String? genre,
  String? albumArtist,
  int? year,
  int? trackNumber,
  Uint8List? artwork,
}) {
  if (payload.isNotEmpty && payload.length < 4) {
    throw const FormatException('M4A meta atom is missing full-box flags.');
  }
  final flags = payload.isEmpty ? Uint8List(4) : Uint8List.fromList(payload.sublist(0, 4));
  final children = _childAtoms(payload, startOffset: 4);
  final ilstAtoms = children.where((atom) => _hasAsciiType(atom, 'ilst')).toList();
  if (ilstAtoms.length > 1) {
    throw const FormatException('M4A contains multiple ilst metadata atoms.');
  }
  final ilstPayload = ilstAtoms.isEmpty
      ? Uint8List(0)
      : Uint8List.fromList(payload.sublist(ilstAtoms.single.payloadStart, ilstAtoms.single.end));
  final updatedIlst = _updatedIlst(
    ilstPayload,
    title: title,
    artist: artist,
    album: album,
    genre: genre,
    albumArtist: albumArtist,
    year: year,
    trackNumber: trackNumber,
    artwork: artwork,
  );

  final output = BytesBuilder(copy: false)..add(flags);
  for (final child in children) {
    if (!_hasAsciiType(child, 'ilst')) {
      output.add(payload.sublist(child.start, child.end));
    }
  }
  output.add(updatedIlst);
  return _atom('meta', output.takeBytes());
}

Uint8List _updatedIlst(
  Uint8List payload, {
  String? title,
  String? artist,
  String? album,
  String? genre,
  String? albumArtist,
  int? year,
  int? trackNumber,
  Uint8List? artwork,
}) {
  final output = BytesBuilder(copy: false);
  for (final item in _childAtoms(payload)) {
    if (!_isEditableItem(
      item.type,
      updateTitle: title != null,
      updateArtist: artist != null,
      updateAlbum: album != null,
      updateGenre: genre != null,
      updateAlbumArtist: albumArtist != null,
      updateYear: year != null,
      updateTrackNumber: trackNumber != null,
      updateArtwork: artwork != null,
    )) {
      output.add(payload.sublist(item.start, item.end));
    }
  }
  if (title != null && title.trim().isNotEmpty) {
    output.add(_textItem(_titleType, title));
  }
  if (artist != null && artist.trim().isNotEmpty) {
    output.add(_textItem(_artistType, artist));
  }
  if (album != null && album.trim().isNotEmpty) {
    output.add(_textItem(_albumType, album));
  }
  if (albumArtist != null && albumArtist.trim().isNotEmpty) {
    output.add(_textItem(_albumArtistType, albumArtist));
  }
  if (year != null && year > 0) {
    output.add(_textItem(_dateType, year.toString()));
  }
  if (trackNumber != null && trackNumber > 0) {
    output.add(_trackNumberItem(trackNumber));
  }
  if (genre != null && genre.trim().isNotEmpty) {
    output.add(_textItem(_genreType, genre));
  }
  if (artwork != null) {
    output.add(_artworkItem(artwork));
  }
  return _atom('ilst', output.takeBytes());
}

List<_M4aAtom> _childAtoms(Uint8List bytes, {int startOffset = 0}) {
  final atoms = <_M4aAtom>[];
  var offset = startOffset;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length || atoms.length >= _maxChildAtoms) {
      throw const FormatException('M4A child atom layout is invalid.');
    }
    final size = _uint32(bytes, offset);
    if (size < 8 || size == 1 || offset + size > bytes.length) {
      throw const FormatException('M4A uses an unsupported child atom size.');
    }
    atoms.add(
      _M4aAtom(
        start: offset,
        end: offset + size,
        payloadStart: offset + 8,
        type: Uint8List.fromList(bytes.sublist(offset + 4, offset + 8)),
      ),
    );
    offset += size;
  }
  return atoms;
}

Uint8List _textItem(List<int> type, String value) {
  final data = BytesBuilder(copy: false)
    ..add(_uint32Bytes(1))
    ..add(const <int>[0, 0, 0, 0])
    ..add(utf8.encode(value.trim()));
  return _atomBytes(type, _atom('data', data.takeBytes()));
}

Uint8List _artworkItem(Uint8List artwork) {
  final dataType = _m4aArtworkDataType(artwork);
  if (dataType == null) {
    throw const FormatException('M4A artwork must be a PNG or JPEG image.');
  }
  final data = BytesBuilder(copy: false)
    ..add(_uint32Bytes(dataType))
    ..add(const <int>[0, 0, 0, 0])
    ..add(artwork);
  return _atom('covr', _atom('data', data.takeBytes()));
}

Uint8List _trackNumberItem(int trackNumber) {
  if (trackNumber <= 0 || trackNumber > 0xffff) {
    throw ArgumentError.value(
      trackNumber,
      'trackNumber',
      'M4A track number must be between 1 and 65535.',
    );
  }
  final data = BytesBuilder(copy: false)
    ..add(_uint32Bytes(0))
    ..add(const <int>[0, 0, 0, 0, 0, 0])
    ..add(<int>[(trackNumber >> 8) & 0xff, trackNumber & 0xff])
    ..add(const <int>[0, 0, 0, 0]);
  return _atom('trkn', _atom('data', data.takeBytes()));
}

List<TrackChapter>? _normalizedChapters(List<TrackChapter>? chapters) {
  if (chapters == null) {
    return null;
  }
  final normalized = TrackChapter.normalize(chapters);
  if (normalized.length > _maxM4aChapters) {
    throw const FormatException('M4A chapter markers exceed the 255-item limit.');
  }
  for (final chapter in normalized) {
    if (utf8.encode(chapter.title).length > 0xff) {
      throw const FormatException('M4A chapter titles must be at most 255 bytes.');
    }
  }
  return normalized;
}

Uint8List _chapterListAtom(List<TrackChapter> chapters) {
  final payload = BytesBuilder(copy: false)
    ..add(const <int>[0, 0, 0, 0])
    ..addByte(chapters.length);
  for (final chapter in chapters) {
    final timestamp = chapter.start.inMicroseconds * _chapterTicksPerMicrosecond;
    if (timestamp < 0 || timestamp > _maxM4aChunkOffset) {
      throw const FormatException('M4A chapter timestamp is out of range.');
    }
    final title = utf8.encode(chapter.title);
    payload
      ..add(_uint64Bytes(timestamp))
      ..addByte(title.length)
      ..add(title);
  }
  return _atom('chpl', payload.takeBytes());
}

Uint8List _uint64Bytes(int value) {
  return Uint8List.fromList(<int>[
    (value >> 56) & 0xff,
    (value >> 48) & 0xff,
    (value >> 40) & 0xff,
    (value >> 32) & 0xff,
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);
}

Uint8List _atom(String type, List<int> payload) {
  return _atomBytes(type.codeUnits, payload);
}

Uint8List _atomBytes(List<int> type, List<int> payload) {
  if (type.length != 4 || payload.length > 0xffffffff - 8) {
    throw const FormatException('M4A atom is too large to update safely.');
  }
  final bytes = BytesBuilder(copy: false)
    ..add(_uint32Bytes(payload.length + 8))
    ..add(type)
    ..add(payload);
  return bytes.takeBytes();
}

Uint8List _shiftMdatChunkOffsets(
  Uint8List moov, {
  required int offsetDelta,
  required List<_M4aAtom> movedMediaAtoms,
}) {
  if (moov.length < 8 || !_matchesAsciiType(moov, 4, 'moov')) {
    throw const FormatException('M4A moov metadata could not be updated safely.');
  }
  final updated = Uint8List.fromList(moov);
  _shiftChunkOffsetContainers(
    updated,
    startOffset: 8,
    endOffset: updated.length,
    offsetDelta: offsetDelta,
    movedMediaAtoms: movedMediaAtoms,
  );
  return updated;
}

void _shiftChunkOffsetContainers(
  Uint8List bytes, {
  required int startOffset,
  required int endOffset,
  required int offsetDelta,
  required List<_M4aAtom> movedMediaAtoms,
  int depth = 0,
}) {
  if (depth > _maxContainerDepth) {
    throw const FormatException('M4A metadata nesting is too deep to update safely.');
  }
  var offset = startOffset;
  var atomCount = 0;
  while (offset < endOffset) {
    if (offset + 8 > endOffset || atomCount >= _maxChildAtoms) {
      throw const FormatException('M4A chunk-offset container layout is invalid.');
    }
    final size = _uint32(bytes, offset);
    if (size < 8 || size == 1 || offset + size > endOffset) {
      throw const FormatException('M4A chunk-offset atom layout is invalid.');
    }
    final payloadStart = offset + 8;
    final atomEnd = offset + size;
    if (_matchesAsciiType(bytes, offset + 4, 'stco')) {
      _shiftStcoOffsets(
        bytes,
        payloadStart: payloadStart,
        payloadEnd: atomEnd,
        offsetDelta: offsetDelta,
        movedMediaAtoms: movedMediaAtoms,
      );
    } else if (_matchesAsciiType(bytes, offset + 4, 'co64')) {
      _shiftCo64Offsets(
        bytes,
        payloadStart: payloadStart,
        payloadEnd: atomEnd,
        offsetDelta: offsetDelta,
        movedMediaAtoms: movedMediaAtoms,
      );
    } else if (_isChunkOffsetContainer(bytes, offset + 4)) {
      var childStart = payloadStart;
      if (_matchesAsciiType(bytes, offset + 4, 'meta')) {
        if (childStart + 4 > atomEnd) {
          throw const FormatException('M4A meta atom is missing full-box flags.');
        }
        childStart += 4;
      }
      _shiftChunkOffsetContainers(
        bytes,
        startOffset: childStart,
        endOffset: atomEnd,
        offsetDelta: offsetDelta,
        movedMediaAtoms: movedMediaAtoms,
        depth: depth + 1,
      );
    }
    offset = atomEnd;
    atomCount += 1;
  }
}

void _shiftStcoOffsets(
  Uint8List bytes, {
  required int payloadStart,
  required int payloadEnd,
  required int offsetDelta,
  required List<_M4aAtom> movedMediaAtoms,
}) {
  if (payloadStart + 8 > payloadEnd) {
    throw const FormatException('M4A stco atom is truncated.');
  }
  final entryCount = _uint32(bytes, payloadStart + 4);
  final entriesStart = payloadStart + 8;
  if (entryCount > (payloadEnd - entriesStart) ~/ 4 ||
      entriesStart + entryCount * 4 != payloadEnd) {
    throw const FormatException('M4A stco atom has an invalid entry count.');
  }
  for (var index = 0; index < entryCount; index += 1) {
    final entryOffset = entriesStart + index * 4;
    final original = _uint32(bytes, entryOffset);
    final updated = _shiftedMediaOffset(original, offsetDelta, movedMediaAtoms);
    if (updated != original) {
      _setUint32(bytes, entryOffset, updated);
    }
  }
}

void _shiftCo64Offsets(
  Uint8List bytes, {
  required int payloadStart,
  required int payloadEnd,
  required int offsetDelta,
  required List<_M4aAtom> movedMediaAtoms,
}) {
  if (payloadStart + 8 > payloadEnd) {
    throw const FormatException('M4A co64 atom is truncated.');
  }
  final entryCount = _uint32(bytes, payloadStart + 4);
  final entriesStart = payloadStart + 8;
  if (entryCount > (payloadEnd - entriesStart) ~/ 8 ||
      entriesStart + entryCount * 8 != payloadEnd) {
    throw const FormatException('M4A co64 atom has an invalid entry count.');
  }
  for (var index = 0; index < entryCount; index += 1) {
    final entryOffset = entriesStart + index * 8;
    final original = _uint64(bytes, entryOffset);
    final updated = _shiftedMediaOffset(original, offsetDelta, movedMediaAtoms);
    if (updated != original) {
      _setUint64(bytes, entryOffset, updated);
    }
  }
}

int _shiftedMediaOffset(
  int original,
  int offsetDelta,
  List<_M4aAtom> movedMediaAtoms,
) {
  final pointsAtMovedMedia = movedMediaAtoms.any(
    (atom) => original >= atom.payloadStart && original < atom.end,
  );
  if (!pointsAtMovedMedia) {
    return original;
  }
  final updated = original + offsetDelta;
  if (updated < 0 || updated > _maxM4aChunkOffset) {
    throw const FormatException('M4A media chunk offset would overflow.');
  }
  return updated;
}

bool _isChunkOffsetContainer(Uint8List bytes, int typeOffset) {
  return _matchesAsciiType(bytes, typeOffset, 'moov') ||
      _matchesAsciiType(bytes, typeOffset, 'trak') ||
      _matchesAsciiType(bytes, typeOffset, 'mdia') ||
      _matchesAsciiType(bytes, typeOffset, 'minf') ||
      _matchesAsciiType(bytes, typeOffset, 'stbl') ||
      _matchesAsciiType(bytes, typeOffset, 'edts') ||
      _matchesAsciiType(bytes, typeOffset, 'dinf') ||
      _matchesAsciiType(bytes, typeOffset, 'udta') ||
      _matchesAsciiType(bytes, typeOffset, 'meta') ||
      _matchesAsciiType(bytes, typeOffset, 'mvex');
}

Future<void> _replaceWithTaggedCopy(File file, _M4aWritePlan plan) async {
  final suffix = DateTime.now().microsecondsSinceEpoch;
  final temporary = File('${file.path}.aethertune-$suffix.part');
  final backup = File('${file.path}.aethertune-$suffix.backup');
  final source = await file.open(mode: FileMode.read);
  final output = await temporary.open(mode: FileMode.write);
  try {
    for (final atom in plan.atoms) {
      if (_hasAsciiType(atom, 'moov')) {
        await output.writeFrom(plan.moov);
      } else {
        await _copyRange(source, output, atom.start, atom.length);
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

/// Restores the original name after an interrupted replacement transaction.
///
/// A single backup is unambiguous. Multiple backups are left untouched rather
/// than selecting an arbitrary potentially stale version of the file.
Future<void> _recoverInterruptedReplacement(File file) async {
  if (await file.exists()) {
    return;
  }

  final parent = file.parent;
  if (!await parent.exists()) {
    return;
  }
  final backupPrefix = '${file.uri.pathSegments.last}.aethertune-';
  final backups = <File>[];
  await for (final entity in parent.list(followLinks: false)) {
    final name = entity.uri.pathSegments.last;
    if (entity is File &&
        name.startsWith(backupPrefix) &&
        name.endsWith('.backup')) {
      backups.add(entity);
    }
  }
  if (backups.isEmpty) {
    return;
  }
  if (backups.length > 1) {
    throw FileSystemException(
      'Multiple interrupted M4A replacement backups require manual recovery.',
      file.path,
    );
  }

  try {
    await backups.single.rename(file.path);
  } on Object {
    throw FileSystemException(
      'Could not restore the interrupted M4A replacement backup.',
      file.path,
    );
  }
}

Future<void> _copyRange(
  RandomAccessFile source,
  RandomAccessFile output,
  int start,
  int length,
) async {
  await source.setPosition(start);
  var remaining = length;
  while (remaining > 0) {
    final chunk = await source.read(remaining > _copyChunkBytes ? _copyChunkBytes : remaining);
    if (chunk.isEmpty) {
      throw const FileSystemException('M4A file ended unexpectedly while copying.');
    }
    await output.writeFrom(chunk);
    remaining -= chunk.length;
  }
}

bool _hasAsciiType(_M4aAtom atom, String type) {
  return atom.type.length == 4 &&
      atom.type[0] == type.codeUnitAt(0) &&
      atom.type[1] == type.codeUnitAt(1) &&
      atom.type[2] == type.codeUnitAt(2) &&
      atom.type[3] == type.codeUnitAt(3);
}

bool _matchesAsciiType(Uint8List bytes, int offset, String type) {
  return offset + 4 <= bytes.length &&
      bytes[offset] == type.codeUnitAt(0) &&
      bytes[offset + 1] == type.codeUnitAt(1) &&
      bytes[offset + 2] == type.codeUnitAt(2) &&
      bytes[offset + 3] == type.codeUnitAt(3);
}

bool _isEditableItem(
  List<int> type, {
  required bool updateTitle,
  required bool updateArtist,
  required bool updateAlbum,
  required bool updateGenre,
  required bool updateAlbumArtist,
  required bool updateYear,
  required bool updateTrackNumber,
  required bool updateArtwork,
}) {
  return (updateTitle && _sameBytes(type, _titleType)) ||
      (updateArtist && _sameBytes(type, _artistType)) ||
      (updateAlbum && _sameBytes(type, _albumType)) ||
      (updateAlbumArtist && _sameBytes(type, _albumArtistType)) ||
      (updateYear && _sameBytes(type, _dateType)) ||
      (updateTrackNumber && _hasAsciiTypeBytes(type, 'trkn')) ||
      (updateGenre && _sameBytes(type, _genreType)) ||
      (updateArtwork && _hasAsciiTypeBytes(type, 'covr'));
}

int? _m4aArtworkDataType(Uint8List bytes) {
  if (bytes.lengthInBytes >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 14;
  }
  if (bytes.lengthInBytes >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 13;
  }
  return null;
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

bool _hasAsciiTypeBytes(List<int> type, String value) {
  return type.length == 4 &&
      type[0] == value.codeUnitAt(0) &&
      type[1] == value.codeUnitAt(1) &&
      type[2] == value.codeUnitAt(2) &&
      type[3] == value.codeUnitAt(3);
}

int _uint32(List<int> bytes, int offset) {
  if (offset + 4 > bytes.length) {
    throw const FormatException('M4A integer field is truncated.');
  }
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

int _uint64(List<int> bytes, int offset) {
  if (offset + 8 > bytes.length) {
    throw const FormatException('M4A 64-bit integer field is truncated.');
  }
  if ((bytes[offset] & 0x80) != 0) {
    throw const FormatException('M4A 64-bit media chunk offset is too large.');
  }
  var value = 0;
  for (var index = 0; index < 8; index += 1) {
    value = (value << 8) | bytes[offset + index];
  }
  return value;
}

Uint8List _uint32Bytes(int value) {
  return Uint8List.fromList(<int>[
    (value >> 24) & 0xff,
    (value >> 16) & 0xff,
    (value >> 8) & 0xff,
    value & 0xff,
  ]);
}

void _setUint32(Uint8List bytes, int offset, int value) {
  if (value < 0 || value > 0xffffffff) {
    throw const FormatException('M4A 32-bit media chunk offset would overflow.');
  }
  bytes[offset] = (value >> 24) & 0xff;
  bytes[offset + 1] = (value >> 16) & 0xff;
  bytes[offset + 2] = (value >> 8) & 0xff;
  bytes[offset + 3] = value & 0xff;
}

void _setUint64(Uint8List bytes, int offset, int value) {
  if (value < 0 || value > _maxM4aChunkOffset) {
    throw const FormatException('M4A 64-bit media chunk offset would overflow.');
  }
  for (var index = 7; index >= 0; index -= 1) {
    bytes[offset + index] = value & 0xff;
    value >>= 8;
  }
}

const _maxMoovBytes = 4 * 1024 * 1024;
const maxM4aEmbeddedArtworkBytes = 512 * 1024;
const _maxTopLevelAtoms = 512;
const _maxChildAtoms = 1024;
const _maxContainerDepth = 32;
const _copyChunkBytes = 64 * 1024;
const _maxM4aChunkOffset = 0x7fffffffffffffff;
const _maxM4aChapters = 255;
const _chapterTicksPerMicrosecond = 10;
const _titleType = <int>[0xa9, 0x6e, 0x61, 0x6d];
const _artistType = <int>[0xa9, 0x41, 0x52, 0x54];
const _albumType = <int>[0xa9, 0x61, 0x6c, 0x62];
const _albumArtistType = <int>[0x61, 0x41, 0x52, 0x54];
const _dateType = <int>[0xa9, 0x64, 0x61, 0x79];
const _genreType = <int>[0xa9, 0x67, 0x65, 0x6e];
