import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const maxTrackArtworkBytes = 10 * 1024 * 1024;

class TrackArtworkFileStore {
  TrackArtworkFileStore({
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documentsDirectory;

  Future<Uri> save(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.lengthInBytes > maxTrackArtworkBytes) {
      throw const FormatException('Artwork must be an image smaller than 10 MiB.');
    }

    final extension = _imageExtension(bytes);
    if (extension == null) {
      throw const FormatException('Choose a PNG, JPEG, GIF, or WebP image.');
    }

    final root = await _rootDirectory();
    await root.create(recursive: true);
    final digest = sha256.convert(bytes).toString();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final destination = File(
      p.join(root.path, '$stamp-${digest.substring(0, 12)}.$extension'),
    );
    final temporary = File('${destination.path}.part');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(destination.path);
    return Uri.file(destination.path);
  }

  Future<void> delete(Uri? uri) async {
    if (uri == null || uri.scheme != 'file') {
      return;
    }
    final root = await _rootDirectory();
    final candidate = File(uri.toFilePath());
    final rootPath = p.normalize(root.path);
    final candidatePath = p.normalize(candidate.path);
    if (!p.isWithin(rootPath, candidatePath)) {
      return;
    }
    if (await candidate.exists()) {
      await candidate.delete();
    }
  }

  Future<Directory> _rootDirectory() async {
    final documents = await _documentsDirectory();
    return Directory(p.join(documents.path, 'track_artwork'));
  }
}

String? _imageExtension(Uint8List bytes) {
  if (bytes.lengthInBytes >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'png';
  }
  if (bytes.lengthInBytes >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpg';
  }
  if (bytes.lengthInBytes >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38 &&
      (bytes[4] == 0x37 || bytes[4] == 0x39) &&
      bytes[5] == 0x61) {
    return 'gif';
  }
  if (bytes.lengthInBytes >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return null;
}
