import 'library_store.dart';
import 'offline_cache_manager.dart';

Future<OfflineCacheEvictionResult> enforceOfflineCacheLimit({
  required LibraryStore library,
  required OfflineCacheManager manager,
}) async {
  final initialUsage = await manager.usage(library.offlineCacheQueue);
  final evictedEntryIds = <String>[];
  var evictedBytes = 0;

  for (final providerLimit
      in library.offlineCacheProviderLimitMegabytes.entries) {
    final sourceId = providerLimit.key;
    final providerEntries = library.offlineCacheQueue.where(
      (entry) => entry.track.sourceId.trim().toLowerCase() == sourceId,
    );
    final providerResult = await manager.evictToSize(
      entries: providerEntries,
      maxBytes: providerLimit.value * 1024 * 1024,
    );
    if (providerResult.evictedEntryIds.isEmpty) {
      continue;
    }

    final reason = 'Evicted automatically to keep $sourceId cache under '
        '${providerLimit.value} MB.';
    for (final entryId in providerResult.evictedEntryIds) {
      await library.markOfflineCacheEntryEvicted(entryId, reason: reason);
    }
    evictedEntryIds.addAll(providerResult.evictedEntryIds);
    evictedBytes += providerResult.evictedBytes;
  }

  final appResult = await manager.evictToSize(
    entries: library.offlineCacheQueue,
    maxBytes: library.offlineCacheLimitBytes,
  );
  if (appResult.evictedEntryIds.isNotEmpty) {
    final reason = 'Evicted automatically to keep cache under '
        '${library.offlineCacheLimitMegabytes} MB.';
    for (final entryId in appResult.evictedEntryIds) {
      await library.markOfflineCacheEntryEvicted(entryId, reason: reason);
    }
    evictedEntryIds.addAll(appResult.evictedEntryIds);
    evictedBytes += appResult.evictedBytes;
  }

  final finalUsage = await manager.usage(library.offlineCacheQueue);
  return OfflineCacheEvictionResult(
    bytesBefore: initialUsage.byteCount,
    bytesAfter: finalUsage.byteCount,
    evictedEntryIds: List.unmodifiable(evictedEntryIds),
    evictedBytes: evictedBytes,
  );
}
