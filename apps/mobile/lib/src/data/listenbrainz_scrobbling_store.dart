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
       _clientFactory = clientFactory ?? ((token) => ListenBrainzClient(token: token)),
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

  String? _token;
  String? _userName;
  String? _lastError;
  bool _loaded = false;
  bool _submitting = false;
  bool _backgroundRetryEnabled = false;

  bool get loaded => _loaded;
  bool get isConfigured => (_token ?? '').isNotEmpty;
  String? get userName => _userName;
  String? get lastError => _lastError;
  bool get submitting => _submitting;
  int get pendingListenCount => _pendingListens.length;
  bool get backgroundRetryEnabled => _backgroundRetryEnabled;

  Future<void> load() async {
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
    _loaded = true;
    notifyListeners();
  }

  Future<void> configure(String token) async {
    final normalized = _normalize(token);
    if (normalized == null) {
      throw const FormatException('Enter a ListenBrainz user token.');
    }
    final userName = await _clientFactory(normalized).validateToken();
    await _credentialVault.write(_credentialId, normalized);
    _token = normalized;
    _userName = userName;
    _lastError = null;
    notifyListeners();
  }

  Future<void> remove() async {
    await _credentialVault.delete(_credentialId);
    _token = null;
    _userName = null;
    _lastError = null;
    _submittedListenKeys.clear();
    _submittingListenKeys.clear();
    _pendingListens.clear();
    _backgroundRetryEnabled = false;
    await _clearPendingListens();
    await _clearBackgroundRetryPreference();
    notifyListeners();
  }

  /// Allows a native Android or iOS scheduler pass to retry pending listens.
  /// This remains disabled by default and never causes a retry during load.
  Future<void> setBackgroundRetryEnabled(bool enabled) async {
    if (enabled && !isConfigured) {
      throw StateError('Connect ListenBrainz before enabling background retry.');
    }
    if (_backgroundRetryEnabled == enabled) {
      return;
    }
    await (await SharedPreferences.getInstance()).setBool(
      _backgroundRetryPreferencesKey,
      enabled,
    );
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
    if (token == null || position < completionThreshold(track.duration)) {
      return;
    }
    final pending = _PendingListen.fromTrack(track, startedAt);
    final key = pending.deduplicationKey;
    if (_submittedListenKeys.contains(key) ||
        !_submittingListenKeys.add(key)) {
      return;
    }

    _submitting = true;
    notifyListeners();
    try {
      await _clientFactory(token).submitListen(
        track: track,
        startedAt: pending.startedAt,
      );
      _submittedListenKeys.add(key);
      _removePending(pending);
      _lastError = null;
    } on Object {
      _enqueuePending(pending);
      _lastError = 'Could not submit the completed ListenBrainz listen.';
    } finally {
      try {
        await _persistPendingListens();
      } on Object {
        _lastError ??= 'Pending ListenBrainz submissions could not be saved.';
      }
      _submittingListenKeys.remove(key);
      _submitting = false;
      notifyListeners();
    }
  }

  /// Retries failed completed-listen submissions.
  ///
  /// Foreground retries are always explicit. Native background callers must
  /// first verify the separate user opt-in and library privacy policy.
  Future<int> retryPendingListens() async {
    final token = _token;
    if (token == null || _pendingListens.isEmpty || _submitting) {
      return 0;
    }

    _submitting = true;
    notifyListeners();
    var submitted = 0;
    try {
      for (final pending in List<_PendingListen>.from(_pendingListens)) {
        try {
          await _clientFactory(token).submitListen(
            track: pending.toTrack(),
            startedAt: pending.startedAt,
          );
          _removePending(pending);
          _submittedListenKeys.add(pending.deduplicationKey);
          submitted += 1;
        } on Object {
          _lastError = 'Could not submit all pending ListenBrainz listens.';
          break;
        }
      }
      if (_pendingListens.isEmpty) {
        _lastError = null;
      }
      try {
        await _persistPendingListens();
      } on Object {
        _lastError ??= 'Pending ListenBrainz submissions could not be saved.';
      }
      return submitted;
    } finally {
      _submitting = false;
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

  Future<void> _loadPendingListens() async {
    final raw = (await SharedPreferences.getInstance()).getString(
      _pendingPreferencesKey,
    );
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
    for (final rawListen
        in (document['listens'] as List).take(_maximumPendingListens)) {
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

  Future<void> _persistPendingListens() async {
    await (await SharedPreferences.getInstance()).setString(
      _pendingPreferencesKey,
      jsonEncode(<String, Object?>{
        'version': _pendingDocumentVersion,
        'listens': _pendingListens
            .map((pending) => pending.toJson())
            .toList(growable: false),
      }),
    );
  }

  Future<void> _clearPendingListens() async {
    await (await SharedPreferences.getInstance()).remove(_pendingPreferencesKey);
  }

  Future<void> _clearBackgroundRetryPreference() async {
    await (await SharedPreferences.getInstance()).remove(
      _backgroundRetryPreferencesKey,
    );
  }

  void _enqueuePending(_PendingListen pending) {
    _removePending(pending);
    _pendingListens.add(pending);
    _pendingListens.sort(
      (first, second) => first.startedAt.compareTo(second.startedAt),
    );
    if (_pendingListens.length > _maximumPendingListens) {
      _pendingListens.removeRange(
        0,
        _pendingListens.length - _maximumPendingListens,
      );
    }
  }

  void _removePending(_PendingListen pending) {
    _pendingListens.removeWhere(
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
    if (title == null || artist == null || startedAt == null || durationMs < 0) {
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
