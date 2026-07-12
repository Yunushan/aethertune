import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/offline_cache_queue_worker.dart';
import '../../data/self_hosted_provider_store.dart';

class OfflineCacheForegroundWorker extends StatefulWidget {
  const OfflineCacheForegroundWorker({super.key, required this.child});

  final Widget child;

  @override
  State<OfflineCacheForegroundWorker> createState() =>
      _OfflineCacheForegroundWorkerState();
}

class _OfflineCacheForegroundWorkerState extends State<OfflineCacheForegroundWorker>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _processing = false;

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
      _processNext();
    }
  }

  void _processNext() {
    if (!mounted || _processing) {
      return;
    }
    final library = context.read<LibraryStore>();
    if (!library.loaded ||
        !library.automaticOfflineQueueEnabled ||
        library.offlineModeEnabled) {
      return;
    }
    unawaited(_run(library));
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
      await worker.processNext(library);
    } finally {
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LibraryStore>();
    return widget.child;
  }
}
