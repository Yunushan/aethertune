import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/track.dart';
import 'listenbrainz_client.dart';
import 'provider_credential_vault.dart';

typedef ListenBrainzClientFactory = ListenBrainzClient Function(String token);

/// Whether a persisted ListenBrainz retry is allowed to run in a native
/// background pass. The caller supplies library privacy state because it is
/// intentionally owned by [LibraryStore], not this credential-scoped store.
bool shouldRetryListenBrainzInBackground({
  required bool isConfigured,
  required bool backgroundRetryEnabled,
  required bool hasPendingListens,
  required bool offlineModeEnabled,
  required bool pauseListeningHistory,
}) {
  return isConfigured &&
      backgroundRetryEnabled &&
      hasPendingListens &&
      !offlineModeEnabled &&
      !pauseListeningHistory;
}

/// Stores only the user token in the credential vault and submits completed,
/// user-opted-in listens. Tokens never enter preferences, backups, or logs.
final class ListenBrainzScrobblingStore extends ChangeNotifier {
  ListenBrainzScrobblingStore({
    ProviderCredentialVault? credentialVault,
    ListenBrainzClientFactory? clientFactory,
    DateTime Function()? clock,
  }) : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
       _clientFactory =
           clientFactory ?? ((token) => ListenBrainzClient(token: token)),
       _clock = clock ?? DateTime.now;

  static const _credentialId = 'listenbrainz-user-token';
  static const _pendingPreferencesKey = 'aethertune.listenbrainz.pending.v1';
  static const _backgroundRetryPreferencesKey =
      'aethertune.listenbrainz.background-retry.v1';
  static const _pendingDocumentVersion = 1;
  static const _maximumPendingListens = 100;
  static const _pendingRetention = Duration(days: 30);
  static const maximumListenDuration = Duration(minutes: 4);

  final ProviderCredentialVault _credentialVault;
  final ListenBrainzClientFactory _clientFactory;
  final DateTime Function() _clock;
  final Set<String> _submittedListenKeys = <String>{};
  final Set<String> _submittingListenKeys = <String>{};
  final List<_PendingListen> _pendingListens = <_PendingListen>[];
  Future<void> _preferenceWrites = Future<void>.value();
  Future<void> _credentialOperations = Future<void>.value();

  String? _token;
  String? _userName;
  String? _lastError;
  bool _loaded = false;
  bool _submitting = false;
  bool _retrying = false;
  bool _backgroundRetryEnabled = false;
  int _credentialGeneration = 0;
  int _activeSubmissions = 0;

  bool get loaded => _loaded;
  bool get isConfigured => (_token ?? '').isNotEmpty;
  String? get userName => _userName;
  String? get lastError => _lastError;
  bool get submitting => _submitting;
  int get pendingListenCount => _pendingListens.length;
  bool get backgroundRetryEnabled => _backgroundRetryEnabled;

  Future<void> load() => _withCredentialOperation(_load);

  Future<void> _load() async {
    if (_loaded) {
      return;
    }
    try {
      _token = _normalize(await _credentialVault.read(_credentialId));
      _lastError = null;
    } on Object {
      _token = null;
      _lastError = 'ListenBrainz token storage is unavailable.';
    }
    try {
      await _loadPendingListens();
    } on Object {
      _pendingListens.clear();
      _lastError ??= 'Pending ListenBrainz submissions could not be loaded.';
    }
    try {
      _backgroundRetryEnabled =
          (await SharedPreferences.getInstance()).getBool(
            _backgroundRetryPreferencesKey,
          ) ??
          false;
    } on Object {
      _backgroundRetryEnabled = false;
    }
    if (_token == null) _backgroundRetryEnabled = false;
    _loaded = true;
    notifyListeners();
  }

  Future<void> configure(String token) =>
      _withCredentialOperation(() => _configure(token));

  Future<void> _configure(String token) async {
    final normalized = _normalize(token);
    if (normalized == null) {
      throw const FormatException('Enter a ListenBrainz user token.');
    }
    if (_token != null && _token != normalized) {
      throw StateError('Disconnect ListenBrainz before changing accounts.');
    }
    final userName = await _clientFactory(normalized).validateToken();
    if (_token == null) {
      // An orphaned queue must never be submitted under a newly connected
      // account, including after an earlier disconnect could not erase it.
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      if (preferences.containsKey(_pendingPreferencesKey)) {
        await _clearPendingListens();
        _pendingListens.clear();
      }
      if (preferences.containsKey(_backgroundRetryPreferencesKey)) {
        await _clearBackgroundRetryPreference();
        _backgroundRetryEnabled = false;
      }
    }
    await _credentialVault.write(_credentialId, normalized);
    if (_token != normalized) _credentialGeneration += 1;
    _token = normalized;
    _userName = userName;
    _lastError = null;
    notifyListeners();
  }

  Future<void> remove() => _withCredentialOperation(_remove);

  Future<void> _remove() async {
    await _credentialVault.delete(_credentialId);
    _credentialGeneration += 1;
    _token = null;
    _userName = null;
    _submittedListenKeys.clear();
    _submittingListenKeys.clear();
    _backgroundRetryEnabled = false;
    var cleanupFailed = false;
    try {
      await _clearPendingListens();
      _pendingListens.clear();
    } on Object {
      cleanupFailed = true;
    }
    try {
      await _clearBackgroundRetryPreference();
    } on Object {
      cleanupFailed = true;
    }
    _lastError = cleanupFailed
        ? 'ListenBrainz disconnected, but local retry data could not be removed.'
        : null;
    notifyListeners();
    if (cleanupFailed) {
      throw StateError(_lastError!);
    }
  }

  /// Allows a native Android or iOS scheduler pass to retry pending listens.
  /// This remains disabled by default and never causes a retry during load.
  Future<void> setBackgroundRetryEnabled(bool enabled) async {
    if (enabled && !isConfigured) {
      throw StateError(
        'Connect ListenBrainz before enabling background retry.',
      );
    }
    if (_backgroundRetryEnabled == enabled) {
      return;
    }
    final generation = _credentialGeneration;
    final preferences = await SharedPreferences.getInstance();
    await _writePreference(
      preferences,
      () => preferences.setBool(_backgroundRetryPreferencesKey, enabled),
      'ListenBrainz background retry setting could not be saved.',
      isCurrent: () => generation == _credentialGeneration,
    );
    if (generation != _credentialGeneration) return;
    _backgroundRetryEnabled = enabled;
    notifyListeners();
  }

  Future<List<ListenBrainzHistoryEntry>> fetchListenHistory({
    int count = 100,
  }) async {
    final token = _token;
    if (token == null) {
      throw StateError('Connect ListenBrainz before importing history.');
    }
    final client = _clientFactory(token);
    var userName = _userName;
    if (userName == null) {
      userName = await client.validateToken();
      if (userName == null) {
        throw StateError('ListenBrainz did not identify an account.');
      }
      _userName = userName;
      notifyListeners();
    }
    return client.fetchListenHistory(userName: userName, count: count);
  }

  Future<void> submitIfEligible({
    required Track track,
    required DateTime startedAt,
    required Duration position,
  }) async {
    final token = _token;
    final generation = _credentialGeneration;
    if (token == null || position < completionThreshold(track.duration)) {
      return;
    }
    final pending = _PendingListen.fromTrack(track, startedAt);
    final key = pending.deduplicationKey;
    if (_submittedListenKeys.contains(key) || !_submittingListenKeys.add(key)) {
      return;
    }

    _activeSubmissions += 1;
    _submitting = true;
    notifyListeners();
    var submitted = false;
    try {
      await _clientFactory(
        token,
      ).submitListen(track: track, startedAt: pending.startedAt);
      if (generation == _credentialGeneration) {
        _submittedListenKeys.add(key);
        submitted = true;
      }
    } on Object {
      if (generation == _credentialGeneration) {
        _lastError = 'Could not submit the completed ListenBrainz listen.';
      }
    } finally {
      if (generation == _credentialGeneration) {
        try {
          await _persistPendingListens(generation, (nextPending) {
            if (submitted) {
              _removePending(nextPending, pending);
            } else {
              _enqueuePending(nextPending, pending);
            }
          });
          if (generation == _credentialGeneration && submitted) {
            _lastError = null;
          }
        } on Object {
          if (generation == _credentialGeneration) {
            _lastError = 'Pending ListenBrainz submissions could not be saved.';
          }
        }
      }
      _submittingListenKeys.remove(key);
      _activeSubmissions -= 1;
      _submitting = _activeSubmissions > 0 || _retrying;
      notifyListeners();
    }
  }

  /// Retries failed completed-listen submissions.
  ///
  /// Foreground retries are always explicit. Native background callers must
  /// first verify the separate user opt-in and library privacy policy.
  /// A remote success followed by a failed local queue removal may be
  /// submitted again after restart; delivery is at least once in that case.
  Future<int> retryPendingListens({bool Function()? shouldContinue}) async {
    final token = _token;
    final generation = _credentialGeneration;
    if (token == null || _pendingListens.isEmpty || _submitting) {
      return 0;
    }

    _retrying = true;
    _submitting = true;
    notifyListeners();
    var submitted = 0;
    final completed = <_PendingListen>[];
    try {
      for (final pending in List<_PendingListen>.from(_pendingListens)) {
        if (generation != _credentialGeneration) break;
        if (shouldContinue?.call() == false) break;
        if (_submittedListenKeys.contains(pending.deduplicationKey)) {
          completed.add(pending);
          continue;
        }
        try {
          await _clientFactory(token).submitListen(
            track: pending.toTrack(),
            startedAt: pending.startedAt,
          );
          if (generation != _credentialGeneration) break;
          completed.add(pending);
          _submittedListenKeys.add(pending.deduplicationKey);
          submitted += 1;
        } on Object {
          if (generation == _credentialGeneration) {
            _lastError = 'Could not submit all pending ListenBrainz listens.';
          }
          break;
        }
      }
      if (generation == _credentialGeneration) {
        try {
          await _persistPendingListens(generation, (nextPending) {
            for (final pending in completed) {
              _removePending(nextPending, pending);
            }
          });
          if (generation == _credentialGeneration) {
            if (_pendingListens.isEmpty) _lastError = null;
          }
        } on Object {
          if (generation == _credentialGeneration) {
            _lastError = 'Pending ListenBrainz submissions could not be saved.';
          }
        }
      }
      return submitted;
    } finally {
      _retrying = false;
      _submitting = _activeSubmissions > 0;
      notifyListeners();
    }
  }

  static Duration completionThreshold(Duration duration) {
    if (duration <= Duration.zero) {
      return maximumListenDuration;
    }
    final half = Duration(milliseconds: duration.inMilliseconds ~/ 2);
    return half < maximumListenDuration ? half : maximumListenDuration;
  }

  static String? _normalize(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }

  Future<void> _withCredentialOperation(
    Future<void> Function() operation,
  ) async {
    final previousOperation = _credentialOperations;
    final completed = Completer<void>();
    _credentialOperations = completed.future;
    try {
      await previousOperation;
      await operation();
    } finally {
      completed.complete();
    }
  }

  Future<void> _loadPendingListens() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final raw = preferences.getString(_pendingPreferencesKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Pending ListenBrainz data is invalid.');
    }
    final document = Map<String, Object?>.from(decoded);
    if (document['version'] != _pendingDocumentVersion ||
        document['listens'] is! List) {
      throw const FormatException('Pending ListenBrainz data is invalid.');
    }
    final minimumStartedAt = _clock().toUtc().subtract(_pendingRetention);
    final parsed = <_PendingListen>[];
    final seen = <String>{};
    for (final rawListen in (document['listens'] as List).take(
      _maximumPendingListens,
    )) {
      if (rawListen is! Map) {
        continue;
      }
      final pending = _PendingListen.tryFromJson(
        Map<String, Object?>.from(rawListen),
      );
      if (pending != null &&
          !pending.startedAt.isBefore(minimumStartedAt) &&
          seen.add(pending.deduplicationKey)) {
        parsed.add(pending);
      }
    }
    parsed.sort((first, second) => first.startedAt.compareTo(second.startedAt));
    _pendingListens
      ..clear()
      ..addAll(parsed);
  }

  Future<void> _persistPendingListens(
    int generation,
    void Function(List<_PendingListen>) update,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    late List<_PendingListen> nextPending;
    await _writePreference(
      preferences,
      () {
        nextPending = List<_PendingListen>.from(_pendingListens);
        update(nextPending);
        return preferences.setString(
          _pendingPreferencesKey,
          jsonEncode(<String, Object?>{
            'version': _pendingDocumentVersion,
            'listens': nextPending
                .map((pending) => pending.toJson())
                .toList(growable: false),
          }),
        );
      },
      'Pending ListenBrainz submissions could not be saved.',
      isCurrent: () => generation == _credentialGeneration,
      afterAccepted: () {
        _pendingListens
          ..clear()
          ..addAll(nextPending);
      },
    );
  }

  Future<void> _clearPendingListens() async {
    final preferences = await SharedPreferences.getInstance();
    await _writePreference(
      preferences,
      () => preferences.remove(_pendingPreferencesKey),
      'Pending ListenBrainz submissions could not be removed.',
    );
  }

  Future<void> _clearBackgroundRetryPreference() async {
    final preferences = await SharedPreferences.getInstance();
    await _writePreference(
      preferences,
      () => preferences.remove(_backgroundRetryPreferencesKey),
      'ListenBrainz background retry setting could not be removed.',
    );
  }

  Future<void> _writePreference(
    SharedPreferences preferences,
    Future<bool> Function() write,
    String failureMessage, {
    bool Function()? isCurrent,
    void Function()? afterAccepted,
  }) async {
    final previousWrite = _preferenceWrites;
    final completed = Completer<void>();
    _preferenceWrites = completed.future;
    try {
      await previousWrite;
      if (isCurrent?.call() == false) {
        throw StateError(
          'ListenBrainz account changed during a preference write.',
        );
      }
      bool accepted;
      try {
        accepted = await write();
      } on Object {
        try {
          await preferences.reload();
        } on Object {
          // Keep the write failure as the actionable error.
        }
        rethrow;
      }
      if (!accepted) {
        try {
          await preferences.reload();
        } on Object {
          // The rejected write still must not be treated as durable.
        }
        throw StateError(failureMessage);
      }
      afterAccepted?.call();
    } finally {
      completed.complete();
    }
  }

  void _enqueuePending(List<_PendingListen> listens, _PendingListen pending) {
    _removePending(listens, pending);
    listens.add(pending);
    listens.sort(
      (first, second) => first.startedAt.compareTo(second.startedAt),
    );
    if (listens.length > _maximumPendingListens) {
      listens.removeRange(0, listens.length - _maximumPendingListens);
    }
  }

  void _removePending(List<_PendingListen> listens, _PendingListen pending) {
    listens.removeWhere(
      (candidate) => candidate.deduplicationKey == pending.deduplicationKey,
    );
  }
}

final class _PendingListen {
  const _PendingListen({
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.startedAt,
  });

  factory _PendingListen.fromTrack(Track track, DateTime startedAt) {
    return _PendingListen(
      title: _text(track.title, fallback: 'Untitled'),
      artist: _text(track.artist, fallback: 'Unknown Artist'),
      album: track.album.trim() == 'Unknown Album'
          ? null
          : _optionalText(track.album),
      duration: track.duration.isNegative ? Duration.zero : track.duration,
      startedAt: startedAt.toUtc(),
    );
  }

  final String title;
  final String artist;
  final String? album;
  final Duration duration;
  final DateTime startedAt;

  String get deduplicationKey =>
      '${startedAt.millisecondsSinceEpoch}:$title:$artist:${album ?? ''}';

  Track toTrack() => Track(
    id: 'listenbrainz-pending:${startedAt.millisecondsSinceEpoch}',
    title: title,
    artist: artist,
    album: album ?? 'Unknown Album',
    duration: duration,
    sourceId: 'listenbrainz-pending',
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'title': title,
    'artist': artist,
    if (album != null) 'album': album,
    'durationMs': duration.inMilliseconds,
    'startedAt': startedAt.toIso8601String(),
  };

  static _PendingListen? tryFromJson(Map<String, Object?> json) {
    final title = _optionalText(json['title']?.toString());
    final artist = _optionalText(json['artist']?.toString());
    final startedAt = DateTime.tryParse(json['startedAt']?.toString() ?? '');
    final durationMs = (json['durationMs'] as num?)?.toInt() ?? 0;
    if (title == null ||
        artist == null ||
        startedAt == null ||
        durationMs < 0) {
      return null;
    }
    return _PendingListen(
      title: title,
      artist: artist,
      album: _optionalText(json['album']?.toString()),
      duration: Duration(milliseconds: durationMs),
      startedAt: startedAt.toUtc(),
    );
  }

  static String _text(String value, {required String fallback}) =>
      _optionalText(value) ?? fallback;

  static String? _optionalText(String? value) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
