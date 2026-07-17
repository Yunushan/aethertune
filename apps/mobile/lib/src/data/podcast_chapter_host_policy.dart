import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's explicit consent for third-party Podcasting 2.0 chapter
/// document hosts. Feed-origin chapter documents do not need an entry here.
final class PodcastChapterHostPolicy extends ChangeNotifier {
  static const _storageKey = 'aethertune.podcast_chapter_hosts.v1';
  static const _maximumHosts = 32;

  final Set<String> _approvedHosts = <String>{};
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  List<String> get approvedHosts {
    final hosts = _approvedHosts.toList()..sort();
    return List<String>.unmodifiable(hosts);
  }

  bool allows(Uri uri) {
    final host = _normalizedHostFromUri(uri);
    return host != null && _approvedHosts.contains(host);
  }

  Future<void> load() async {
    if (_loaded) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_storageKey) ?? const <String>[];
      _approvedHosts
        ..clear()
        ..addAll(
          saved
              .map(normalizePodcastChapterHost)
              .whereType<String>()
              .take(_maximumHosts),
        );
      _loadError = null;
    } on Object catch (error) {
      _loadError = error.toString();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> approveHost(String value) async {
    final host = normalizePodcastChapterHost(value);
    if (host == null) {
      throw const FormatException('Enter a valid HTTPS chapter hostname.');
    }
    if (_approvedHosts.contains(host)) {
      return;
    }
    if (_approvedHosts.length >= _maximumHosts) {
      throw const FormatException('Only 32 chapter hosts can be approved.');
    }
    _approvedHosts.add(host);
    try {
      await _save();
    } on Object {
      _approvedHosts.remove(host);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> revokeHost(String value) async {
    final host = normalizePodcastChapterHost(value);
    if (host == null || !_approvedHosts.remove(host)) {
      return;
    }
    try {
      await _save();
    } on Object {
      _approvedHosts.add(host);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setStringList(_storageKey, approvedHosts);
    if (!saved) {
      throw StateError('Could not save approved podcast chapter hosts.');
    }
  }
}

String? normalizePodcastChapterHost(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty ||
      normalized.contains('/') ||
      normalized.contains('@') ||
      normalized.contains('?') ||
      normalized.contains('#') ||
      normalized.contains(':')) {
    return null;
  }
  final uri = Uri.tryParse('https://$normalized');
  if (uri == null || uri.host.isEmpty || uri.host != normalized) {
    return null;
  }
  return uri.host;
}

String? _normalizedHostFromUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https' || uri.host.isEmpty) {
    return null;
  }
  return uri.host.toLowerCase();
}
