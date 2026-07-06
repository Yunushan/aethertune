import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/playback_history_entry.dart';
import '../domain/playlist.dart';
import '../domain/track.dart';
import '../domain/track_lyrics.dart';

enum LibrarySortMode { recentlyAdded, title, artist, album }

enum PlaylistDocumentFormat { json, m3u, csv }

enum LibraryBrowseType { artist, album, genre, source, folder }

enum SmartPlaylistType { favorites, recentlyAdded, recentlyPlayed, mostPlayed }

class LibraryBrowseGroup {
  const LibraryBrowseGroup({
    required this.type,
    required this.key,
    required this.label,
    required this.trackCount,
    required this.totalDuration,
  });

  final LibraryBrowseType type;
  final String key;
  final String label;
  final int trackCount;
  final Duration totalDuration;
}

class SmartPlaylist {
  const SmartPlaylist({
    required this.type,
    required this.name,
    required this.description,
    required this.trackCount,
  });

  final SmartPlaylistType type;
  final String name;
  final String description;
  final int trackCount;
}

class LibraryStore extends ChangeNotifier {
  LibraryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _backupVersion = 1;
  static const _playlistDocumentVersion = 1;
  static const _tracksKey = 'aethertune.tracks.v1';
  static const _playlistsKey = 'aethertune.playlists.v1';
  static const _lyricsKey = 'aethertune.lyrics.v1';
  static const _historyKey = 'aethertune.playback_history.v1';
  static const _maxHistoryEntries = 500;
  static final _posixPathContext = path.Context(style: path.Style.posix);
  static final _windowsPathContext = path.Context(style: path.Style.windows);

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
    final normalized = _normalizeQuery(query);
    final source = favoritesOnly ? favorites : tracks;

    final results = normalized.isEmpty
        ? source.toList(growable: false)
        : source
            .where((track) => _trackMatchesQuery(track, normalized))
            .toList(growable: false);

    return _sortTrackResults(results, sortMode);
  }

  List<LibraryBrowseGroup> browseGroups(
    LibraryBrowseType type, {
    String query = '',
  }) {
    final groupsByKey = <String, _MutableBrowseGroup>{};

    for (final track in _tracks) {
      final label = _browseLabelForTrack(track, type);
      final key = _browseKey(label);
      final group = groupsByKey.putIfAbsent(
        key,
        () => _MutableBrowseGroup(
          type: type,
          key: key,
          label: label,
        ),
      );
      group.add(track);
    }

    final normalized = _normalizeQuery(query);
    final groups = groupsByKey.values
        .where(
          (group) =>
              normalized.isEmpty ||
              group.label.toLowerCase().contains(normalized),
        )
        .map((group) => group.toBrowseGroup())
        .toList(growable: false);

    groups.sort((a, b) {
      final byLabel = _compareText(a.label, b.label);
      if (byLabel != 0) {
        return byLabel;
      }

      return b.trackCount.compareTo(a.trackCount);
    });

    return groups;
  }

  List<Track> tracksForBrowseGroup(
    LibraryBrowseType type,
    String key, {
    LibrarySortMode sortMode = LibrarySortMode.album,
  }) {
    final normalizedKey = _browseKey(key);
    final tracks = _tracks
        .where((track) {
          return _browseKey(_browseLabelForTrack(track, type)) == normalizedKey;
        })
        .toList(growable: false);

    return _sortTrackResults(tracks, sortMode);
  }

  List<SmartPlaylist> smartPlaylists() {
    return SmartPlaylistType.values.map((type) {
      final trackCount = tracksForSmartPlaylist(
        type,
        limit: _tracks.length,
      ).length;

      return SmartPlaylist(
        type: type,
        name: _smartPlaylistName(type),
        description: _smartPlaylistDescription(type),
        trackCount: trackCount,
      );
    }).toList(growable: false);
  }

  List<Track> tracksForSmartPlaylist(
    SmartPlaylistType type, {
    int limit = 50,
  }) {
    if (limit <= 0) {
      return <Track>[];
    }

    switch (type) {
      case SmartPlaylistType.favorites:
        final tracks = _sortTrackResults(
          favorites.toList(growable: false),
          LibrarySortMode.artist,
        );
        return tracks.take(limit).toList(growable: false);
      case SmartPlaylistType.recentlyAdded:
        return recentlyAddedTracks(limit: limit);
      case SmartPlaylistType.recentlyPlayed:
        return recentlyPlayedTracks(limit: limit);
      case SmartPlaylistType.mostPlayed:
        return _mostPlayedTracks(limit: limit);
    }
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

  String exportPlaylistDocument(
    String playlistId, {
    required PlaylistDocumentFormat format,
  }) {
    switch (format) {
      case PlaylistDocumentFormat.json:
        return exportPlaylistJson(playlistId);
      case PlaylistDocumentFormat.m3u:
        return exportPlaylistM3u(playlistId);
      case PlaylistDocumentFormat.csv:
        return exportPlaylistCsv(playlistId);
    }
  }

  String exportPlaylistJson(String playlistId) {
    final playlist = _requirePlaylist(playlistId);
    final tracks = tracksForPlaylist(playlistId);
    const encoder = JsonEncoder.withIndent('  ');

    return encoder.convert(<String, Object?>{
      'type': 'aethertune.playlist',
      'version': _playlistDocumentVersion,
      'exportedAt': _clock().toIso8601String(),
      'playlist': playlist.toJson(),
      'tracks': tracks.map((track) => track.toJson()).toList(),
    });
  }

  String exportPlaylistM3u(String playlistId) {
    final playlist = _requirePlaylist(playlistId);
    final buffer = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#PLAYLIST:${playlist.name}');

    for (final track in tracksForPlaylist(playlistId)) {
      final seconds = track.duration == Duration.zero
          ? -1
          : track.duration.inSeconds;
      buffer
        ..writeln('#EXTINF:$seconds,${track.artist} - ${track.title}')
        ..writeln(_playlistTrackLocator(track));
    }

    return buffer.toString();
  }

  String exportPlaylistCsv(String playlistId) {
    final playlist = _requirePlaylist(playlistId);
    final buffer = StringBuffer()
      ..writeln(
        <String>[
          'playlist',
          'title',
          'artist',
          'album',
          'genre',
          'id',
          'localPath',
          'streamUrl',
        ].map(_escapeCsvField).join(','),
      );

    for (final track in tracksForPlaylist(playlistId)) {
      buffer.writeln(
        <String>[
          playlist.name,
          track.title,
          track.artist,
          track.album,
          track.genre,
          track.id,
          track.localPath ?? '',
          track.streamUrl ?? '',
        ].map(_escapeCsvField).join(','),
      );
    }

    return buffer.toString();
  }

  Future<Playlist> importPlaylistDocument(
    String document, {
    required PlaylistDocumentFormat format,
    String fallbackName = 'Imported playlist',
  }) {
    switch (format) {
      case PlaylistDocumentFormat.json:
        return importPlaylistJson(document, fallbackName: fallbackName);
      case PlaylistDocumentFormat.m3u:
        return importPlaylistM3u(document, fallbackName: fallbackName);
      case PlaylistDocumentFormat.csv:
        return importPlaylistCsv(document, fallbackName: fallbackName);
    }
  }

  Future<Playlist> importPlaylistJson(
    String document, {
    String fallbackName = 'Imported playlist',
  }) async {
    final decoded = jsonDecode(document);
    if (decoded is! Map) {
      throw const FormatException('Playlist JSON must be an object.');
    }

    final root = Map<String, Object?>.from(decoded);
    if (root['type'] != 'aethertune.playlist') {
      throw const FormatException('Unsupported playlist JSON type.');
    }

    if (root['version'] != _playlistDocumentVersion) {
      throw FormatException(
        'Unsupported playlist JSON version: ${root['version']}.',
      );
    }

    final rawPlaylist = root['playlist'];
    if (rawPlaylist is! Map) {
      throw const FormatException('Playlist JSON is missing playlist data.');
    }

    final playlistData = Map<String, Object?>.from(rawPlaylist);
    final name = (playlistData['name'] as String?)?.trim();
    final rawTracks = root['tracks'];
    if (rawTracks is! List) {
      throw const FormatException('Playlist JSON is missing track data.');
    }

    final importedTrackIds = <String?>[];
    for (final item in rawTracks) {
      if (item is! Map) {
        throw const FormatException('Playlist JSON contains invalid tracks.');
      }

      importedTrackIds.add(
        _matchImportedTrack(Map<String, Object?>.from(item)),
      );
    }

    final matchedTrackIds = _dedupeTrackIds(importedTrackIds);
    if (matchedTrackIds.isEmpty) {
      throw const FormatException(
        'Imported playlist did not match any library tracks.',
      );
    }

    return createPlaylist(
      name == null || name.isEmpty ? fallbackName : name,
      trackIds: matchedTrackIds,
    );
  }

  Future<Playlist> importPlaylistM3u(
    String document, {
    String fallbackName = 'Imported playlist',
  }) async {
    String? name;
    String? extInfo;
    final trackIds = <String?>[];

    for (final rawLine in const LineSplitter().convert(document)) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }

      if (line.startsWith('#PLAYLIST:')) {
        name = line.substring('#PLAYLIST:'.length).trim();
        continue;
      }

      if (line.startsWith('#EXTINF:')) {
        extInfo = line;
        continue;
      }

      if (line.startsWith('#')) {
        continue;
      }

      trackIds.add(
        _matchM3uEntry(line, extInfo),
      );
      extInfo = null;
    }

    final importedTrackIds = _dedupeTrackIds(trackIds);
    if (importedTrackIds.isEmpty) {
      throw const FormatException(
        'Imported playlist did not match any library tracks.',
      );
    }

    final playlistName = name == null || name.isEmpty ? fallbackName : name;
    return createPlaylist(playlistName, trackIds: importedTrackIds);
  }

  Future<Playlist> importPlaylistCsv(
    String document, {
    String fallbackName = 'Imported playlist',
  }) async {
    final rows = _parseCsvRows(document);
    if (rows.isEmpty) {
      throw const FormatException('Playlist CSV is empty.');
    }

    final header = rows.first.map((field) => field.trim()).toList();
    final indexes = <String, int>{
      for (var index = 0; index < header.length; index += 1)
        header[index]: index,
    };
    String? name;
    final trackIds = <String?>[];

    for (final row in rows.skip(1)) {
      if (row.every((field) => field.trim().isEmpty)) {
        continue;
      }

      name ??= _fieldAt(row, indexes['playlist'])?.trim();
      trackIds.add(
        _matchImportedTrack(<String, Object?>{
          'id': _fieldAt(row, indexes['id']),
          'title': _fieldAt(row, indexes['title']),
          'artist': _fieldAt(row, indexes['artist']),
          'album': _fieldAt(row, indexes['album']),
          'genre': _fieldAt(row, indexes['genre']),
          'localPath': _fieldAt(row, indexes['localPath']),
          'streamUrl': _fieldAt(row, indexes['streamUrl']),
        }),
      );
    }

    final importedTrackIds = _dedupeTrackIds(trackIds);
    if (importedTrackIds.isEmpty) {
      throw const FormatException(
        'Imported playlist did not match any library tracks.',
      );
    }

    final playlistName = name == null || name.isEmpty ? fallbackName : name;
    return createPlaylist(playlistName, trackIds: importedTrackIds);
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

  List<Track> tracksForPlaylist(String playlistId, {String query = ''}) {
    final playlist = playlistById(playlistId);
    if (playlist == null) {
      return <Track>[];
    }

    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };

    final tracks = playlist.trackIds
        .map((trackId) => byId[trackId])
        .whereType<Track>()
        .toList(growable: false);
    final normalized = _normalizeQuery(query);
    if (normalized.isEmpty) {
      return tracks;
    }

    return tracks
        .where((track) => _trackMatchesQuery(track, normalized))
        .toList(growable: false);
  }

  List<Track> recentlyPlayedTracks({int limit = 25}) {
    if (limit <= 0) {
      return <Track>[];
    }

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

  List<Track> _mostPlayedTracks({required int limit}) {
    final tracks = _tracks
        .where((track) => playCountForTrack(track.id) > 0)
        .toList(growable: false);

    tracks.sort((a, b) {
      final byPlayCount =
          playCountForTrack(b.id).compareTo(playCountForTrack(a.id));
      if (byPlayCount != 0) {
        return byPlayCount;
      }

      final aLastPlayed = lastPlayedAt(a.id);
      final bLastPlayed = lastPlayedAt(b.id);
      if (aLastPlayed != null && bLastPlayed != null) {
        final byLastPlayed = bLastPlayed.compareTo(aLastPlayed);
        if (byLastPlayed != 0) {
          return byLastPlayed;
        }
      }

      return _compareText(a.title, b.title);
    });

    return tracks.take(limit).toList(growable: false);
  }

  String _smartPlaylistName(SmartPlaylistType type) {
    switch (type) {
      case SmartPlaylistType.favorites:
        return 'Favorites';
      case SmartPlaylistType.recentlyAdded:
        return 'Recently added';
      case SmartPlaylistType.recentlyPlayed:
        return 'Recently played';
      case SmartPlaylistType.mostPlayed:
        return 'Most played';
    }
  }

  String _smartPlaylistDescription(SmartPlaylistType type) {
    switch (type) {
      case SmartPlaylistType.favorites:
        return 'Tracks marked with the heart.';
      case SmartPlaylistType.recentlyAdded:
        return 'Newest imports first.';
      case SmartPlaylistType.recentlyPlayed:
        return 'Latest unique tracks from history.';
      case SmartPlaylistType.mostPlayed:
        return 'Highest local play counts.';
    }
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

  Future<void> moveTrackInPlaylist(
    String playlistId,
    int fromIndex,
    int toIndex,
  ) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) {
      return;
    }

    final playlist = _playlists[index];
    if (fromIndex < 0 ||
        fromIndex >= playlist.trackIds.length ||
        toIndex < 0 ||
        toIndex >= playlist.trackIds.length ||
        fromIndex == toIndex) {
      return;
    }

    final trackIds = playlist.trackIds.toList(growable: true);
    final trackId = trackIds.removeAt(fromIndex);
    trackIds.insert(toIndex, trackId);

    _playlists[index] = playlist.copyWith(
      trackIds: trackIds,
      updatedAt: _clock(),
    );
    _sortPlaylists();
    await _save();
    notifyListeners();
  }

  Playlist _requirePlaylist(String playlistId) {
    final playlist = playlistById(playlistId);
    if (playlist == null) {
      throw StateError('Playlist does not exist: $playlistId');
    }

    return playlist;
  }

  String _playlistTrackLocator(Track track) {
    return track.localPath ?? track.streamUrl ?? track.id;
  }

  List<String> _dedupeTrackIds(Iterable<String?> trackIds) {
    final seen = <String>{};
    final result = <String>[];

    for (final trackId in trackIds) {
      if (trackId == null || trackId.isEmpty || seen.contains(trackId)) {
        continue;
      }

      seen.add(trackId);
      result.add(trackId);
    }

    return result;
  }

  String? _matchImportedTrack(Map<String, Object?> candidate) {
    final id = _stringValue(candidate['id']);
    if (id != null && _tracks.any((track) => track.id == id)) {
      return id;
    }

    final localPath = _stringValue(candidate['localPath']);
    if (localPath != null) {
      final track = _tracks.where((track) => track.localPath == localPath);
      if (track.isNotEmpty) {
        return track.first.id;
      }
    }

    final streamUrl = _stringValue(candidate['streamUrl']);
    if (streamUrl != null) {
      final track = _tracks.where((track) => track.streamUrl == streamUrl);
      if (track.isNotEmpty) {
        return track.first.id;
      }
    }

    final title = _stringValue(candidate['title']);
    final artist = _stringValue(candidate['artist']);
    final album = _stringValue(candidate['album']);
    if (title == null || artist == null) {
      return null;
    }

    final matches = _tracks.where((track) {
      final titleMatches = _sameText(track.title, title);
      final artistMatches = _sameText(track.artist, artist);
      final albumMatches = album == null || _sameText(track.album, album);

      return titleMatches && artistMatches && albumMatches;
    });

    return matches.isEmpty ? null : matches.first.id;
  }

  String? _matchM3uEntry(String locator, String? extInfo) {
    final directMatch = _matchImportedTrack(<String, Object?>{
      'id': locator,
      'localPath': locator,
      'streamUrl': locator,
    });
    if (directMatch != null) {
      return directMatch;
    }

    final commaIndex = extInfo?.indexOf(',') ?? -1;
    if (commaIndex == -1 || extInfo == null) {
      return null;
    }

    final label = extInfo.substring(commaIndex + 1).trim();
    final separatorIndex = label.indexOf(' - ');
    if (separatorIndex == -1) {
      return _matchImportedTrack(<String, Object?>{
        'title': label,
        'artist': 'Unknown Artist',
      });
    }

    return _matchImportedTrack(<String, Object?>{
      'artist': label.substring(0, separatorIndex),
      'title': label.substring(separatorIndex + 3),
    });
  }

  String? _stringValue(Object? value) {
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _sameText(String left, String right) {
    return left.trim().toLowerCase() == right.trim().toLowerCase();
  }

  String _escapeCsvField(String value) {
    if (!value.contains(',') &&
        !value.contains('"') &&
        !value.contains('\n') &&
        !value.contains('\r')) {
      return value;
    }

    return '"${value.replaceAll('"', '""')}"';
  }

  List<List<String>> _parseCsvRows(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < input.length; index += 1) {
      final char = input[index];

      if (inQuotes) {
        if (char == '"') {
          final nextIndex = index + 1;
          if (nextIndex < input.length && input[nextIndex] == '"') {
            field.write('"');
            index += 1;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(char);
        }
        continue;
      }

      if (char == '"') {
        if (field.length > 0) {
          throw const FormatException('Invalid quoted CSV field.');
        }
        inQuotes = true;
        continue;
      }

      if (char == ',') {
        row.add(field.toString());
        field.clear();
        continue;
      }

      if (char == '\n' || char == '\r') {
        row.add(field.toString());
        field.clear();
        if (row.any((value) => value.isNotEmpty)) {
          rows.add(row);
        }
        row = <String>[];
        if (char == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index += 1;
        }
        continue;
      }

      field.write(char);
    }

    if (inQuotes) {
      throw const FormatException('CSV contains an unterminated quoted field.');
    }

    row.add(field.toString());
    if (row.any((value) => value.isNotEmpty)) {
      rows.add(row);
    }

    return rows;
  }

  String? _fieldAt(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) {
      return null;
    }

    return row[index];
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

  String _normalizeQuery(String query) => query.trim().toLowerCase();

  bool _trackMatchesQuery(Track track, String normalizedQuery) {
    return track.title.toLowerCase().contains(normalizedQuery) ||
        track.artist.toLowerCase().contains(normalizedQuery) ||
        track.album.toLowerCase().contains(normalizedQuery) ||
        track.genre.toLowerCase().contains(normalizedQuery);
  }

  String _browseLabelForTrack(Track track, LibraryBrowseType type) {
    switch (type) {
      case LibraryBrowseType.artist:
        return _nonEmptyMetadata(track.artist, 'Unknown Artist');
      case LibraryBrowseType.album:
        return _nonEmptyMetadata(track.album, 'Unknown Album');
      case LibraryBrowseType.genre:
        return _nonEmptyMetadata(track.genre, 'Unknown Genre');
      case LibraryBrowseType.source:
        return _nonEmptyMetadata(track.sourceId, 'Unknown Source');
      case LibraryBrowseType.folder:
        return _folderLabelForTrack(track);
    }
  }

  String _folderLabelForTrack(Track track) {
    final localPath = track.localPath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return 'Remote Streams';
    }

    final context = _looksLikeWindowsPath(localPath)
        ? _windowsPathContext
        : _posixPathContext;
    final directory = context.dirname(localPath);
    if (directory == '.' || directory == localPath) {
      return 'Unknown Folder';
    }

    return _nonEmptyMetadata(directory, 'Unknown Folder');
  }

  bool _looksLikeWindowsPath(String value) {
    return value.contains('\\') || RegExp(r'^[A-Za-z]:').hasMatch(value);
  }

  String _nonEmptyMetadata(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String _browseKey(String value) => _nonEmptyMetadata(value, '').toLowerCase();

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
