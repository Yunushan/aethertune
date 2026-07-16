import 'track.dart';

class TrackQueueSnapshot {
  const TrackQueueSnapshot({
    required this.tracks,
    this.currentTrackId,
    this.updatedAt,
  });

  final List<Track> tracks;
  final String? currentTrackId;
  final DateTime? updatedAt;

  Track? get currentTrack {
    for (final track in tracks) {
      if (track.id == currentTrackId) {
        return track;
      }
    }

    return tracks.isEmpty ? null : tracks.first;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'currentTrackId': currentTrackId,
      'updatedAt': updatedAt?.toIso8601String(),
      'tracks': tracks.map((track) => track.toJson()).toList(),
    };
  }

  factory TrackQueueSnapshot.fromJson(Map<String, Object?> json) {
    final decodedTracks = json['tracks'] as List<dynamic>? ?? const <dynamic>[];

    return TrackQueueSnapshot(
      currentTrackId: json['currentTrackId'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      tracks: decodedTracks
          .whereType<Map>()
          .map((item) => Track.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false),
    );
  }
}

/// A privacy-safe queue representation for an opt-in library sync snapshot.
///
/// It deliberately contains only library track IDs: local paths, stream URLs,
/// artwork, provider credentials, and playback position stay on each device.
class TrackQueueReferenceSnapshot {
  const TrackQueueReferenceSnapshot({
    required this.trackIds,
    required this.updatedAt,
    this.currentTrackId,
  });

  static const syncVersion = 1;
  static const maxTrackIds = 500;

  final List<String> trackIds;
  final String? currentTrackId;
  final DateTime updatedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': syncVersion,
      'trackIds': trackIds,
      'currentTrackId': currentTrackId,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory TrackQueueReferenceSnapshot.fromJson(Map<String, Object?> json) {
    final version = json['version'] as int? ?? syncVersion;
    if (version != syncVersion) {
      throw FormatException('Unsupported queue sync version: $version.');
    }
    final rawTrackIds = json['trackIds'];
    if (rawTrackIds is! List) {
      throw const FormatException('Queue sync track IDs must be a list.');
    }

    final trackIds = <String>[];
    for (final value in rawTrackIds) {
      if (value is! String) {
        continue;
      }
      final id = value.trim();
      if (id.isEmpty || id.length > 1024) {
        continue;
      }
      trackIds.add(id);
      if (trackIds.length == maxTrackIds) {
        break;
      }
    }
    final currentTrackId = json['currentTrackId'] as String?;
    final normalizedCurrentTrackId = currentTrackId?.trim();
    final updatedAt = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    if (updatedAt == null) {
      throw const FormatException('Queue sync update time is missing.');
    }

    return TrackQueueReferenceSnapshot(
      trackIds: List<String>.unmodifiable(trackIds),
      currentTrackId: normalizedCurrentTrackId == null ||
              normalizedCurrentTrackId.isEmpty ||
              !trackIds.contains(normalizedCurrentTrackId)
          ? null
          : normalizedCurrentTrackId,
      updatedAt: updatedAt.toUtc(),
    );
  }
}

List<T> moveQueueItem<T>(List<T> items, int fromIndex, int toIndex) {
  if (fromIndex < 0 ||
      fromIndex >= items.length ||
      toIndex < 0 ||
      toIndex >= items.length ||
      fromIndex == toIndex) {
    return items.toList(growable: false);
  }

  final reordered = items.toList(growable: true);
  final item = reordered.removeAt(fromIndex);
  reordered.insert(toIndex, item);

  return reordered.toList(growable: false);
}

List<Track> removeTrackFromQueueItems(List<Track> queue, String trackId) {
  return queue
      .where((track) => track.id != trackId)
      .toList(growable: false);
}
