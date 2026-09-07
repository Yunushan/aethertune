import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'library_store.dart';
import 'listenbrainz_scrobbling_store.dart';
import 'offline_cache_background_scheduler.dart';
import 'offline_cache_background_session.dart';
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

  try {
    await OfflineCacheBackgroundSession().run((session) async {
      PodcastRefreshReport? podcastReport;
      final library = LibraryStore();
      final listenBrainz = ListenBrainzScrobblingStore();
      SelfHostedProviderStore? providers;
      OfflineCacheQueueWorker? worker;
      try {
        await library.load();
        if (!session.shouldContinue) return;
        if (!library.loaded) {
          throw StateError(
            'The saved library needs recovery before background work can run.',
          );
        }
        await listenBrainz.load();
        if (!session.shouldContinue) return;
        final canRetryListenBrainz = shouldRetryListenBrainzInBackground(
          isConfigured: listenBrainz.isConfigured,
          backgroundRetryEnabled: listenBrainz.backgroundRetryEnabled,
          hasPendingListens: listenBrainz.pendingListenCount > 0,
          offlineModeEnabled: library.offlineModeEnabled,
          pauseListeningHistory: library.pauseListeningHistory,
        );
        if (canRetryListenBrainz) {
          await listenBrainz.retryPendingListens(
            shouldContinue: () => session.shouldContinue,
          );
        }
        if (!session.shouldContinue) return;
        if (library.automaticOfflineQueueEnabled &&
            !library.offlineModeEnabled) {
          podcastReport = await refreshDuePodcastSubscriptionsInBackground(
            library,
            shouldContinue: () => session.shouldContinue,
          );
          if (!session.shouldContinue) return;
          providers = SelfHostedProviderStore();
          await providers.load();
          if (!session.shouldContinue) return;
          final root = await getApplicationDocumentsDirectory();
          if (!session.shouldContinue) return;
          worker = OfflineCacheQueueWorker(
            cacheRoot: root,
            resolveTrack: providers.resolveTrack,
          );
          session.cancelCurrentWith(worker.stop);
          await worker.processPending(library);
        }
        final hasOfflineCacheWork =
            library.automaticOfflineQueueEnabled &&
            !library.offlineModeEnabled &&
            library.hasPendingOfflineCacheWork;
        hasPendingWork =
            hasOfflineCacheWork ||
            shouldRetryListenBrainzInBackground(
              isConfigured: listenBrainz.isConfigured,
              backgroundRetryEnabled: listenBrainz.backgroundRetryEnabled,
              hasPendingListens: listenBrainz.pendingListenCount > 0,
              offlineModeEnabled: library.offlineModeEnabled,
              pauseListeningHistory: library.pauseListeningHistory,
            );
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
      } finally {
        try {
          if (worker != null &&
              !session.shouldContinue &&
              library.saveError == null) {
            await library.requeueProcessingOfflineCacheEntriesForBackground();
          }
        } finally {
          session.cancelCurrentWith(null);
          providers?.dispose();
          listenBrainz.dispose();
          library.dispose();
        }
      }
    });
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
  bool Function()? shouldContinue,
}) {
  return (worker ?? PodcastSubscriptionRefreshWorker()).refreshDue(
    library,
    shouldContinue: shouldContinue,
  );
}
