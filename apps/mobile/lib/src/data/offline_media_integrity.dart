import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/offline_cache_cancellation.dart';

final class OfflineMediaInspection {
  const OfflineMediaInspection(
    this.byteCount,
    this.checksum,
    this.expectedChecksumVerified,
  );

  final int byteCount;
  final String checksum;
  final bool expectedChecksumVerified;
}

final class OfflineMediaSizeLimitExceeded implements Exception {
  const OfflineMediaSizeLimitExceeded(this.maxBytes);

  final int maxBytes;

  @override
  String toString() => 'Offline media exceeds the $maxBytes byte limit.';
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<OfflineMediaInspection> inspectOfflineMedia(
  File file, {
  String? expectedChecksum,
  int? maxBytes,
  OfflineCacheCancellationToken? cancellationToken,
}) async {
  final expected = expectedChecksum?.trim().toLowerCase();
  final separator = expected?.indexOf(':') ?? -1;
  final algorithm = separator > 0 ? expected!.substring(0, separator) : '';
  final hash = switch (algorithm) {
    'md5' => md5,
    'sha1' => sha1,
    'sha256' => sha256,
    _ => null,
  };
  final digest = _DigestSink();
  final sink = hash?.startChunkedConversion(digest);
  final checksum = OfflineMediaChecksum();
  var byteCount = 0;
  try {
    await for (final chunk in file.openRead()) {
      cancellationToken?.throwIfCancelled();
      byteCount += chunk.length;
      if (maxBytes != null && byteCount > maxBytes) {
        throw OfflineMediaSizeLimitExceeded(maxBytes);
      }
      checksum.add(chunk);
      sink?.add(chunk);
    }
  } finally {
    sink?.close();
  }
  return OfflineMediaInspection(
    byteCount,
    checksum.value,
    digest.value != null &&
        digest.value.toString() == expected!.substring(separator + 1),
  );
}

/// Incremental FNV-1a, retaining the persisted/native-export checksum format.
final class OfflineMediaChecksum {
  int _hash = 0x811c9dc5;

  void add(List<int> bytes) {
    for (final byte in bytes) {
      _hash = (_hash ^ (byte & 0xff)).toUnsigned(32);
      _hash = (_hash * 0x01000193).toUnsigned(32);
    }
  }

  String get value => _hash.toRadixString(16).padLeft(8, '0');
}
