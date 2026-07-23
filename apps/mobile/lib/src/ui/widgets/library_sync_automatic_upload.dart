import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/library_store.dart';
import '../../data/library_sync_store.dart';
import '../../player/player_controller.dart';
import 'desktop_background_work_policy.dart';

typedef AutomaticLibraryUploadRunner = Future<bool> Function(
  LibraryStore library,
  LibrarySyncStore sync,
  PlayerController? player,
);

class LibrarySyncAutomaticUpload extends StatefulWidget {
  LibrarySyncAutomaticUpload({
    super.key,
    required this.child,
    this.runUpload,
    TargetPlatform? platform,
  }) : platform = platform ?? defaultTargetPlatform;

  final Widget child;
  final AutomaticLibraryUploadRunner? runUpload;
  final TargetPlatform platform;

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
    if (state == AppLifecycleState.resumed ||
        shouldKeepBackgroundWorkInDesktopProcess(
          platform: widget.platform,
          state: state,
        )) {
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
    final runUpload = widget.runUpload;
    if (runUpload != null) {
      unawaited(runUpload(library, sync, player));
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
