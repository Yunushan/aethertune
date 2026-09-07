import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/listenbrainz_scrobbling_store.dart';
import '../../data/offline_cache_background_scheduler.dart';
import '../../data/offline_cache_queue_worker.dart';
import '../../data/self_hosted_provider_store.dart';
import 'desktop_background_work_policy.dart';

/// True when a desktop AetherTune process should keep its automatic queue
/// moving after its window is hidden or minimized to the system tray.
///
/// This deliberately excludes [AppLifecycleState.detached]: the process is
/// ending, so desktop has no operating-system job that can safely continue it.
bool shouldKeepOfflineQueueProcessingInProcess({
  required TargetPlatform platform,
  required AppLifecycleState state,
}) {
  return shouldKeepBackgroundWorkInDesktopProcess(
    platform: platform,
    state: state,
  );
}

class OfflineCacheForegroundWorker extends StatefulWidget {
  OfflineCacheForegroundWorker({
    super.key,
    required this.child,
    OfflineCacheBackgroundScheduler? backgroundScheduler,
    TargetPlatform? platform,
    this.createWorker,
  }) : backgroundScheduler =
           backgroundScheduler ?? OfflineCacheBackgroundScheduler(),
       platform = platform ?? defaultTargetPlatform;

  final Widget child;
  final OfflineCacheBackgroundScheduler backgroundScheduler;
  final TargetPlatform platform;
  final Future<OfflineCacheQueueWorker> Function()? createWorker;

  @override
  State<OfflineCacheForegroundWorker> createState() =>
      _OfflineCacheForegroundWorkerState();
}

class _OfflineCacheForegroundWorkerState
    extends State<OfflineCacheForegroundWorker>
    with WidgetsBindingObserver {
  Timer? _timer;
  OfflineCacheQueueWorker? _worker;
  Future<void>? _activeRun;
  Future<void> _lifecycleTail = Future<void>.value();
  int _lifecycleGeneration = 0;
  bool _transitioning = true;
  bool _ready = false;
  bool _appInForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _appInForeground =
        state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive ||
        shouldKeepOfflineQueueProcessingInProcess(
          platform: widget.platform,
          state: state,
        );
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _processNext());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _queueLifecycleTransition(reload: false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _worker?.stop();
    _lifecycleGeneration++;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final wasInForeground = _appInForeground;
      _appInForeground = true;
      if (wasInForeground) {
        _processNext();
      } else {
        _queueLifecycleTransition();
      }
    } else if (shouldKeepOfflineQueueProcessingInProcess(
      platform: widget.platform,
      state: state,
    )) {
      _appInForeground = true;
      _processNext();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      _worker?.stop();
      _queueLifecycleTransition();
    }
  }

  void _processNext() {
    if (!mounted ||
        !_appInForeground ||
        _transitioning ||
        !_ready ||
        _activeRun != null) {
      return;
    }
    final library = context.read<LibraryStore>();
    if (!library.loaded ||
        library.saveError != null ||
        !library.automaticOfflineQueueEnabled ||
        library.offlineModeEnabled ||
        !library.hasPendingOfflineCacheWork) {
      return;
    }
    final run = _run(library);
    _activeRun = run;
    unawaited(
      run.whenComplete(() {
        if (identical(_activeRun, run)) _activeRun = null;
      }),
    );
  }

  void _queueLifecycleTransition({bool reload = true}) {
    if (!mounted) return;
    final generation = ++_lifecycleGeneration;
    _transitioning = true;
    _ready = false;
    final library = context.read<LibraryStore>();
    bool current() => mounted && generation == _lifecycleGeneration;
    _lifecycleTail = _lifecycleTail
        .then((_) async {
          if (!current()) return;
          await _activeRun;
          if (!current()) return;
          if (_appInForeground) {
            await _cancelBackgroundJob();
            if (!current()) return;
            // A headless engine can have committed a newer snapshot while this
            // window was paused. Never resume work using its old revision.
            if (reload && library.loaded) await library.reloadSavedLibrary();
          } else {
            await library.requeueProcessingOfflineCacheEntriesForBackground();
            if (!current()) return;
            await _syncBackgroundJob(library);
          }
          if (current()) _ready = true;
        })
        .catchError((Object error, StackTrace stack) {
          _reportError(error, stack);
        })
        .whenComplete(() {
          if (current()) {
            _transitioning = false;
            if (_appInForeground) _processNext();
          }
        });
  }

  Future<void> _cancelBackgroundJob() async {
    await widget.backgroundScheduler.cancel();
  }

  Future<void> _syncBackgroundJob(LibraryStore library) async {
    if (!widget.backgroundScheduler.isSupported) return;
    try {
      final listenBrainz = context.read<ListenBrainzScrobblingStore?>();
      final canRetryListenBrainz =
          listenBrainz != null &&
          shouldRetryListenBrainzInBackground(
            isConfigured: listenBrainz.isConfigured,
            backgroundRetryEnabled: listenBrainz.backgroundRetryEnabled,
            hasPendingListens: listenBrainz.pendingListenCount > 0,
            offlineModeEnabled: library.offlineModeEnabled,
            pauseListeningHistory: library.pauseListeningHistory,
          );
      if (!library.loaded ||
          library.saveError != null ||
          _appInForeground ||
          library.offlineModeEnabled) {
        await widget.backgroundScheduler.cancel();
        return;
      }

      final podcastDelay = library.nextPodcastSubscriptionRefreshDelay(
        DateTime.now(),
      );
      final hasAutomaticOfflineWork =
          library.automaticOfflineQueueEnabled &&
          (library.hasPendingOfflineCacheWork || podcastDelay != null);
      if (!hasAutomaticOfflineWork && !canRetryListenBrainz) {
        await widget.backgroundScheduler.cancel();
        return;
      }

      final accepted = await widget.backgroundScheduler.schedule(
        minimumLatency:
            library.hasPendingOfflineCacheWork || canRetryListenBrainz
            ? null
            : podcastDelay,
      );
      if (!accepted) {
        throw StateError('The native scheduler did not accept offline work.');
      }
    } on MissingPluginException {
      // Desktop and test engines have no native scheduler channel.
    }
  }

  Future<void> _run(LibraryStore library) async {
    try {
      final customWorker = await widget.createWorker?.call();
      final root = customWorker == null
          ? await getApplicationDocumentsDirectory()
          : null;
      if (!mounted || !_appInForeground || _transitioning) {
        customWorker?.stop();
        return;
      }
      final worker =
          customWorker ??
          OfflineCacheQueueWorker(
            cacheRoot: root!,
            resolveTrack: context.read<SelfHostedProviderStore>().resolveTrack,
          );
      _worker = worker;
      await worker.processPending(library);
    } on Object catch (error, stack) {
      // Storage/platform failures must reach diagnostics without escaping an
      // unawaited lifecycle callback or causing a rebuild-driven retry loop.
      _ready = false;
      _reportError(error, stack);
    } finally {
      _worker = null;
    }
  }

  void _reportError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'offline cache foreground worker',
        context: ErrorDescription('while coordinating offline background work'),
      ),
    );
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
