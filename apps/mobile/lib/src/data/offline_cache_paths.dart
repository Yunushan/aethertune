import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/offline_cache_entry.dart';

/// Restricts cache operations to regular files immediately inside our directory.
final class OfflineCachePaths {
  OfflineCachePaths(this.root);

  final Directory root;

  Directory get mediaDirectory =>
      Directory(p.join(root.path, 'aethertune', 'offline_media'));

  static String fileStem(String id) {
    OfflineCacheEntry.validateId(id);
    // Keep lowercase legacy names. Mixed-case IDs must not alias each other
    // on Windows and other case-insensitive native filesystems.
    if (id.length <= 128 &&
        id == id.toLowerCase() &&
        !RegExp(r'^cache-[a-f0-9]{64}$').hasMatch(id) &&
        !RegExp(
          r'^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])$',
          caseSensitive: false,
        ).hasMatch(id)) {
      return id;
    }
    return 'cache-${sha256.convert(utf8.encode(id))}';
  }

  Future<String> verifyDirectory({bool create = false}) async {
    if (create) {
      await root.create(recursive: true);
    }
    var canonical = await root.resolveSymbolicLinks();
    var directory = root.absolute;
    for (final name in ['aethertune', 'offline_media']) {
      directory = Directory(p.join(directory.path, name));
      var type = await FileSystemEntity.type(
        directory.path,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound && create) {
        await directory.create();
        type = await FileSystemEntity.type(directory.path, followLinks: false);
      }
      canonical = p.join(canonical, name);
      if (type != FileSystemEntityType.directory ||
          !p.equals(await directory.resolveSymbolicLinks(), canonical)) {
        throw StateError('Offline cache directory must not contain links.');
      }
    }
    return canonical;
  }

  bool containsPath(File file) => p.equals(
    p.dirname(p.normalize(file.absolute.path)),
    p.normalize(mediaDirectory.absolute.path),
  );

  Future<void> verifyDestination(File file) async {
    if (!containsPath(file)) {
      throw StateError('File is outside the private offline cache.');
    }
    final canonicalDirectory = await verifyDirectory();
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type != FileSystemEntityType.file ||
        !p.equals(
          await file.resolveSymbolicLinks(),
          p.join(canonicalDirectory, p.basename(file.path)),
        )) {
      throw StateError('Offline cache files must not be links or directories.');
    }
  }

  Future<bool> containsRegularFile(File file) async {
    if (!containsPath(file)) {
      return false;
    }
    try {
      await verifyDestination(file);
      return await file.exists();
    } on FileSystemException {
      return false;
    } on StateError {
      return false;
    }
  }

  Future<void> deleteFile(File file) async {
    await verifyDestination(file);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
