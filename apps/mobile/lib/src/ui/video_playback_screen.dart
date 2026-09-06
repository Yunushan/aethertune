import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'android_video_picture_in_picture.dart';
import '../data/file_picker_adapter.dart';
import '../domain/legal_video_captions.dart';
import '../domain/video_frame_capture.dart';
import '../domain/video_track_selection.dart';
import 'platform_image_share.dart';

enum _CaptionAction { choose, embedded, automatic, disabled }

enum _FrameAction { save, share }

typedef VideoPlayback = ({
  Player player,
  Widget video,
  Future<void> firstFrame,
});
typedef VideoPlaybackFactory = VideoPlayback Function();

/// Full-screen-capable renderer for user-selected local or HTTPS video.
class VideoPlaybackScreen extends StatefulWidget {
  const VideoPlaybackScreen({
    super.key,
    required this.source,
    required this.title,
    this.playbackFactory,
  });

  final Uri source;
  final String title;
  @visibleForTesting
  final VideoPlaybackFactory? playbackFactory;

  @override
  State<VideoPlaybackScreen> createState() => _VideoPlaybackScreenState();
}

class _VideoPlaybackScreenState extends State<VideoPlaybackScreen> {
  static const _startupTimeout = Duration(seconds: 30);
  static const _cleanupTimeout = Duration(seconds: 10);
  VideoPlayback? _playback;
  StreamSubscription<String>? _errorSubscription;
  Future<void> _pendingDisposal = Future<void>.value();
  Completer<void>? _cancelOpen;
  int _generation = 0;
  Player get _player => _playback!.player;
  final _pictureInPicture = AndroidVideoPictureInPictureBridge();
  Object? _error;
  var _opening = true;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void didUpdateWidget(covariant VideoPlaybackScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) unawaited(_open());
  }

  @override
  void dispose() {
    _generation++;
    _cancelOpeningWait();
    _retirePlayback();
    super.dispose();
  }

  Future<void> _open() async {
    final generation = ++_generation;
    _cancelOpeningWait();
    final cancelled = _cancelOpen = Completer<void>();
    final cleanup = _retirePlayback();
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await _waitFor(cleanup, cancelled, _cleanupTimeout);
      if (!_isCurrent(generation)) return;
      final source = widget.source;
      final playback = widget.playbackFactory?.call() ?? _createPlayback();
      setState(() => _playback = playback);
      _errorSubscription = playback.player.stream.error.listen((_) {
        _fail(generation);
      });
      await _waitFor(
        _initializePlayback(playback, source, generation),
        cancelled,
        _startupTimeout,
      );
      if (_isCurrent(generation)) {
        setState(() => _opening = false);
      }
    } on Object {
      _fail(generation);
    }
  }

  bool _isCurrent(int generation) =>
      mounted && generation == _generation && _error == null;

  void _cancelOpeningWait() {
    final cancelled = _cancelOpen;
    _cancelOpen = null;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
  }

  static Future<void> _waitFor(
    Future<void> operation,
    Completer<void> cancelled,
    Duration timeout,
  ) => Future.any<void>([operation, cancelled.future]).timeout(timeout);

  Future<void> _initializePlayback(
    VideoPlayback playback,
    Uri source,
    int generation,
  ) async {
    // Native open accepts the source before decoding/rendering necessarily ends.
    await Future.wait<void>([
      playback.player.open(Media(source.toString())),
      playback.firstFrame,
    ], eagerError: true);
    if (!_isCurrent(generation)) return;
    final sidecar = await loadLocalVideoCaptionSidecar(source);
    if (!_isCurrent(generation)) return;
    if (sidecar != null) {
      await playback.player.setSubtitleTrack(
        SubtitleTrack.data(sidecar.text, title: sidecar.title),
      );
    }
  }

  Future<void> _retirePlayback() {
    final playback = _playback;
    if (playback == null) return _pendingDisposal;
    final subscription = _errorSubscription;
    _playback = null;
    _errorSubscription = null;
    // A timeout stops waiting, not native cleanup. Keep this future across
    // retries/source changes and never allocate a successor before it succeeds.
    _pendingDisposal = () async {
      try {
        await subscription?.cancel();
      } finally {
        await playback.player.dispose();
      }
    }();
    // Unmount has no waiter. Keep cleanup errors observed, but retries still
    // await the original failed future and cannot accumulate native players.
    _pendingDisposal.ignore();
    return _pendingDisposal;
  }

  static VideoPlayback _createPlayback() {
    final player = Player();
    final controller = VideoController(player);
    return (
      player: player,
      video: Video(controller: controller),
      firstFrame: controller.waitUntilFirstFrameRendered,
    );
  }

  void _fail(int generation) {
    if (!mounted || generation != _generation || _error != null) return;
    setState(() {
      _opening = false;
      _error = const FormatException('Video playback failed.');
    });
    _cancelOpeningWait();
    unawaited(_stopFailedPlayer(_playback?.player));
  }

  static Future<void> _stopFailedPlayer(Player? player) async {
    try {
      await player?.stop();
    } on Object {
      // The error UI remains available when the native device cannot stop.
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
                    _playback?.video ?? const SizedBox.shrink(),
                    if (_opening) const CircularProgressIndicator(),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Semantics(
                    liveRegion: true,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons.video_file_outlined,
                          size: 48,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Could not open this video.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        IconButton(
                          tooltip: 'Retry video',
                          onPressed: () => unawaited(_open()),
                          color: Colors.white,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
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

    final file = await pickSingleFile(
      type: FileType.custom,
      allowedExtensions: const <String>['srt', 'vtt'],
    );
    if (!mounted || file == null) {
      return;
    }

    try {
      final bytes = await readPickedFileBytes(file);
      if (!mounted) {
        return;
      }
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
          (track) => isSelectableEmbeddedVideoTrackId(track.id) && !track.uri,
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
    if (outputPath == null) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) {
      await File.fromUri(outputPath).writeAsBytes(bytes, flush: true);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved aethertune-video-frame.png.')),
      );
    }
  }
}
