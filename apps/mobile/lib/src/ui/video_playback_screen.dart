import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'android_video_picture_in_picture.dart';

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
}
