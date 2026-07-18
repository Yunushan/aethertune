import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/library_store.dart';
import '../../domain/aethertune_deep_link.dart';

/// Imports supported custom URLs after the local library is ready.
///
/// A cold-start link can arrive before persistent storage finishes loading.
/// Keeping it in this widget's short-lived queue makes the first open behave
/// the same as an already-running app without retaining shared-link payloads.
class AetherTuneDeepLinkListener extends StatefulWidget {
  const AetherTuneDeepLinkListener({
    required this.library,
    required this.child,
    this.incomingUriStream,
    this.onImported,
    super.key,
  });

  final LibraryStore library;
  final Stream<Uri>? incomingUriStream;
  final ValueChanged<AetherTuneDeepLinkKind>? onImported;
  final Widget child;

  @override
  State<AetherTuneDeepLinkListener> createState() =>
      _AetherTuneDeepLinkListenerState();
}

class _AetherTuneDeepLinkListenerState
    extends State<AetherTuneDeepLinkListener> {
  StreamSubscription<Uri>? _subscription;
  final List<Uri> _pendingUris = <Uri>[];
  final Set<String> _handledUris = <String>{};
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _listen(widget.incomingUriStream);
  }

  @override
  void didUpdateWidget(covariant AetherTuneDeepLinkListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.incomingUriStream != widget.incomingUriStream) {
      _subscription?.cancel();
      _listen(widget.incomingUriStream);
    }
    unawaited(_importPending());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _listen(Stream<Uri>? stream) {
    _subscription = stream?.listen(
      _enqueue,
      onError: (_, _) {},
    );
  }

  void _enqueue(Uri uri) {
    final link = AetherTuneDeepLink.tryParse(uri);
    if (link == null || !_handledUris.add(uri.toString())) {
      return;
    }
    _pendingUris.add(uri);
    unawaited(_importPending());
  }

  Future<void> _importPending() async {
    if (_isImporting || !widget.library.loaded) {
      return;
    }
    _isImporting = true;
    try {
      while (mounted && _pendingUris.isNotEmpty && widget.library.loaded) {
        final uri = _pendingUris.removeAt(0);
        final link = AetherTuneDeepLink.tryParse(uri);
        if (link == null) {
          continue;
        }
        try {
          final name = switch (link.kind) {
            AetherTuneDeepLinkKind.playlist =>
              (await widget.library.importPlaylistLink(uri.toString())).name,
            AetherTuneDeepLinkKind.smartPlaylist =>
              (await widget.library.importCustomSmartPlaylistLink(uri.toString()))
                  .name,
          };
          if (!mounted) {
            return;
          }
          widget.onImported?.call(link.kind);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported $name from shared link.')),
          );
        } on FormatException catch (error) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        }
      }
    } finally {
      _isImporting = false;
    }
  }
}
