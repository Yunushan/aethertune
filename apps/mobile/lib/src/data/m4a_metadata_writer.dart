import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class M4aMetadataWriter {
  const M4aMetadataWriter();

  Future<void> write({
    required String path,
    required String title,
    required String artist,
    required String album,
    required String genre,
  }) async {
    if (!path.toLowerCase().endsWith('.m4a')) {
      throw const FormatException('Only local M4A files can be updated.');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('The M4A file no longer exists.', path);
    }

    final plan = await _buildWritePlan(
      file,
      title: title,
      artist: artist,
      album: album,
      genre: genre,
    );
    await _replaceWithTaggedCopy(file, plan);
  }
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
  required String title,
  required String artist,
  required String album,
  required String genre,
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
    if (mediaAtoms.isEmpty || mediaAtoms.any((atom) => atom.start > moov.start)) {
      throw const FormatException(
        'Only M4A files with media data before moov can be safely updated.',
      );
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

    return _M4aWritePlan(
      atoms: atoms,
      moov: _updatedMoov(
        Uint8List.fromList(payload),
        title: title,
        artist: artist,
        album: album,
        genre: genre,
      ),
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
    final size = _uint32(header, 0);
    if (size < 8 || size == 1 || offset + size > fileLength) {
      throw const FormatException('M4A uses an unsupported top-level atom size.');
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
  required String title,
  required String artist,
  required String album,
  required String genre,
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
  required String title,
  required String artist,
  required String album,
  required String genre,
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
  );

  final output = BytesBuilder(copy: false);
  for (final child in children) {
    if (!_hasAsciiType(child, 'meta')) {
      output.add(payload.sublist(child.start, child.end));
    }
  }
  output.add(updatedMeta);
  return _atom('udta', output.takeBytes());
}

Uint8List _updatedMeta(
  Uint8List payload, {
  required String title,
  required String artist,
  required String album,
  required String genre,
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
  required String title,
  required String artist,
  required String album,
  required String genre,
}) {
  final output = BytesBuilder(copy: false);
  for (final item in _childAtoms(payload)) {
    if (!_isEditableItem(item.type)) {
      output.add(payload.sublist(item.start, item.end));
    }
  }
  if (title.trim().isNotEmpty) {
    output.add(_textItem(_titleType, title));
  }
  if (artist.trim().isNotEmpty) {
    output.add(_textItem(_artistType, artist));
  }
  if (album.trim().isNotEmpty) {
    output.add(_textItem(_albumType, album));
  }
  if (genre.trim().isNotEmpty) {
    output.add(_textItem(_genreType, genre));
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

bool _isEditableItem(List<int> type) {
  return _sameBytes(type, _titleType) ||
      _sameBytes(type, _artistType) ||
      _sameBytes(type, _albumType) ||
      _sameBytes(type, _genreType);
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

int _uint32(List<int> bytes, int offset) {
  if (offset + 4 > bytes.length) {
    throw const FormatException('M4A integer field is truncated.');
  }
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

const _maxMoovBytes = 4 * 1024 * 1024;
const _maxTopLevelAtoms = 512;
const _maxChildAtoms = 1024;
const _copyChunkBytes = 64 * 1024;
const _titleType = <int>[0xa9, 0x6e, 0x61, 0x6d];
const _artistType = <int>[0xa9, 0x41, 0x52, 0x54];
const _albumType = <int>[0xa9, 0x61, 0x6c, 0x62];
const _genreType = <int>[0xa9, 0x67, 0x65, 0x6e];
