import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/track.dart';

const jamendoChartCacheLifetime = Duration(hours: 24);

final class JamendoCachedChart {
  const JamendoCachedChart({required this.tracks, required this.savedAt});

  final List<Track> tracks;
  final DateTime savedAt;

  bool isExpired(DateTime now) => now.difference(savedAt) > jamendoChartCacheLifetime;
}

abstract interface class JamendoChartCache {
  Future<JamendoCachedChart?> read(String key);
  Future<void> write(String key, List<Track> tracks);
  Future<void> clear();
}

final class SharedPreferencesJamendoChartCache implements JamendoChartCache {
  static const _prefix = 'aethertune.jamendo.chart.v1.';
  static const _maximumTracks = 6;

  SharedPreferencesJamendoChartCache({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  @override
  Future<JamendoCachedChart?> read(String key) async {
    final raw = (await SharedPreferences.getInstance()).getString('$_prefix$key');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<dynamic, dynamic>) {
        return null;
      }
      final savedAtMilliseconds = decoded['savedAtMilliseconds'];
      final rawTracks = decoded['tracks'];
      if (savedAtMilliseconds is! num ||
          !savedAtMilliseconds.isFinite ||
          rawTracks is! List<dynamic> ||
          rawTracks.isEmpty ||
          rawTracks.length > _maximumTracks) {
        return null;
      }
      final tracks = <Track>[];
      for (final rawTrack in rawTracks.whereType<Map<dynamic, dynamic>>()) {
        final track = Track.fromJson(rawTrack.cast<String, Object?>());
        if (_isSafeCachedTrack(track)) {
          tracks.add(track);
        }
      }
      if (tracks.isEmpty) {
        return null;
      }
      return JamendoCachedChart(
        tracks: List<Track>.unmodifiable(tracks),
        savedAt: DateTime.fromMillisecondsSinceEpoch(
          savedAtMilliseconds.round(),
          isUtc: true,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(String key, List<Track> tracks) async {
    final safeTracks = tracks
        .where(_isCacheableTrack)
        .take(_maximumTracks)
        .map(_safeTrackJson)
        .toList(growable: false);
    if (safeTracks.isEmpty) {
      return;
    }
    await (await SharedPreferences.getInstance()).setString(
      '$_prefix$key',
      jsonEncode(<String, Object?>{
        'savedAtMilliseconds': _clock().millisecondsSinceEpoch,
        'tracks': safeTracks,
      }),
    );
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

String jamendoChartCacheKey({String? genre, String? lyricsLanguageCode}) {
  final normalizedGenre = genre?.trim().toLowerCase() ?? '';
  final normalizedLanguage = lyricsLanguageCode?.trim().toLowerCase() ?? '';
  return '${normalizedGenre.isEmpty ? 'popular' : normalizedGenre}.'
      '${normalizedLanguage.isEmpty ? 'all' : normalizedLanguage}';
}

bool _isSafeCachedTrack(Track track) {
  return track.streamUrl == null && _isCacheableTrack(track);
}

bool _isCacheableTrack(Track track) {
  if (track.sourceId != 'jamendo' ||
      !RegExp(r'^jamendo:\d+$').hasMatch(track.id) ||
      !RegExp(r'^\d+$').hasMatch(track.externalId ?? '') ||
      track.localPath != null ||
      track.duration.isNegative ||
      track.duration.inMicroseconds > const Duration(hours: 12).inMicroseconds) {
    return false;
  }
  return _isSafeArtworkUri(track.artworkUri) &&
      _isSafeArtworkUri(track.artworkSourceUri);
}

bool _isSafeArtworkUri(Uri? uri) {
  return uri == null ||
      (uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty);
}

Map<String, Object?> _safeTrackJson(Track track) {
  return <String, Object?>{
    'id': track.id,
    'title': track.title,
    'artist': track.artist,
    'album': track.album,
    if (track.albumArtist != null) 'albumArtist': track.albumArtist,
    if (track.year != null) 'year': track.year,
    if (track.trackNumber != null) 'trackNumber': track.trackNumber,
    'genre': track.genre,
    'durationMs': track.duration.inMilliseconds,
    'artworkUri': track.artworkUri?.toString(),
    'artworkSourceUri': track.artworkSourceUri?.toString(),
    'sourceId': track.sourceId,
    'externalId': track.externalId,
    'addedAt': track.addedAt.toIso8601String(),
  };
}
