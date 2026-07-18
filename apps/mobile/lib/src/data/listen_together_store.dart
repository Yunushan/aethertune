import 'package:flutter/foundation.dart';

import '../domain/listen_together_session.dart';
import '../domain/track.dart';
import '../player/player_controller.dart';
import 'library_store.dart';
import 'library_sync_client.dart';

typedef ListenTogetherGatewayFactory = ListenTogetherGateway Function();
typedef ListenTogetherClock = DateTime Function();

/// Coordinates a portable, account-scoped listening session.
///
/// Sessions contain only stable library IDs and playback state. Each device
/// resolves those IDs against its own library and never receives media URLs,
/// local paths, or credentials.
class ListenTogetherStore extends ChangeNotifier {
  ListenTogetherStore({
    ListenTogetherGatewayFactory? gatewayFactory,
    ListenTogetherClock? clock,
  })  : _gatewayFactory = gatewayFactory,
        _clock = clock ?? DateTime.now;

  ListenTogetherGatewayFactory? _gatewayFactory;
  final ListenTogetherClock _clock;
  int _revision = 0;
  ListenTogetherSession? _session;
  DateTime? _updatedAt;
  String? _updatedByDevice;
  String? _inviteCode;
  bool _hosting = false;
  bool _joined = false;
  bool _busy = false;
  String? _lastError;
  int _unavailableTrackCount = 0;

  int get revision => _revision;
  ListenTogetherSession? get session => _session;
  DateTime? get updatedAt => _updatedAt;
  String? get updatedByDevice => _updatedByDevice;
  String? get inviteCode => _inviteCode;
  bool get hosting => _hosting;
  bool get joined => _joined;
  bool get busy => _busy;
  String? get lastError => _lastError;
  int get unavailableTrackCount => _unavailableTrackCount;
  bool get available => _gatewayFactory != null;

  void updateGatewayFactory(ListenTogetherGatewayFactory? gatewayFactory) {
    if (identical(_gatewayFactory, gatewayFactory)) {
      return;
    }
    _gatewayFactory = gatewayFactory;
    if (gatewayFactory == null) {
      _reset();
    }
  }

  Future<void> host(LibraryStore library, PlayerController player) {
    return _runBusy(() async {
      _requireOnline(library);
      final gateway = _requireGateway();
      final remote = await gateway.fetchListenTogetherSession();
      if (remote.session != null) {
        throw StateError('A listen-together session is already active.');
      }
      final local = _sessionFromPlayer(library, player);
      final published = await gateway.publishListenTogetherSession(
        baseRevision: remote.revision,
        session: local,
      );
      _applyMetadata(published, session: local);
      _inviteCode = null;
      _hosting = true;
      _joined = true;
      _unavailableTrackCount = 0;
    });
  }

  Future<int> join(LibraryStore library, PlayerController player) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await _requireGateway().fetchListenTogetherSession();
      final shared = remote.session;
      if (shared == null) {
        throw StateError('No active listen-together session was found.');
      }
      final restored = await _applySession(
        shared,
        library,
        player,
        updatedAt: remote.updatedAt,
      );
      _applyMetadata(remote, session: shared);
      _inviteCode = null;
      _hosting = false;
      _joined = true;
      return restored;
    });
  }

  Future<String> createInvite() {
    return _runBusy(() async {
      if (!_hosting) {
        throw StateError('Host a listen-together session before sharing it.');
      }
      return _requireGateway().issueListenTogetherInvite();
    });
  }

  Future<int> joinInvite(
    String inviteCode,
    LibraryStore library,
    PlayerController player,
  ) {
    return _runBusy(() async {
      _requireOnline(library);
      final remote = await _requireGateway().fetchListenTogetherInvite(inviteCode);
      final shared = remote.session;
      if (shared == null) {
        throw StateError('That listen-together invite has ended.');
      }
      final restored = await _applySession(
        shared,
        library,
        player,
        updatedAt: remote.updatedAt,
      );
      _applyMetadata(remote, session: shared);
      _inviteCode = inviteCode.trim();
      _hosting = false;
      _joined = true;
      return restored;
    });
  }

  /// Applies a newer host update for a device that already joined.
  Future<int> refreshJoined(LibraryStore library, PlayerController player) {
    return _runBusy(() async {
      if (!_joined || _hosting) {
        return 0;
      }
      _requireOnline(library);
      final gateway = _requireGateway();
      final remote = _inviteCode == null
          ? await gateway.fetchListenTogetherSession()
          : await gateway.fetchListenTogetherInvite(_inviteCode!);
      final shared = remote.session;
      if (shared == null) {
        _reset();
        return 0;
      }
      if (remote.revision == _revision && _unavailableTrackCount == 0) {
        return 0;
      }
      final restored = await _applySession(
        shared,
        library,
        player,
        updatedAt: remote.updatedAt,
      );
      _applyMetadata(remote, session: shared);
      return restored;
    });
  }

  /// Publishes the host device's latest queue, item, position, and play state.
  Future<void> publishHostPlayback(
    LibraryStore library,
    PlayerController player,
  ) {
    return _runBusy(() async {
      if (!_hosting) {
        return;
      }
      _requireOnline(library);
      final local = _sessionFromPlayer(library, player);
      if (_sameSession(_session, local)) {
        return;
      }
      try {
        final published = await _requireGateway().publishListenTogetherSession(
          baseRevision: _revision,
          session: local,
        );
        _applyMetadata(published, session: local);
      } on ListenTogetherConflictException {
        _hosting = false;
        _joined = false;
        rethrow;
      }
    });
  }

  Future<void> endHostedSession() {
    return _runBusy(() async {
      if (!_hosting) {
        _reset();
        return;
      }
      final deleted = await _requireGateway().leaveListenTogetherSession(
        baseRevision: _revision,
      );
      _applyMetadata(deleted);
      _reset();
    });
  }

  void leave() {
    _reset();
    notifyListeners();
  }

  ListenTogetherSession _sessionFromPlayer(
    LibraryStore library,
    PlayerController player,
  ) {
    final libraryIds = library.tracks.map((track) => track.id).toSet();
    final playerQueue = player.queue;
    final trackIds = <String>[];
    for (final track in playerQueue) {
      if (libraryIds.contains(track.id)) {
        trackIds.add(track.id);
      }
      if (trackIds.length == ListenTogetherSession.maxTrackIds) {
        break;
      }
    }
    final playerCurrentIndex = player.currentQueueIndex;
    final fallbackCurrentIndex = playerQueue.indexWhere(
      (track) => track.id == player.current?.id,
    );
    final sourceCurrentIndex = playerCurrentIndex ?? fallbackCurrentIndex;
    if (trackIds.isEmpty) {
      throw StateError('Queue a library track before starting a shared session.');
    }
    final hasLocalCurrent = sourceCurrentIndex >= 0 &&
        sourceCurrentIndex < playerQueue.length &&
        libraryIds.contains(playerQueue[sourceCurrentIndex].id);
    var currentIndex = hasLocalCurrent
        ? _portableQueueIndexForPlayerIndex(
            playerQueue,
            libraryIds,
            sourceCurrentIndex,
          )
        : 0;
    if (currentIndex >= trackIds.length) {
      trackIds
        ..removeLast()
        ..add(playerQueue[sourceCurrentIndex].id);
      currentIndex = trackIds.length - 1;
    }
    return ListenTogetherSession(
      trackIds: List<String>.unmodifiable(trackIds),
      currentTrackId: trackIds[currentIndex],
      currentIndex: currentIndex,
      position: player.position,
      playing: player.isPlaying,
    );
  }

  int _portableQueueIndexForPlayerIndex(
    List<Track> queue,
    Set<String> libraryIds,
    int playerIndex,
  ) {
    var portableIndex = 0;
    for (var index = 0; index < playerIndex; index += 1) {
      if (libraryIds.contains(queue[index].id)) {
        portableIndex += 1;
      }
    }
    return portableIndex;
  }

  Future<int> _applySession(
    ListenTogetherSession session,
    LibraryStore library,
    PlayerController player, {
    DateTime? updatedAt,
  }) async {
    final tracksById = <String, Track>{
      for (final track in library.tracks) track.id: track,
    };
    final queue = session.trackIds
        .map((id) => tracksById[id])
        .whereType<Track>()
        .toList(growable: false);
    _unavailableTrackCount = session.trackIds.length - queue.length;
    if (queue.isEmpty) {
      throw StateError('None of the shared tracks are available in this library.');
    }
    final requestedCurrentIndex = _currentIndexForSession(session);
    final requestedCurrentId = requestedCurrentIndex == null
        ? null
        : session.trackIds[requestedCurrentIndex];
    final resolvedCurrent = requestedCurrentId == null
        ? null
        : tracksById[requestedCurrentId];
    final current = resolvedCurrent ?? queue.first;
    final currentQueueIndex = resolvedCurrent == null
        ? 0
        : _resolvedQueueIndexForSessionIndex(
            session,
            tracksById,
            requestedCurrentIndex!,
          );
    final targetPosition = resolvedCurrent == null && requestedCurrentId != null
        ? Duration.zero
        : _positionAtReceipt(session, updatedAt);
    if (_matchesActiveQueue(player, queue, current, currentQueueIndex)) {
      final drift = targetPosition - player.position;
      if (drift.inMilliseconds.abs() >
          _positionDriftTolerance.inMilliseconds) {
        await player.seek(targetPosition);
      }
      if (player.isPlaying != session.playing) {
        await player.togglePlayPause();
      }
      return queue.length;
    }
    await player.playTrack(
      current,
      queue: queue,
      queueIndex: currentQueueIndex,
      initialPosition: targetPosition,
    );
    if (!session.playing) {
      await player.togglePlayPause();
    }
    return queue.length;
  }

  int? _currentIndexForSession(ListenTogetherSession session) {
    final currentIndex = session.currentIndex;
    if (currentIndex != null) {
      return currentIndex;
    }
    final currentTrackId = session.currentTrackId;
    return currentTrackId == null ? null : session.trackIds.indexOf(currentTrackId);
  }

  int _resolvedQueueIndexForSessionIndex(
    ListenTogetherSession session,
    Map<String, Track> tracksById,
    int sessionIndex,
  ) {
    var resolvedIndex = -1;
    for (var index = 0; index <= sessionIndex; index += 1) {
      if (tracksById.containsKey(session.trackIds[index])) {
        resolvedIndex += 1;
      }
    }
    return resolvedIndex < 0 ? 0 : resolvedIndex;
  }

  bool _sameSession(
    ListenTogetherSession? previous,
    ListenTogetherSession next,
  ) {
    if (previous == null ||
        previous.currentTrackId != next.currentTrackId ||
        previous.currentIndex != next.currentIndex ||
        previous.position != next.position ||
        previous.playing != next.playing ||
        previous.trackIds.length != next.trackIds.length) {
      return false;
    }
    for (var index = 0; index < previous.trackIds.length; index += 1) {
      if (previous.trackIds[index] != next.trackIds[index]) {
        return false;
      }
    }
    return true;
  }

  Duration _positionAtReceipt(
    ListenTogetherSession session,
    DateTime? updatedAt,
  ) {
    if (!session.playing || updatedAt == null) {
      return session.position;
    }
    final elapsed = _clock().toUtc().difference(updatedAt.toUtc());
    return elapsed.isNegative ? session.position : session.position + elapsed;
  }

  bool _matchesActiveQueue(
    PlayerController player,
    List<Track> queue,
    Track current,
    int currentQueueIndex,
  ) {
    if (player.current?.id != current.id ||
        (player.currentQueueIndex != null &&
            player.currentQueueIndex != currentQueueIndex) ||
        player.queue.length != queue.length) {
      return false;
    }
    for (var index = 0; index < queue.length; index += 1) {
      if (player.queue[index].id != queue[index].id) {
        return false;
      }
    }
    return true;
  }

  ListenTogetherGateway _requireGateway() {
    final factory = _gatewayFactory;
    if (factory == null) {
      throw StateError('Configure a library sync server first.');
    }
    return factory();
  }

  void _requireOnline(LibraryStore library) {
    if (library.offlineModeEnabled) {
      throw StateError('Turn off offline mode before joining a shared session.');
    }
  }

  void _applyMetadata(
    ListenTogetherRemoteSession remote, {
    ListenTogetherSession? session,
  }) {
    _revision = remote.revision;
    _session = session;
    _updatedAt = remote.updatedAt;
    _updatedByDevice = remote.updatedByDevice;
  }

  void _reset() {
    _revision = 0;
    _session = null;
    _updatedAt = null;
    _updatedByDevice = null;
    _inviteCode = null;
    _hosting = false;
    _joined = false;
    _unavailableTrackCount = 0;
  }

  Future<T> _runBusy<T>(Future<T> Function() action) async {
    if (_busy) {
      throw StateError('A listen-together operation is already running.');
    }
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      return await action();
    } on Object catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

const _positionDriftTolerance = Duration(seconds: 2);
