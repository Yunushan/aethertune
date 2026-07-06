import 'track.dart';

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
