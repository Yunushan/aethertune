import 'dart:async';

import 'package:audio_service_mpris/audio_service_mpris.dart';
import 'package:audio_service_mpris/metadata.dart';
import 'package:audio_service_mpris/mpris.dart';
// Tests exercise the vendored adapter's existing platform and D-Bus contracts.
// ignore: depend_on_referenced_packages
import 'package:audio_service_platform_interface/audio_service_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Position advances between authoritative Playing state updates',
    () async {
      final player = OrgMprisMediaPlayer2(identity: 'AetherTune')
        ..position = const Duration(seconds: 10)
        ..playbackState = 'Playing';
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(player.getPosition().value, greaterThan(10000000));
    },
  );

  test(
    'timestamped state uses monotonic progress, pause, readiness and rate',
    () {
      final clock = _Clock();
      final player = _Player(clock);
      _track(player);
      player.updatePlayback(
        position: const Duration(seconds: 10),
        updateTime: clock.wall.subtract(const Duration(seconds: 2)),
        playing: true,
        ready: true,
        speed: 1,
      );
      expect(player.position.inSeconds, 12);
      clock.advance(const Duration(seconds: 3));
      expect(player.position.inSeconds, 15);
      // Wall-clock corrections after receipt cannot move the position.
      clock.wall = clock.wall.subtract(const Duration(hours: 4));
      expect(player.position.inSeconds, 15);
      player.updateRate(2);
      clock.advance(const Duration(seconds: 2));
      expect(player.position.inSeconds, 19);
      player.playbackState = 'Paused';
      clock.advance(const Duration(seconds: 3));
      expect(player.position.inSeconds, 19);
      player.updatePlayback(
        position: const Duration(seconds: 20),
        updateTime: clock.wall,
        playing: true,
        ready: false,
        speed: 2,
      );
      clock.advance(const Duration(seconds: 3));
      expect(player.position.inSeconds, 20);
      player.updatePlayback(
        position: const Duration(seconds: 30),
        updateTime: clock.wall,
        playing: false,
        ready: false,
        speed: 1,
        stopped: true,
      );
      expect(player.playbackState, 'Stopped');
      clock.advance(const Duration(seconds: 3));
      expect(player.position.inSeconds, 30);
      expect(player.changed, everyElement(isNot(contains('Position'))));
    },
  );

  test(
    'requested rate cannot change projection before an authoritative snapshot',
    () async {
      final clock = _Clock();
      final player = _Player(clock);
      final adapter = AudioServiceMpris(player: player);
      final callbacks = _Callbacks();
      adapter.setHandlerCallbacks(callbacks);
      _track(player);
      _state(player, clock, position: 10, playing: true);
      await player.setRate(2);
      await Future<void>.delayed(Duration.zero);
      expect(callbacks.rateRequest?.speed, 2);
      expect(player.getRate().value, 1);
      clock.advance(const Duration(seconds: 2));
      expect(player.position.inSeconds, 12);
      // The actual adapter listener consumes a rejected application callback.
      callbacks.rateCompletion.completeError(
        StateError('decoder rejected rate'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(player.getRate().value, 1);
      expect(player.changed.any((keys) => keys.contains('Rate')), isFalse);
      await adapter.setState(
        SetStateRequest(
          state: PlaybackStateMessage(
            processingState: AudioProcessingStateMessage.ready,
            playing: true,
            controls: [],
            systemActions: {},
            updatePosition: const Duration(seconds: 12),
            bufferedPosition: Duration.zero,
            updateTime: clock.wall,
            speed: 2,
          ),
        ),
      );
      clock.advance(const Duration(seconds: 2));
      expect(player.position.inSeconds, 16);
      expect(player.getRate().value, 2);
      expect(await player.setRate(double.nan), isA<DBusMethodErrorResponse>());
    },
  );

  test(
    'length bounds, metadata refresh and track changes retain truthful anchors',
    () {
      final clock = _Clock();
      final player = _Player(clock);
      _track(player);
      _state(player, clock, position: 179, playing: true);
      clock.advance(const Duration(seconds: 4));
      expect(player.position.inSeconds, 180);
      player.metadata = Metadata(
        trackId: mprisTrackPathForId('one'),
        title: 'Updated title',
        length: const Duration(minutes: 3),
      );
      expect(player.position.inSeconds, 180);
      player.metadata = Metadata(
        trackId: mprisTrackPathForId('two'),
        title: 'Two',
        length: const Duration(minutes: 1),
      );
      expect(player.position, Duration.zero);
      clock.advance(const Duration(seconds: 3));
      expect(player.position, Duration.zero);
      expect(
        () => player.updatePlayback(
          position: Duration.zero,
          updateTime: clock.wall,
          playing: true,
          ready: true,
          speed: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => player.updatePlayback(
          position: const Duration(seconds: -1),
          updateTime: clock.wall,
          playing: true,
          ready: true,
          speed: 1,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'Seek waits for confirmed actual position, emits Seeked once and ignores stale bounds',
    () async {
      final clock = _Clock();
      final player = _Player(clock);
      _track(player);
      _state(player, clock, position: 10);
      final completion = Completer<MprisPlaybackSnapshot>();
      var calls = 0;
      player.seekHandler = (target, mediaId) {
        calls++;
        expect(target.inSeconds, 15);
        expect(mediaId, 'one');
        return completion.future;
      };
      final requests = <Duration>[];
      final subscription = player.positionStream.listen(requests.add);
      addTearDown(subscription.cancel);
      final response = player.doSeek(5000000);
      await Future<void>.delayed(Duration.zero);
      expect(player.position.inSeconds, 10);
      expect(player.seeked, isEmpty);
      expect(await player.doSeek(1000000), isA<DBusMethodErrorResponse>());
      completion.complete(_snapshot(clock, position: 14));
      expect(await response, isA<DBusMethodSuccessResponse>());
      expect(player.position.inSeconds, 14);
      expect(player.seeked, <int>[14000000]);
      expect(requests, <Duration>[const Duration(seconds: 15)]);
      for (final input in <(String, int)>[
        (mprisTrackPathForId('two').value, 12000000),
        ('/org/mpris/MediaPlayer2/TrackList/NoTrack', 12000000),
        (mprisTrackPathForId('one').value, -1),
        (mprisTrackPathForId('one').value, 180000001),
      ]) {
        expect(
          await player.doSetPosition(input.$1, input.$2),
          isA<DBusMethodSuccessResponse>(),
        );
      }
      expect(calls, 1);
      expect(player.position.inSeconds, 14);
      expect(player.changed, everyElement(isNot(contains('Position'))));
    },
  );

  test(
    'failed, stale, mismatched and out-of-range confirmations never report Seeked',
    () async {
      for (final kind in <String>[
        'error',
        'track',
        'track-return',
        'timestamp',
        'identity',
        'ready',
        'length',
        'nan',
      ]) {
        final clock = _Clock();
        final player = _Player(clock);
        _track(player);
        _state(player, clock, position: 10);
        player.seekHandler = (_, _) async {
          if (kind == 'error') throw StateError('decoder failure');
          if (kind == 'track' || kind == 'track-return') {
            player.metadata = Metadata(
              trackId: mprisTrackPathForId('two'),
              title: 'Two',
            );
            if (kind == 'track-return') _track(player);
          }
          return MprisPlaybackSnapshot(
            mediaId: kind == 'identity' ? 'two' : 'one',
            position: Duration(seconds: kind == 'length' ? 181 : 20),
            updateTime: kind == 'timestamp'
                ? clock.wall.subtract(const Duration(seconds: 1))
                : clock.wall,
            playing: false,
            ready: kind != 'ready',
            speed: kind == 'nan' ? double.nan : 1,
          );
        };
        expect(
          await player.doSeek(5000000),
          isA<DBusMethodErrorResponse>(),
          reason: kind,
        );
        expect(player.seeked, isEmpty, reason: kind);
        expect(
          player.position.inSeconds,
          kind.startsWith('track') ? 0 : 10,
          reason: kind,
        );
      }
    },
  );

  test(
    'D-Bus SetPosition dispatches a raw object path through the real method handler',
    () async {
      final clock = _Clock();
      final player = _Player(clock);
      _track(player);
      _state(player, clock, position: 10);
      var calls = 0;
      player.seekHandler = (target, mediaId) async {
        calls++;
        expect(target.inSeconds, 12);
        expect(mediaId, 'one');
        return _snapshot(clock, position: 11);
      };
      DBusMethodCall request(DBusObjectPath path) => DBusMethodCall(
        sender: ':1.2',
        interface: 'org.mpris.MediaPlayer2.Player',
        name: 'SetPosition',
        values: <DBusValue>[path, const DBusInt64(12000000)],
      );
      final response = await player.handleMethodCall(
        request(mprisTrackPathForId('one')),
      );
      expect(response, isA<DBusMethodSuccessResponse>());
      expect(calls, 1);
      expect(player.position.inSeconds, 11);
      expect(player.seeked, <int>[11000000]);
      expect(
        await player.handleMethodCall(request(mprisTrackPathForId('two'))),
        isA<DBusMethodSuccessResponse>(),
      );
      expect(calls, 1);
      expect(player.seeked, <int>[11000000]);
    },
  );

  test(
    'CanSeek changes notify once and unavailable Seek cannot dispatch Next',
    () async {
      final clock = _Clock();
      final player = _Player(clock);
      _track(player);
      _state(player, clock, position: 10);
      final controls = <String>[];
      final subscription = player.controlStream.listen(controls.add);
      addTearDown(subscription.cancel);
      expect(player.getCanSeek().value, isFalse);
      expect(await player.doSeek(200000000), isA<DBusMethodSuccessResponse>());
      player.seekHandler = (_, _) async => _snapshot(clock, position: 15);
      expect(player.seekCapabilities, <bool>[true]);
      player.updatePlayback(
        position: const Duration(seconds: 10),
        updateTime: clock.wall,
        playing: true,
        ready: false,
        speed: 1,
      );
      player.updatePlayback(
        position: const Duration(seconds: 10),
        updateTime: clock.wall,
        playing: true,
        ready: false,
        speed: 1,
      );
      expect(player.seekCapabilities, <bool>[true, false]);
      expect(await player.doSeek(200000000), isA<DBusMethodSuccessResponse>());
      await Future<void>.delayed(Duration.zero);
      expect(controls, isEmpty);
      _state(player, clock, position: 10);
      expect(await player.doSeek(200000000), isA<DBusMethodSuccessResponse>());
      await Future<void>.delayed(Duration.zero);
      expect(controls, <String>['next']);
      player.metadata = Metadata(
        trackId: mprisTrackPathForId('two'),
        title: 'Two',
      );
      _state(player, clock, position: 0);
      expect(player.getCanSeek().value, isFalse);
      player.setTracks([MprisTrack(mediaId: 'two', metadata: player.metadata)]);
      expect(player.getCanSeek().value, isTrue);
      player.seekHandler = null;
      expect(player.seekCapabilities, <bool>[
        true,
        false,
        true,
        false,
        true,
        false,
      ]);
      expect(player.changed, everyElement(isNot(contains('Position'))));
    },
  );

  test(
    'adapter awaits dbusSeek and rejects untyped application snapshots',
    () async {
      final clock = _Clock();
      final player = _Player(clock);
      final adapter = AudioServiceMpris(player: player);
      final callbacks = _Callbacks();
      adapter.setHandlerCallbacks(callbacks);
      await adapter.setQueue(
        const SetQueueRequest(
          queue: <MediaItemMessage>[
            MediaItemMessage(
              id: 'one',
              title: 'One',
              duration: Duration(minutes: 3),
            ),
          ],
        ),
      );
      await adapter.setMediaItem(
        const SetMediaItemRequest(
          mediaItem: MediaItemMessage(
            id: 'one',
            title: 'One',
            duration: Duration(minutes: 3),
          ),
        ),
      );
      await adapter.setState(
        SetStateRequest(
          state: PlaybackStateMessage(
            processingState: AudioProcessingStateMessage.ready,
            playing: false,
            controls: [],
            systemActions: {},
            updatePosition: const Duration(seconds: 10),
            bufferedPosition: Duration.zero,
            updateTime: clock.wall,
          ),
        ),
      );
      final pending = player.doSetPosition(
        mprisTrackPathForId('one').value,
        20000000,
      );
      await Future<void>.delayed(Duration.zero);
      expect(callbacks.request?.name, 'dbusSeek');
      expect(callbacks.request?.extras, {
        'mediaId': 'one',
        'positionUs': 20000000,
      });
      expect(player.position.inSeconds, 10);
      callbacks.completion.complete({
        'mediaId': 'one',
        'positionUs': 19000000,
        'updateTimeUs': clock.wall.microsecondsSinceEpoch,
        'playing': false,
        'ready': true,
        'speed': 1.0,
      });
      expect(await pending, isA<DBusMethodSuccessResponse>());
      expect(player.seeked, <int>[19000000]);
      callbacks.completion = Completer<dynamic>();
      final malformed = player.doSeek(1000000);
      callbacks.completion.complete({
        'mediaId': 'one',
        'positionUs': '20000000',
      });
      expect(await malformed, isA<DBusMethodErrorResponse>());
      expect(player.seeked, <int>[19000000]);
    },
  );
}

class _Clock {
  Duration mono = Duration.zero;
  DateTime wall = DateTime.utc(2026, 10, 3);
  void advance(Duration amount) {
    mono += amount;
    wall = wall.add(amount);
  }
}

class _Player extends OrgMprisMediaPlayer2 {
  _Player(_Clock clock)
    : super(
        identity: 'AetherTune',
        monotonicNow: () => clock.mono,
        now: () => clock.wall,
      );
  final seeked = <int>[];
  final changed = <Set<String>>[];
  final seekCapabilities = <bool>[];
  @override
  Future<void> emitSeeked(Duration position) async {
    seeked.add(position.inMicroseconds);
  }

  @override
  Future<void> emitPropertiesChanged(
    String interface, {
    Map<String, DBusValue> changedProperties = const {},
    List<String> invalidatedProperties = const [],
  }) async {
    changed.add(changedProperties.keys.toSet());
    final canSeek = changedProperties['CanSeek'];
    if (canSeek is DBusBoolean) seekCapabilities.add(canSeek.value);
  }
}

void _track(OrgMprisMediaPlayer2 player) {
  final metadata = Metadata(
    trackId: mprisTrackPathForId('one'),
    title: 'One',
    length: const Duration(minutes: 3),
  );
  player.setTracks([MprisTrack(mediaId: 'one', metadata: metadata)]);
  player.metadata = metadata;
}

void _state(
  OrgMprisMediaPlayer2 player,
  _Clock clock, {
  required int position,
  bool playing = false,
}) {
  player.updatePlayback(
    position: Duration(seconds: position),
    updateTime: clock.wall,
    playing: playing,
    ready: true,
    speed: 1,
  );
}

MprisPlaybackSnapshot _snapshot(_Clock clock, {required int position}) =>
    MprisPlaybackSnapshot(
      mediaId: 'one',
      position: Duration(seconds: position),
      updateTime: clock.wall,
      playing: false,
      ready: true,
      speed: 1,
    );

class _Callbacks extends AudioHandlerCallbacks {
  Completer<dynamic> completion = Completer<dynamic>();
  CustomActionRequest? request;
  final rateCompletion = Completer<void>();
  SetSpeedRequest? rateRequest;
  @override
  Future<void> setSpeed(SetSpeedRequest request) {
    rateRequest = request;
    return rateCompletion.future;
  }

  @override
  Future<dynamic> customAction(CustomActionRequest request) {
    this.request = request;
    return completion.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
