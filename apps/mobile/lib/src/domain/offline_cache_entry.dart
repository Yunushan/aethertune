import 'music_source_provider.dart';
import 'track.dart';

enum OfflineCacheEntryStatus { queued, paused, processing, cached, failed }

extension OfflineCacheEntryStatusLabel on OfflineCacheEntryStatus {
  String get label {
    switch (this) {
      case OfflineCacheEntryStatus.queued:
        return 'Queued';
      case OfflineCacheEntryStatus.paused:
        return 'Paused';
      case OfflineCacheEntryStatus.processing:
        return 'Processing';
      case OfflineCacheEntryStatus.cached:
        return 'Cached';
      case OfflineCacheEntryStatus.failed:
        return 'Failed';
    }
  }
}

final class OfflineCacheEntry {
  OfflineCacheEntry({
    required this.id,
    required this.track,
    required this.action,
    this.status = OfflineCacheEntryStatus.queued,
    required this.createdAt,
    DateTime? updatedAt,
    this.reason = '',
    this.cachedByteCount = 0,
    this.cachedMediaChecksum = '',
  }) : updatedAt = updatedAt ?? createdAt;

  final String id;
  final Track track;
  final OfflineMediaAction action;
  final OfflineCacheEntryStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String reason;
  final int cachedByteCount;
  final String cachedMediaChecksum;

  OfflineCacheEntry copyWith({
    Track? track,
    OfflineMediaAction? action,
    OfflineCacheEntryStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? reason,
    int? cachedByteCount,
    String? cachedMediaChecksum,
  }) {
    return OfflineCacheEntry(
      id: id,
      track: track ?? this.track,
      action: action ?? this.action,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reason: reason ?? this.reason,
      cachedByteCount: cachedByteCount ?? this.cachedByteCount,
      cachedMediaChecksum: cachedMediaChecksum ?? this.cachedMediaChecksum,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'track': track.toJson(),
      'action': action.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'reason': reason,
      'cachedByteCount': cachedByteCount,
      'cachedMediaChecksum': cachedMediaChecksum,
    };
  }

  factory OfflineCacheEntry.fromJson(Map<String, Object?> json) {
    final rawTrack = json['track'];
    if (rawTrack is! Map) {
      throw const FormatException('Offline cache entry track must be an object.');
    }

    return OfflineCacheEntry(
      id: _jsonString(json, 'id'),
      track: Track.fromJson(Map<String, Object?>.from(rawTrack)),
      action: _offlineMediaActionFromName(_jsonString(json, 'action')),
      status: _offlineCacheEntryStatusFromName(
        json['status'] as String? ?? OfflineCacheEntryStatus.queued.name,
      ),
      createdAt: _jsonDateTime(json, 'createdAt'),
      updatedAt: _jsonDateTime(json, 'updatedAt'),
      reason: json['reason'] as String? ?? '',
      cachedByteCount: _jsonInt(json, 'cachedByteCount'),
      cachedMediaChecksum: json['cachedMediaChecksum'] as String? ?? '',
    );
  }

  static String stableIdFor(Track track, OfflineMediaAction action) {
    final providerLocator = track.externalId ??
        track.streamUrl ??
        track.localPath ??
        '${track.artist}|${track.album}|${track.title}|${track.duration}';
    return Track.stableLocalId(
      '${action.name}|${track.sourceId}|$providerLocator',
    );
  }
}

String _jsonString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Offline cache entry "$key" must be a string.');
  }

  return value;
}

DateTime _jsonDateTime(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(json[key] as String? ?? '');
  if (value == null) {
    throw FormatException('Offline cache entry "$key" must be a date.');
  }

  return value;
}

int _jsonInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return 0;
  }
  if (value is int) {
    return value < 0 ? 0 : value;
  }

  return 0;
}

OfflineMediaAction _offlineMediaActionFromName(String value) {
  for (final action in OfflineMediaAction.values) {
    if (action.name == value) {
      return action;
    }
  }

  throw FormatException('Unknown offline media action: $value.');
}

OfflineCacheEntryStatus _offlineCacheEntryStatusFromName(String value) {
  for (final status in OfflineCacheEntryStatus.values) {
    if (status.name == value) {
      return status;
    }
  }

  throw FormatException('Unknown offline cache status: $value.');
}
