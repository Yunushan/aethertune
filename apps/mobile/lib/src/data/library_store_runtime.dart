part of 'library_store.dart';

class _MutableBrowseGroup {
  _MutableBrowseGroup({
    required this.type,
    required this.key,
    required this.label,
  });

  final LibraryBrowseType type;
  final String key;
  final String label;
  int trackCount = 0;
  Duration totalDuration = Duration.zero;

  void add(Track track) {
    trackCount += 1;
    totalDuration += track.duration;
  }

  LibraryBrowseGroup toBrowseGroup() {
    return LibraryBrowseGroup(
      type: type,
      key: key,
      label: label,
      trackCount: trackCount,
      totalDuration: totalDuration,
    );
  }
}

class _MutableFolderNode {
  _MutableFolderNode({
    required this.key,
    required this.parentKey,
    required this.path,
    required this.label,
    required this.depth,
  });

  final String key;
  final String? parentKey;
  final String path;
  final String label;
  final int depth;
  final Set<String> trackIds = <String>{};
  final Set<String> directTrackIds = <String>{};
  final Set<String> childKeys = <String>{};
  Duration totalDuration = Duration.zero;

  void addChild(String key) {
    childKeys.add(key);
  }

  void addTrack(Track track, {required bool direct}) {
    if (trackIds.add(track.id)) {
      totalDuration += track.duration;
    }
    if (direct) {
      directTrackIds.add(track.id);
    }
  }

  LibraryFolderNode toFolderNode() {
    return LibraryFolderNode(
      key: key,
      parentKey: parentKey,
      path: path,
      label: label,
      depth: depth,
      trackCount: trackIds.length,
      directTrackCount: directTrackIds.length,
      totalDuration: totalDuration,
      childCount: childKeys.length,
    );
  }
}

class _MutableDuplicateTrackGroup {
  _MutableDuplicateTrackGroup({required this.key, required this.type});

  final String key;
  final DuplicateMatchType type;
  final List<Track> tracks = <Track>[];

  void add(Track track) {
    if (tracks.any((existing) => existing.id == track.id)) {
      return;
    }

    tracks.add(track);
  }

  DuplicateTrackGroup toDuplicateTrackGroup() {
    tracks.sort((a, b) => b.addedAt.compareTo(a.addedAt));

    return DuplicateTrackGroup(
      key: key,
      type: type,
      tracks: List.unmodifiable(tracks),
    );
  }
}

class _MutableLibraryStatsGroup {
  _MutableLibraryStatsGroup({required this.label});

  final String label;
  final Set<String> trackIds = <String>{};
  int playCount = 0;
  Duration estimatedListeningDuration = Duration.zero;
  DateTime? lastPlayedAt;

  void add(Track track, DateTime playedAt) {
    trackIds.add(track.id);
    playCount += 1;
    estimatedListeningDuration += track.duration;
    final currentLastPlayed = lastPlayedAt;
    if (currentLastPlayed == null || playedAt.isAfter(currentLastPlayed)) {
      lastPlayedAt = playedAt;
    }
  }

  LibraryStatsGroup toLibraryStatsGroup() {
    return LibraryStatsGroup(
      label: label,
      playCount: playCount,
      trackCount: trackIds.length,
      estimatedListeningDuration: estimatedListeningDuration,
      lastPlayedAt: lastPlayedAt,
    );
  }
}
