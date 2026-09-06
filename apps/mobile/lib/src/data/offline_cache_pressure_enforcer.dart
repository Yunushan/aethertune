import 'library_store.dart';
import 'offline_cache_manager.dart';

OfflineCacheBudget offlineCacheBudget(
  LibraryStore library,
) => OfflineCacheBudget(
  totalBytes: library.offlineCacheLimitBytes,
  entries: library.offlineCacheQueue,
  providerBytes: {
    for (final limit in library.offlineCacheProviderLimitMegabytes.entries)
      limit.key: limit.value * 1024 * 1024,
  },
  onEvicted: (ids) async {
    for (final id in ids) {
      await library.markOfflineCacheEntryEvicted(
        id,
        reason:
            'Evicted automatically to reserve space for an offline download.',
      );
    }
  },
);

int offlineCacheTransferLimitBytes(LibraryStore library, String sourceId) {
  final providerLimit = library.offlineCacheProviderLimitBytesFor(sourceId);
  final appLimit = library.offlineCacheLimitBytes;
  return providerLimit != null && providerLimit < appLimit
      ? providerLimit
      : appLimit;
}

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
      skipIfBusy: true,
    );
    if (providerResult.evictedEntryIds.isEmpty) {
      continue;
    }

    final reason =
        'Evicted automatically to keep $sourceId cache under '
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
    skipIfBusy: true,
  );
  if (appResult.evictedEntryIds.isNotEmpty) {
    final reason =
        'Evicted automatically to keep cache under '
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
