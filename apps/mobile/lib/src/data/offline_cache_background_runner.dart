import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'library_store.dart';
import 'offline_cache_background_scheduler.dart';
import 'offline_cache_queue_worker.dart';
import 'podcast_subscription_refresh_worker.dart';
import 'self_hosted_provider_store.dart';

/// Runs a persisted Android or iOS background scheduler pass after foreground
/// processing has been stopped.
Future<void> runOfflineCacheBackgroundQueue() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = OfflineCacheBackgroundScheduler();
  var hasPendingWork = true;
  Duration? nextRunDelay;
  PodcastRefreshReport? podcastReport;

  try {
    final library = LibraryStore();
    await library.load();
    if (library.automaticOfflineQueueEnabled && !library.offlineModeEnabled) {
      podcastReport = await refreshDuePodcastSubscriptionsInBackground(
        library,
      );
      final providers = SelfHostedProviderStore();
      await providers.load();
      final root = await getApplicationDocumentsDirectory();
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: providers.resolveTrack,
      );
      await worker.processPending(library);
    }
    hasPendingWork =
        library.automaticOfflineQueueEnabled &&
        !library.offlineModeEnabled &&
        library.hasPendingOfflineCacheWork;
    if (!hasPendingWork &&
        library.automaticOfflineQueueEnabled &&
        !library.offlineModeEnabled) {
      nextRunDelay = library.nextPodcastSubscriptionRefreshDelay(
        DateTime.now(),
      );
      if (podcastReport != null && podcastReport.failedCount > 0) {
        nextRunDelay = const Duration(hours: 1);
      }
    }
  } on Object {
    // Ask JobScheduler to apply its bounded exponential backoff. Queue entries
    // retain their own error reason once the worker has a chance to process.
    hasPendingWork = true;
  } finally {
    try {
      await scheduler.complete(
        hasPendingWork: hasPendingWork,
        nextRunDelay: nextRunDelay,
      );
    } on MissingPluginException {
      // This entry point is meaningful only for a native background scheduler.
    }
  }
}

/// Refreshes due RSS feeds within an already-authorized native background
/// pass. The worker itself rejects offline mode before making any request.
Future<PodcastRefreshReport> refreshDuePodcastSubscriptionsInBackground(
  LibraryStore library, {
  PodcastSubscriptionRefreshWorker? worker,
}) {
  return (worker ?? PodcastSubscriptionRefreshWorker()).refreshDue(library);
}
