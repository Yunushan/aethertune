import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'android_video_picture_in_picture.dart';
import '../domain/legal_video_captions.dart';

enum _CaptionAction { choose, automatic, disabled }

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
                value: _CaptionAction.automatic,
                child: Text('Use embedded captions'),
              ),
              PopupMenuItem<_CaptionAction>(
                value: _CaptionAction.disabled,
                child: Text('Turn captions off'),
              ),
            ],
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
      case _CaptionAction.automatic:
        await _player.setSubtitleTrack(SubtitleTrack.auto());
        return;
      case _CaptionAction.disabled:
        await _player.setSubtitleTrack(SubtitleTrack.no());
        return;
      case _CaptionAction.choose:
        break;
    }

    final result = await FilePicker.platform.pickFiles(
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
}
