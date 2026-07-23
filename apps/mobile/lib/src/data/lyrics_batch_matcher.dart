import '../domain/lyrics_provider.dart';
import '../domain/track.dart';

/// Searches a bounded set of tracks and selects only unambiguous lyric matches.
///
/// Applying a result remains the caller's responsibility so user-owned lyrics
/// can be protected at the persistence boundary.
final class LyricsBatchMatcher {
  LyricsBatchMatcher(this.provider);

  static const maxTracksPerBatch = 25;

  final LyricsProvider provider;

  Future<LyricsBatchMatchReport> match(Iterable<Track> tracks) async {
    final candidates = <Track>[];
    final seenTrackIds = <String>{};
    var wasLimited = false;
    for (final track in tracks) {
      if (!seenTrackIds.add(track.id)) {
        continue;
      }
      if (candidates.length == maxTracksPerBatch) {
        wasLimited = true;
        break;
      }
      candidates.add(track);
    }

    final outcomes = <LyricsBatchMatchOutcome>[];
    for (final track in candidates) {
      if (!_hasKnownArtist(track.artist)) {
        outcomes.add(LyricsBatchMatchOutcome.noMatch(track));
        continue;
      }
      try {
        final results = await provider.search(
          LyricsSearchQuery(
            trackName: track.title,
            artistName: track.artist,
            albumName: track.album,
            duration: track.duration,
          ),
        );
        outcomes.add(
          LyricsBatchMatchOutcome(
            track: track,
            result: _singleExactMatch(track, results),
          ),
        );
      } on Object catch (error) {
        outcomes.add(LyricsBatchMatchOutcome.failed(track, error));
      }
    }
    return LyricsBatchMatchReport(
      outcomes: List.unmodifiable(outcomes),
      wasLimited: wasLimited,
    );
  }

  static LyricsSearchResult? _singleExactMatch(
    Track track,
    Iterable<LyricsSearchResult> results,
  ) {
    final matches = <LyricsSearchResult>[];
    final seenExternalIds = <String>{};
    for (final result in results) {
      if (!result.isSelectable ||
          !_sameMetadata(track.title, result.trackName) ||
          !_sameMetadata(track.artist, result.artistName) ||
          !_hasCompatibleDuration(track.duration, result.duration) ||
          !seenExternalIds.add('${result.providerId}\u0000${result.externalId}')) {
        continue;
      }
      matches.add(result);
    }
    return matches.length == 1 ? matches.single : null;
  }
}

final class LyricsBatchMatchReport {
  const LyricsBatchMatchReport({
    required this.outcomes,
    required this.wasLimited,
  });

  final List<LyricsBatchMatchOutcome> outcomes;
  final bool wasLimited;

  Iterable<LyricsBatchMatchOutcome> get matches =>
      outcomes.where((outcome) => outcome.result != null);

  int get unmatchedCount =>
      outcomes.where((outcome) => outcome.result == null && outcome.error == null).length;

  int get failedCount => outcomes.where((outcome) => outcome.error != null).length;
}

final class LyricsBatchMatchOutcome {
  const LyricsBatchMatchOutcome({
    required this.track,
    this.result,
    this.error,
  });

  const LyricsBatchMatchOutcome.noMatch(Track track) : this(track: track);

  const LyricsBatchMatchOutcome.failed(Track track, Object error)
    : this(track: track, error: error);

  final Track track;
  final LyricsSearchResult? result;
  final Object? error;
}

bool _hasKnownArtist(String value) {
  final normalized = value.trim();
  return normalized.isNotEmpty && normalized.toLowerCase() != 'unknown artist';
}

bool _hasCompatibleDuration(Duration trackDuration, Duration resultDuration) {
  if (trackDuration <= Duration.zero || resultDuration <= Duration.zero) {
    return true;
  }
  return (trackDuration - resultDuration).abs() <= const Duration(seconds: 3);
}

bool _sameMetadata(String left, String right) {
  final leftTrimmed = left.trim();
  final rightTrimmed = right.trim();
  if (leftTrimmed.isEmpty || rightTrimmed.isEmpty) {
    return false;
  }
  if (leftTrimmed.toLowerCase() == rightTrimmed.toLowerCase()) {
    return true;
  }
  final leftCompact = leftTrimmed
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final rightCompact = rightTrimmed
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  return leftCompact.isNotEmpty && leftCompact == rightCompact;
}
