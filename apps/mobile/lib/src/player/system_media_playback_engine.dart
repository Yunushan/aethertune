import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:just_audio/just_audio.dart';

import '../domain/track.dart';
import 'android_playback_widget_bridge.dart';
import 'desktop_media_session.dart';
import 'playback_audio_effects.dart';
import 'playback_audio_engine.dart';

/// Adds operating-system media controls around the app's playback engine.
class SystemMediaPlaybackEngine extends BaseAudioHandler
    with SeekHandler
    implements
        CrossfadePlaybackAudioEngine,
        AudioEffectsPlaybackAudioEngine,
        VirtualizerPlaybackAudioEngine,
        AudioVisualizationPlaybackAudioEngine,
        SkipSilencePlaybackAudioEngine,
        PitchPlaybackAudioEngine,
        PlaybackErrorAudioEngine,
        MediaLibraryBrowsePlaybackAudioEngine {
  SystemMediaPlaybackEngine(
    this._engine, {
    PlaybackWidgetBridge? playbackWidgetBridge,
    DesktopMediaSession? desktopMediaSession,
  }) : _playbackWidgetBridge =
           playbackWidgetBridge ?? const AndroidPlaybackWidgetBridge(),
       _desktopMediaSession = desktopMediaSession {
    _stateSubscription = _engine.stateChanges.listen((_) => _publishState());
    _processingSubscription = _engine.processingStateStream.listen((state) {
      _processingState = state;
      _publishState();
    });
    _indexSubscription = _engine.currentIndexStream.listen((index) {
      _currentIndex = index;
      _runtimeDuration = null;
      _publishQueueAndCurrentItem();
      _publishState();
    });
    _durationSubscription = _engine.durationStream.listen((duration) {
      _runtimeDuration = duration;
      _publishQueueAndCurrentItem();
      _publishWidgetState();
      _publishDesktopMediaSession();
    });
    _positionSubscription = _engine.positionStream.listen(
      _publishWidgetProgress,
    );
    _publishState();
    unawaited(_startDesktopMediaSession());
  }

  static const _widgetProgressUpdateInterval = Duration(seconds: 1);
  static const _androidAutoQueueId = 'aethertune:android-auto:queue';
  static const _androidAutoLibraryId = 'aethertune:android-auto:library';
  static const _androidAutoAllTracksId =
      'aethertune:android-auto:library:all-tracks';
  static const _androidAutoPlaylistsId =
      'aethertune:android-auto:library:playlists';
  static const _androidAutoArtistsId =
      'aethertune:android-auto:library:artists';
  static const _androidAutoAlbumsId =
      'aethertune:android-auto:library:albums';
  static const _androidAutoGenresId =
      'aethertune:android-auto:library:genres';
  static const _androidAutoSourcesId =
      'aethertune:android-auto:library:sources';
  static const _androidAutoFoldersId =
      'aethertune:android-auto:library:folders';
  static const _androidAutoPlaylistIdPrefix =
      'aethertune:android-auto:library:playlist:';
  static const _androidAutoPlaylistTrackIdPrefix =
      'aethertune:android-auto:library:playlist-track:';
  static const _androidAutoFolderIdPrefix =
      'aethertune:android-auto:library:folder:';
  static const _androidAutoFolderTrackIdPrefix =
      'aethertune:android-auto:library:folder-track:';
  static const _androidAutoLibraryTrackIdPrefix =
      'aethertune:android-auto:library-track:';

  final PlaybackAudioEngine _engine;
  final PlaybackWidgetBridge _playbackWidgetBridge;
  final DesktopMediaSession? _desktopMediaSession;
  final List<Track> _tracks = <Track>[];
  final List<Track> _libraryBrowseTracks = <Track>[];
  final List<MediaLibraryBrowsePlaylist> _libraryBrowsePlaylists =
      <MediaLibraryBrowsePlaylist>[];
  final List<MediaLibraryBrowseFolder> _libraryBrowseFolders =
      <MediaLibraryBrowseFolder>[];
  MediaLibraryTrackSelectionHandler? _onLibraryTrackSelected;
  MediaLibraryPlaylistTrackSelectionHandler? _onPlaylistTrackSelected;
  StreamSubscription<Object?>? _stateSubscription;
  StreamSubscription<ProcessingState>? _processingSubscription;
  StreamSubscription<int?>? _indexSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  int? _currentIndex;
  Duration? _runtimeDuration;
  Duration? _lastWidgetProgressPosition;
  ProcessingState _processingState = ProcessingState.idle;
  bool _desktopMediaSessionStarted = false;

  @override
  Stream<Object?> get stateChanges => _engine.stateChanges;

  @override
  Stream<Duration?> get durationStream => _engine.durationStream;

  @override
  Stream<Duration> get positionStream => _engine.positionStream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _engine.processingStateStream;

  @override
  Stream<int?> get currentIndexStream => _engine.currentIndexStream;

  @override
  Stream<Object> get errorStream {
    final engine = _engine;
    return engine is PlaybackErrorAudioEngine
        ? (engine as PlaybackErrorAudioEngine).errorStream
        : const Stream<Object>.empty();
  }

  @override
  bool get playing => _engine.playing;

  @override
  bool get shuffleModeEnabled => _engine.shuffleModeEnabled;

  @override
  LoopMode get loopMode => _engine.loopMode;

  @override
  Duration get position => _engine.position;

  @override
  Duration get bufferedPosition => _engine.bufferedPosition;

  @override
  double get speed => _engine.speed;

  @override
  bool get supportsPitch =>
      _engine is PitchPlaybackAudioEngine && _engine.supportsPitch;

  @override
  double get pitch => _engine is PitchPlaybackAudioEngine ? _engine.pitch : 1;

  @override
  double get volume => _engine.volume;

  @override
  bool get hasNext => _engine.hasNext;

  @override
  bool get hasPrevious => _engine.hasPrevious;

  @override
  bool get supportsCrossfade =>
      _engine is CrossfadePlaybackAudioEngine &&
      _engine.supportsCrossfade;

  @override
  Duration get crossfadeDuration => _engine is CrossfadePlaybackAudioEngine
      ? _engine.crossfadeDuration
      : Duration.zero;

  @override
  bool get supportsEqualizer =>
      _engine is AudioEffectsPlaybackAudioEngine && _engine.supportsEqualizer;

  @override
  bool get supportsLoudnessEnhancer =>
      _engine is AudioEffectsPlaybackAudioEngine &&
      _engine.supportsLoudnessEnhancer;

  @override
  bool get supportsVirtualizer =>
      _engine is VirtualizerPlaybackAudioEngine && _engine.supportsVirtualizer;

  @override
  bool get supportsSkipSilence =>
      _engine is SkipSilencePlaybackAudioEngine &&
      _engine.supportsSkipSilence;

  @override
  bool get supportsVisualizer =>
      _engine is AudioVisualizationPlaybackAudioEngine &&
      _engine.supportsVisualizer;

  @override
  Stream<List<double>> get visualizerBands =>
      _engine is AudioVisualizationPlaybackAudioEngine
      ? _engine.visualizerBands
      : const Stream<List<double>>.empty();

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    final previousTracks = List<Track>.from(_tracks);
    final previousIndex = _currentIndex;
    _tracks
      ..clear()
      ..addAll(tracks);
    _currentIndex = initialIndex;
    _runtimeDuration = null;
    _publishQueueAndCurrentItem();

    try {
      await _engine.setQueue(
        tracks,
        initialIndex: initialIndex,
        initialPosition: initialPosition,
      );
      _publishState();
    } on Object {
      _tracks
        ..clear()
        ..addAll(previousTracks);
      _currentIndex = previousIndex;
      _runtimeDuration = null;
      _publishQueueAndCurrentItem();
      rethrow;
    }
  }

  @override
  void setMediaLibraryBrowseTracks(
    Iterable<Track> tracks, {
    required MediaLibraryTrackSelectionHandler onTrackSelected,
    Iterable<MediaLibraryBrowsePlaylist> playlists =
        const <MediaLibraryBrowsePlaylist>[],
    Iterable<MediaLibraryBrowseFolder> folders =
        const <MediaLibraryBrowseFolder>[],
    MediaLibraryPlaylistTrackSelectionHandler? onPlaylistTrackSelected,
  }) {
    _libraryBrowseTracks
      ..clear()
      ..addAll(tracks);
    _libraryBrowsePlaylists
      ..clear()
      ..addAll(playlists);
    _libraryBrowseFolders
      ..clear()
      ..addAll(folders);
    _onLibraryTrackSelected = onTrackSelected;
    _onPlaylistTrackSelected = onPlaylistTrackSelected;
    _publishMprisPlaylists();
  }

  @override
  Future<void> play() => _engine.play();

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> stop() async {
    await _engine.stop();
    _publishState();
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    await _engine.seek(position, index: index);
    _publishState();
  }

  @override
  Future<void> seekToNext() => _engine.seekToNext();

  @override
  Future<void> seekToPrevious() => _engine.seekToPrevious();

  @override
  Future<void> skipToNext() async {
    if (_engine.hasNext) {
      await _engine.seekToNext();
    } else if (_engine.loopMode == LoopMode.all && _tracks.isNotEmpty) {
      await _engine.seek(Duration.zero, index: 0);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_engine.hasPrevious) {
      await _engine.seekToPrevious();
    } else if (_engine.loopMode == LoopMode.all && _tracks.isNotEmpty) {
      await _engine.seek(Duration.zero, index: _tracks.length - 1);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.length) {
      throw RangeError.index(index, _tracks, 'index');
    }
    await _engine.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    await _engine.setShuffleModeEnabled(enabled);
    _publishState();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffleModeEnabled(shuffleMode != AudioServiceShuffleMode.none);

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    await _engine.setLoopMode(mode);
    _publishState();
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _engine.setSpeed(speed);
    _publishState();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      setLoopMode(_loopModeForRepeatMode(repeatMode));

  @override
  Future<void> setVolume(double volume) async {
    await _engine.setVolume(volume);
    setMprisVolume(volume);
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'dbusVolume') {
      final value = extras?['value'];
      if (value is num) {
        final volume = value.toDouble();
        if (volume.isFinite && volume >= 0 && volume <= 1) {
          await setVolume(volume);
        }
      }
      return;
    }
    return super.customAction(name, extras);
  }

  @override
  void setCrossfadeTrackVolumeResolver(
    CrossfadeTrackVolumeResolver? resolver,
  ) {
    final engine = _engine;
    if (engine is CrossfadePlaybackAudioEngine) {
      engine.setCrossfadeTrackVolumeResolver(resolver);
    }
  }

  @override
  Future<void> setCrossfadeDuration(Duration duration) {
    final engine = _engine;
    if (engine is! CrossfadePlaybackAudioEngine || !engine.supportsCrossfade) {
      throw UnsupportedError('Crossfade is unavailable for this audio backend.');
    }
    return engine.setCrossfadeDuration(duration);
  }

  @override
  Future<void> setPitch(double pitch) {
    final engine = _engine;
    if (engine is! PitchPlaybackAudioEngine || !engine.supportsPitch) {
      throw UnsupportedError('Pitch control is unavailable for this backend.');
    }
    return engine.setPitch(pitch);
  }

  @override
  Future<void> setEqualizerEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    return engine.setEqualizerEnabled(enabled);
  }

  @override
  Future<void> setEqualizerProfile(PlaybackEqualizerProfile profile) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    return engine.setEqualizerProfile(profile);
  }

  @override
  Future<List<PlaybackEqualizerBand>> loadEqualizerBands() {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsEqualizer) {
      throw UnsupportedError('Equalizer is unavailable for this audio backend.');
    }
    return engine.loadEqualizerBands();
  }

  @override
  Future<void> setLoudnessEnhancerEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsLoudnessEnhancer) {
      throw UnsupportedError(
        'Loudness enhancer is unavailable for this audio backend.',
      );
    }
    return engine.setLoudnessEnhancerEnabled(enabled);
  }

  @override
  Future<void> setLoudnessEnhancerTargetGain(double gainDb) {
    final engine = _engine;
    if (engine is! AudioEffectsPlaybackAudioEngine ||
        !engine.supportsLoudnessEnhancer) {
      throw UnsupportedError(
        'Loudness enhancer is unavailable for this audio backend.',
      );
    }
    return engine.setLoudnessEnhancerTargetGain(gainDb);
  }

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    switch (parentMediaId) {
      case AudioService.browsableRootId:
        return <MediaItem>[
          _androidAutoQueueFolder(),
          _androidAutoLibraryFolder(),
        ];
      case AudioService.recentRootId:
        final currentItem = _currentQueueMediaItem();
        return currentItem == null
            ? const <MediaItem>[]
            : <MediaItem>[currentItem];
      case _androidAutoQueueId:
        return _queueMediaItems();
      case _androidAutoLibraryId:
        return <MediaItem>[
          _androidAutoAllTracksFolder(),
          if (_hasBrowseCategory(MediaLibraryBrowseCategory.playlist))
            _androidAutoPlaylistsFolder(),
          if (_hasBrowseCategory(MediaLibraryBrowseCategory.artist))
            _androidAutoArtistsFolder(),
          if (_hasBrowseCategory(MediaLibraryBrowseCategory.album))
            _androidAutoAlbumsFolder(),
          if (_hasBrowseCategory(MediaLibraryBrowseCategory.genre))
            _androidAutoGenresFolder(),
          if (_hasBrowseCategory(MediaLibraryBrowseCategory.source))
            _androidAutoSourcesFolder(),
          if (_libraryBrowseFolders.isNotEmpty) _androidAutoFoldersFolder(),
        ];
      case _androidAutoAllTracksId:
        return _libraryBrowseMediaItems();
      case _androidAutoPlaylistsId:
        return _playlistBrowseFolders(MediaLibraryBrowseCategory.playlist);
      case _androidAutoArtistsId:
        return _playlistBrowseFolders(MediaLibraryBrowseCategory.artist);
      case _androidAutoAlbumsId:
        return _playlistBrowseFolders(MediaLibraryBrowseCategory.album);
      case _androidAutoGenresId:
        return _playlistBrowseFolders(MediaLibraryBrowseCategory.genre);
      case _androidAutoSourcesId:
        return _playlistBrowseFolders(MediaLibraryBrowseCategory.source);
      case _androidAutoFoldersId:
        return _libraryBrowseFolders.map(_folderBrowseFolder).toList(
          growable: false,
        );
      default:
        final folder = _folderForMediaId(parentMediaId);
        if (folder != null) {
          return _folderBrowseChildren(folder);
        }
        final playlist = _playlistForMediaId(parentMediaId);
        if (playlist != null) {
          return _playlistBrowseTrackItems(playlist);
        }
        return const <MediaItem>[];
    }
  }

  @override
  Future<MediaItem?> getMediaItem(String mediaId) async {
    if (mediaId == _androidAutoQueueId) {
      return _androidAutoQueueFolder();
    }
    if (mediaId == _androidAutoLibraryId) {
      return _androidAutoLibraryFolder();
    }
    if (mediaId == _androidAutoAllTracksId) {
      return _androidAutoAllTracksFolder();
    }
    if (mediaId == _androidAutoPlaylistsId) {
      return _androidAutoPlaylistsFolder();
    }
    if (mediaId == _androidAutoArtistsId) {
      return _androidAutoArtistsFolder();
    }
    if (mediaId == _androidAutoAlbumsId) {
      return _androidAutoAlbumsFolder();
    }
    if (mediaId == _androidAutoGenresId) {
      return _androidAutoGenresFolder();
    }
    if (mediaId == _androidAutoSourcesId) {
      return _androidAutoSourcesFolder();
    }
    if (mediaId == _androidAutoFoldersId) {
      return _androidAutoFoldersFolder();
    }
    for (var index = 0; index < _tracks.length; index += 1) {
      if (_tracks[index].id == mediaId) {
        final runtimeDuration = index == _currentIndex
            ? _runtimeDuration
            : null;
        return _mediaItemForTrack(_tracks[index], runtimeDuration);
      }
    }
    final libraryTrack = _libraryTrackForMediaId(mediaId);
    if (libraryTrack != null) {
      return _mediaItemForTrack(
        libraryTrack,
        null,
        mediaId: mediaId,
      );
    }
    final folder = _folderForMediaId(mediaId);
    if (folder != null) {
      return _folderBrowseFolder(folder);
    }
    final folderSelection = _folderTrackSelectionForMediaId(mediaId);
    if (folderSelection != null) {
      return _mediaItemForTrack(
        folderSelection.track,
        null,
        mediaId: folderSelection.mediaId,
      );
    }
    final playlist = _playlistForMediaId(mediaId);
    if (playlist != null) {
      return _playlistBrowseFolder(playlist);
    }
    final playlistSelection = _playlistTrackSelectionForMediaId(mediaId);
    if (playlistSelection != null) {
      return _mediaItemForTrack(
        playlistSelection.track,
        null,
        mediaId: playlistSelection.mediaId,
      );
    }
    return null;
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final index = _tracks.indexWhere((track) => track.id == mediaId);
    if (index < 0) {
      final libraryTrack = _libraryTrackForMediaId(mediaId);
      if (libraryTrack != null) {
        final onLibraryTrackSelected = _onLibraryTrackSelected;
        if (onLibraryTrackSelected != null) {
          await onLibraryTrackSelected(libraryTrack);
        }
        return;
      }
      final playlist = _playlistForMediaId(mediaId);
      final onPlaylistTrackSelected = _onPlaylistTrackSelected;
      if (playlist != null &&
          playlist.tracks.isNotEmpty &&
          onPlaylistTrackSelected != null) {
        await onPlaylistTrackSelected(playlist.tracks.first, playlist.tracks, 0);
        return;
      }
      final folderSelection = _folderTrackSelectionForMediaId(mediaId);
      if (folderSelection != null && onPlaylistTrackSelected != null) {
        await onPlaylistTrackSelected(
          folderSelection.track,
          folderSelection.folder.queueTracks,
          folderSelection.queueIndex,
        );
        return;
      }
      final playlistSelection = _playlistTrackSelectionForMediaId(mediaId);
      if (playlistSelection != null && onPlaylistTrackSelected != null) {
        await onPlaylistTrackSelected(
          playlistSelection.track,
          playlistSelection.playlist.tracks,
          playlistSelection.index,
        );
      }
      return;
    }
    await _engine.seek(Duration.zero, index: index);
    await _engine.play();
  }

  @override
  Future<void> setVirtualizerEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! VirtualizerPlaybackAudioEngine ||
        !engine.supportsVirtualizer) {
      throw UnsupportedError('Virtualizer is unavailable for this audio backend.');
    }
    return engine.setVirtualizerEnabled(enabled);
  }

  @override
  Future<void> setVirtualizerStrength(int strength) {
    final engine = _engine;
    if (engine is! VirtualizerPlaybackAudioEngine ||
        !engine.supportsVirtualizer) {
      throw UnsupportedError('Virtualizer is unavailable for this audio backend.');
    }
    return engine.setVirtualizerStrength(strength);
  }

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) {
    final engine = _engine;
    if (engine is! SkipSilencePlaybackAudioEngine ||
        !engine.supportsSkipSilence) {
      throw UnsupportedError(
        'Skip silence is unavailable for this audio backend.',
      );
    }
    return engine.setSkipSilenceEnabled(enabled);
  }

  @override
  Future<bool> startVisualizer() {
    final engine = _engine;
    if (engine is! AudioVisualizationPlaybackAudioEngine ||
        !engine.supportsVisualizer) {
      return Future<bool>.value(false);
    }
    return engine.startVisualizer();
  }

  @override
  Future<void> stopVisualizer() {
    final engine = _engine;
    if (engine is! AudioVisualizationPlaybackAudioEngine ||
        !engine.supportsVisualizer) {
      return Future<void>.value();
    }
    return engine.stopVisualizer();
  }

  @override
  Future<void> dispose() async {
    await _stateSubscription?.cancel();
    await _processingSubscription?.cancel();
    await _indexSubscription?.cancel();
    await _durationSubscription?.cancel();
    await _positionSubscription?.cancel();
    await _desktopMediaSession?.dispose();
    await _engine.dispose();
  }

  void _publishQueueAndCurrentItem() {
    final items = _queueMediaItems();
    queue.add(List<MediaItem>.unmodifiable(items));

    final index = _currentIndex;
    if (index == null || index < 0 || index >= items.length) {
      mediaItem.add(null);
      return;
    }
    mediaItem.add(items[index]);
  }

  List<MediaItem> _queueMediaItems() {
    return List<MediaItem>.generate(_tracks.length, (index) {
      final runtimeDuration = index == _currentIndex ? _runtimeDuration : null;
      return _mediaItemForTrack(_tracks[index], runtimeDuration);
    }, growable: false);
  }

  List<MediaItem> _libraryBrowseMediaItems() {
    return _libraryBrowseTracks
        .map(
          (track) => _mediaItemForTrack(
            track,
            null,
            mediaId: _libraryMediaId(track),
          ),
        )
        .toList(growable: false);
  }

  Track? _libraryTrackForMediaId(String mediaId) {
    if (!mediaId.startsWith(_androidAutoLibraryTrackIdPrefix)) {
      return null;
    }
    final trackId = mediaId.substring(_androidAutoLibraryTrackIdPrefix.length);
    for (final track in _libraryBrowseTracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  String _libraryMediaId(Track track) =>
      '$_androidAutoLibraryTrackIdPrefix${track.id}';

  MediaItem? _currentQueueMediaItem() {
    final index = _currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) {
      return null;
    }
    return _mediaItemForTrack(_tracks[index], _runtimeDuration);
  }

  MediaItem _androidAutoQueueFolder() {
    return const MediaItem(
      id: _androidAutoQueueId,
      title: 'Current queue',
      displaySubtitle: 'AetherTune',
      playable: false,
    );
  }

  MediaItem _androidAutoLibraryFolder() {
    return const MediaItem(
      id: _androidAutoLibraryId,
      title: 'Library',
      displaySubtitle: 'AetherTune',
      playable: false,
    );
  }

  MediaItem _androidAutoAllTracksFolder() {
    return const MediaItem(
      id: _androidAutoAllTracksId,
      title: 'All tracks',
      displaySubtitle: 'AetherTune library',
      playable: false,
    );
  }

  MediaItem _androidAutoPlaylistsFolder() {
    return const MediaItem(
      id: _androidAutoPlaylistsId,
      title: 'Playlists',
      displaySubtitle: 'AetherTune library',
      playable: false,
    );
  }

  MediaItem _androidAutoArtistsFolder() {
    return const MediaItem(
      id: _androidAutoArtistsId,
      title: 'Artists',
      displaySubtitle: 'AetherTune library',
      playable: false,
    );
  }

  MediaItem _androidAutoAlbumsFolder() {
    return const MediaItem(
      id: _androidAutoAlbumsId,
      title: 'Albums',
      displaySubtitle: 'AetherTune library',
      playable: false,
    );
  }

  MediaItem _androidAutoGenresFolder() {
    return const MediaItem(
      id: _androidAutoGenresId,
      title: 'Genres',
      displaySubtitle: 'AetherTune library',
      playable: false,
    );
  }

  MediaItem _androidAutoSourcesFolder() {
    return const MediaItem(
      id: _androidAutoSourcesId,
      title: 'Sources',
      displaySubtitle: 'AetherTune library',
      playable: false,
    );
  }

  MediaItem _androidAutoFoldersFolder() {
    return const MediaItem(
      id: _androidAutoFoldersId,
      title: 'Folders',
      displaySubtitle: 'AetherTune library',
      playable: false,
    );
  }

  bool _hasBrowseCategory(MediaLibraryBrowseCategory category) {
    return _libraryBrowsePlaylists.any(
      (collection) => collection.category == category,
    );
  }

  List<MediaItem> _playlistBrowseFolders(MediaLibraryBrowseCategory category) {
    return _libraryBrowsePlaylists
        .where((collection) => collection.category == category)
        .map(_playlistBrowseFolder)
        .toList(growable: false);
  }

  MediaItem _folderBrowseFolder(MediaLibraryBrowseFolder folder) {
    final childCount = folder.children.length;
    final directTrackCount = folder.directTracks.length;
    final subtitle = <String>[
      if (childCount > 0)
        childCount == 1 ? '1 folder' : '$childCount folders',
      if (directTrackCount > 0)
        directTrackCount == 1 ? '1 track' : '$directTrackCount tracks',
    ].join(', ');
    return MediaItem(
      id: _folderMediaId(folder),
      title: folder.title,
      displaySubtitle: subtitle,
      playable: false,
    );
  }

  List<MediaItem> _folderBrowseChildren(MediaLibraryBrowseFolder folder) {
    return <MediaItem>[
      ...folder.children.map(_folderBrowseFolder),
      ..._folderTrackSelections(folder).map(
        (selection) => _mediaItemForTrack(
          selection.track,
          null,
          mediaId: selection.mediaId,
        ),
      ),
    ];
  }

  MediaLibraryBrowseFolder? _folderForMediaId(String mediaId) {
    for (final folder in _allBrowseFolders()) {
      if (_folderMediaId(folder) == mediaId) {
        return folder;
      }
    }
    return null;
  }

  _FolderTrackSelection? _folderTrackSelectionForMediaId(String mediaId) {
    for (final folder in _allBrowseFolders()) {
      for (final selection in _folderTrackSelections(folder)) {
        if (selection.mediaId == mediaId) {
          return selection;
        }
      }
    }
    return null;
  }

  Iterable<MediaLibraryBrowseFolder> _allBrowseFolders() sync* {
    for (final folder in _libraryBrowseFolders) {
      yield folder;
      yield* _descendantBrowseFolders(folder);
    }
  }

  Iterable<MediaLibraryBrowseFolder> _descendantBrowseFolders(
    MediaLibraryBrowseFolder folder,
  ) sync* {
    for (final child in folder.children) {
      yield child;
      yield* _descendantBrowseFolders(child);
    }
  }

  Iterable<_FolderTrackSelection> _folderTrackSelections(
    MediaLibraryBrowseFolder folder,
  ) sync* {
    for (final track in folder.directTracks) {
      final queueIndex = folder.queueTracks.indexWhere(
        (candidate) => candidate.id == track.id,
      );
      if (queueIndex < 0) {
        continue;
      }
      yield _FolderTrackSelection(
        folder: folder,
        track: track,
        queueIndex: queueIndex,
      );
    }
  }

  String _folderMediaId(MediaLibraryBrowseFolder folder) =>
      '$_androidAutoFolderIdPrefix${Uri.encodeComponent(folder.id)}';

  MediaItem _playlistBrowseFolder(MediaLibraryBrowsePlaylist playlist) {
    final count = playlist.tracks.length;
    return MediaItem(
      id: _playlistMediaId(playlist),
      title: playlist.title,
      displaySubtitle: count == 1 ? '1 track' : '$count tracks',
      artUri: playlist.artworkUri,
      playable: false,
    );
  }

  List<MediaItem> _playlistBrowseTrackItems(
    MediaLibraryBrowsePlaylist playlist,
  ) {
    return _playlistTrackSelections(playlist)
        .map(
          (selection) => _mediaItemForTrack(
            selection.track,
            null,
            mediaId: selection.mediaId,
          ),
        )
        .toList(growable: false);
  }

  MediaLibraryBrowsePlaylist? _playlistForMediaId(String mediaId) {
    for (final playlist in _libraryBrowsePlaylists) {
      if (_playlistMediaId(playlist) == mediaId) {
        return playlist;
      }
    }
    return null;
  }

  _PlaylistTrackSelection? _playlistTrackSelectionForMediaId(String mediaId) {
    for (final playlist in _libraryBrowsePlaylists) {
      for (final selection in _playlistTrackSelections(playlist)) {
        if (selection.mediaId == mediaId) {
          return selection;
        }
      }
    }
    return null;
  }

  Iterable<_PlaylistTrackSelection> _playlistTrackSelections(
    MediaLibraryBrowsePlaylist playlist,
  ) sync* {
    for (var index = 0; index < playlist.tracks.length; index += 1) {
      yield _PlaylistTrackSelection(
        playlist: playlist,
        track: playlist.tracks[index],
        index: index,
      );
    }
  }

  String _playlistMediaId(MediaLibraryBrowsePlaylist playlist) =>
      '$_androidAutoPlaylistIdPrefix${playlist.category.name}:'
      '${Uri.encodeComponent(playlist.id)}';

  void _publishMprisPlaylists() {
    setMprisPlaylists(
      _libraryBrowsePlaylists
          .where(
            (playlist) =>
                playlist.category == MediaLibraryBrowseCategory.playlist,
          )
          .map(
            (playlist) => MprisPlaylist(
              mediaId: _playlistMediaId(playlist),
              name: playlist.title,
              iconUri: playlist.artworkUri?.toString() ?? '',
            ),
          ),
    );
  }

  void _publishState() {
    playbackState.add(
      PlaybackState(
        controls: <MediaControl>[
          if (_engine.hasPrevious || _engine.loopMode == LoopMode.all)
            MediaControl.skipToPrevious,
          if (_engine.playing) MediaControl.pause else MediaControl.play,
          if (_engine.hasNext || _engine.loopMode == LoopMode.all)
            MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const <MediaAction>{
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: _audioProcessingState(_processingState),
        playing: _engine.playing,
        updatePosition: _engine.position,
        bufferedPosition: _engine.bufferedPosition,
        speed: _engine.speed,
        queueIndex: _currentIndex,
        repeatMode: _repeatModeForLoopMode(_engine.loopMode),
        shuffleMode: _engine.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
      ),
    );
    _publishWidgetState();
    _publishDesktopMediaSession();
  }

  void _publishWidgetProgress(Duration position) {
    final lastPosition = _lastWidgetProgressPosition;
    if (!_engine.playing ||
        (lastPosition != null &&
            (position - lastPosition).abs() <
                _widgetProgressUpdateInterval)) {
      return;
    }
    _publishWidgetState(position: position);
  }

  void _publishWidgetState({Duration? position}) {
    final index = _currentIndex;
    final currentTrack = index != null && index >= 0 && index < _tracks.length
        ? _tracks[index]
        : null;
    final runtimeDuration = _runtimeDuration;
    final trackDuration = currentTrack?.duration ?? Duration.zero;
    final duration = runtimeDuration != null && runtimeDuration > Duration.zero
        ? runtimeDuration
        : trackDuration > Duration.zero
        ? trackDuration
        : null;
    final currentPosition = position ?? _engine.position;
    _lastWidgetProgressPosition = currentPosition;
    unawaited(
      _playbackWidgetBridge.update(
        track: currentTrack,
        isPlaying: _engine.playing,
        position: currentPosition,
        duration: duration,
      ),
    );
    _publishDesktopMediaSession();
  }

  Future<void> _startDesktopMediaSession() async {
    final session = _desktopMediaSession;
    if (session == null) {
      return;
    }
    try {
      await session.start(_handleDesktopMediaSessionCommand);
      _desktopMediaSessionStarted = true;
      _publishDesktopMediaSession();
    } on Object {
      // Native system-media integration must not prevent local playback.
    }
  }

  void _publishDesktopMediaSession() {
    final session = _desktopMediaSession;
    if (session == null || !_desktopMediaSessionStarted) {
      return;
    }
    final index = _currentIndex;
    final track = index != null && index >= 0 && index < _tracks.length
        ? _tracks[index]
        : null;
    final knownDuration = _runtimeDuration ?? track?.duration;
    unawaited(
      session
          .publish(
            DesktopMediaSessionState(
              track: track,
              processingState: _processingState,
              isPlaying: _engine.playing,
              position: _engine.position,
              duration: knownDuration != null && knownDuration > Duration.zero
                  ? knownDuration
                  : null,
              canGoPrevious:
                  _engine.hasPrevious || _engine.loopMode == LoopMode.all,
              canGoNext: _engine.hasNext || _engine.loopMode == LoopMode.all,
            ),
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _handleDesktopMediaSessionCommand(
    DesktopMediaSessionCommand command,
  ) {
    switch (command) {
      case DesktopMediaSessionCommand.play:
        return play();
      case DesktopMediaSessionCommand.pause:
        return pause();
      case DesktopMediaSessionCommand.previous:
        return skipToPrevious();
      case DesktopMediaSessionCommand.next:
        return skipToNext();
      case DesktopMediaSessionCommand.seekBackward:
        return seek(_offsetPosition(const Duration(seconds: -10)));
      case DesktopMediaSessionCommand.seekForward:
        return seek(_offsetPosition(const Duration(seconds: 30)));
      case DesktopMediaSessionCommand.stop:
        return stop();
    }
  }

  Duration _offsetPosition(Duration offset) {
    final target = _engine.position + offset;
    final duration = _runtimeDuration;
    if (target < Duration.zero) {
      return Duration.zero;
    }
    if (duration != null && duration > Duration.zero && target > duration) {
      return duration;
    }
    return target;
  }
}

MediaItem _mediaItemForTrack(
  Track track,
  Duration? runtimeDuration, {
  String? mediaId,
}) {
  final knownDuration = runtimeDuration ?? track.duration;
  return MediaItem(
    id: mediaId ?? track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    genre: track.genre,
    duration: knownDuration > Duration.zero ? knownDuration : null,
    artUri: track.artworkUri,
    extras: <String, Object>{
      'sourceId': track.sourceId,
      if (track.externalId != null) 'externalId': track.externalId!,
    },
  );
}

class _FolderTrackSelection {
  const _FolderTrackSelection({
    required this.folder,
    required this.track,
    required this.queueIndex,
  });

  final MediaLibraryBrowseFolder folder;
  final Track track;
  final int queueIndex;

  String get mediaId =>
      '${SystemMediaPlaybackEngine._androidAutoFolderTrackIdPrefix}'
      '${Uri.encodeComponent(folder.id)}:$queueIndex';
}

class _PlaylistTrackSelection {
  const _PlaylistTrackSelection({
    required this.playlist,
    required this.track,
    required this.index,
  });

  final MediaLibraryBrowsePlaylist playlist;
  final Track track;
  final int index;

  String get mediaId =>
      '${SystemMediaPlaybackEngine._androidAutoPlaylistTrackIdPrefix}'
      '${playlist.category.name}:${Uri.encodeComponent(playlist.id)}:$index';
}

AudioProcessingState _audioProcessingState(ProcessingState state) {
  switch (state) {
    case ProcessingState.idle:
      return AudioProcessingState.idle;
    case ProcessingState.loading:
      return AudioProcessingState.loading;
    case ProcessingState.buffering:
      return AudioProcessingState.buffering;
    case ProcessingState.ready:
      return AudioProcessingState.ready;
    case ProcessingState.completed:
      return AudioProcessingState.completed;
  }
}

AudioServiceRepeatMode _repeatModeForLoopMode(LoopMode mode) {
  switch (mode) {
    case LoopMode.off:
      return AudioServiceRepeatMode.none;
    case LoopMode.one:
      return AudioServiceRepeatMode.one;
    case LoopMode.all:
      return AudioServiceRepeatMode.all;
  }
}

LoopMode _loopModeForRepeatMode(AudioServiceRepeatMode mode) {
  switch (mode) {
    case AudioServiceRepeatMode.one:
      return LoopMode.one;
    case AudioServiceRepeatMode.all:
    case AudioServiceRepeatMode.group:
      return LoopMode.all;
    case AudioServiceRepeatMode.none:
      return LoopMode.off;
  }
}
