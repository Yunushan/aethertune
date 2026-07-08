import 'library_store.dart';
import 'offline_cache_manager.dart';

Future<OfflineCacheEvictionResult> enforceOfflineCacheLimit({
  required LibraryStore library,
  required OfflineCacheManager manager,
}) async {
  final result = await manager.evictToSize(
    entries: library.offlineCacheQueue,
    maxBytes: library.offlineCacheLimitBytes,
  );
  if (result.evictedEntryIds.isEmpty) {
    return result;
  }

  final reason = 'Evicted automatically to keep cache under '
      '${library.offlineCacheLimitMegabytes} MB.';
  for (final entryId in result.evictedEntryIds) {
    await library.markOfflineCacheEntryEvicted(entryId, reason: reason);
  }

  return result;
}
