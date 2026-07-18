import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class PodcastChapterHostApproval {
  const PodcastChapterHostApproval({
    required this.subscriptionId,
    required this.host,
    required this.approvedAt,
  });

  final String subscriptionId;
  final String host;
  final DateTime approvedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'subscriptionId': subscriptionId,
    'host': host,
    'approvedAt': approvedAt.toUtc().toIso8601String(),
  };

  static PodcastChapterHostApproval? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final subscriptionId = value['subscriptionId'];
    final rawHost = value['host'];
    final rawApprovedAt = value['approvedAt'];
    final host = normalizePodcastChapterHost(rawHost is String ? rawHost : '');
    final approvedAt = DateTime.tryParse(
      rawApprovedAt is String ? rawApprovedAt : '',
    );
    if (subscriptionId is! String ||
        subscriptionId.trim().isEmpty ||
        subscriptionId.length > 256 ||
        host == null ||
        approvedAt == null) {
      return null;
    }
    return PodcastChapterHostApproval(
      subscriptionId: subscriptionId,
      host: host,
      approvedAt: approvedAt.toUtc(),
    );
  }
}

/// Stores the user's explicit consent for third-party Podcasting 2.0 chapter
/// document hosts. Feed-origin chapter documents do not need an entry here.
final class PodcastChapterHostPolicy extends ChangeNotifier {
  static const _storageKey = 'aethertune.podcast_chapter_hosts.v2';
  static const _legacyStorageKey = 'aethertune.podcast_chapter_hosts.v1';
  static const _maximumHosts = 32;
  static const _maximumHistoryRecords = 64;
  static const _maximumHistoryRecordsPerSubscription = 8;

  PodcastChapterHostPolicy({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Set<String> _approvedHosts = <String>{};
  final List<PodcastChapterHostApproval> _approvalHistory =
      <PodcastChapterHostApproval>[];
  bool _loaded = false;
  String? _loadError;

  bool get loaded => _loaded;
  String? get loadError => _loadError;
  List<String> get approvedHosts {
    final hosts = _approvedHosts.toList()..sort();
    return List<String>.unmodifiable(hosts);
  }

  List<PodcastChapterHostApproval> approvalHistoryForSubscription(
    String subscriptionId,
  ) {
    if (subscriptionId.trim().isEmpty) {
      return const <PodcastChapterHostApproval>[];
    }
    final history = _approvalHistory
        .where((entry) => entry.subscriptionId == subscriptionId)
        .toList()
      ..sort((left, right) => right.approvedAt.compareTo(left.approvedAt));
    return List<PodcastChapterHostApproval>.unmodifiable(history);
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
      final saved = _readSavedPolicy(prefs);
      _approvedHosts
        ..clear()
        ..addAll(
          saved.hosts
              .map(normalizePodcastChapterHost)
              .whereType<String>()
              .take(_maximumHosts),
        );
      _approvalHistory
        ..clear()
        ..addAll(_normalizeHistory(saved.history));
      _loadError = null;
    } on Object catch (error) {
      _loadError = error.toString();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> approveHost(String value) async {
    await _approveHost(value);
  }

  Future<void> approveHostForSubscription(
    String subscriptionId,
    String value,
  ) async {
    final normalizedSubscriptionId = subscriptionId.trim();
    if (normalizedSubscriptionId.isEmpty || normalizedSubscriptionId.length > 256) {
      throw const FormatException('Podcast subscription is invalid.');
    }
    await _approveHost(value, subscriptionId: normalizedSubscriptionId);
  }

  Future<void> _approveHost(String value, {String? subscriptionId}) async {
    final host = normalizePodcastChapterHost(value);
    if (host == null) {
      throw const FormatException('Enter a valid HTTPS chapter hostname.');
    }
    final wasApproved = _approvedHosts.contains(host);
    if (!wasApproved && _approvedHosts.length >= _maximumHosts) {
      throw const FormatException('Only 32 chapter hosts can be approved.');
    }
    final previousHistory = List<PodcastChapterHostApproval>.from(_approvalHistory);
    if (!wasApproved) {
      _approvedHosts.add(host);
    }
    if (subscriptionId != null) {
      _setApprovalHistory(subscriptionId, host);
    }
    if (wasApproved && subscriptionId == null) {
      return;
    }
    try {
      await _save();
    } on Object {
      if (!wasApproved) {
        _approvedHosts.remove(host);
      }
      _approvalHistory
        ..clear()
        ..addAll(previousHistory);
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
    final saved = await prefs.setString(
      _storageKey,
      jsonEncode(<String, Object?>{
        'approvedHosts': approvedHosts,
        'approvalHistory': _approvalHistory
            .map((entry) => entry.toJson())
            .toList(growable: false),
      }),
    );
    if (!saved) {
      throw StateError('Could not save approved podcast chapter hosts.');
    }
  }

  void _setApprovalHistory(String subscriptionId, String host) {
    final updated = <PodcastChapterHostApproval>[
      PodcastChapterHostApproval(
        subscriptionId: subscriptionId,
        host: host,
        approvedAt: _clock().toUtc(),
      ),
      ..._approvalHistory.where(
        (entry) =>
            entry.subscriptionId != subscriptionId || entry.host != host,
      ),
    ];
    _approvalHistory
      ..clear()
      ..addAll(_normalizeHistory(updated));
  }

  List<PodcastChapterHostApproval> _normalizeHistory(
    Iterable<PodcastChapterHostApproval> entries,
  ) {
    final ordered = entries.toList()
      ..sort((left, right) => right.approvedAt.compareTo(left.approvedAt));
    final keptPerSubscription = <String, int>{};
    final seen = <String>{};
    final normalized = <PodcastChapterHostApproval>[];
    for (final entry in ordered) {
      final key = '${entry.subscriptionId}\u0000${entry.host}';
      final count = keptPerSubscription[entry.subscriptionId] ?? 0;
      if (!seen.add(key) || count >= _maximumHistoryRecordsPerSubscription) {
        continue;
      }
      normalized.add(entry);
      keptPerSubscription[entry.subscriptionId] = count + 1;
      if (normalized.length == _maximumHistoryRecords) {
        break;
      }
    }
    return normalized;
  }

  _SavedPodcastChapterHostPolicy _readSavedPolicy(SharedPreferences prefs) {
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          final hosts = decoded['approvedHosts'];
          final history = decoded['approvalHistory'];
          return _SavedPodcastChapterHostPolicy(
            hosts: hosts is List ? hosts.whereType<String>() : const <String>[],
            history: history is List
                ? history
                    .map(PodcastChapterHostApproval.tryFromJson)
                    .whereType<PodcastChapterHostApproval>()
                : const <PodcastChapterHostApproval>[],
          );
        }
      } on FormatException {
        // Fall back to the old host-only preference on malformed local data.
      }
    }
    return _SavedPodcastChapterHostPolicy(
      hosts: prefs.getStringList(_legacyStorageKey) ?? const <String>[],
      history: const <PodcastChapterHostApproval>[],
    );
  }
}

final class _SavedPodcastChapterHostPolicy {
  const _SavedPodcastChapterHostPolicy({
    required this.hosts,
    required this.history,
  });

  final Iterable<String> hosts;
  final Iterable<PodcastChapterHostApproval> history;
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
