import 'dart:developer';
import 'dart:io';

import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
import 'package:dbus/dbus.dart';

import 'metadata.dart';
import 'mpris.dart';

export 'mpris.dart' show MprisPlaylist;

/// Publishes the app-owned playlist catalog when the Linux MPRIS adapter runs.
void setMprisPlaylists(Iterable<MprisPlaylist> playlists) {
  AudioServiceMpris._activeInstance?.setPlaylists(playlists);
}

/// Publishes an app-originated volume update to the Linux MPRIS adapter.
void setMprisVolume(double volume) {
  AudioServiceMpris._activeInstance?.setVolume(volume);
}

class AudioServiceMpris extends AudioServicePlatform {
  static AudioServiceMpris? _activeInstance;
  late final DBusClient _dBusClient;
  late final OrgMprisMediaPlayer2 _mpris;
  AudioHandlerCallbacks? _handlerCallbacks;
  bool _isPlaying = false;

  AudioServiceMpris({OrgMprisMediaPlayer2? player}) {
    if (player != null) {
      _mpris = player;
      _installSeekHandler();
      _listenToRateStream();
    }
  }

  void _listenToOpenUriStream() {
    _mpris.openUriStream.listen((uri) {
      if (_handlerCallbacks == null) return;

      _handlerCallbacks!.playFromUri(PlayFromUriRequest(uri: uri));
    });
  }

  void _installSeekHandler() {
    _mpris.seekHandler = (position, mediaId) async {
      final callbacks = _handlerCallbacks;
      if (callbacks == null) throw StateError('No application handler');
      final result = await callbacks.customAction(CustomActionRequest(
        name: 'dbusSeek',
        extras: {'mediaId': mediaId, 'positionUs': position.inMicroseconds},
      ));
      if (result is! Map ||
          result['mediaId'] != mediaId ||
          result['positionUs'] is! int ||
          result['updateTimeUs'] is! int ||
          result['playing'] is! bool ||
          result['ready'] is! bool ||
          result['speed'] is! num) {
        throw StateError('Invalid application seek snapshot');
      }
      return MprisPlaybackSnapshot(
        mediaId: mediaId,
        position: Duration(microseconds: result['positionUs'] as int),
        updateTime:
            DateTime.fromMicrosecondsSinceEpoch(result['updateTimeUs'] as int),
        playing: result['playing'] as bool,
        ready: result['ready'] as bool,
        speed: (result['speed'] as num).toDouble(),
      );
    };
  }

  void _listenToControlStream() {
    _mpris.controlStream.listen((event) {
      log('Requested from DBus: $event', name: 'audio_service_mpris');
      if (_handlerCallbacks == null) return;

      switch (event) {
        case 'play':
          _handlerCallbacks!.play(const PlayRequest());
        case 'pause':
          _handlerCallbacks!.pause(const PauseRequest());
        case 'stop':
          _handlerCallbacks!.stop(const StopRequest());
        case 'next':
          _handlerCallbacks!.skipToNext(const SkipToNextRequest());
        case 'previous':
          _handlerCallbacks!.skipToPrevious(const SkipToPreviousRequest());
        case 'playPause':
          _isPlaying
              ? _handlerCallbacks!.pause(const PauseRequest())
              : _handlerCallbacks!.play(const PlayRequest());
      }
    });
  }

  void _listenToVolumeStream() {
    _mpris.volumeStream.listen((value) {
      if (_handlerCallbacks == null) return;

      final req =
          CustomActionRequest(name: 'dbusVolume', extras: {'value': value});
      _handlerCallbacks!.customAction(req);
    });
  }

  void _listenToTrackStream() {
    _mpris.trackStream.listen((mediaId) {
      final callbacks = _handlerCallbacks;
      if (callbacks == null) return;
      final index = _queue.indexWhere((item) => item.id == mediaId);
      if (index >= 0) {
        callbacks.skipToQueueItem(SkipToQueueItemRequest(index: index));
      }
    });
  }

  void _listenToPlaylistStream() {
    _mpris.playlistStream.listen((mediaId) {
      final callbacks = _handlerCallbacks;
      if (callbacks != null) {
        callbacks.playFromMediaId(PlayFromMediaIdRequest(mediaId: mediaId));
      }
    });
  }

  void _listenToLoopStream() {
    _mpris.loopStream.listen((value) {
      final callbacks = _handlerCallbacks;
      if (callbacks == null) return;
      final repeatMode = switch (value) {
        'Track' => AudioServiceRepeatModeMessage.one,
        'Playlist' => AudioServiceRepeatModeMessage.all,
        _ => AudioServiceRepeatModeMessage.none,
      };
      callbacks.setRepeatMode(SetRepeatModeRequest(repeatMode: repeatMode));
    });
  }

  void _listenToShuffleStream() {
    _mpris.shuffleStream.listen((enabled) {
      _handlerCallbacks?.setShuffleMode(
        SetShuffleModeRequest(
          shuffleMode: enabled
              ? AudioServiceShuffleModeMessage.all
              : AudioServiceShuffleModeMessage.none,
        ),
      );
    });
  }

  void _listenToRateStream() {
    _mpris.rateStream.listen((value) async {
      final callbacks = _handlerCallbacks;
      if (callbacks == null) return;
      try {
        await callbacks.setSpeed(SetSpeedRequest(speed: value));
      } catch (_) {
        // Keep the last authoritative speed and observe callback rejection.
        log('Application speed change failed', name: 'audio_service_mpris');
      }
    });
  }

  final List<MediaItemMessage> _queue = <MediaItemMessage>[];

  static void registerWith() {
    AudioServicePlatform.instance = AudioServiceMpris();
  }

  @override
  Future<void> configure(ConfigureRequest request) async {
    log('Configure AudioServiceLinux.', name: 'audio_service_mpris');
    assert(
        request.config.androidNotificationChannelId != null,
        "androidNotificationChannelId is required for registering"
        " DBus object. e.g com.ryanheise.myapp.channel.audio");

    _dBusClient = DBusClient.session();
    _mpris = OrgMprisMediaPlayer2(
        path: DBusObjectPath('/org/mpris/MediaPlayer2'),
        identity: request.config.androidNotificationChannelName);

    _listenToControlStream();
    _installSeekHandler();
    _listenToOpenUriStream();
    _listenToVolumeStream();
    _listenToTrackStream();
    _listenToPlaylistStream();
    _listenToLoopStream();
    _listenToShuffleStream();
    _listenToRateStream();

    await _dBusClient.registerObject(_mpris);
    await _dBusClient.requestName(
        'org.mpris.MediaPlayer2.${request.config.androidNotificationChannelId}.instance$pid',
        flags: {DBusRequestNameFlag.doNotQueue});
    _activeInstance = this;
  }

  @override
  Future<void> setState(SetStateRequest request) async {
    final state = request.state;
    _isPlaying = state.playing;
    _mpris.updatePlayback(
      position: state.updatePosition,
      updateTime: state.updateTime,
      playing: state.playing,
      ready: state.processingState == AudioProcessingStateMessage.ready,
      speed: state.speed,
      stopped: state.processingState == AudioProcessingStateMessage.idle ||
          state.processingState == AudioProcessingStateMessage.completed ||
          state.processingState == AudioProcessingStateMessage.error,
    );
    _mpris.updateLoopStatus(switch (request.state.repeatMode) {
      AudioServiceRepeatModeMessage.one => 'Track',
      AudioServiceRepeatModeMessage.all => 'Playlist',
      _ => 'None',
    });
    _mpris.updateShuffle(
      request.state.shuffleMode != AudioServiceShuffleModeMessage.none,
    );
  }

  @override
  Future<void> setQueue(SetQueueRequest request) async {
    _queue
      ..clear()
      ..addAll(request.queue);
    _mpris.setTracks(
      request.queue.map(
        (item) => MprisTrack(
          mediaId: item.id,
          metadata: Metadata(
            trackId: mprisTrackPathForId(item.id),
            title: item.title,
            length: item.duration,
            artist: item.artist == null ? null : <String>[item.artist!],
            artUrl: item.artUri?.toString(),
            album: item.album,
            genre: item.genre == null ? null : <String>[item.genre!],
          ),
        ),
      ),
    );
  }

  void setPlaylists(Iterable<MprisPlaylist> playlists) {
    _mpris.setPlaylists(playlists);
  }

  void setVolume(double volume) {
    _mpris.updateVolume(volume);
  }

  @override
  Future<void> setMediaItem(SetMediaItemRequest request) async {
    List<String>? artist;
    if (request.mediaItem.artist != null) artist = [request.mediaItem.artist!];

    List<String>? genre;
    if (request.mediaItem.genre != null) genre = [request.mediaItem.genre!];

    _mpris.metadata = Metadata(
        trackId: mprisTrackPathForId(request.mediaItem.id),
        title: request.mediaItem.title,
        length: request.mediaItem.duration,
        artist: artist,
        artUrl: request.mediaItem.artUri.toString(),
        album: request.mediaItem.album,
        genre: genre);
  }

  @override
  Future<void> stopService(StopServiceRequest request) async {
    _mpris.playbackState = 'Stopped';
  }

  @override
  Future<void> notifyChildrenChanged(
      NotifyChildrenChangedRequest request) async {
    throw UnimplementedError(
        'notifyChildrenChanged() has not been implemented.');
  }

  @override
  void setHandlerCallbacks(AudioHandlerCallbacks callbacks) {
    _handlerCallbacks = callbacks;
  }
}
