import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'offline_cache_paths.dart';

/// Sidecar identity is bounded and contains no raw signed URLs/credentials.
/// Content without a strong validator restarts unless a provider digest will
/// verify the entire assembled object before publication.
final class OfflineCacheResume {
  OfflineCacheResume(this.paths, this.partial);
  final OfflineCachePaths paths;
  final File partial;
  File get file => File('${partial.path}.resume');

  Future<String?> validator(Uri uri, String? expectedChecksum) async {
    await paths.verifyDestination(file);
    if (!await file.exists()) return null;
    if (await file.length() > 4096) return null;
    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map ||
          data['uriHash'] != _uriHash(uri) ||
          data['expectedChecksum'] != expectedChecksum) {
        return null;
      }
      return strongEtag(data['etag'] is String ? data['etag'] as String : null);
    } on FormatException {
      return null;
    }
  }

  Future<void> write(Uri uri, String? expectedChecksum, String? etag) async {
    await paths.verifyDestination(file);
    await file.writeAsString(
      jsonEncode({
        'uriHash': _uriHash(uri),
        'expectedChecksum': expectedChecksum,
        'etag': strongEtag(etag),
      }),
      flush: true,
    );
  }

  Future<void> delete() => paths.deleteFile(file);

  static String? strongEtag(String? value) {
    if (value == null ||
        value.length > 1024 ||
        !RegExp(r'^"[\x21\x23-\x7e\x80-\xff]*"$').hasMatch(value)) {
      return null;
    }
    return value;
  }
}

String _uriHash(Uri uri) =>
    sha256.convert(utf8.encode(uri.toString())).toString();
