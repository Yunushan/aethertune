import 'package:just_audio/just_audio.dart';

import '../domain/track.dart';

abstract interface class PlaybackAudioEngine {
  Stream<Object?> get stateChanges;
  Stream<Duration?> get durationStream;
  Stream<ProcessingState> get processingStateStream;
  Stream<int?> get currentIndexStream;

  bool get playing;
  bool get shuffleModeEnabled;
  LoopMode get loopMode;
  Duration get position;
  double get volume;
  bool get hasNext;
  bool get hasPrevious;

  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  });

  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position, {int? index});
  Future<void> seekToNext();
  Future<void> seekToPrevious();
  Future<void> setShuffleModeEnabled(bool enabled);
  Future<void> setLoopMode(LoopMode mode);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class JustAudioPlaybackEngine implements PlaybackAudioEngine {
  JustAudioPlaybackEngine({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Object?> get stateChanges => _player.playerStateStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<ProcessingState> get processingStateStream =>
      _player.processingStateStream;

  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;

  @override
  bool get playing => _player.playing;

  @override
  bool get shuffleModeEnabled => _player.shuffleModeEnabled;

  @override
  LoopMode get loopMode => _player.loopMode;

  @override
  Duration get position => _player.position;

  @override
  double get volume => _player.volume;

  @override
  bool get hasNext => _player.hasNext;

  @override
  bool get hasPrevious => _player.hasPrevious;

  @override
  Future<void> setQueue(
    List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    if (tracks.isEmpty) {
      throw ArgumentError.value(tracks, 'tracks', 'Queue cannot be empty.');
    }
    if (initialIndex < 0 || initialIndex >= tracks.length) {
      throw RangeError.index(initialIndex, tracks, 'initialIndex');
    }

    final playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: tracks.map(_audioSourceForTrack).toList(growable: false),
    );
    await _player.setAudioSource(
      playlist,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
  }

  AudioSource _audioSourceForTrack(Track track) {
    if (track.hasLocalSource) {
      return AudioSource.file(track.localPath!, tag: track.id);
    }
    if (track.hasStreamSource) {
      return AudioSource.uri(Uri.parse(track.streamUrl!), tag: track.id);
    }
    throw StateError('Track has no local path or stream URL: ${track.title}');
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position, {int? index}) =>
      _player.seek(position, index: index);

  @override
  Future<void> seekToNext() => _player.seekToNext();

  @override
  Future<void> seekToPrevious() => _player.seekToPrevious();

  @override
  Future<void> setShuffleModeEnabled(bool enabled) =>
      _player.setShuffleModeEnabled(enabled);

  @override
  Future<void> setLoopMode(LoopMode mode) => _player.setLoopMode(mode);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() async {
    await _player.dispose();
  }
}
