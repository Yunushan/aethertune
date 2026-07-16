import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/listen_together_store.dart';
import '../../player/player_controller.dart';

/// Keeps an active shared session current while the app is in the foreground.
class ListenTogetherForegroundSync extends StatefulWidget {
  const ListenTogetherForegroundSync({super.key, required this.child});

  final Widget child;

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
    if (state == AppLifecycleState.resumed) {
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
    final player = context.read<PlayerController>();
    if (!library.loaded || library.offlineModeEnabled) {
      return;
    }
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
