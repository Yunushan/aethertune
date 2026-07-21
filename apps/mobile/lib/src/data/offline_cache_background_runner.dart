import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'library_store.dart';
import 'offline_cache_background_scheduler.dart';
import 'offline_cache_queue_worker.dart';
import 'self_hosted_provider_store.dart';

/// Runs a persisted Android JobScheduler pass after the foreground activity
/// has been stopped.
Future<void> runOfflineCacheBackgroundQueue() async {
  WidgetsFlutterBinding.ensureInitialized();
  final scheduler = OfflineCacheBackgroundScheduler();
  var hasPendingWork = true;

  try {
    final library = LibraryStore();
    await library.load();
    if (library.automaticOfflineQueueEnabled && !library.offlineModeEnabled) {
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
  } on Object {
    // Ask JobScheduler to apply its bounded exponential backoff. Queue entries
    // retain their own error reason once the worker has a chance to process.
    hasPendingWork = true;
  } finally {
    try {
      await scheduler.complete(hasPendingWork: hasPendingWork);
    } on MissingPluginException {
      // This entry point is meaningful only for the Android job service.
    }
  }
}
