import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aethertune/src/data/library_store.dart';
import 'package:aethertune/src/data/library_sync_client.dart';
import 'package:aethertune/src/data/listen_together_store.dart';
import 'package:aethertune/src/domain/listen_together_session.dart';
import 'package:aethertune/src/domain/track.dart';
import 'package:aethertune/src/player/playback_audio_engine.dart';
import 'package:aethertune/src/player/player_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('hosts a portable queue and joins it with local tracks', () async {
    final library = LibraryStore();
    await library.load();
    final first = _track('first');
    final second = _track('second');
    await library.addTracks(<Track>[first, second]);

    final gateway = _MemoryListenTogetherGateway();
    final hostEngine = _TestAudioEngine();
    final hostPlayer = PlayerController(audioEngine: hostEngine);
    addTearDown(hostPlayer.dispose);
    await hostPlayer.playTrack(second, queue: <Track>[first, second]);
    await hostPlayer.seek(const Duration(seconds: 12));

    final host = ListenTogetherStore(gatewayFactory: () => gateway);
    await host.host(library, hostPlayer);

    expect(host.hosting, isTrue);
    expect(gateway.session?.trackIds, <String>['first', 'second']);
    expect(gateway.session?.currentTrackId, 'second');
    expect(gateway.session?.position, const Duration(seconds: 12));
    expect(gateway.session?.playing, isTrue);

    final guestEngine = _TestAudioEngine();
    final guestPlayer = PlayerController(audioEngine: guestEngine);
    addTearDown(guestPlayer.dispose);
    final guest = ListenTogetherStore(gatewayFactory: () => gateway);
    final restored = await guest.join(library, guestPlayer);

    expect(restored, 2);
    expect(guest.joined, isTrue);
    expect(guest.hosting, isFalse);
    expect(guestPlayer.queue.map((track) => track.id), <String>[
      'first',
      'second',
    ]);
    expect(guestPlayer.current?.id, 'second');
    expect(guestEngine.positionValue, const Duration(seconds: 12));
    expect(guestPlayer.isPlaying, isTrue);
  });

  test('keeps a joined session paused when the host is paused', () async {
    final library = LibraryStore();
    await library.load();
    final track = _track('shared');
    await library.addTracks(<Track>[track]);
    final gateway = _MemoryListenTogetherGateway()
      ..session = const ListenTogetherSession(
        trackIds: <String>['shared'],
        currentTrackId: 'shared',
        position: Duration(seconds: 7),
        playing: false,
      )
      ..revision = 3;
    final engine = _TestAudioEngine();
    final player = PlayerController(audioEngine: engine);
    addTearDown(player.dispose);

    await ListenTogetherStore(gatewayFactory: () => gateway).join(
      library,
      player,
    );

    expect(player.current?.id, 'shared');
    expect(engine.positionValue, const Duration(seconds: 7));
    expect(player.isPlaying, isFalse);
  });

  test('corrects shared playback drift without restarting an unchanged queue',
      () async {
    final library = LibraryStore();
    await library.load();
    final first = _track('first');
    final second = _track('second');
    await library.addTracks(<Track>[first, second]);
    final now = DateTime.utc(2026, 7, 18, 12);
    final gateway = _MemoryListenTogetherGateway()
      ..updatedAt = now
      ..session = const ListenTogetherSession(
        trackIds: <String>['first'],
        currentTrackId: 'first',
        position: Duration(seconds: 5),
        playing: true,
      )
      ..revision = 1;
    final engine = _TestAudioEngine();
    final player = PlayerController(audioEngine: engine);
    addTearDown(player.dispose);
    final store = ListenTogetherStore(
      gatewayFactory: () => gateway,
      clock: () => now,
    );

    await store.join(library, player);
    expect(engine.setQueueCalls, 1);

    gateway
      ..session = const ListenTogetherSession(
        trackIds: <String>['first'],
        currentTrackId: 'first',
        position: Duration(seconds: 6),
        playing: true,
      )
      ..revision = 2;
    await store.refreshJoined(library, player);
    expect(engine.setQueueCalls, 1);
    expect(engine.seekCalls, 0);

    gateway
      ..session = const ListenTogetherSession(
        trackIds: <String>['first'],
        currentTrackId: 'first',
        position: Duration(seconds: 10),
        playing: false,
      )
      ..revision = 3;
    await store.refreshJoined(library, player);
    expect(engine.setQueueCalls, 1);
    expect(engine.seekCalls, 1);
    expect(engine.positionValue, const Duration(seconds: 10));
    expect(player.isPlaying, isFalse);

    gateway
      ..session = const ListenTogetherSession(
        trackIds: <String>['second'],
        currentTrackId: 'second',
        position: Duration.zero,
        playing: true,
      )
      ..revision = 4;
    await store.refreshJoined(library, player);
    expect(engine.setQueueCalls, 2);
    expect(player.current?.id, 'second');
  });

  test('refreshes an invite guest through the host invite endpoint', () async {
    final library = LibraryStore();
    await library.load();
    final track = _track('shared');
    await library.addTracks(<Track>[track]);
    final gateway = _MemoryListenTogetherGateway()
      ..session = const ListenTogetherSession(
        trackIds: <String>['shared'],
        currentTrackId: 'shared',
        position: Duration.zero,
        playing: true,
      )
      ..revision = 1;
    final player = PlayerController(audioEngine: _TestAudioEngine());
    addTearDown(player.dispose);
    final store = ListenTogetherStore(gatewayFactory: () => gateway);

    await store.joinInvite('AAAAAAAAAAAAAAAAAAAAAAAA', library, player);
    gateway.revision = 2;
    await store.refreshJoined(library, player);

    expect(store.inviteCode, 'AAAAAAAAAAAAAAAAAAAAAAAA');
    expect(gateway.inviteFetchCalls, 2);
  });
}

Track _track(String id) => Track(
  id: id,
  title: 'Track $id',
  localPath: '/music/$id.mp3',
);

class _MemoryListenTogetherGateway implements ListenTogetherGateway {
  int revision = 0;
  int inviteFetchCalls = 0;
  DateTime updatedAt = DateTime.utc(2026, 7, 16);
  ListenTogetherSession? session;

  @override
  Future<ListenTogetherRemoteSession> fetchListenTogetherSession() async {
    return _remote();
  }

  @override
  Future<ListenTogetherRemoteSession> publishListenTogetherSession({
    required int baseRevision,
    required ListenTogetherSession session,
  }) async {
    if (baseRevision != revision) {
      throw ListenTogetherConflictException(currentRevision: revision);
    }
    this.session = session;
    revision += 1;
    return _remote();
  }

  @override
  Future<ListenTogetherRemoteSession> leaveListenTogetherSession({
    required int baseRevision,
  }) async {
    if (baseRevision != revision) {
      throw ListenTogetherConflictException(currentRevision: revision);
    }
    session = null;
    revision += 1;
    return _remote();
  }

  @override
  Future<String> issueListenTogetherInvite() async =>
      'AAAAAAAAAAAAAAAAAAAAAAAA';

  @override
  Future<ListenTogetherRemoteSession> fetchListenTogetherInvite(
    String inviteCode,
  ) async {
    inviteFetchCalls += 1;
    return _remote();
  }

  ListenTogetherRemoteSession _remote() => ListenTogetherRemoteSession(
    revision: revision,
    updatedAt: updatedAt,
    updatedByDevice: 'Test device',
    session: session,
  );
}

class _TestAudioEngine implements PlaybackAudioEngine {
  List<Track> queue = <Track>[];
  Duration positionValue = Duration.zero;
  bool playingValue = false;
  int setQueueCalls = 0;
  int seekCalls = 0;

  @override
  Stream<Object?> get stateChanges => const Stream<Object?>.empty();
  @override
  Stream<Duration?> get durationStream => const Stream<Duration?>.empty();
  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();
  @override
  Stream<ProcessingState> get processingStateStream =>
      const Stream<ProcessingState>.empty();
  @override
  Stream<int?> get currentIndexStream => const Stream<int?>.empty();
  @override
  bool get playing => playingValue;
  @override
  bool get shuffleModeEnabled => false;
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  Duration get position => positionValue;
  @override
  Duration get bufferedPosition => positionValue;
  @override
  double get speed => 1;
  @override
  double get volume => 1;
  @override
  bool get hasNext => false;
  @override
  bool get hasPrevious => false;
  @override
  Future<void> setQueue(List<Track> tracks, {
    required int initialIndex,
    Duration initialPosition = Duration.zero,
  }) async {
    setQueueCalls += 1;
    queue = List<Track>.from(tracks);
    positionValue = initialPosition;
  }
  @override
  Future<void> play() async => playingValue = true;
  @override
  Future<void> pause() async => playingValue = false;
  @override
  Future<void> stop() async => playingValue = false;
  @override
  Future<void> seek(Duration position, {int? index}) async {
    seekCalls += 1;
    positionValue = position;
  }
  @override
  Future<void> seekToNext() async {}
  @override
  Future<void> seekToPrevious() async {}
  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
}
