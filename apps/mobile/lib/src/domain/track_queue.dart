import 'track.dart';

class TrackQueueSnapshot {
  const TrackQueueSnapshot({
    required this.tracks,
    this.currentTrackId,
  });

  final List<Track> tracks;
  final String? currentTrackId;

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
      'tracks': tracks.map((track) => track.toJson()).toList(),
    };
  }

  factory TrackQueueSnapshot.fromJson(Map<String, Object?> json) {
    final decodedTracks = json['tracks'] as List<dynamic>? ?? const <dynamic>[];

    return TrackQueueSnapshot(
      currentTrackId: json['currentTrackId'] as String?,
      tracks: decodedTracks
          .whereType<Map>()
          .map((item) => Track.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false),
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
