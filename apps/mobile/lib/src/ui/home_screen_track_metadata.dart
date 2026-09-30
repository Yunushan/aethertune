part of 'home_screen.dart';

class _TrackMetadataDraft {
  const _TrackMetadataDraft({
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.year,
    required this.trackNumber,
    required this.genre,
  });

  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int? year;
  final int? trackNumber;
  final String genre;
}

Future<void> _showTrackMetadataEditor(BuildContext context, Track track) async {
  final library = context.read<LibraryStore>();
  final messenger = ScaffoldMessenger.of(context);
  final draft = await _promptForTrackMetadata(context, track);

  if (!context.mounted || draft == null) {
    return;
  }

  final updated = await library.updateTrackMetadata(
    track.id,
    title: draft.title,
    artist: draft.artist,
    album: draft.album,
    albumArtist: draft.albumArtist,
    clearAlbumArtist: draft.albumArtist.trim().isEmpty,
    year: draft.year,
    clearYear: draft.year == null,
    trackNumber: draft.trackNumber,
    clearTrackNumber: draft.trackNumber == null,
    genre: draft.genre,
  );

  if (!context.mounted) {
    return;
  }

  if (updated != null && _canWriteEmbeddedMetadata(updated)) {
    final writeFile = await _confirmEmbeddedTagWrite(context, updated);
    if (!context.mounted) {
      return;
    }
    if (writeFile == true) {
      try {
        if (_isLocalMp3(updated)) {
          await const Mp3Id3v1TagWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        } else if (_isLocalFlac(updated)) {
          await const FlacVorbisCommentWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        } else if (_isLocalM4aM4bM4rOrAlac(updated)) {
          await const M4aMetadataWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist ?? '',
            year: updated.year ?? 0,
            trackNumber: updated.trackNumber ?? 0,
            genre: updated.genre,
          );
        } else if (_isLocalOggOrOpus(updated)) {
          await const OggVorbisCommentWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            albumArtist: updated.albumArtist,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        } else {
          await const WavRiffInfoWriter().write(
            path: updated.localPath!,
            title: updated.title,
            artist: updated.artist,
            album: updated.album,
            year: updated.year,
            trackNumber: updated.trackNumber,
            genre: updated.genre,
          );
        }
      } on Object catch (error) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Saved app metadata, but could not update embedded tags: $error',
              ),
            ),
          );
        }
        return;
      }
    }
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        updated == null
            ? 'Track is no longer in the library.'
            : 'Saved metadata for ${updated.title}.',
      ),
    ),
  );
}

Future<_TrackMetadataDraft?> _promptForTrackMetadata(
  BuildContext context,
  Track track,
) async {
  final library = context.read<LibraryStore>();
  final titleController = TextEditingController(text: track.title);
  final artistController = TextEditingController(text: track.artist);
  final albumController = TextEditingController(text: track.album);
  final albumArtistController = TextEditingController(
    text: track.albumArtist ?? '',
  );
  final yearController = TextEditingController(
    text: track.year?.toString() ?? '',
  );
  final trackNumberController = TextEditingController(
    text: track.trackNumber?.toString() ?? '',
  );
  final genreController = TextEditingController(text: track.genre);
  String? titleErrorText;
  String? yearErrorText;
  String? trackNumberErrorText;

  try {
    return showDialog<_TrackMetadataDraft>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void submit() {
              final title = titleController.text.trim();
              if (title.isEmpty) {
                setDialogState(() {
                  titleErrorText = 'Title is required';
                });
                return;
              }

              final yearText = yearController.text.trim();
              final year = yearText.isEmpty ? null : int.tryParse(yearText);
              final trackNumberText = trackNumberController.text.trim();
              final trackNumber = trackNumberText.isEmpty
                  ? null
                  : int.tryParse(trackNumberText);
              if ((yearText.isNotEmpty &&
                      (year == null || year < 1000 || year > 9999)) ||
                  (trackNumberText.isNotEmpty &&
                      (trackNumber == null || trackNumber <= 0))) {
                setDialogState(() {
                  yearErrorText =
                      yearText.isNotEmpty &&
                          (year == null || year < 1000 || year > 9999)
                      ? 'Use a four-digit year'
                      : null;
                  trackNumberErrorText =
                      trackNumberText.isNotEmpty &&
                          (trackNumber == null || trackNumber <= 0)
                      ? 'Use a positive whole number'
                      : null;
                });
                return;
              }

              Navigator.of(dialogContext).pop(
                _TrackMetadataDraft(
                  title: title,
                  artist: artistController.text,
                  album: albumController.text,
                  albumArtist: albumArtistController.text,
                  year: year,
                  trackNumber: trackNumber,
                  genre: genreController.text,
                ),
              );
            }

            return AlertDialog(
              title: const Text('Edit metadata'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextField(
                        autofocus: true,
                        controller: titleController,
                        decoration: InputDecoration(
                          errorText: titleErrorText,
                          labelText: 'Title',
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (titleErrorText != null) {
                            setDialogState(() {
                              titleErrorText = null;
                            });
                          }
                        },
                      ),
                      TextField(
                        controller: artistController,
                        decoration: const InputDecoration(labelText: 'Artist'),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: albumController,
                        decoration: const InputDecoration(labelText: 'Album'),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: albumArtistController,
                        decoration: const InputDecoration(
                          labelText: 'Album artist',
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      TextField(
                        controller: yearController,
                        decoration: InputDecoration(
                          errorText: yearErrorText,
                          labelText: 'Release year',
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (yearErrorText != null) {
                            setDialogState(() {
                              yearErrorText = null;
                            });
                          }
                        },
                      ),
                      TextField(
                        controller: trackNumberController,
                        decoration: InputDecoration(
                          errorText: trackNumberErrorText,
                          labelText: 'Track number',
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (trackNumberErrorText != null) {
                            setDialogState(() {
                              trackNumberErrorText = null;
                            });
                          }
                        },
                      ),
                      TextField(
                        controller: genreController,
                        decoration: const InputDecoration(labelText: 'Genre'),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => submit(),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const Key('track-metadata-find-musicbrainz'),
                          onPressed: library.offlineModeEnabled
                              ? null
                              : () async {
                                  final candidate =
                                      await showMusicBrainzMetadataSearchSheet(
                                        dialogContext,
                                        track: Track(
                                          id: track.id,
                                          title: titleController.text,
                                          artist: artistController.text,
                                          album: albumController.text,
                                          genre: genreController.text,
                                          duration: track.duration,
                                        ),
                                        provider: _musicBrainzMetadataProvider,
                                        offlineModeEnabled:
                                            library.offlineModeEnabled,
                                      );
                                  if (candidate == null ||
                                      !dialogContext.mounted) {
                                    return;
                                  }
                                  setDialogState(() {
                                    titleController.text = candidate.title;
                                    artistController.text = candidate.artist;
                                    albumController.text = candidate.album;
                                    if (candidate.genre.isNotEmpty) {
                                      genreController.text = candidate.genre;
                                    }
                                    titleErrorText = null;
                                  });
                                },
                          icon: const Icon(Icons.manage_search_outlined),
                          label: const Text('Find metadata'),
                        ),
                      ),
                      if (library.offlineModeEnabled)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('Offline mode prevents metadata lookup.'),
                        ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(onPressed: submit, child: const Text('Save')),
              ],
            );
          },
        );
      },
    );
  } finally {
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    albumArtistController.dispose();
    yearController.dispose();
    trackNumberController.dispose();
    genreController.dispose();
  }
}

Future<void> _editTrackArtwork(BuildContext context, Track track) async {
  if (track.sourceId != 'local') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Artwork editing is available for local library tracks.'),
      ),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose image file'),
              subtitle: const Text(
                'Store a private PNG, JPEG, GIF, or WebP image.',
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickTrackArtworkFile(context, track);
              },
            ),
            ListTile(
              leading: const Icon(Icons.link_outlined),
              title: const Text('Set image URL'),
              subtitle: const Text('Use an http or https image URL.'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _setTrackArtworkUrl(context, track);
              },
            ),
            if (track.artworkUri != null)
              ListTile(
                leading: const Icon(Icons.crop_outlined),
                title: const Text('Crop and position'),
                subtitle: const Text('Pan and zoom the current artwork.'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _editTrackArtworkCrop(context, track);
                },
              ),
            if (_isLocalM4aM4bM4rOrAlac(track))
              ListTile(
                leading: const Icon(Icons.save_alt_outlined),
                title: const Text('Write cover to M4A/M4B/M4R/ALAC file'),
                subtitle: const Text(
                  'Replace the embedded cover with a PNG or JPEG under 512 KiB.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _writeM4aArtwork(context, track);
                },
              ),
            if (track.artworkIsUserManaged)
              ListTile(
                leading: const Icon(Icons.restore_outlined),
                title: const Text('Restore scanned artwork'),
                subtitle: const Text(
                  'Remove the saved cover and use the embedded artwork again.',
                ),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await _restoreTrackArtwork(context, track);
                },
              ),
          ],
        ),
      );
    },
  );
}

Future<void> _pickTrackArtworkFile(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await pickSingleFile(
    type: FileType.image,
    dialogTitle: 'Choose track artwork',
  );
  if (!context.mounted || file == null) {
    return;
  }

  Uri? savedArtwork;
  try {
    savedArtwork = await _trackArtworkFileStore.save(
      await readPickedFileBytes(file),
    );
    if (!context.mounted) {
      await _trackArtworkFileStore.delete(savedArtwork);
      return;
    }
    final updated = await context.read<LibraryStore>().updateTrackArtwork(
      track.id,
      savedArtwork,
    );
    if (!context.mounted || updated == null) {
      await _trackArtworkFileStore.delete(savedArtwork);
      return;
    }
    await _trackArtworkFileStore.delete(
      track.artworkIsUserManaged ? track.artworkUri : null,
    );
    if (!context.mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Updated artwork for ${updated.title}.')),
    );
  } on FormatException catch (error) {
    await _trackArtworkFileStore.delete(savedArtwork);
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on Object catch (error) {
    await _trackArtworkFileStore.delete(savedArtwork);
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save artwork: $error')),
      );
    }
  }
}

Future<void> _writeM4aArtwork(BuildContext context, Track track) async {
  final messenger = ScaffoldMessenger.of(context);
  final library = context.read<LibraryStore>();
  final file = await pickSingleFile(
    type: FileType.image,
    dialogTitle: 'Choose M4A/M4B/M4R/ALAC cover artwork',
  );
  if (!context.mounted || file == null) {
    return;
  }

  final artwork = await readPickedFileBytes(file);
  if (!context.mounted) {
    return;
  }
  final confirmed = await _confirmM4aArtworkWrite(context);
  if (!context.mounted || confirmed != true) {
    return;
  }

  try {
    await const M4aMetadataWriter().writeArtwork(
      path: track.localPath!,
      artwork: artwork,
    );
    final updated = await library.updateEmbeddedTrackArtwork(
      track.id,
      _m4aArtworkDataUri(artwork),
    );
    if (!context.mounted || updated == null) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Wrote embedded artwork for ${updated.title}.')),
    );
  } on FormatException catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  } on Object catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not update embedded M4A/M4B/M4R/ALAC artwork: $error',
          ),
        ),
      );
    }
  }
}

Future<bool?> _confirmM4aArtworkWrite(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Update M4A/M4B/M4R/ALAC embedded artwork?'),
      content: const Text(
        'This replaces the file cover with the selected PNG or JPEG. Other M4A/M4B/M4R/ALAC metadata is preserved. Standard front-loaded files repair validated chunk offsets; malformed or fragmented layouts are left unchanged.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Update M4A/M4B/M4R/ALAC'),
        ),
      ],
    ),
  );
}

Uri _m4aArtworkDataUri(List<int> artwork) {
  final mimeType =
      artwork.length >= 8 &&
          artwork[0] == 0x89 &&
          artwork[1] == 0x50 &&
          artwork[2] == 0x4e &&
          artwork[3] == 0x47 &&
          artwork[4] == 0x0d &&
          artwork[5] == 0x0a &&
          artwork[6] == 0x1a &&
          artwork[7] == 0x0a
      ? 'image/png'
      : 'image/jpeg';
  return Uri.parse('data:$mimeType;base64,${base64Encode(artwork)}');
}

Future<void> _setTrackArtworkUrl(BuildContext context, Track track) async {
  final initialValue =
      track.artworkIsUserManaged &&
          track.artworkUri != null &&
          _isNetworkImageUri(track.artworkUri!)
      ? track.artworkUri!.toString()
      : '';
  final value = await _promptForTrackArtworkUrl(context, initialValue);
  if (!context.mounted || value == null) {
    return;
  }

  final artworkUri = Uri.tryParse(value.trim());
  if (artworkUri == null || !_isNetworkImageUri(artworkUri)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enter an http or https image URL.')),
    );
    return;
  }

  try {
    final updated = await context.read<LibraryStore>().updateTrackArtwork(
      track.id,
      artworkUri,
    );
    if (!context.mounted || updated == null) {
      return;
    }
    await _trackArtworkFileStore.delete(
      track.artworkIsUserManaged ? track.artworkUri : null,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Updated artwork for ${updated.title}.')),
    );
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save artwork: $error')));
    }
  }
}

Future<void> _restoreTrackArtwork(BuildContext context, Track track) async {
  final updated = await context.read<LibraryStore>().updateTrackArtwork(
    track.id,
    null,
  );
  if (!context.mounted || updated == null) {
    return;
  }
  await _trackArtworkFileStore.delete(track.artworkUri);
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Restored scanned artwork for ${updated.title}.')),
  );
}

Future<void> _editTrackArtworkCrop(BuildContext context, Track track) async {
  final artworkUri = track.artworkUri;
  if (artworkUri == null) {
    return;
  }
  final crop = await showArtworkCropEditor(
    context,
    artworkUri: artworkUri,
    initialCrop: track.artworkCrop,
  );
  if (!context.mounted || crop == null) {
    return;
  }
  final updated = await context.read<LibraryStore>().updateTrackArtworkCrop(
    track.id,
    crop,
  );
  if (!context.mounted || updated == null) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Updated artwork crop for ${updated.title}.')),
  );
}

Future<String?> _promptForTrackArtworkUrl(
  BuildContext context,
  String initialValue,
) async {
  final controller = TextEditingController(text: initialValue);
  try {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Track artwork URL'),
          content: TextField(
            autofocus: true,
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Image URL',
              hintText: 'https://example.com/cover.png',
            ),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  } finally {
    controller.dispose();
  }
}
