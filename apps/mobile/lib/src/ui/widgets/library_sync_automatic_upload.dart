import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/library_sync_store.dart';
import '../../player/player_controller.dart';

class LibrarySyncAutomaticUpload extends StatefulWidget {
  const LibrarySyncAutomaticUpload({super.key, required this.child});

  final Widget child;

  @override
  State<LibrarySyncAutomaticUpload> createState() =>
      _LibrarySyncAutomaticUploadState();
}

class _LibrarySyncAutomaticUploadState extends State<LibrarySyncAutomaticUpload>
    with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _runIfDue());
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
    if (state == AppLifecycleState.resumed) {
      _runIfDue();
    }
  }

  void _runIfDue() {
    if (!mounted) {
      return;
    }
    final library = context.read<LibraryStore>();
    final sync = context.read<LibrarySyncStore>();
    final player = context.read<PlayerController?>();
    if (!library.loaded || !sync.loaded) {
      return;
    }
    unawaited(sync.uploadAutomaticallyIfDue(library, player: player));
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryStore>();
    final sync = context.watch<LibrarySyncStore>();
    if (library.loaded && sync.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runIfDue());
    }
    return widget.child;
  }
}
