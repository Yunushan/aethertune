import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/podcast_chapter_host_policy.dart';
import '../../data/podcast_subscription_refresh_worker.dart';
import 'desktop_background_work_policy.dart';

typedef PodcastRefreshRunner =
    Future<PodcastRefreshReport> Function(LibraryStore library);

class PodcastRssRefreshWorker extends StatefulWidget {
  PodcastRssRefreshWorker({
    super.key,
    required this.child,
    this.runRefresh,
    TargetPlatform? platform,
  }) : platform = platform ?? defaultTargetPlatform;

  final Widget child;
  final PodcastRefreshRunner? runRefresh;
  final TargetPlatform platform;

  @override
  State<PodcastRssRefreshWorker> createState() =>
      _PodcastRssRefreshWorkerState();
}

class _PodcastRssRefreshWorkerState extends State<PodcastRssRefreshWorker>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _refreshing = false;
  late final PodcastRefreshRunner _runRefresh;

  @override
  void initState() {
    super.initState();
    _runRefresh = widget.runRefresh ??
        PodcastSubscriptionRefreshWorker(
          isExternalChapterUriApproved:
              context.read<PodcastChapterHostPolicy>().allows,
        ).refreshDue;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _runIfDue());
    WidgetsBinding.instance.addPostFrameCallback((_) => _runIfDue());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        shouldKeepBackgroundWorkInDesktopProcess(
          platform: widget.platform,
          state: state,
        )) {
      _runIfDue();
    }
  }

  void _runIfDue() {
    if (!mounted || _refreshing) {
      return;
    }
    final library = context.read<LibraryStore>();
    if (!library.loaded || library.offlineModeEnabled) {
      return;
    }
    unawaited(_run(library));
  }

  Future<void> _run(LibraryStore library) async {
    _refreshing = true;
    try {
      await _runRefresh(library);
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    if (library.loaded && !library.offlineModeEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runIfDue());
    }
    return widget.child;
  }
}
