import 'package:flutter/foundation.dart';

import '../domain/listen_together_session.dart';
import '../domain/track.dart';
import '../player/player_controller.dart';
import 'library_store.dart';
import 'library_sync_client.dart';

typedef ListenTogetherGatewayFactory = ListenTogetherGateway Function();

/// Coordinates a portable, account-scoped listening session.
///
/// Sessions contain only stable library IDs and playback state. Each device
/// resolves those IDs against its own library and never receives media URLs,
/// local paths, or credentials.
class ListenTogetherStore extends ChangeNotifier {
  ListenTogetherStore({ListenTogetherGatewayFactory? gatewayFactory})
      : _gatewayFactory = gatewayFactory;

  ListenTogetherGatewayFactory? _gatewayFactory;
  int _revision = 0;
  ListenTogetherSession? _session;
  DateTime? _updatedAt;
  String? _updatedByDevice;
  bool _hosting = false;
  bool _joined = false;
  bool _busy = false;
  String? _lastError;

  int get revision => _revision;
  ListenTogetherSession? get session => _session;
  DateTime? get updatedAt => _updatedAt;
  String? get updatedByDevice => _updatedByDevice;
  bool get hosting => _hosting;
  bool get joined => _joined;
  bool get busy => _busy;
  String? get lastError => _lastError;
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
      _hosting = true;
      _joined = true;
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
      final restored = await _applySession(shared, library, player);
      _applyMetadata(remote, session: shared);
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
      final remote = await _requireGateway().fetchListenTogetherSession();
      final shared = remote.session;
      if (shared == null) {
        _reset();
        return 0;
      }
      if (remote.revision == _revision) {
        return 0;
      }
      final restored = await _applySession(shared, library, player);
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
    final trackIds = <String>[];
    for (final track in player.queue) {
      if (libraryIds.contains(track.id) && !trackIds.contains(track.id)) {
        trackIds.add(track.id);
      }
      if (trackIds.length == ListenTogetherSession.maxTrackIds) {
        break;
      }
    }
    final currentTrackId = player.current?.id;
    if (currentTrackId != null &&
        libraryIds.contains(currentTrackId) &&
        !trackIds.contains(currentTrackId) &&
        trackIds.length < ListenTogetherSession.maxTrackIds) {
      trackIds.add(currentTrackId);
    }
    if (trackIds.isEmpty) {
      throw StateError('Queue a library track before starting a shared session.');
    }
    final current = currentTrackId != null && trackIds.contains(currentTrackId)
        ? currentTrackId
        : trackIds.first;
    return ListenTogetherSession(
      trackIds: List<String>.unmodifiable(trackIds),
      currentTrackId: current,
      position: player.position,
      playing: player.isPlaying,
    );
  }

  Future<int> _applySession(
    ListenTogetherSession session,
    LibraryStore library,
    PlayerController player,
  ) async {
    final tracksById = <String, Track>{
      for (final track in library.tracks) track.id: track,
    };
    final queue = session.trackIds
        .map((id) => tracksById[id])
        .whereType<Track>()
        .toList(growable: false);
    if (queue.isEmpty) {
      throw StateError('None of the shared tracks are available in this library.');
    }
    final current = tracksById[session.currentTrackId] ?? queue.first;
    await player.playTrack(
      current,
      queue: queue,
      initialPosition: session.position,
    );
    if (!session.playing) {
      await player.togglePlayPause();
    }
    return queue.length;
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
    _hosting = false;
    _joined = false;
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
