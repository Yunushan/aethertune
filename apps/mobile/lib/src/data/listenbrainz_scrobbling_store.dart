import 'package:flutter/foundation.dart';

import '../domain/track.dart';
import 'listenbrainz_client.dart';
import 'provider_credential_vault.dart';

typedef ListenBrainzClientFactory = ListenBrainzClient Function(String token);

/// Stores only the user token in the credential vault and submits completed,
/// user-opted-in listens. Tokens never enter preferences, backups, or logs.
final class ListenBrainzScrobblingStore extends ChangeNotifier {
  ListenBrainzScrobblingStore({
    ProviderCredentialVault? credentialVault,
    ListenBrainzClientFactory? clientFactory,
  }) : _credentialVault = credentialVault ?? SecureProviderCredentialVault(),
       _clientFactory = clientFactory ?? ((token) => ListenBrainzClient(token: token));

  static const _credentialId = 'listenbrainz-user-token';
  static const maximumListenDuration = Duration(minutes: 4);

  final ProviderCredentialVault _credentialVault;
  final ListenBrainzClientFactory _clientFactory;
  final Set<String> _submittedListenKeys = <String>{};

  String? _token;
  String? _userName;
  String? _lastError;
  bool _loaded = false;
  bool _submitting = false;

  bool get loaded => _loaded;
  bool get isConfigured => (_token ?? '').isNotEmpty;
  String? get userName => _userName;
  String? get lastError => _lastError;
  bool get submitting => _submitting;

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
    notifyListeners();
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
    final key = '${track.id}:${startedAt.toUtc().millisecondsSinceEpoch}';
    if (!_submittedListenKeys.add(key)) {
      return;
    }

    _submitting = true;
    notifyListeners();
    try {
      await _clientFactory(token).submitListen(track: track, startedAt: startedAt);
      _lastError = null;
    } on Object {
      _submittedListenKeys.remove(key);
      _lastError = 'Could not submit the completed ListenBrainz listen.';
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
}
