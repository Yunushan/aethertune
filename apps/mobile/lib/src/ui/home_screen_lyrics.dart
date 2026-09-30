part of 'home_screen.dart';

class _LyricsEditorResult {
  const _LyricsEditorResult({
    required this.plainText,
    this.sourceId = 'manual',
    this.sourceName = '',
    this.sourceExternalId = '',
    this.sourceUri,
  });

  final String plainText;
  final String sourceId;
  final String sourceName;
  final String sourceExternalId;
  final Uri? sourceUri;
}

class _SyncedLyricsPreview extends StatelessWidget {
  const _SyncedLyricsPreview({required this.lines});

  final List<SyncedLyricLine> lines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final timestampStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: colorScheme.primary);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(
        height: 180,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: lines.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final line = lines[index];
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 48,
                    child: Text(
                      formatSyncedLyricTimestamp(line.timestamp),
                      textAlign: TextAlign.end,
                      style: timestampStyle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(line.text)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NowPlayingLyricsSheet extends StatelessWidget {
  const _NowPlayingLyricsSheet({
    required this.track,
    required this.library,
    required this.player,
    required this.translator,
    required this.translationTargetLanguage,
    required this.onEdit,
    required this.onShare,
    required this.onShareRange,
    required this.onAdjustTiming,
    required this.onSearch,
  });

  final Track track;
  final LibraryStore library;
  final PlayerController player;
  final LyricsTranslator? translator;
  final String translationTargetLanguage;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback onAdjustTiming;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final currentLyrics = library.lyricsForTrack(track.id);
        if (currentLyrics == null || currentLyrics.isEmpty) {
          return _EmptyNowPlayingLyrics(track: track, onEdit: onEdit);
        }

        final syncedLines = currentLyrics.syncedLines;
        if (syncedLines.isEmpty) {
          return _PlainNowPlayingLyrics(
            track: track,
            lyrics: currentLyrics.plainText,
            sourceLabel: currentLyrics.attributionLabel,
            onEdit: onEdit,
            onShare: onShare,
            onShareRange: onShareRange,
            onSearch: onSearch,
            onTranslate: _translationAction(context, currentLyrics.plainText),
          );
        }

        return _SyncedNowPlayingLyrics(
          track: track,
          lines: syncedLines,
          sourceLabel: currentLyrics.attributionLabel,
          player: player,
          onEdit: onEdit,
          onShare: onShare,
          onShareRange: onShareRange,
          onAdjustTiming: onAdjustTiming,
          onSearch: onSearch,
          onTranslate: _translationAction(
            context,
            syncedLines.map((line) => line.text).join('\n'),
          ),
        );
      },
    );
  }

  VoidCallback? _translationAction(BuildContext context, String lyricsText) {
    final currentTranslator = translator;
    if (currentTranslator == null || lyricsText.trim().isEmpty) {
      return null;
    }
    return () => unawaited(() async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (!context.mounted) {
        return;
      }
      await _showLyricsTranslation(
        context,
        translator: currentTranslator,
        lyrics: lyricsText,
        targetLanguage: translationTargetLanguage,
      );
    }());
  }
}

class _EmptyNowPlayingLyrics extends StatelessWidget {
  const _EmptyNowPlayingLyrics({required this.track, required this.onEdit});

  final Track track;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: <Widget>[
          _NowPlayingLyricsHeader(
            track: track,
            subtitle: 'No lyrics saved',
            onEdit: onEdit,
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.subtitles_outlined),
            title: Text('No lyrics yet'),
            subtitle: Text(
              'Add plain lyrics or import LRC, SRT, WebVTT, or TTML timed lyrics.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainNowPlayingLyrics extends StatelessWidget {
  const _PlainNowPlayingLyrics({
    required this.track,
    required this.lyrics,
    required this.sourceLabel,
    required this.onEdit,
    required this.onShare,
    required this.onShareRange,
    required this.onSearch,
    this.onTranslate,
  });

  final Track track;
  final String lyrics;
  final String? sourceLabel;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback onSearch;
  final VoidCallback? onTranslate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return ListView(
            controller: controller,
            children: <Widget>[
              _NowPlayingLyricsHeader(
                track: track,
                subtitle: _lyricsSubtitle('Plain lyrics', sourceLabel),
                onEdit: onEdit,
                onShare: onShare,
                onShareRange: onShareRange,
                onSearch: onSearch,
                onTranslate: onTranslate,
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(lyrics),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SyncedNowPlayingLyrics extends StatefulWidget {
  const _SyncedNowPlayingLyrics({
    required this.track,
    required this.lines,
    required this.sourceLabel,
    required this.player,
    required this.onEdit,
    required this.onShare,
    required this.onShareRange,
    required this.onAdjustTiming,
    required this.onSearch,
    this.onTranslate,
  });

  final Track track;
  final List<SyncedLyricLine> lines;
  final String? sourceLabel;
  final PlayerController player;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onShareRange;
  final VoidCallback onAdjustTiming;
  final VoidCallback onSearch;
  final VoidCallback? onTranslate;

  @override
  State<_SyncedNowPlayingLyrics> createState() =>
      _SyncedNowPlayingLyricsState();
}

class _SyncedNowPlayingLyricsState extends State<_SyncedNowPlayingLyrics> {
  static const _estimatedLineExtent = 72.0;
  int _lastScrolledIndex = -1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return StreamBuilder<Duration>(
            stream: widget.player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final activeIndex = syncedLyricLineIndexAt(
                widget.lines,
                position,
              );
              _scrollToActiveLine(controller, activeIndex);

              return ListView.separated(
                controller: controller,
                itemCount: widget.lines.length + 1,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _NowPlayingLyricsHeader(
                      track: widget.track,
                      subtitle: _lyricsSubtitle(
                        activeIndex == -1
                            ? 'Synced lyrics'
                            : 'Line ${activeIndex + 1} of ${widget.lines.length}',
                        widget.sourceLabel,
                      ),
                      onEdit: widget.onEdit,
                      onShare: widget.onShare,
                      onShareRange: widget.onShareRange,
                      onAdjustTiming: widget.onAdjustTiming,
                      onSearch: widget.onSearch,
                      onTranslate: widget.onTranslate,
                    );
                  }

                  final lineIndex = index - 1;
                  final line = widget.lines[lineIndex];
                  return _SyncedNowPlayingLyricLine(
                    line: line,
                    isActive: lineIndex == activeIndex,
                    position: position,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _scrollToActiveLine(ScrollController controller, int activeIndex) {
    if (activeIndex < 0 || activeIndex == _lastScrolledIndex) {
      return;
    }

    _lastScrolledIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) {
        return;
      }

      final targetOffset = (activeIndex * _estimatedLineExtent)
          .clamp(0.0, controller.position.maxScrollExtent)
          .toDouble();
      controller.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}

class _NowPlayingLyricsHeader extends StatelessWidget {
  const _NowPlayingLyricsHeader({
    required this.track,
    required this.subtitle,
    required this.onEdit,
    this.onShare,
    this.onShareRange,
    this.onAdjustTiming,
    this.onSearch,
    this.onTranslate,
  });

  final Track track;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback? onShare;
  final VoidCallback? onShareRange;
  final VoidCallback? onAdjustTiming;
  final VoidCallback? onSearch;
  final VoidCallback? onTranslate;

  @override
  Widget build(BuildContext context) {
    final hasOverflowActions =
        onShare != null ||
        onShareRange != null ||
        onAdjustTiming != null ||
        onTranslate != null;

    return ListTile(
      leading: const Icon(Icons.subtitles_outlined),
      title: Text(track.title),
      subtitle: Text('${track.artist} · $subtitle'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (onSearch != null)
            IconButton(
              tooltip: 'Find in lyrics',
              onPressed: onSearch,
              icon: const Icon(Icons.manage_search_outlined),
            ),
          if (hasOverflowActions)
            PopupMenuButton<_NowPlayingLyricsMenuAction>(
              tooltip: 'Lyrics actions',
              onSelected: _selectOverflowAction,
              itemBuilder: (context) =>
                  <PopupMenuEntry<_NowPlayingLyricsMenuAction>>[
                    if (onShare != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.share,
                        child: Text('Copy share text'),
                      ),
                    if (onShareRange != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.shareRange,
                        child: Text('Share selected lines'),
                      ),
                    if (onTranslate != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.translate,
                        child: Text('Translate lyrics'),
                      ),
                    if (onAdjustTiming != null)
                      const PopupMenuItem<_NowPlayingLyricsMenuAction>(
                        value: _NowPlayingLyricsMenuAction.adjustTiming,
                        child: Text('Adjust lyric timing'),
                      ),
                  ],
            ),
          IconButton(
            tooltip: 'Edit lyrics',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
    );
  }

  void _selectOverflowAction(_NowPlayingLyricsMenuAction action) {
    switch (action) {
      case _NowPlayingLyricsMenuAction.share:
        onShare?.call();
      case _NowPlayingLyricsMenuAction.shareRange:
        onShareRange?.call();
      case _NowPlayingLyricsMenuAction.translate:
        onTranslate?.call();
      case _NowPlayingLyricsMenuAction.adjustTiming:
        onAdjustTiming?.call();
    }
  }
}

Future<void> _configureLyricsSearchEndpoint(BuildContext context) async {
  final store = context.read<LyricsSearchEndpointSettingsStore?>();
  if (store == null) {
    return;
  }
  final controller = TextEditingController(
    text: store.endpoint?.toString() ?? '',
  );
  String? validationError;
  try {
    final endpoint = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Configure lyrics search'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'AetherTune sends track title, artist, album, and any search terms only to the HTTPS LRCLIB-compatible service you choose. This endpoint receives no credentials and results remain stored on this device.',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('lyrics-search-endpoint'),
                  controller: controller,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Service URL',
                    hintText: 'https://lyrics.example',
                  ),
                  onSubmitted: (value) =>
                      Navigator.of(dialogContext).pop(value),
                ),
                if (validationError != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) {
                  setDialogState(
                    () => validationError = 'Enter an HTTPS service URL.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || endpoint == null) {
      return;
    }
    // Let the route dispose before its setting notification rebuilds Options.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!context.mounted) {
      return;
    }
    await store.save(endpoint);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lyrics search service configured.')),
      );
    }
  } on FormatException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save lyrics search settings.')),
      );
    }
  } finally {
    controller.dispose();
  }
}

Future<void> _removeLyricsSearchEndpoint(BuildContext context) async {
  final store = context.read<LyricsSearchEndpointSettingsStore?>();
  if (store == null || !store.isConfigured) {
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Use public LRCLIB again?'),
      content: const Text(
        'This removes the custom lyrics search endpoint from this device. Saved lyrics and cached searches remain unchanged.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  if (!context.mounted || confirmed != true) {
    return;
  }
  try {
    await store.remove();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Using public LRCLIB for lyrics search.')),
      );
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove lyrics search settings.'),
        ),
      );
    }
  }
}

enum _NowPlayingLyricsMenuAction { share, shareRange, translate, adjustTiming }

String _lyricsSubtitle(String base, String? sourceLabel) {
  final source = sourceLabel?.trim() ?? '';
  return source.isEmpty ? base : '$base - $source';
}

String _formatLyricsTimingOffset(Duration offset) {
  final milliseconds = offset.inMilliseconds;
  final sign = milliseconds < 0 ? '-' : '+';
  final absoluteMilliseconds = milliseconds.abs();
  final seconds = absoluteMilliseconds ~/ 1000;
  final tenths = (absoluteMilliseconds % 1000) ~/ 100;
  return '$sign$seconds.$tenths s';
}

class _LyricsSearchEntry {
  const _LyricsSearchEntry({
    required this.lineNumber,
    required this.text,
    this.timestamp,
  });

  final int lineNumber;
  final String text;
  final Duration? timestamp;
}

Future<void> _showLyricsSearch(
  BuildContext context, {
  required Track track,
  required TrackLyrics? lyrics,
  required PlayerController player,
}) async {
  final currentLyrics = lyrics;
  if (currentLyrics == null || currentLyrics.isEmpty) {
    return;
  }

  final syncedLines = currentLyrics.syncedLines;
  final entries = syncedLines.isNotEmpty
      ? <_LyricsSearchEntry>[
          for (var index = 0; index < syncedLines.length; index += 1)
            _LyricsSearchEntry(
              lineNumber: index + 1,
              text: syncedLines[index].text,
              timestamp: syncedLines[index].timestamp,
            ),
        ]
      : <_LyricsSearchEntry>[
          for (final entry
              in currentLyrics.plainText
                  .split(RegExp(r'\r?\n'))
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList(growable: false)
                  .indexed)
            _LyricsSearchEntry(lineNumber: entry.$1 + 1, text: entry.$2),
        ];
  if (entries.isEmpty) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (_) =>
        _LyricsSearchDialog(track: track, entries: entries, player: player),
  );
}

class _LyricsSearchDialog extends StatefulWidget {
  const _LyricsSearchDialog({
    required this.track,
    required this.entries,
    required this.player,
  });

  final Track track;
  final List<_LyricsSearchEntry> entries;
  final PlayerController player;

  @override
  State<_LyricsSearchDialog> createState() => _LyricsSearchDialogState();
}

class _LyricsSearchDialogState extends State<_LyricsSearchDialog> {
  final _controller = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchingIndices = findLyricLineMatchIndices(
      widget.entries.map((entry) => entry.text).toList(growable: false),
      _query,
    );

    return AlertDialog(
      title: Text('Find in ${widget.track.title}'),
      content: SizedBox(
        width: 460,
        height: 360,
        child: Column(
          children: <Widget>[
            TextField(
              autofocus: true,
              controller: _controller,
              key: const Key('lyrics-find-input'),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Find lyrics',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _query.trim().isEmpty
                  ? const SizedBox.shrink()
                  : matchingIndices.isEmpty
                  ? const Center(child: Text('No matching lines'))
                  : ListView.separated(
                      itemCount: matchingIndices.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = widget.entries[matchingIndices[index]];
                        return ListTile(
                          key: Key('lyric-search-result-${entry.lineNumber}'),
                          dense: true,
                          title: Text(
                            entry.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.timestamp == null
                                ? 'Line ${entry.lineNumber}'
                                : formatSyncedLyricTimestamp(entry.timestamp!),
                          ),
                          onTap: () async {
                            if (entry.timestamp != null) {
                              await widget.player.seek(entry.timestamp!);
                            }
                            if (!mounted) {
                              return;
                            }
                            Navigator.of(this.context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

Future<void> _showLyricsTimingAdjustment(
  BuildContext context,
  LibraryStore library,
  Track track,
) async {
  if (library.lyricsForTrack(track.id)?.hasSyncedLines != true) {
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final offset =
              library.lyricsForTrack(track.id)?.timingOffset ?? Duration.zero;

          Future<void> adjust(Duration change) async {
            await library.setLyricsTimingOffset(track.id, offset + change);
            if (dialogContext.mounted) {
              setDialogState(() {});
            }
          }

          Future<void> reset() async {
            await library.setLyricsTimingOffset(track.id, Duration.zero);
            if (dialogContext.mounted) {
              setDialogState(() {});
            }
          }

          return AlertDialog(
            title: const Text('Adjust lyric timing'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(_formatLyricsTimingOffset(offset)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Move lyrics 0.5 seconds earlier',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: -500))),
                      icon: const Icon(Icons.fast_rewind_outlined),
                    ),
                    IconButton(
                      tooltip: 'Move lyrics 0.1 seconds earlier',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: -100))),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Move lyrics 0.1 seconds later',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: 100))),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    IconButton(
                      tooltip: 'Move lyrics 0.5 seconds later',
                      onPressed: () =>
                          unawaited(adjust(const Duration(milliseconds: 500))),
                      icon: const Icon(Icons.fast_forward_outlined),
                    ),
                  ],
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: offset == Duration.zero
                    ? null
                    : () => unawaited(reset()),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showLyricsTranslation(
  BuildContext context, {
  required LyricsTranslator translator,
  required String lyrics,
  required String targetLanguage,
}) async {
  final localizations = AppLocalizations.of(context)!;
  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      duration: Duration(days: 1),
      content: Text(localizations.translatingLyrics),
    ),
  );

  try {
    final translated = await translator.translate(
      lyrics,
      targetLanguage: targetLanguage,
    );
    messenger.hideCurrentSnackBar();
    if (!navigator.mounted) {
      return;
    }
    await showDialog<void>(
      context: navigator.context,
      builder: (_) => _TranslatedLyricsDialog(
        lyrics: translated,
        targetLanguage: targetLanguage,
      ),
    );
  } on Object catch (error) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(content: Text(localizations.couldNotTranslateLyrics('$error'))),
    );
  }
}

class _TranslatedLyricsDialog extends StatelessWidget {
  const _TranslatedLyricsDialog({
    required this.lyrics,
    required this.targetLanguage,
  });

  final String lyrics;
  final String targetLanguage;

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return AlertDialog(
      title: Text(localizations.translatedLyrics),
      content: SizedBox(
        width: 560,
        height: height,
        child: ListView(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.translate_outlined),
              title: Text(
                localizations.translatedLyricsForLanguage(targetLanguage),
              ),
              trailing: IconButton(
                tooltip: localizations.copyTranslatedLyrics,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: lyrics));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(localizations.translatedLyricsCopied),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.content_copy_outlined),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(lyrics),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _SyncedNowPlayingLyricLine extends StatelessWidget {
  const _SyncedNowPlayingLyricLine({
    required this.line,
    required this.isActive,
    required this.position,
  });

  final SyncedLyricLine line;
  final bool isActive;
  final Duration position;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final backgroundColor = isActive
        ? colorScheme.primaryContainer
        : Colors.transparent;
    final textStyle = isActive
        ? textTheme.titleMedium?.copyWith(
            color: colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          )
        : textTheme.bodyLarge;

    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 52,
              child: Text(
                formatSyncedLyricTimestamp(line.timestamp),
                textAlign: TextAlign.end,
                style: textTheme.labelMedium?.copyWith(
                  color: isActive
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: line.hasWordTiming
                  ? _KaraokeLyricText(
                      words: line.words,
                      activeWordIndex: syncedLyricWordIndexAt(
                        line.words,
                        position,
                      ),
                      activeStyle: textStyle?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                      inactiveStyle: textStyle,
                    )
                  : Text(line.text, style: textStyle),
            ),
          ],
        ),
      ),
    );
  }
}

class _KaraokeLyricText extends StatelessWidget {
  const _KaraokeLyricText({
    required this.words,
    required this.activeWordIndex,
    required this.activeStyle,
    required this.inactiveStyle,
  });

  final List<SyncedLyricWord> words;
  final int activeWordIndex;
  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: List<InlineSpan>.generate(words.length, (index) {
          final prefix = index == 0 ? '' : ' ';
          return TextSpan(
            text: '$prefix${words[index].text}',
            style: index == activeWordIndex ? activeStyle : inactiveStyle,
          );
        }),
      ),
    );
  }
}
