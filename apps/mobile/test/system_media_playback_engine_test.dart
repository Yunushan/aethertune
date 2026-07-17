import 'dart:async';

import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/android_playback_widget_bridge.dart';
import 'package:aethertune/src/player/desktop_media_session.dart';
import 'package:aethertune/src/player/playback_audio_effects.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/playback_audio_engine_factory.dart';
import 'package:aethertune/src/player/system_media_playback_engine.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test('publishes queue metadata and current media item', () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    final tracks = <Track>[
      _track('one', duration: const Duration(minutes: 3)),
      _track('two', artwork: Uri.parse('https://example.test/two.jpg')),
    ];

    await engine.setQueue(tracks, initialIndex: 1);

    expect(engine.queue.value.map((item) => item.id), <String>['one', 'two']);
    expect(engine.mediaItem.value?.id, 'two');
    expect(engine.mediaItem.value?.title, 'Track two');
    expect(engine.mediaItem.value?.artist, 'Artist two');
    expect(
      engine.mediaItem.value?.artUri,
      Uri.parse('https://example.test/two.jpg'),
    );
    expect(engine.mediaItem.value?.extras?['sourceId'], 'local');

    delegate.emitDuration(const Duration(minutes: 4));
    expect(engine.mediaItem.value?.duration, const Duration(minutes: 4));
  });

  test('does not publish authenticated stream URLs to system media metadata',
      () async {
    const secret = 'private-api-key';
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    final track = Track(
      id: 'private-track',
      title: 'Private Track',
      artist: 'Private Artist',
      artworkUri: Uri.file('/private/cache/provider-artwork.png'),
      artworkUriIsEphemeral: true,
      providerArtworkId: 'cover-1',
      streamUrl: 'https://media.example.test/audio?api_key=$secret',
      streamUrlIsEphemeral: true,
      sourceId: 'self-hosted-jellyfin',
      externalId: 'song-1',
    );

    await engine.setQueue(<Track>[track], initialIndex: 0);

    final item = engine.mediaItem.value!;
    expect(item.id, 'private-track');
    expect(item.artUri, Uri.file('/private/cache/provider-artwork.png'));
    expect(item.extras, isNot(contains('streamUrl')));
    expect(item.extras.toString(), isNot(contains(secret)));
    expect(item.extras?['sourceId'], 'self-hosted-jellyfin');
    expect(item.extras?['externalId'], 'song-1');
  });

  test('publishes playback state for notifications and control center',
      () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    await engine.setQueue(
      <Track>[_track('one'), _track('two')],
      initialIndex: 0,
    );

    delegate
      ..positionValue = const Duration(seconds: 12)
      ..bufferedPositionValue = const Duration(seconds: 28)
      ..emitProcessingState(ProcessingState.ready)
      ..emitPlaying(true);

    final state = engine.playbackState.value;
    expect(state.playing, isTrue);
    expect(state.processingState, AudioProcessingState.ready);
    expect(state.updatePosition, const Duration(seconds: 12));
    expect(state.bufferedPosition, const Duration(seconds: 28));
    expect(state.queueIndex, 0);
    expect(state.controls, contains(MediaControl.pause));
    expect(state.controls, contains(MediaControl.skipToNext));
    expect(state.systemActions, contains(MediaAction.seek));

    await engine.setSpeed(1.5);
    expect(delegate.speedValue, 1.5);
    expect(engine.playbackState.value.speed, 1.5);
  });

  test('forwards pitch only when the wrapped backend supports it', () async {
    final delegate = _FakePitchPlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);

    expect(engine.supportsPitch, isTrue);
    await engine.setPitch(1.25);
    expect(engine.pitch, 1.25);
    expect(delegate.pitchValue, 1.25);

    final unsupported = SystemMediaPlaybackEngine(_FakePlaybackAudioEngine());
    addTearDown(unsupported.dispose);
    expect(unsupported.supportsPitch, isFalse);
    expect(() => unsupported.setPitch(1.25), throwsUnsupportedError);
  });

  test('enables pitch control only on supported production backends', () {
    expect(supportsPitchControl(TargetPlatform.android), isTrue);
    expect(supportsPitchControl(TargetPlatform.linux), isTrue);
    expect(supportsPitchControl(TargetPlatform.windows), isTrue);
    expect(supportsPitchControl(TargetPlatform.iOS), isFalse);
    expect(supportsPitchControl(TargetPlatform.macOS), isFalse);
  });

  test('publishes the current title and play state to Android widgets',
      () async {
    final delegate = _FakePlaybackAudioEngine();
    final widget = _FakePlaybackWidgetBridge();
    final engine = SystemMediaPlaybackEngine(
      delegate,
      playbackWidgetBridge: widget,
    );
    addTearDown(engine.dispose);
    widget.updates.clear();

    await engine.setQueue(
      <Track>[
        _track('one', duration: const Duration(minutes: 3)),
        _track('two'),
      ],
      initialIndex: 0,
    );
    expect(
      widget.updates.last,
      const _WidgetUpdate(
        'Track one',
        'Artist one',
        false,
        Duration.zero,
        Duration(minutes: 3),
      ),
    );

    delegate.emitPlaying(true);
    expect(
      widget.updates.last,
      const _WidgetUpdate(
        'Track one',
        'Artist one',
        true,
        Duration.zero,
        Duration(minutes: 3),
      ),
    );

    final updatesBeforeShortProgress = widget.updates.length;
    delegate.emitPosition(const Duration(milliseconds: 500));
    expect(widget.updates, hasLength(updatesBeforeShortProgress));

    delegate.emitPosition(const Duration(seconds: 1));
    expect(
      widget.updates.last,
      const _WidgetUpdate(
        'Track one',
        'Artist one',
        true,
        Duration(seconds: 1),
        Duration(minutes: 3),
      ),
    );

    await engine.seek(Duration.zero, index: 1);
    expect(
      widget.updates.last,
      const _WidgetUpdate(
        'Track two',
        'Artist two',
        true,
        Duration.zero,
        null,
      ),
    );
  });

  test('routes system transport, repeat, and shuffle commands', () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    await engine.setQueue(
      <Track>[_track('one'), _track('two'), _track('three')],
      initialIndex: 1,
    );

    await engine.skipToNext();
    expect(delegate.currentIndex, 2);
    await engine.skipToPrevious();
    expect(delegate.currentIndex, 1);
    await engine.skipToQueueItem(0);
    expect(delegate.currentIndex, 0);
    await engine.seek(const Duration(seconds: 45));
    expect(delegate.positionValue, const Duration(seconds: 45));

    await engine.setRepeatMode(AudioServiceRepeatMode.all);
    await engine.setShuffleMode(AudioServiceShuffleMode.all);
    expect(delegate.loopModeValue, LoopMode.all);
    expect(delegate.shuffleValue, isTrue);
    expect(engine.playbackState.value.repeatMode, AudioServiceRepeatMode.all);
    expect(
      engine.playbackState.value.shuffleMode,
      AudioServiceShuffleMode.all,
    );
  });

  test('forwards native audio effects through the system media wrapper',
      () async {
    final delegate = _FakeAudioEffectsPlaybackEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    const profile = PlaybackEqualizerProfile(
      preset: PlaybackEqualizerPreset.bassBoost,
    );

    expect(engine.supportsEqualizer, isTrue);
    expect(engine.supportsLoudnessEnhancer, isTrue);
    expect(engine.supportsVirtualizer, isTrue);
    await engine.setEqualizerEnabled(true);
    await engine.setEqualizerProfile(profile);
    await engine.setLoudnessEnhancerTargetGain(4.5);
    await engine.setLoudnessEnhancerEnabled(true);
    await engine.setVirtualizerStrength(650);
    await engine.setVirtualizerEnabled(true);

    expect(delegate.equalizerEnabledValue, isTrue);
    expect(delegate.equalizerProfileValue, same(profile));
    expect(delegate.loudnessEnhancerTargetGainValue, 4.5);
    expect(delegate.loudnessEnhancerEnabledValue, isTrue);
    expect(delegate.virtualizerStrengthValue, 650);
    expect(delegate.virtualizerEnabledValue, isTrue);
    expect(await engine.loadEqualizerBands(), delegate.bands);
  });

  test('publishes and routes a desktop system media session', () async {
    final delegate = _FakePlaybackAudioEngine();
    final desktopSession = _FakeDesktopMediaSession();
    final engine = SystemMediaPlaybackEngine(
      delegate,
      desktopMediaSession: desktopSession,
    );
    addTearDown(engine.dispose);
    await Future<void>.delayed(Duration.zero);
    await engine.setQueue(
      <Track>[
        _track('one', duration: const Duration(minutes: 3)),
        _track('two'),
      ],
      initialIndex: 0,
    );
    delegate
      ..emitProcessingState(ProcessingState.ready)
      ..emitPosition(const Duration(seconds: 12))
      ..emitPlaying(true);
    await Future<void>.delayed(Duration.zero);

    final state = desktopSession.states.last;
    expect(state.track?.id, 'one');
    expect(state.isPlaying, isTrue);
    expect(state.position, const Duration(seconds: 12));
    expect(state.duration, const Duration(minutes: 3));
    expect(state.canGoNext, isTrue);

    await desktopSession.send(DesktopMediaSessionCommand.seekForward);
    expect(delegate.positionValue, const Duration(seconds: 42));
    await desktopSession.send(DesktopMediaSessionCommand.next);
    expect(delegate.currentIndex, 1);
    await desktopSession.send(DesktopMediaSessionCommand.stop);
    expect(delegate.playingValue, isFalse);
  });

  test('browses the current queue and library through Android Auto', () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    await engine.setQueue(
      <Track>[_track('one'), _track('two')],
      initialIndex: 1,
    );

    final rootItems = await engine.getChildren(AudioService.browsableRootId);
    expect(rootItems.map((item) => item.title), <String>[
      'Current queue',
      'Library',
    ]);
    expect(rootItems.every((item) => item.playable == false), isTrue);

    final queueItems = await engine.getChildren(rootItems.first.id);
    expect(queueItems.map((item) => item.id), <String>['one', 'two']);
    expect(queueItems.every((item) => item.playable == true), isTrue);
    expect(
      (await engine.getChildren(AudioService.recentRootId)).single.id,
      'two',
    );
    expect((await engine.getMediaItem('one'))?.title, 'Track one');
    expect(await engine.getMediaItem('missing'), isNull);

    await engine.playFromMediaId('one');
    expect(delegate.currentIndex, 0);
    expect(delegate.playingValue, isTrue);
  });

  test('routes an Android Auto library selection back to the app', () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    final libraryTracks = <Track>[_track('one'), _track('two')];
    Track? selectedTrack;
    engine.setMediaLibraryBrowseTracks(
      libraryTracks,
      onTrackSelected: (track) async {
        selectedTrack = track;
      },
    );

    final rootItems = await engine.getChildren(AudioService.browsableRootId);
    final libraryFolder = rootItems.singleWhere(
      (item) => item.title == 'Library',
    );
    final allTracksFolder =
        (await engine.getChildren(libraryFolder.id)).single;
    expect(allTracksFolder.title, 'All tracks');
    expect(allTracksFolder.playable, isFalse);

    final libraryItems = await engine.getChildren(allTracksFolder.id);
    expect(
      libraryItems.map((item) => item.id),
      <String>[
        'aethertune:android-auto:library-track:one',
        'aethertune:android-auto:library-track:two',
      ],
    );
    expect(
      (await engine.getMediaItem(libraryItems.last.id))?.title,
      'Track two',
    );

    await engine.playFromMediaId(libraryItems.last.id);
    expect(selectedTrack, same(libraryTracks.last));
    expect(delegate.playingValue, isFalse);
  });

  test('browses Android Auto playlists and selects their ordered queue',
      () async {
    final delegate = _FakePlaybackAudioEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);
    final tracks = <Track>[_track('one'), _track('two')];
    Track? selectedTrack;
    List<Track>? selectedQueue;
    int? selectedQueueIndex;
    engine.setMediaLibraryBrowseTracks(
      tracks,
      onTrackSelected: (_) async {},
      playlists: <MediaLibraryBrowsePlaylist>[
        MediaLibraryBrowsePlaylist(
          id: 'favorites',
          title: 'Favorites',
          artworkUri: Uri.parse('https://example.test/favorites.jpg'),
          tracks: <Track>[tracks.last, tracks.first, tracks.last],
        ),
        MediaLibraryBrowsePlaylist(
          id: 'artist:artist-one',
          title: 'Artist one',
          category: MediaLibraryBrowseCategory.artist,
          tracks: <Track>[tracks.first, tracks.last],
        ),
        MediaLibraryBrowsePlaylist(
          id: 'album:album-one',
          title: 'Album one',
          category: MediaLibraryBrowseCategory.album,
          tracks: <Track>[tracks.last, tracks.first],
        ),
      ],
      onPlaylistTrackSelected: (track, queue, queueIndex) async {
        selectedTrack = track;
        selectedQueue = queue;
        selectedQueueIndex = queueIndex;
      },
    );

    final libraryFolder = (await engine.getChildren(
      AudioService.browsableRootId,
    )).singleWhere((item) => item.title == 'Library');
    final libraryChildren = await engine.getChildren(libraryFolder.id);
    final playlistsFolder = libraryChildren.singleWhere(
      (item) => item.title == 'Playlists',
    );
    final playlistFolder = (await engine.getChildren(playlistsFolder.id)).single;
    expect(playlistFolder.title, 'Favorites');
    expect(playlistFolder.displaySubtitle, '3 tracks');
    expect(playlistFolder.artUri, Uri.parse('https://example.test/favorites.jpg'));

    final playlistTracks = await engine.getChildren(playlistFolder.id);
    expect(
      playlistTracks.map((item) => item.title),
      <String>['Track two', 'Track one', 'Track two'],
    );
    expect(playlistTracks.map((item) => item.id).toSet(), hasLength(3));

    final artistsFolder = libraryChildren.singleWhere(
      (item) => item.title == 'Artists',
    );
    final artistFolder = (await engine.getChildren(artistsFolder.id)).single;
    expect(artistFolder.title, 'Artist one');
    final artistTracks = await engine.getChildren(artistFolder.id);
    expect(
      artistTracks.map((item) => item.title),
      <String>['Track one', 'Track two'],
    );

    final albumsFolder = libraryChildren.singleWhere(
      (item) => item.title == 'Albums',
    );
    final albumFolder = (await engine.getChildren(albumsFolder.id)).single;
    expect(albumFolder.title, 'Album one');
    final albumTracks = await engine.getChildren(albumFolder.id);
    expect(
      albumTracks.map((item) => item.title),
      <String>['Track two', 'Track one'],
    );

    await engine.playFromMediaId(playlistTracks.last.id);
    expect(selectedTrack, same(tracks.last));
    expect(selectedQueue, <Track>[tracks.last, tracks.first, tracks.last]);
    expect(selectedQueueIndex, 2);
    expect(delegate.playingValue, isFalse);

    await engine.playFromMediaId(albumTracks.first.id);
    expect(selectedTrack, same(tracks.last));
    expect(selectedQueue, <Track>[tracks.last, tracks.first]);
    expect(selectedQueueIndex, 0);
  });

  test('forwards an opt-in visualizer through the system media wrapper',
      () async {
    final delegate = _FakeVisualizationPlaybackEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);

    expect(engine.supportsVisualizer, isTrue);
    expect(await engine.startVisualizer(), isTrue);
    await engine.stopVisualizer();

    expect(delegate.startCalls, 1);
    expect(delegate.stopCalls, 1);
    expect(await engine.visualizerBands.first, <double>[0.2, 0.8]);
  });

  test('forwards skip silence through the system media wrapper', () async {
    final delegate = _FakeSkipSilencePlaybackEngine();
    final engine = SystemMediaPlaybackEngine(delegate);
    addTearDown(engine.dispose);

    expect(engine.supportsSkipSilence, isTrue);
    await engine.setSkipSilenceEnabled(true);

    expect(delegate.skipSilenceEnabledValue, isTrue);
  });

  test('enables native media sessions only on supported platforms', () {
    expect(supportsSystemMediaSession(TargetPlatform.android), isTrue);
    expect(supportsSystemMediaSession(TargetPlatform.iOS), isTrue);
    expect(supportsSystemMediaSession(TargetPlatform.macOS), isTrue);
    expect(supportsSystemMediaSession(TargetPlatform.linux), isTrue);
    expect(supportsSystemMediaSession(TargetPlatform.windows), isTrue);
    expect(usesAudioServiceSystemMediaSession(TargetPlatform.linux), isTrue);
    expect(usesAudioServiceSystemMediaSession(TargetPlatform.windows), isFalse);
    expect(supportsAndroidAudioEffects(TargetPlatform.android), isTrue);
    expect(supportsAndroidAudioEffects(TargetPlatform.iOS), isFalse);
    expect(supportsAndroidAudioEffects(TargetPlatform.windows), isFalse);
    expect(supportsSkipSilence(TargetPlatform.android), isTrue);
    expect(supportsSkipSilence(TargetPlatform.iOS), isFalse);
    expect(supportsSkipSilence(TargetPlatform.windows), isFalse);
  });
}

Track _track(String id, {Duration duration = Duration.zero, Uri? artwork}) {
  return Track(
    id: id,
    title: 'Track $id',
    artist: 'Artist $id',
    album: 'Album $id',
    duration: duration,
    artworkUri: artwork,
    localPath: '/music/$id.mp3',
  );
}

class _FakePlaybackAudioEngine implements PlaybackAudioEngine {
  final _stateController = StreamController<Object?>.broadcast(sync: true);
  final _durationController =
      StreamController<Duration?>.broadcast(sync: true);
  final _positionController = StreamController<Duration>.broadcast(sync: true);
  final _processingController =
      StreamController<ProcessingState>.broadcast(sync: true);
  final _indexController = StreamController<int?>.broadcast(sync: true);

  List<Track> tracks = <Track>[];
  int currentIndex = 0;
  bool playingValue = false;
  bool shuffleValue = false;
  LoopMode loopModeValue = LoopMode.off;
  Duration positionValue = Duration.zero;
  Duration bufferedPositionValue = Duration.zero;
  double volumeValue = 1;
  double speedValue = 1;

  @override
  Stream<Object?> get stateChanges => _stateController.stream;

  @override
  Stream<Duration?> get durationStream => _durationController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _processingController.stream;

  @override
  Stream<int?> get currentIndexStream => _indexController.stream;

  @override
  bool get playing => playingValue;

  @override
  bool get shuffleModeEnabled => shuffleValue;

  @override
  LoopMode get loopMode => loopModeValue;

  @override
  Duration get position => positionValue;

  @override
  Duration get bufferedPosition => bufferedPositionValue;

  @override
  double get speed => speedValue;

  @override
  double get volume => volumeValue;

  @override
  bool get hasNext => currentIndex + 1 < tracks.length;

  @override
  bool get hasPrevious => currentIndex > 0;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    this.tracks = List<Track>.from(tracks);
    currentIndex = initialIndex;
    positionValue = initialPosition;
    _indexController.add(currentIndex);
  }

  void emitPlaying(bool playing) {
    playingValue = playing;
    _stateController.add(null);
  }

  void emitDuration(Duration duration) {
    _durationController.add(duration);
  }

  void emitPosition(Duration position) {
    positionValue = position;
    _positionController.add(position);
  }

  void emitProcessingState(ProcessingState state) {
    _processingController.add(state);
  }

  @override
  Future<void> play() async => emitPlaying(true);

  @override
  Future<void> pause() async => emitPlaying(false);

  @override
  Future<void> stop() async => emitPlaying(false);

  @override
  Future<void> seek(Duration position, {int? index}) async {
    positionValue = position;
    _positionController.add(position);
    if (index != null) {
      currentIndex = index;
      _indexController.add(index);
    }
  }

  @override
  Future<void> seekToNext() => seek(Duration.zero, index: currentIndex + 1);

  @override
  Future<void> seekToPrevious() =>
      seek(Duration.zero, index: currentIndex - 1);

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    shuffleValue = enabled;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopModeValue = mode;
  }

  @override
  Future<void> setSpeed(double speed) async {
    speedValue = speed;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeValue = volume;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _durationController.close();
    await _positionController.close();
    await _processingController.close();
    await _indexController.close();
  }
}

class _FakePitchPlaybackAudioEngine extends _FakePlaybackAudioEngine
    implements PitchPlaybackAudioEngine {
  double pitchValue = 1;

  @override
  bool get supportsPitch => true;

  @override
  double get pitch => pitchValue;

  @override
  Future<void> setPitch(double pitch) async {
    pitchValue = pitch;
  }
}

class _FakeAudioEffectsPlaybackEngine extends _FakePlaybackAudioEngine
    implements AudioEffectsPlaybackAudioEngine, VirtualizerPlaybackAudioEngine {
  bool equalizerEnabledValue = false;
  PlaybackEqualizerProfile equalizerProfileValue =
      const PlaybackEqualizerProfile(
        preset: PlaybackEqualizerPreset.flat,
      );
  bool loudnessEnhancerEnabledValue = false;
  double loudnessEnhancerTargetGainValue = 0;
  bool virtualizerEnabledValue = false;
  int virtualizerStrengthValue = 500;
  final List<PlaybackEqualizerBand> bands = const <PlaybackEqualizerBand>[
    PlaybackEqualizerBand(
      index: 0,
      centerFrequencyHz: 60,
      gainDb: 0,
      minGainDb: -12,
      maxGainDb: 12,
    ),
  ];

  @override
  bool get supportsEqualizer => true;

  @override
  bool get supportsLoudnessEnhancer => true;

  @override
  bool get supportsVirtualizer => true;

  @override
  Future<void> setEqualizerEnabled(bool enabled) async {
    equalizerEnabledValue = enabled;
  }

  @override
  Future<void> setEqualizerProfile(PlaybackEqualizerProfile profile) async {
    equalizerProfileValue = profile;
  }

  @override
  Future<List<PlaybackEqualizerBand>> loadEqualizerBands() async => bands;

  @override
  Future<void> setLoudnessEnhancerEnabled(bool enabled) async {
    loudnessEnhancerEnabledValue = enabled;
  }

  @override
  Future<void> setLoudnessEnhancerTargetGain(double gainDb) async {
    loudnessEnhancerTargetGainValue = gainDb;
  }

  @override
  Future<void> setVirtualizerEnabled(bool enabled) async {
    virtualizerEnabledValue = enabled;
  }

  @override
  Future<void> setVirtualizerStrength(int strength) async {
    virtualizerStrengthValue = strength;
  }
}

class _FakeVisualizationPlaybackEngine extends _FakePlaybackAudioEngine
    implements AudioVisualizationPlaybackAudioEngine {
  int startCalls = 0;
  int stopCalls = 0;

  @override
  bool get supportsVisualizer => true;

  @override
  Stream<List<double>> get visualizerBands =>
      Stream<List<double>>.value(<double>[0.2, 0.8]);

  @override
  Future<bool> startVisualizer() async {
    startCalls += 1;
    return true;
  }

  @override
  Future<void> stopVisualizer() async {
    stopCalls += 1;
  }
}

class _FakeSkipSilencePlaybackEngine extends _FakePlaybackAudioEngine
    implements SkipSilencePlaybackAudioEngine {
  bool skipSilenceEnabledValue = false;

  @override
  bool get supportsSkipSilence => true;

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) async {
    skipSilenceEnabledValue = enabled;
  }
}

class _FakeDesktopMediaSession implements DesktopMediaSession {
  final List<DesktopMediaSessionState> states = <DesktopMediaSessionState>[];
  Future<void> Function(DesktopMediaSessionCommand command)? _onCommand;
  bool disposed = false;

  @override
  Future<void> start(
    Future<void> Function(DesktopMediaSessionCommand command) onCommand,
  ) async {
    _onCommand = onCommand;
  }

  @override
  Future<void> publish(DesktopMediaSessionState state) async {
    states.add(state);
  }

  Future<void> send(DesktopMediaSessionCommand command) async {
    await _onCommand!(command);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakePlaybackWidgetBridge implements PlaybackWidgetBridge {
  final List<_WidgetUpdate> updates = <_WidgetUpdate>[];

  @override
  Future<void> update({
    Track? track,
    required bool isPlaying,
    required Duration position,
    Duration? duration,
  }) {
    updates.add(
      _WidgetUpdate(
        track?.title ?? 'AetherTune',
        track?.artist ?? '',
        isPlaying,
        position,
        duration,
      ),
    );
    return Future<void>.value();
  }
}

class _WidgetUpdate {
  const _WidgetUpdate(
    this.title,
    this.artist,
    this.isPlaying,
    this.position,
    this.duration,
  );

  final String title;
  final String artist;
  final bool isPlaying;
  final Duration position;
  final Duration? duration;

  @override
  bool operator ==(Object other) {
    return other is _WidgetUpdate &&
        title == other.title &&
        artist == other.artist &&
        isPlaying == other.isPlaying &&
        position == other.position &&
        duration == other.duration;
  }

  @override
  int get hashCode => Object.hash(title, artist, isPlaying, position, duration);

  @override
  String toString() =>
      '_WidgetUpdate(title: $title, artist: $artist, isPlaying: $isPlaying, '
      'position: $position, duration: $duration)';
}
