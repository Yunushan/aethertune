part of 'home_screen.dart';

class _LyricsShareRange {
  const _LyricsShareRange({required this.startLine, required this.endLine});

  final int startLine;
  final int endLine;
}

Future<void> _copyLyricsSelectedRangeShareText(
  BuildContext context,
  LibraryStore library,
  Track track, {
  String? plainText,
}) async {
  final lines = library.lyricsShareLines(track.id, plainText: plainText);
  if (lines.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Add lyrics before sharing selected lines.'),
      ),
    );
    return;
  }
  final range = await _promptForLyricsShareRange(context, lines: lines);
  if (!context.mounted || range == null) {
    return;
  }

  await _copyTextToClipboard(
    context,
    library.shareLyricsText(
      track.id,
      plainText: plainText,
      startLine: range.startLine,
      endLine: range.endLine,
      maxLines: _maxLyricsShareRangeLines,
    ),
    copiedMessage: 'Copied selected lyrics for ${track.title}.',
    unavailableMessage: 'Selected lyrics are unavailable for ${track.title}.',
  );
}

Future<_LyricsShareRange?> _promptForLyricsShareRange(
  BuildContext context, {
  required List<String> lines,
}) async {
  var startLine = 0;
  var endLine = _lyricsShareRangeEndLimit(startLine, lines.length);

  return showDialog<_LyricsShareRange>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (_, setDialogState) {
          final maximumEndLine = _lyricsShareRangeEndLimit(
            startLine,
            lines.length,
          );
          final selectedLines = lines.sublist(startLine, endLine + 1);

          return AlertDialog(
            title: const Text('Share selected lines'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Choose up to 8 visible lyrics lines.'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('lyrics-share-start-$startLine'),
                    initialValue: startLine,
                    decoration: const InputDecoration(labelText: 'Start line'),
                    items: <DropdownMenuItem<int>>[
                      for (var index = 0; index < lines.length; index++)
                        DropdownMenuItem<int>(
                          value: index,
                          child: Text('Line ${index + 1}'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        startLine = value;
                        final newMaximumEndLine = _lyricsShareRangeEndLimit(
                          startLine,
                          lines.length,
                        );
                        endLine = endLine
                            .clamp(startLine, newMaximumEndLine)
                            .toInt();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('lyrics-share-end-$startLine-$endLine'),
                    initialValue: endLine,
                    decoration: const InputDecoration(labelText: 'End line'),
                    items: <DropdownMenuItem<int>>[
                      for (
                        var index = startLine;
                        index <= maximumEndLine;
                        index++
                      )
                        DropdownMenuItem<int>(
                          value: index,
                          child: Text('Line ${index + 1}'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => endLine = value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    selectedLines.join('\n'),
                    maxLines: _maxLyricsShareRangeLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(
                  _LyricsShareRange(startLine: startLine, endLine: endLine),
                ),
                icon: const Icon(Icons.ios_share),
                label: const Text('Copy selected lines'),
              ),
            ],
          );
        },
      );
    },
  );
}

int _lyricsShareRangeEndLimit(int startLine, int lineCount) {
  return (startLine + _maxLyricsShareRangeLines - 1)
      .clamp(startLine, lineCount - 1)
      .toInt();
}

Future<void> _showLyricsShareCard(
  BuildContext context,
  LibraryStore library,
  Track track,
  String plainText,
) async {
  final shareText =
      library.shareLyricsText(track.id, plainText: plainText) ?? '';
  if (shareText.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add lyrics before saving a share card.')),
    );
    return;
  }
  final boundaryKey = GlobalKey();
  final localArtwork = _lyricsShareCardLocalArtwork(track);
  var includeArtwork = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Lyrics share card'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (localArtwork != null)
                SwitchListTile.adaptive(
                  key: const Key('lyrics-share-card-artwork-toggle'),
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.image_outlined),
                  title: const Text('Include local artwork'),
                  subtitle: const Text(
                    'Include this selected local image only in the PNG you save or share.',
                  ),
                  value: includeArtwork,
                  onChanged: (enabled) {
                    setDialogState(() => includeArtwork = enabled);
                  },
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: LyricsShareCard(
                    title: track.title,
                    artist: track.artist,
                    shareText: shareText,
                    backgroundImage: includeArtwork ? localArtwork : null,
                    artworkCrop: includeArtwork
                        ? track.artworkCrop
                        : ArtworkCrop.centered,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton.icon(
            onPressed: () => unawaited(
              _saveLyricsShareCard(dialogContext, boundaryKey, track),
            ),
            icon: const Icon(Icons.save_alt_outlined),
            label: const Text('Save PNG'),
          ),
          FilledButton.icon(
            onPressed: () => unawaited(
              _shareLyricsShareCard(dialogContext, boundaryKey, track),
            ),
            icon: const Icon(Icons.ios_share),
            label: const Text('Share'),
          ),
        ],
      ),
    ),
  );
}

ImageProvider? _lyricsShareCardLocalArtwork(Track track) {
  return localLyricsShareCardBackgroundImageProvider(
    artworkIsUserManaged: track.artworkIsUserManaged,
    artworkUri: track.artworkUri,
  );
}

Future<void> _saveLyricsShareCard(
  BuildContext context,
  GlobalKey boundaryKey,
  Track track,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await captureLyricsShareCardPng(boundaryKey);
    final fileName = 'aethertune-lyrics-${track.id}.png';
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save lyrics share card',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const <String>['png'],
      bytes: bytes,
    );
    if (outputPath == null) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
    }
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('Saved $fileName.')));
    }
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save lyrics share card: $error')),
      );
    }
  }
}

Future<void> _shareLyricsShareCard(
  BuildContext context,
  GlobalKey boundaryKey,
  Track track,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final sharePositionOrigin = platformSharePositionOrigin(context);
  try {
    final status = await const SharePlusImageShareService().share(
      PlatformImageShareRequest(
        bytes: await captureLyricsShareCardPng(boundaryKey),
        fileName: 'aethertune-lyrics.png',
        title: '${track.title} lyrics - AetherTune',
        subject: 'AetherTune lyrics share card',
        text: '${track.title} by ${track.artist}',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    if (!context.mounted || status == PlatformImageShareStatus.dismissed) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          status == PlatformImageShareStatus.shared
              ? 'Shared lyrics share card.'
              : 'Sharing is unavailable. Save the PNG instead.',
        ),
      ),
    );
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share lyrics share card: $error')),
      );
    }
  }
}

Future<void> _copyLyricsDraftExportDocument(
  BuildContext context,
  Track track,
  String plainText,
) {
  final export = buildLyricsDocumentExport(
    title: track.title,
    artist: track.artist,
    plainText: plainText,
  );

  return _copyTextToClipboard(
    context,
    export?.text,
    copiedMessage: export == null
        ? 'Copied lyrics export text.'
        : 'Copied ${export.fileName} export text.',
    unavailableMessage: 'Add lyrics before copying export text.',
  );
}

Future<void> _saveLyricsDraftExportDocument(
  BuildContext context,
  Track track,
  String plainText,
) async {
  final export = buildLyricsDocumentExport(
    title: track.title,
    artist: track.artist,
    plainText: plainText,
  );
  if (export == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add lyrics before saving an export file.')),
    );
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final bytes = Uint8List.fromList(export.bytes);
  try {
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save lyrics file',
      fileName: export.fileName,
      type: FileType.custom,
      allowedExtensions: <String>[export.extension],
      bytes: bytes,
    );
    if (outputPath == null) {
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
    }
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${export.fileName}.')),
    );
  } on Exception catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Could not save lyrics file: $error')),
    );
  }
}

Future<void> _copyTextToClipboard(
  BuildContext context,
  String? value, {
  required String copiedMessage,
  required String unavailableMessage,
}) async {
  final text = value?.trim();
  if (text == null || text.isEmpty) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(unavailableMessage)));
    return;
  }

  await Clipboard.setData(ClipboardData(text: text));

  if (!context.mounted) {
    return;
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(copiedMessage),
      action: SnackBarAction(
        label: 'Share',
        onPressed: () => unawaited(_shareCopiedText(context, text)),
      ),
    ),
  );
}

Future<void> _shareCopiedText(BuildContext context, String text) async {
  if (!context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final renderBox = context.findRenderObject() as RenderBox?;
  final origin = renderBox == null || !renderBox.hasSize
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  try {
    final status = await _platformTextShareService.share(
      PlatformTextShareRequest(text: text, sharePositionOrigin: origin),
    );
    if (!context.mounted || status != PlatformTextShareStatus.unavailable) {
      return;
    }
    messenger.showSnackBar(
      const SnackBar(content: Text('Native sharing is unavailable here.')),
    );
  } on Object catch (error) {
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Could not open the share sheet: $error')),
    );
  }
}
