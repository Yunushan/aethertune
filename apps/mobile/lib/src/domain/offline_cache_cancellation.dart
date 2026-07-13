import 'dart:async';

final class OfflineCacheCancelled implements Exception {
  const OfflineCacheCancelled();

  @override
  String toString() => 'Offline cache request was paused by the user.';
}

final class OfflineCacheCancellationToken {
  bool _cancelled = false;
  final Completer<void> _cancelledSignal = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _cancelledSignal.future;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _cancelledSignal.complete();
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const OfflineCacheCancelled();
    }
  }
}

/// Coordinates an active foreground request with persisted queue controls.
///
/// The token remains in memory only. The queue stores the user-visible paused
/// state, while an interrupted HTTP response leaves its private `.part` file
/// available for a later Range resume.
final class OfflineCacheCancellationRegistry {
  OfflineCacheCancellationRegistry._();

  static final OfflineCacheCancellationRegistry instance =
      OfflineCacheCancellationRegistry._();

  final Map<String, OfflineCacheCancellationToken> _tokens =
      <String, OfflineCacheCancellationToken>{};

  OfflineCacheCancellationToken begin(String entryId) {
    final token = OfflineCacheCancellationToken();
    _tokens[entryId] = token;
    return token;
  }

  OfflineCacheCancellationToken tokenFor(String entryId) {
    return _tokens.putIfAbsent(entryId, OfflineCacheCancellationToken.new);
  }

  void cancel(String entryId) {
    _tokens[entryId]?.cancel();
  }

  void release(String entryId, OfflineCacheCancellationToken token) {
    if (identical(_tokens[entryId], token)) {
      _tokens.remove(entryId);
    }
  }

  void clear(String entryId) {
    _tokens.remove(entryId);
  }
}
