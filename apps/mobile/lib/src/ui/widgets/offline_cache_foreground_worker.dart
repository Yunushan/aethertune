import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/offline_cache_background_scheduler.dart';
import '../../data/offline_cache_queue_worker.dart';
import '../../data/self_hosted_provider_store.dart';

/// True when a desktop AetherTune process should keep its automatic queue
/// moving after its window is hidden or minimized to the system tray.
///
/// This deliberately excludes [AppLifecycleState.detached]: the process is
/// ending, so desktop has no operating-system job that can safely continue it.
bool shouldKeepOfflineQueueProcessingInProcess({
  required TargetPlatform platform,
  required AppLifecycleState state,
}) {
  final isDesktop =
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows;
  return isDesktop &&
      (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused);
}

class OfflineCacheForegroundWorker extends StatefulWidget {
  OfflineCacheForegroundWorker({
    super.key,
    required this.child,
    OfflineCacheBackgroundScheduler? backgroundScheduler,
    TargetPlatform? platform,
  }) : backgroundScheduler =
           backgroundScheduler ?? OfflineCacheBackgroundScheduler(),
       platform = platform ?? defaultTargetPlatform;

  final Widget child;
  final OfflineCacheBackgroundScheduler backgroundScheduler;
  final TargetPlatform platform;

  @override
  State<OfflineCacheForegroundWorker> createState() =>
      _OfflineCacheForegroundWorkerState();
}

class _OfflineCacheForegroundWorkerState
    extends State<OfflineCacheForegroundWorker>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _processing = false;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _processNext());
    WidgetsBinding.instance.addPostFrameCallback((_) => _processNext());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _processNext();
    } else if (shouldKeepOfflineQueueProcessingInProcess(
      platform: widget.platform,
      state: state,
    )) {
      _appInForeground = true;
      _processNext();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      if (mounted) {
        final library = context.read<LibraryStore>();
        unawaited(_handoffToBackgroundJob(library));
      }
    }
  }

  void _processNext() {
    if (!mounted || _processing) {
      return;
    }
    final library = context.read<LibraryStore>();
    unawaited(_syncBackgroundJob(library));
    if (!library.loaded ||
        !library.automaticOfflineQueueEnabled ||
        library.offlineModeEnabled ||
        !library.hasPendingOfflineCacheWork) {
      return;
    }
    unawaited(_run(library));
  }

  Future<void> _syncBackgroundJob(LibraryStore library) async {
    try {
      if (!library.loaded ||
          _appInForeground ||
          !library.automaticOfflineQueueEnabled ||
          library.offlineModeEnabled) {
        await widget.backgroundScheduler.cancel();
        return;
      }

      final podcastDelay = library.nextPodcastSubscriptionRefreshDelay(
        DateTime.now(),
      );
      if (!library.hasPendingOfflineCacheWork && podcastDelay == null) {
        await widget.backgroundScheduler.cancel();
        return;
      }

      await widget.backgroundScheduler.schedule(
        minimumLatency: library.hasPendingOfflineCacheWork
            ? null
            : podcastDelay,
      );
    } on PlatformException {
      // Foreground queue processing must remain available if a device omits
      // the optional Android wrapper service.
    } on MissingPluginException {
      // Desktop and test engines have no native scheduler channel.
    }
  }

  Future<void> _handoffToBackgroundJob(LibraryStore library) async {
    await library.requeueProcessingOfflineCacheEntriesForBackground();
    await _syncBackgroundJob(library);
  }

  Future<void> _run(LibraryStore library) async {
    _processing = true;
    try {
      final root = await getApplicationDocumentsDirectory();
      if (!mounted) {
        return;
      }
      final resolver = context.read<SelfHostedProviderStore>().resolveTrack;
      final worker = OfflineCacheQueueWorker(
        cacheRoot: root,
        resolveTrack: resolver,
      );
      await worker.processPending(library);
    } finally {
      _processing = false;
      await _syncBackgroundJob(library);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    if (library.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _processNext());
    }
    return widget.child;
  }
}
