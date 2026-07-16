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

/// A durable local queue slot. Only the active slot is loaded into the audio
/// engine; the remaining slots are inert snapshots until the user switches.
class SavedTrackQueue {
  const SavedTrackQueue({
    required this.id,
    required this.name,
    required this.snapshot,
  });

  final String id;
  final String name;
  final TrackQueueSnapshot snapshot;

  SavedTrackQueue copyWith({
    String? name,
    TrackQueueSnapshot? snapshot,
  }) {
    return SavedTrackQueue(
      id: id,
      name: name ?? this.name,
      snapshot: snapshot ?? this.snapshot,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'snapshot': snapshot.toJson(),
    };
  }

  factory SavedTrackQueue.fromJson(Map<String, Object?> json) {
    final id = (json['id'] as String? ?? '').trim();
    final name = (json['name'] as String? ?? '').trim();
    final rawSnapshot = json['snapshot'];
    if (id.isEmpty || id.length > 128 || name.isEmpty || name.length > 80) {
      throw const FormatException('Saved queue metadata is invalid.');
    }
    if (rawSnapshot is! Map) {
      throw const FormatException('Saved queue snapshot is missing.');
    }
    return SavedTrackQueue(
      id: id,
      name: name,
      snapshot: TrackQueueSnapshot.fromJson(
        Map<String, Object?>.from(rawSnapshot),
      ),
    );
  }
}

/// Versioned local persistence for a bounded set of independently resumable
/// queues. This stays device-local and is deliberately excluded from sync.
class SavedTrackQueueCollection {
  const SavedTrackQueueCollection({
    required this.activeQueueId,
    required this.queues,
  });

  static const version = 1;
  static const maxQueues = 12;

  final String activeQueueId;
  final List<SavedTrackQueue> queues;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'activeQueueId': activeQueueId,
      'queues': queues.map((queue) => queue.toJson()).toList(growable: false),
    };
  }

  factory SavedTrackQueueCollection.fromJson(Map<String, Object?> json) {
    if (json['version'] != version) {
      throw FormatException(
        'Unsupported saved queue collection version: ${json['version']}.',
      );
    }
    final activeQueueId = (json['activeQueueId'] as String? ?? '').trim();
    final rawQueues = json['queues'];
    if (activeQueueId.isEmpty || rawQueues is! List) {
      throw const FormatException('Saved queue collection is malformed.');
    }

    final queues = <SavedTrackQueue>[];
    final ids = <String>{};
    for (final rawQueue in rawQueues) {
      if (rawQueue is! Map) {
        continue;
      }
      final queue = SavedTrackQueue.fromJson(
        Map<String, Object?>.from(rawQueue),
      );
      if (!ids.add(queue.id)) {
        throw const FormatException('Saved queue IDs must be unique.');
      }
      queues.add(queue);
      if (queues.length == maxQueues) {
        break;
      }
    }
    if (queues.isEmpty || !ids.contains(activeQueueId)) {
      throw const FormatException('Saved queue collection has no active queue.');
    }
    return SavedTrackQueueCollection(
      activeQueueId: activeQueueId,
      queues: List<SavedTrackQueue>.unmodifiable(queues),
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
