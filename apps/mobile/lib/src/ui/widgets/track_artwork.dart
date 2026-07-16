import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/self_hosted_provider_store.dart';
import '../../domain/artwork_crop.dart';

typedef ProviderArtworkLoader = Future<Uint8List?> Function(int maxWidth);

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.artworkUri,
    this.providerId,
    this.providerArtworkId,
    this.providerArtworkVersion,
    this.loadProviderArtwork,
    this.artworkCrop = ArtworkCrop.centered,
    this.size = 44,
    this.borderRadius = 8,
    this.fallbackIcon = Icons.music_note,
    super.key,
  });

  final Uri? artworkUri;
  final String? providerId;
  final String? providerArtworkId;
  final String? providerArtworkVersion;
  final ProviderArtworkLoader? loadProviderArtwork;
  final ArtworkCrop artworkCrop;
  final double size;
  final double borderRadius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final normalizedProviderId = providerId?.trim() ?? '';
    final normalizedArtworkId = providerArtworkId?.trim() ?? '';
    final needsProviderArtwork = artworkUri == null &&
        normalizedProviderId.isNotEmpty &&
        normalizedArtworkId.isNotEmpty;
    final store = needsProviderArtwork
        ? context.watch<SelfHostedProviderStore?>()
        : null;
    final maxWidth = (size * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(64, 1024);
    final availableStore = store?.loaded == true &&
            store!.hasCredentialForProvider(normalizedProviderId)
        ? store
        : null;
    final storeLoader = availableStore == null
        ? null
        : (int width) => availableStore.loadArtwork(
              sourceId: normalizedProviderId,
              artworkId: normalizedArtworkId,
              version: providerArtworkVersion,
              maxWidth: width,
            );
    final loader = storeLoader ?? loadProviderArtwork;
    final requestKey = needsProviderArtwork && loader != null
        ? '$normalizedProviderId|$normalizedArtworkId|'
            '${providerArtworkVersion ?? ''}|$maxWidth|'
            '${store?.artworkRevision ?? 0}'
        : null;

    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: _TrackArtworkContent(
          artworkUri: artworkUri,
          requestKey: requestKey,
          loadProviderArtwork: loader,
          maxWidth: maxWidth,
          fallbackIcon: fallbackIcon,
          artworkCrop: artworkCrop,
        ),
      ),
    );
  }
}

class _TrackArtworkContent extends StatefulWidget {
  const _TrackArtworkContent({
    required this.artworkUri,
    required this.requestKey,
    required this.loadProviderArtwork,
    required this.maxWidth,
    required this.fallbackIcon,
    required this.artworkCrop,
  });

  final Uri? artworkUri;
  final String? requestKey;
  final ProviderArtworkLoader? loadProviderArtwork;
  final int maxWidth;
  final IconData fallbackIcon;
  final ArtworkCrop artworkCrop;

  @override
  State<_TrackArtworkContent> createState() => _TrackArtworkContentState();
}

class _TrackArtworkContentState extends State<_TrackArtworkContent> {
  Future<Uint8List?>? _request;

  @override
  void initState() {
    super.initState();
    _startRequest();
  }

  @override
  void didUpdateWidget(covariant _TrackArtworkContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkUri != widget.artworkUri ||
        oldWidget.requestKey != widget.requestKey) {
      _startRequest();
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = trackArtworkImageProvider(widget.artworkUri);
    if (imageProvider != null) {
      return _artworkImage(imageProvider);
    }
    final request = _request;
    if (request == null) {
      return _TrackArtworkFallback(icon: widget.fallbackIcon);
    }
    return FutureBuilder<Uint8List?>(
      future: request,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _TrackArtworkFallback(icon: widget.fallbackIcon);
        }
        return _artworkImage(MemoryImage(bytes));
      },
    );
  }

  void _startRequest() {
    _request = widget.artworkUri == null && widget.requestKey != null
        ? widget.loadProviderArtwork?.call(widget.maxWidth)
        : null;
  }

  Widget _artworkImage(ImageProvider imageProvider) {
    return Transform.scale(
      scale: widget.artworkCrop.zoom,
      alignment: Alignment(
        widget.artworkCrop.alignmentX,
        widget.artworkCrop.alignmentY,
      ),
      child: Image(
        image: imageProvider,
        fit: BoxFit.cover,
        alignment: Alignment(
          widget.artworkCrop.alignmentX,
          widget.artworkCrop.alignmentY,
        ),
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return _TrackArtworkFallback(icon: widget.fallbackIcon);
        },
      ),
    );
  }
}

ImageProvider? trackArtworkImageProvider(Uri? uri) {
  if (uri == null) {
    return null;
  }

  switch (uri.scheme.toLowerCase()) {
    case 'http':
    case 'https':
      return NetworkImage(uri.toString());
    case 'file':
      return FileImage(File(uri.toFilePath()));
    case 'data':
      final data = uri.data;
      if (data == null || !data.mimeType.toLowerCase().startsWith('image/')) {
        return null;
      }

      return MemoryImage(Uint8List.fromList(data.contentAsBytes()));
  }

  if (!uri.hasScheme && uri.path.trim().isNotEmpty) {
    return FileImage(File(uri.path));
  }

  return null;
}

class _TrackArtworkFallback extends StatelessWidget {
  const _TrackArtworkFallback({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ColoredBox(
      color: colorScheme.secondaryContainer,
      child: Icon(
        icon,
        color: colorScheme.onSecondaryContainer,
      ),
    );
  }
}
