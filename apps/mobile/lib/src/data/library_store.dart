import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playback_history_entry.dart';
import '../domain/playlist.dart';
import '../domain/track.dart';
import '../domain/track_lyrics.dart';

enum LibrarySortMode { recentlyAdded, title, artist, album }

class LibraryStore extends ChangeNotifier {
  LibraryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _backupVersion = 1;
  static const _tracksKey = 'aethertune.tracks.v1';
  static const _playlistsKey = 'aethertune.playlists.v1';
  static const _lyricsKey = 'aethertune.lyrics.v1';
  static const _historyKey = 'aethertune.playback_history.v1';
  static const _maxHistoryEntries = 500;

  final List<Track> _tracks = <Track>[];
  final List<Playlist> _playlists = <Playlist>[];
  final List<PlaybackHistoryEntry> _history = <PlaybackHistoryEntry>[];
  final Map<String, TrackLyrics> _lyricsByTrackId = <String, TrackLyrics>{};
  final DateTime Function() _clock;
  bool _loaded = false;

  bool get loaded => _loaded;
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<PlaybackHistoryEntry> get playbackHistory =>
      List.unmodifiable(_history);
  List<TrackLyrics> get lyrics => List.unmodifiable(_lyricsByTrackId.values);
  List<Track> get favorites =>
      _tracks.where((track) => track.isFavorite).toList(growable: false);

  Future<void> load() async {
    if (_loaded) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final rawTracks = prefs.getString(_tracksKey);
    if (rawTracks != null && rawTracks.isNotEmpty) {
      final decoded = jsonDecode(rawTracks) as List<dynamic>;
      _tracks
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((item) => Track.fromJson(Map<String, Object?>.from(item)))
              .toList(growable: false),
        );
    }

    final rawPlaylists = prefs.getString(_playlistsKey);
    if (rawPlaylists != null && rawPlaylists.isNotEmpty) {
      final decoded = jsonDecode(rawPlaylists) as List<dynamic>;
      _playlists
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map(
                (item) => Playlist.fromJson(Map<String, Object?>.from(item)),
              )
              .toList(growable: false),
        );
    }

    final rawLyrics = prefs.getString(_lyricsKey);
    if (rawLyrics != null && rawLyrics.isNotEmpty) {
      final decoded = jsonDecode(rawLyrics) as List<dynamic>;
      _lyricsByTrackId
        ..clear()
        ..addEntries(
          decoded
              .whereType<Map>()
              .map(
                (item) => TrackLyrics.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .where((lyrics) => !lyrics.isEmpty)
              .map(
                (lyrics) => MapEntry<String, TrackLyrics>(
                  lyrics.trackId,
                  lyrics,
                ),
              ),
        );
    }

    final rawHistory = prefs.getString(_historyKey);
    if (rawHistory != null && rawHistory.isNotEmpty) {
      final decoded = jsonDecode(rawHistory) as List<dynamic>;
      _history
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map(
                (item) => PlaybackHistoryEntry.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList(growable: false),
        );
    }

    _removeMissingPlaylistTracks();
    _removeMissingLyrics();
    _removeMissingHistory();
    _sortHistory();
    _loaded = true;
    notifyListeners();
  }

  Future<void> addTracks(List<Track> incoming) async {
    final knownIds = _tracks.map((track) => track.id).toSet();
    var changed = false;

    for (final track in incoming) {
      if (!knownIds.contains(track.id)) {
        _tracks.add(track);
        knownIds.add(track.id);
        changed = true;
      }
    }

    if (changed) {
      _sortTracks();
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeTrack(String id) async {
    _tracks.removeWhere((track) => track.id == id);
    _removeTrackFromPlaylists(id);
    _lyricsByTrackId.remove(id);
    _history.removeWhere((entry) => entry.trackId == id);
    await _save();
    notifyListeners();
  }

  Future<void> clear() async {
    _tracks.clear();
    _playlists.clear();
    _history.clear();
    _lyricsByTrackId.clear();
    await _save();
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    final index = _tracks.indexWhere((track) => track.id == id);
    if (index == -1) {
      return;
    }

    final current = _tracks[index];
    _tracks[index] = current.copyWith(isFavorite: !current.isFavorite);
    await _save();
    notifyListeners();
  }

  List<Track> search(
    String query, {
    bool favoritesOnly = false,
    LibrarySortMode sortMode = LibrarySortMode.recentlyAdded,
  }) {
    final normalized = query.trim().toLowerCase();
    final source = favoritesOnly ? favorites : tracks;

    final results = normalized.isEmpty
        ? source.toList(growable: false)
        : source.where((track) {
            return track.title.toLowerCase().contains(normalized) ||
                track.artist.toLowerCase().contains(normalized) ||
                track.album.toLowerCase().contains(normalized);
          }).toList(growable: false);

    return _sortTrackResults(results, sortMode);
  }

  String exportBackupJson() {
    const encoder = JsonEncoder.withIndent('  ');

    return encoder.convert(<String, Object?>{
      'version': _backupVersion,
      'exportedAt': _clock().toIso8601String(),
      'tracks': _tracks.map((track) => track.toJson()).toList(),
      'playlists': _playlists.map((playlist) => playlist.toJson()).toList(),
      'history': _history.map((entry) => entry.toJson()).toList(),
      'lyrics': _lyricsByTrackId.values
          .map((lyrics) => lyrics.toJson())
          .toList(),
    });
  }

  Future<void> restoreBackupJson(String backupJson) async {
    final decoded = jsonDecode(backupJson);
    if (decoded is! Map) {
      throw const FormatException('Backup must be a JSON object.');
    }

    final backup = Map<String, Object?>.from(decoded);
    if (backup['version'] != _backupVersion) {
      throw FormatException(
        'Unsupported backup version: ${backup['version']}.',
      );
    }

    final restoredTracks = <Track>[];
    final restoredPlaylists = <Playlist>[];
    final restoredHistory = <PlaybackHistoryEntry>[];
    final restoredLyrics = <TrackLyrics>[];

    try {
      restoredTracks.addAll(
        _jsonObjectList(backup, 'tracks').map(Track.fromJson),
      );
      restoredPlaylists.addAll(
        _jsonObjectList(backup, 'playlists').map(Playlist.fromJson),
      );
      restoredHistory.addAll(
        _jsonObjectList(backup, 'history', isRequired: false).map(
          PlaybackHistoryEntry.fromJson,
        ),
      );
      restoredLyrics.addAll(
        _jsonObjectList(backup, 'lyrics').map(TrackLyrics.fromJson),
      );
    } on Object catch (error) {
      throw FormatException('Invalid backup data: $error');
    }

    final uniqueTracks = <String, Track>{
      for (final track in restoredTracks) track.id: track,
    };
    final knownTrackIds = uniqueTracks.keys.toSet();
    final sanitizedPlaylists = restoredPlaylists.map((playlist) {
      final filteredTrackIds = playlist.trackIds
          .where(knownTrackIds.contains)
          .toSet()
          .toList(growable: false);

      return playlist.copyWith(trackIds: filteredTrackIds);
    }).toList(growable: false);
    final sanitizedLyrics = <String, TrackLyrics>{
      for (final lyrics in restoredLyrics)
        if (knownTrackIds.contains(lyrics.trackId) && !lyrics.isEmpty)
          lyrics.trackId: lyrics,
    };
    final sanitizedHistory = restoredHistory
        .where((entry) => knownTrackIds.contains(entry.trackId))
        .toList(growable: false);

    _tracks
      ..clear()
      ..addAll(uniqueTracks.values);
    _playlists
      ..clear()
      ..addAll(sanitizedPlaylists);
    _history
      ..clear()
      ..addAll(sanitizedHistory);
    _lyricsByTrackId
      ..clear()
      ..addAll(sanitizedLyrics);

    _sortTracks();
    _sortPlaylists();
    _sortHistory();
    _trimHistory();
    await _save();
    notifyListeners();
  }

  Playlist? playlistById(String id) {
    final index = _playlists.indexWhere((playlist) => playlist.id == id);
    if (index == -1) {
      return null;
    }

    return _playlists[index];
  }

  List<Track> tracksForPlaylist(String playlistId) {
    final playlist = playlistById(playlistId);
    if (playlist == null) {
      return <Track>[];
    }

    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };

    return playlist.trackIds
        .map((trackId) => byId[trackId])
        .whereType<Track>()
        .toList(growable: false);
  }

  List<Track> recentlyPlayedTracks({int limit = 25}) {
    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };
    final seen = <String>{};
    final recentTracks = <Track>[];

    for (final entry in _history) {
      if (seen.contains(entry.trackId)) {
        continue;
      }

      final track = byId[entry.trackId];
      if (track == null) {
        continue;
      }

      seen.add(entry.trackId);
      recentTracks.add(track);
      if (recentTracks.length >= limit) {
        break;
      }
    }

    return recentTracks;
  }

  List<Track> recentlyAddedTracks({int limit = 25}) {
    if (limit <= 0) {
      return <Track>[];
    }

    return tracks.take(limit).toList(growable: false);
  }

  int playCountForTrack(String trackId) {
    return _history.where((entry) => entry.trackId == trackId).length;
  }

  DateTime? lastPlayedAt(String trackId) {
    for (final entry in _history) {
      if (entry.trackId == trackId) {
        return entry.playedAt;
      }
    }

    return null;
  }

  Future<void> recordPlayback(String trackId) async {
    if (!_tracks.any((track) => track.id == trackId)) {
      return;
    }

    _history.insert(
      0,
      PlaybackHistoryEntry(
        trackId: trackId,
        playedAt: _clock(),
      ),
    );
    _trimHistory();
    await _save();
    notifyListeners();
  }

  Future<void> clearPlaybackHistory() async {
    if (_history.isEmpty) {
      return;
    }

    _history.clear();
    await _save();
    notifyListeners();
  }

  TrackLyrics? lyricsForTrack(String trackId) => _lyricsByTrackId[trackId];

  Future<void> setLyrics(String trackId, String plainText) async {
    if (!_tracks.any((track) => track.id == trackId)) {
      return;
    }

    final normalized = plainText.trim();
    if (normalized.isEmpty) {
      await deleteLyrics(trackId);
      return;
    }

    _lyricsByTrackId[trackId] = TrackLyrics(
      trackId: trackId,
      plainText: normalized,
      updatedAt: _clock(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> deleteLyrics(String trackId) async {
    if (!_lyricsByTrackId.containsKey(trackId)) {
      return;
    }

    _lyricsByTrackId.remove(trackId);
    await _save();
    notifyListeners();
  }

  Future<Playlist> createPlaylist(
    String name, {
    Iterable<String> trackIds = const <String>[],
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty.');
    }

    final now = _clock();
    final knownTrackIds = _tracks.map((track) => track.id).toSet();
    final filteredTrackIds = trackIds
        .where(knownTrackIds.contains)
        .toSet()
        .toList(growable: false);
    final playlist = Playlist(
      id: _playlistId(normalizedName, now),
      name: normalizedName,
      trackIds: filteredTrackIds,
      createdAt: now,
      updatedAt: now,
    );

    _playlists.add(playlist);
    _sortPlaylists();
    await _save();
    notifyListeners();

    return playlist;
  }

  Future<void> renamePlaylist(String playlistId, String name) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Playlist name cannot be empty.');
    }

    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) {
      return;
    }

    _playlists[index] = _playlists[index].copyWith(
      name: normalizedName,
      updatedAt: _clock(),
    );
    _sortPlaylists();
    await _save();
    notifyListeners();
  }

  Future<void> deletePlaylist(String playlistId) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) {
      return;
    }

    _playlists.removeAt(index);
    await _save();
    notifyListeners();
  }

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    if (!_tracks.any((track) => track.id == trackId)) {
      return;
    }

    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1 || _playlists[index].containsTrack(trackId)) {
      return;
    }

    _playlists[index] = _playlists[index].copyWith(
      trackIds: <String>[..._playlists[index].trackIds, trackId],
      updatedAt: _clock(),
    );
    _sortPlaylists();
    await _save();
    notifyListeners();
  }

  Future<void> removeTrackFromPlaylist(
    String playlistId,
    String trackId,
  ) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1 || !_playlists[index].containsTrack(trackId)) {
      return;
    }

    _playlists[index] = _playlists[index].copyWith(
      trackIds: _playlists[index]
          .trackIds
          .where((existingId) => existingId != trackId)
          .toList(growable: false),
      updatedAt: _clock(),
    );
    _sortPlaylists();
    await _save();
    notifyListeners();
  }

  void _sortTracks() {
    _tracks.sort((a, b) => b.addedAt.compareTo(a.addedAt));
  }

  List<Track> _sortTrackResults(
    List<Track> results,
    LibrarySortMode sortMode,
  ) {
    results.sort((a, b) {
      switch (sortMode) {
        case LibrarySortMode.recentlyAdded:
          return _compareByDateThenTitle(a, b);
        case LibrarySortMode.title:
          return _compareText(a.title, b.title);
        case LibrarySortMode.artist:
          final byArtist = _compareText(a.artist, b.artist);
          return byArtist == 0 ? _compareText(a.title, b.title) : byArtist;
        case LibrarySortMode.album:
          final byAlbum = _compareText(a.album, b.album);
          return byAlbum == 0 ? _compareText(a.title, b.title) : byAlbum;
      }
    });

    return results;
  }

  int _compareByDateThenTitle(Track a, Track b) {
    final byDate = b.addedAt.compareTo(a.addedAt);
    return byDate == 0 ? _compareText(a.title, b.title) : byDate;
  }

  int _compareText(String a, String b) {
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  void _sortPlaylists() {
    _playlists.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  void _removeMissingPlaylistTracks() {
    final knownTrackIds = _tracks.map((track) => track.id).toSet();

    for (var index = 0; index < _playlists.length; index += 1) {
      final playlist = _playlists[index];
      final filteredTrackIds = playlist.trackIds
          .where(knownTrackIds.contains)
          .toList(growable: false);

      if (filteredTrackIds.length != playlist.trackIds.length) {
        _playlists[index] = playlist.copyWith(trackIds: filteredTrackIds);
      }
    }
  }

  void _removeMissingLyrics() {
    final knownTrackIds = _tracks.map((track) => track.id).toSet();
    _lyricsByTrackId.removeWhere(
      (trackId, _) => !knownTrackIds.contains(trackId),
    );
  }

  void _removeMissingHistory() {
    final knownTrackIds = _tracks.map((track) => track.id).toSet();
    _history.removeWhere((entry) => !knownTrackIds.contains(entry.trackId));
  }

  void _sortHistory() {
    _history.sort((a, b) => b.playedAt.compareTo(a.playedAt));
  }

  void _trimHistory() {
    if (_history.length <= _maxHistoryEntries) {
      return;
    }

    _history.removeRange(_maxHistoryEntries, _history.length);
  }

  void _removeTrackFromPlaylists(String trackId) {
    for (var index = 0; index < _playlists.length; index += 1) {
      final playlist = _playlists[index];
      if (playlist.containsTrack(trackId)) {
        _playlists[index] = playlist.copyWith(
          trackIds: playlist.trackIds
              .where((existingId) => existingId != trackId)
              .toList(growable: false),
          updatedAt: _clock(),
        );
      }
    }
  }

  String _playlistId(String name, DateTime createdAt) {
    final base = '${createdAt.microsecondsSinceEpoch}-$name';
    return base64Url.encode(utf8.encode(base)).replaceAll('=', '');
  }

  List<Map<String, Object?>> _jsonObjectList(
    Map<String, Object?> backup,
    String key, {
    bool isRequired = true,
  }) {
    final rawList = backup[key];
    if (rawList == null && !isRequired) {
      return <Map<String, Object?>>[];
    }

    if (rawList is! List) {
      throw FormatException('Backup field "$key" must be a list.');
    }

    return rawList.map((item) {
      if (item is! Map) {
        throw FormatException('Backup field "$key" contains a non-object.');
      }

      return Map<String, Object?>.from(item);
    }).toList(growable: false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedTracks = jsonEncode(
      _tracks.map((track) => track.toJson()).toList(),
    );
    final encodedPlaylists = jsonEncode(
      _playlists.map((playlist) => playlist.toJson()).toList(),
    );
    final encodedHistory = jsonEncode(
      _history.map((entry) => entry.toJson()).toList(),
    );
    final encodedLyrics = jsonEncode(
      _lyricsByTrackId.values.map((lyrics) => lyrics.toJson()).toList(),
    );
    await prefs.setString(_tracksKey, encodedTracks);
    await prefs.setString(_playlistsKey, encodedPlaylists);
    await prefs.setString(_historyKey, encodedHistory);
    await prefs.setString(_lyricsKey, encodedLyrics);
  }
}
