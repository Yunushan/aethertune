import 'package:flutter/material.dart';

import '../../domain/artwork_crop.dart';
import 'track_artwork.dart';

Future<ArtworkCrop?> showArtworkCropEditor(
  BuildContext context, {
  required Uri artworkUri,
  required ArtworkCrop initialCrop,
}) {
  return showDialog<ArtworkCrop>(
    context: context,
    builder: (context) => _ArtworkCropEditorDialog(
      artworkUri: artworkUri,
      initialCrop: initialCrop,
    ),
  );
}

class _ArtworkCropEditorDialog extends StatefulWidget {
  const _ArtworkCropEditorDialog({
    required this.artworkUri,
    required this.initialCrop,
  });

  final Uri artworkUri;
  final ArtworkCrop initialCrop;

  @override
  State<_ArtworkCropEditorDialog> createState() =>
      _ArtworkCropEditorDialogState();
}

class _ArtworkCropEditorDialogState extends State<_ArtworkCropEditorDialog> {
  late ArtworkCrop _crop = widget.initialCrop;

  @override
  Widget build(BuildContext context) {
    final zoomPercent = (_crop.zoom * 100).round();
    return AlertDialog(
      title: const Text('Crop artwork'),
      content: SizedBox(
        width: 288,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    key: const Key('artwork-crop-preview'),
                    onPanUpdate: (details) =>
                        _moveCrop(details, constraints.maxWidth),
                    child: TrackArtwork(
                      artworkUri: widget.artworkUri,
                      artworkCrop: _crop,
                      size: constraints.maxWidth,
                      borderRadius: 0,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                const Icon(Icons.zoom_in_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    key: const Key('artwork-crop-zoom'),
                    value: _crop.zoom,
                    min: 1,
                    max: ArtworkCrop.maximumZoom,
                    divisions: 20,
                    label: '$zoomPercent%',
                    semanticFormatterCallback: (value) =>
                        'Artwork zoom ${(value * 100).round()} percent',
                    onChanged: (value) {
                      setState(() {
                        _crop = _crop.copyWith(zoom: value);
                      });
                    },
                  ),
                ),
                Text('$zoomPercent%'),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Reset crop',
                onPressed: _crop.isCentered
                    ? null
                    : () {
                        setState(() {
                          _crop = ArtworkCrop.centered;
                        });
                      },
                icon: const Icon(Icons.center_focus_strong_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_crop),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _moveCrop(DragUpdateDetails details, double width) {
    setState(() {
      _crop = _crop.copyWith(
        alignmentX: _crop.alignmentX + (details.delta.dx / width) * 2,
        alignmentY: _crop.alignmentY + (details.delta.dy / width) * 2,
      );
    });
  }
}
