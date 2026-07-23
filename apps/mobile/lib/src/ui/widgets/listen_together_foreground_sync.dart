import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/listen_together_store.dart';
import '../../player/player_controller.dart';
import 'desktop_background_work_policy.dart';

typedef ListenTogetherSynchronizationRunner = Future<void> Function(
  ListenTogetherStore session,
  LibraryStore library,
);

/// Keeps an active shared session current while the app is in the foreground.
class ListenTogetherForegroundSync extends StatefulWidget {
  ListenTogetherForegroundSync({
    super.key,
    required this.child,
    this.runSynchronization,
    TargetPlatform? platform,
  }) : platform = platform ?? defaultTargetPlatform;

  final Widget child;
  final ListenTogetherSynchronizationRunner? runSynchronization;
  final TargetPlatform platform;

  @override
  State<ListenTogetherForegroundSync> createState() =>
      _ListenTogetherForegroundSyncState();
}

class _ListenTogetherForegroundSyncState
    extends State<ListenTogetherForegroundSync> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _synchronize());
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
      _synchronize();
    }
  }

  void _synchronize() {
    if (!mounted) {
      return;
    }
    final session = context.read<ListenTogetherStore>();
    if (!session.available || session.busy || !session.joined) {
      return;
    }
    final library = context.read<LibraryStore>();
    if (!library.loaded || library.offlineModeEnabled) {
      return;
    }
    final runSynchronization = widget.runSynchronization;
    if (runSynchronization != null) {
      unawaited(_ignoreErrors(runSynchronization(session, library)));
      return;
    }
    final player = context.read<PlayerController>();
    if (session.hosting) {
      unawaited(_ignoreErrors(session.publishHostPlayback(library, player)));
    } else {
      unawaited(_ignoreErrors(session.refreshJoined(library, player)));
    }
  }

  Future<void> _ignoreErrors(Future<void> operation) async {
    try {
      await operation;
    } on Object {
      // The store retains a safe error state for the settings panel.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
