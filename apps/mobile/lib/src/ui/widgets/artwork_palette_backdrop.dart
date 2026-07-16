import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/artwork_palette.dart';
import 'track_artwork.dart';

/// Applies a subtle, local palette tint behind a player surface.
///
/// Only URI artwork that [TrackArtwork] can render without credential-aware
/// provider loading is resolved here. Self-hosted provider images therefore
/// keep the normal themed surface rather than exposing a second image path.
class ArtworkPaletteBackdrop extends StatefulWidget {
  const ArtworkPaletteBackdrop({
    required this.artworkUri,
    required this.child,
    super.key,
  });

  final Uri? artworkUri;
  final Widget child;

  @override
  State<ArtworkPaletteBackdrop> createState() =>
      _ArtworkPaletteBackdropState();
}

class _ArtworkPaletteBackdropState extends State<ArtworkPaletteBackdrop> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  ArtworkPalette? _palette;
  String? _requestKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(covariant ArtworkPaletteBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkUri != widget.artworkUri) {
      _resolveArtwork();
    }
  }

  @override
  void dispose() {
    _removeImageListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Theme.of(context).colorScheme.surface;
    return AnimatedContainer(
      key: const Key('now-playing-artwork-palette'),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      color: artworkPaletteSurfaceColor(
        fallback: fallback,
        palette: _palette,
      ),
      child: widget.child,
    );
  }

  void _resolveArtwork() {
    final requestKey = widget.artworkUri?.toString();
    if (_requestKey == requestKey && _imageListener != null) {
      return;
    }
    _requestKey = requestKey;
    _removeImageListener();
    if (_palette != null) {
      setState(() => _palette = null);
    }

    final imageProvider = trackArtworkImageProvider(widget.artworkUri);
    if (imageProvider == null) {
      return;
    }

    final imageStream = ResizeImage(
      imageProvider,
      width: 192,
      height: 192,
    ).resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (image, _) => unawaited(_extractPalette(image.image, requestKey)),
      onError: (_, __) {},
    );
    _imageStream = imageStream;
    _imageListener = listener;
    imageStream.addListener(listener);
  }

  Future<void> _extractPalette(ui.Image image, String? requestKey) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final bytes = data?.buffer.asUint8List();
    final palette = bytes == null ? null : artworkPaletteFromRgba(bytes);
    if (!mounted || _requestKey != requestKey) {
      return;
    }
    setState(() => _palette = palette);
  }

  void _removeImageListener() {
    final stream = _imageStream;
    final listener = _imageListener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _imageStream = null;
    _imageListener = null;
  }
}
