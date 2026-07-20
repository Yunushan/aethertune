import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'android_video_picture_in_picture.dart';
import '../domain/legal_video_captions.dart';
import '../domain/video_frame_capture.dart';
import '../domain/video_track_selection.dart';
import 'platform_image_share.dart';

enum _CaptionAction { choose, embedded, automatic, disabled }

enum _FrameAction { save, share }

/// Full-screen-capable renderer for user-selected local or HTTPS video.
class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({
    super.key,
    required this.source,
    required this.title,
  });

  final Uri source;
  final String title;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  final _pictureInPicture = AndroidVideoPictureInPictureBridge();
  Object? _error;
  var _opening = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await _player.open(Media(widget.source.toString()));
      final sidecar = await loadLocalVideoCaptionSidecar(widget.source);
      if (sidecar != null) {
        await _player.setSubtitleTrack(
          SubtitleTrack.data(sidecar.text, title: sidecar.title),
        );
      }
      if (mounted) {
        setState(() => _opening = false);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _opening = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reload video',
            onPressed: _opening ? null : () => unawaited(_open()),
            icon: const Icon(Icons.refresh),
          ),
          if (_pictureInPicture.isSupportedPlatform)
            IconButton(
              tooltip: 'Picture in picture',
              onPressed: _opening || error != null
                  ? null
                  : () => unawaited(_enterPictureInPicture()),
              icon: const Icon(Icons.picture_in_picture_alt_outlined),
            ),
          IconButton(
            tooltip: 'Audio tracks',
            onPressed: _opening || error != null
                ? null
                : () => unawaited(_selectEmbeddedAudioTrack()),
            icon: const Icon(Icons.audiotrack_outlined),
          ),
          PopupMenuButton<_CaptionAction>(
            tooltip: 'Captions',
            enabled: !_opening && error == null,
            icon: const Icon(Icons.closed_caption_outlined),
            onSelected: (action) => unawaited(_selectCaptions(action)),
            itemBuilder: (context) => const <PopupMenuEntry<_CaptionAction>>[
              PopupMenuItem<_CaptionAction>(
                value: _CaptionAction.choose,
                child: Text('Choose captions'),
              ),
              PopupMenuItem<_CaptionAction>(
                value: _CaptionAction.embedded,
                child: Text('Choose embedded captions'),
              ),
              PopupMenuItem<_CaptionAction>(
                value: _CaptionAction.automatic,
                child: Text('Use embedded captions'),
              ),
              PopupMenuItem<_CaptionAction>(
                value: _CaptionAction.disabled,
                child: Text('Turn captions off'),
              ),
            ],
          ),
          PopupMenuButton<_FrameAction>(
            tooltip: 'Capture video frame',
            enabled: !_opening && error == null,
            icon: const Icon(Icons.camera_alt_outlined),
            onSelected: (action) => unawaited(_captureFrame(action)),
            itemBuilder: (context) => const <PopupMenuEntry<_FrameAction>>[
              PopupMenuItem<_FrameAction>(
                value: _FrameAction.save,
                child: Text('Save frame'),
              ),
              PopupMenuItem<_FrameAction>(
                value: _FrameAction.share,
                child: Text('Share frame'),
              ),
            ],
          ),
        ],
      ),
      body: ColoredBox(
        color: Colors.black,
        child: Center(
          child: error == null
              ? Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Video(controller: _controller),
                    if (_opening) const CircularProgressIndicator(),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.video_file_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text('Could not open this video.'),
                    const SizedBox(height: 8),
                    IconButton(
                      tooltip: 'Retry video',
                      onPressed: () => unawaited(_open()),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _enterPictureInPicture() async {
    if (await _pictureInPicture.enter() || !mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Picture in picture is unavailable.')),
    );
  }

  Future<void> _selectCaptions(_CaptionAction action) async {
    switch (action) {
      case _CaptionAction.embedded:
        await _selectEmbeddedSubtitleTrack();
        return;
      case _CaptionAction.automatic:
        await _player.setSubtitleTrack(SubtitleTrack.auto());
        return;
      case _CaptionAction.disabled:
        await _player.setSubtitleTrack(SubtitleTrack.no());
        return;
      case _CaptionAction.choose:
        break;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['srt', 'vtt'],
      allowMultiple: false,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read that caption file.')),
      );
      return;
    }

    try {
      final captions = decodeLegalVideoCaptionDocument(
        bytes,
        fileName: file.name,
      );
      await _player.setSubtitleTrack(
        SubtitleTrack.data(captions.text, title: captions.title),
      );
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load captions: $error')),
      );
    }
  }

  Future<void> _selectEmbeddedAudioTrack() async {
    final tracks = _player.state.tracks.audio
        .where(
          (track) =>
              isSelectableEmbeddedVideoTrackId(track.id) && !track.uri,
        )
        .toList(growable: false);
    final selected = await _pickTrack<AudioTrack>(
      tracks: tracks,
      title: 'Audio tracks',
      fallback: 'Audio',
      labelFor: (track, index) => videoTrackSelectionLabel(
        fallback: 'Audio',
        index: index,
        title: track.title,
        language: track.language,
      ),
    );
    if (selected != null) {
      await _player.setAudioTrack(selected);
    }
  }

  Future<void> _selectEmbeddedSubtitleTrack() async {
    final tracks = _player.state.tracks.subtitle
        .where(
          (track) =>
              isSelectableEmbeddedVideoTrackId(track.id) &&
              !track.uri &&
              !track.data,
        )
        .toList(growable: false);
    final selected = await _pickTrack<SubtitleTrack>(
      tracks: tracks,
      title: 'Embedded captions',
      fallback: 'Caption',
      labelFor: (track, index) => videoTrackSelectionLabel(
        fallback: 'Caption',
        index: index,
        title: track.title,
        language: track.language,
      ),
    );
    if (selected != null) {
      await _player.setSubtitleTrack(selected);
    }
  }

  Future<T?> _pickTrack<T>({
    required List<T> tracks,
    required String title,
    required String fallback,
    required String Function(T track, int index) labelFor,
  }) async {
    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No $fallback tracks are available.')),
        );
      }
      return null;
    }

    return showModalBottomSheet<T>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              ListTile(title: Text(title)),
              for (var index = 0; index < tracks.length; index += 1)
                ListTile(
                  leading: Icon(
                    fallback == 'Audio'
                        ? Icons.audiotrack_outlined
                        : Icons.closed_caption_outlined,
                  ),
                  title: Text(labelFor(tracks[index], index)),
                  onTap: () => Navigator.of(sheetContext).pop(tracks[index]),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureFrame(_FrameAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await captureVideoFramePng(
        () => _player.screenshot(
          format: 'image/png',
          includeLibassSubtitles: true,
        ),
      );
      if (!mounted) {
        return;
      }

      switch (action) {
        case _FrameAction.save:
          await _saveFrame(bytes);
          break;
        case _FrameAction.share:
          final status = await const SharePlusImageShareService().share(
            PlatformImageShareRequest(
              bytes: bytes,
              fileName: 'aethertune-video-frame.png',
              title: 'AetherTune video frame',
              subject: 'AetherTune video frame',
              text: 'Video frame captured in AetherTune.',
              sharePositionOrigin: platformSharePositionOrigin(context),
            ),
          );
          if (!mounted || status == PlatformImageShareStatus.shared) {
            return;
          }
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                status == PlatformImageShareStatus.dismissed
                    ? 'Frame sharing was dismissed.'
                    : 'Frame sharing is unavailable.',
              ),
            ),
          );
          break;
      }
    } on Object catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not capture video frame: $error')),
        );
      }
    }
  }

  Future<void> _saveFrame(Uint8List bytes) async {
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save video frame',
      fileName: 'aethertune-video-frame.png',
      type: FileType.custom,
      allowedExtensions: const <String>['png'],
      bytes: bytes,
    );
    if (outputPath == null || outputPath.isEmpty) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File(outputPath).writeAsBytes(bytes, flush: true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved aethertune-video-frame.png.')),
      );
    }
  }
}
