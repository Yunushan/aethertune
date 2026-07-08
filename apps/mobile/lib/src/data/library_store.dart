import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/music_source_provider.dart';
import '../domain/offline_cache_entry.dart';
import '../domain/playback_history_entry.dart';
import '../domain/playback_progress_entry.dart';
import '../domain/playlist.dart';
import '../domain/podcast_subscription.dart';
import '../domain/track.dart';
import '../domain/track_lyrics.dart';

enum LibrarySortMode { recentlyAdded, title, artist, album }

enum PlaylistDocumentFormat { json, m3u, csv }

enum LibraryStatsExportFormat { json, csv }

enum LibraryBrowseType { artist, album, genre, source, folder }

enum SearchSuggestionType {
  query,
  recent,
  title,
  artist,
  album,
  genre,
  source,
  folder,
}

enum DuplicateMatchType { localPath, sourceExternalId, streamUrl, metadata }

enum SmartPlaylistType { favorites, recentlyAdded, recentlyPlayed, mostPlayed }

enum LibraryHomeSectionType {
  continueListening,
  recentlyPlayed,
  radioSeeds,
  mostPlayed,
  favorites,
  recentlyAdded,
}

enum LibraryChartRange { allTime, sevenDays, thirtyDays, year }

enum CustomSmartPlaylistSortMode {
  recentlyAdded,
  title,
  artist,
  album,
  recentlyPlayed,
  mostPlayed,
}

enum AppThemePreference { system, light, dark, amoled }

extension AppThemePreferenceLabel on AppThemePreference {
  String get label {
    switch (this) {
      case AppThemePreference.system:
        return 'System';
      case AppThemePreference.light:
        return 'Light';
      case AppThemePreference.dark:
        return 'Dark';
      case AppThemePreference.amoled:
        return 'AMOLED';
    }
  }
}

class SearchSuggestion {
  const SearchSuggestion({
    required this.type,
    required this.value,
  });

  final SearchSuggestionType type;
  final String value;
}

class DuplicateTrackGroup {
  const DuplicateTrackGroup({
    required this.key,
    required this.type,
    required this.tracks,
  });

  final String key;
  final DuplicateMatchType type;
  final List<Track> tracks;
}

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

class LibraryHomeSection {
  const LibraryHomeSection({
    required this.type,
    required this.tracks,
  });

  final LibraryHomeSectionType type;
  final List<Track> tracks;
}

class LibraryChartsSnapshot {
  const LibraryChartsSnapshot({
    required this.range,
    required this.stats,
  });

  final LibraryChartRange range;
  final LibraryStatsSummary stats;
}

class CustomSmartPlaylist {
  CustomSmartPlaylist({
    required this.id,
    required this.name,
    this.query = '',
    this.favoritesOnly = false,
    this.minimumPlayCount = 0,
    this.sortMode = CustomSmartPlaylistSortMode.recentlyAdded,
    this.limit = 50,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final String query;
  final bool favoritesOnly;
  final int minimumPlayCount;
  final CustomSmartPlaylistSortMode sortMode;
  final int limit;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomSmartPlaylist copyWith({
    String? id,
    String? name,
    String? query,
    bool? favoritesOnly,
    int? minimumPlayCount,
    CustomSmartPlaylistSortMode? sortMode,
    int? limit,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomSmartPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      query: query ?? this.query,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      minimumPlayCount: minimumPlayCount ?? this.minimumPlayCount,
      sortMode: sortMode ?? this.sortMode,
      limit: limit ?? this.limit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'query': query,
      'favoritesOnly': favoritesOnly,
      'minimumPlayCount': minimumPlayCount,
      'sortMode': sortMode.name,
      'limit': limit,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory CustomSmartPlaylist.fromJson(Map<String, Object?> json) {
    return CustomSmartPlaylist(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled smart playlist',
      query: json['query'] as String? ?? '',
      favoritesOnly: json['favoritesOnly'] as bool? ?? false,
      minimumPlayCount: json['minimumPlayCount'] as int? ?? 0,
      sortMode: _customSmartPlaylistSortModeFromName(
        json['sortMode'] as String?,
      ),
      limit: json['limit'] as int? ?? 50,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class LibraryStatsSummary {
  const LibraryStatsSummary({
    this.from,
    this.to,
    required this.trackCount,
    required this.libraryDuration,
    required this.favoriteTrackCount,
    required this.playbackCount,
    required this.uniquePlayedTrackCount,
    required this.estimatedListeningDuration,
    required this.topTracks,
    required this.topArtists,
    required this.topAlbums,
    required this.topGenres,
  });

  final DateTime? from;
  final DateTime? to;
  final int trackCount;
  final Duration libraryDuration;
  final int favoriteTrackCount;
  final int playbackCount;
  final int uniquePlayedTrackCount;
  final Duration estimatedListeningDuration;
  final List<LibraryStatsTrack> topTracks;
  final List<LibraryStatsGroup> topArtists;
  final List<LibraryStatsGroup> topAlbums;
  final List<LibraryStatsGroup> topGenres;
}

class LibraryStatsTrack {
  const LibraryStatsTrack({
    required this.track,
    required this.playCount,
    required this.estimatedListeningDuration,
    this.lastPlayedAt,
  });

  final Track track;
  final int playCount;
  final Duration estimatedListeningDuration;
  final DateTime? lastPlayedAt;
}

class LibraryStatsGroup {
  const LibraryStatsGroup({
    required this.label,
    required this.playCount,
    required this.trackCount,
    required this.estimatedListeningDuration,
    this.lastPlayedAt,
  });

  final String label;
  final int playCount;
  final int trackCount;
  final Duration estimatedListeningDuration;
  final DateTime? lastPlayedAt;
}

class TrackRadioSeedQueue {
  const TrackRadioSeedQueue({
    required this.seedTrack,
    required this.tracks,
  });

  final Track seedTrack;
  final List<Track> tracks;
}

final class _TrackRadioCandidate {
  const _TrackRadioCandidate({
    required this.track,
    required this.score,
    this.lastPlayedAt,
  });

  final Track track;
  final int score;
  final DateTime? lastPlayedAt;
}

CustomSmartPlaylistSortMode _customSmartPlaylistSortModeFromName(
  String? value,
) {
  return CustomSmartPlaylistSortMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => CustomSmartPlaylistSortMode.recentlyAdded,
  );
}

AppThemePreference _appThemePreferenceFromName(String? value) {
  return AppThemePreference.values.firstWhere(
    (preference) => preference.name == value,
    orElse: () => AppThemePreference.system,
  );
}

class LibraryStore extends ChangeNotifier {
  LibraryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _backupVersion = 1;
  static const _playlistDocumentVersion = 1;
  static const _libraryStatsDocumentVersion = 1;
  static const _tracksKey = 'aethertune.tracks.v1';
  static const _playlistsKey = 'aethertune.playlists.v1';
  static const _customSmartPlaylistsKey =
      'aethertune.custom_smart_playlists.v1';
  static const _podcastSubscriptionsKey =
      'aethertune.podcast_subscriptions.v1';
  static const _lyricsKey = 'aethertune.lyrics.v1';
  static const _historyKey = 'aethertune.playback_history.v1';
  static const _progressKey = 'aethertune.playback_progress.v1';
  static const _searchQueryHistoryKey = 'aethertune.search_query_history.v1';
  static const _offlineModeKey = 'aethertune.offline_mode.v1';
  static const _themePreferenceKey = 'aethertune.theme_preference.v1';
  static const _offlineCacheQueueKey = 'aethertune.offline_cache_queue.v1';
  static const _maxHistoryEntries = 500;
  static const _maxSearchQueryHistoryEntries = 20;
  static const _minSavedProgress = Duration(seconds: 5);
  static const _completedProgressThreshold = Duration(seconds: 20);
  static final _posixPathContext = path.Context(style: path.Style.posix);
  static final _windowsPathContext = path.Context(style: path.Style.windows);

  final List<Track> _tracks = <Track>[];
  final List<Playlist> _playlists = <Playlist>[];
  final List<CustomSmartPlaylist> _customSmartPlaylists =
      <CustomSmartPlaylist>[];
  final List<PodcastSubscription> _podcastSubscriptions =
      <PodcastSubscription>[];
  final List<PlaybackHistoryEntry> _history = <PlaybackHistoryEntry>[];
  final List<String> _searchQueryHistory = <String>[];
  final Map<String, PlaybackProgressEntry> _progressByTrackId =
      <String, PlaybackProgressEntry>{};
  final Map<String, TrackLyrics> _lyricsByTrackId = <String, TrackLyrics>{};
  final List<OfflineCacheEntry> _offlineCacheQueue = <OfflineCacheEntry>[];
  final DateTime Function() _clock;
  bool _offlineModeEnabled = false;
  AppThemePreference _themePreference = AppThemePreference.system;
  bool _loaded = false;

  bool get loaded => _loaded;
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<CustomSmartPlaylist> get customSmartPlaylists =>
      List.unmodifiable(_customSmartPlaylists);
  List<PodcastSubscription> get podcastSubscriptions =>
      List.unmodifiable(_podcastSubscriptions);
  List<PlaybackHistoryEntry> get playbackHistory =>
      List.unmodifiable(_history);
  List<String> get searchQueryHistory =>
      List.unmodifiable(_searchQueryHistory);
  List<PlaybackProgressEntry> get playbackProgress =>
      List.unmodifiable(_progressByTrackId.values);
  List<TrackLyrics> get lyrics => List.unmodifiable(_lyricsByTrackId.values);
  List<OfflineCacheEntry> get offlineCacheQueue =>
      List.unmodifiable(_offlineCacheQueue);
  List<Track> get favorites =>
      _tracks.where((track) => track.isFavorite).toList(growable: false);
  bool get offlineModeEnabled => _offlineModeEnabled;
  AppThemePreference get themePreference => _themePreference;

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

    final rawCustomSmartPlaylists = prefs.getString(_customSmartPlaylistsKey);
    if (rawCustomSmartPlaylists != null && rawCustomSmartPlaylists.isNotEmpty) {
      final decoded = jsonDecode(rawCustomSmartPlaylists) as List<dynamic>;
      _customSmartPlaylists
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map(
                (item) => CustomSmartPlaylist.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList(growable: false),
        );
    }

    final rawPodcastSubscriptions = prefs.getString(_podcastSubscriptionsKey);
    if (rawPodcastSubscriptions != null && rawPodcastSubscriptions.isNotEmpty) {
      final decoded = jsonDecode(rawPodcastSubscriptions) as List<dynamic>;
      _podcastSubscriptions
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map(
                (item) => PodcastSubscription.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .where((subscription) => subscription.feedUrl.isNotEmpty)
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

    final rawSearchQueryHistory = prefs.getString(_searchQueryHistoryKey);
    if (rawSearchQueryHistory != null && rawSearchQueryHistory.isNotEmpty) {
      final decoded = jsonDecode(rawSearchQueryHistory) as List<dynamic>;
      _searchQueryHistory
        ..clear()
        ..addAll(
          _dedupeSearchQueryHistory(decoded.whereType<String>()),
        );
    }

    final rawProgress = prefs.getString(_progressKey);
    if (rawProgress != null && rawProgress.isNotEmpty) {
      final decoded = jsonDecode(rawProgress) as List<dynamic>;
      _progressByTrackId
        ..clear()
        ..addEntries(
          decoded
              .whereType<Map>()
              .map(
                (item) => PlaybackProgressEntry.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .where((entry) => entry.position >= _minSavedProgress)
              .map(
                (entry) => MapEntry<String, PlaybackProgressEntry>(
                  entry.trackId,
                  entry,
                ),
              ),
        );
    }
    _offlineModeEnabled = prefs.getBool(_offlineModeKey) ?? false;
    _themePreference = _appThemePreferenceFromName(
      prefs.getString(_themePreferenceKey),
    );
    final rawOfflineCacheQueue = prefs.getString(_offlineCacheQueueKey);
    if (rawOfflineCacheQueue != null && rawOfflineCacheQueue.isNotEmpty) {
      final decoded = jsonDecode(rawOfflineCacheQueue) as List<dynamic>;
      _offlineCacheQueue
        ..clear()
        ..addAll(
          _dedupeOfflineCacheQueue(
            decoded
                .whereType<Map>()
                .map(
                  (item) => OfflineCacheEntry.fromJson(
                    Map<String, Object?>.from(item),
                  ),
                )
                .toList(growable: false),
          ),
        );
    }

    _removeMissingPlaylistTracks();
    _removeMissingLyrics();
    _removeMissingHistory();
    _removeMissingProgress();
    _sortHistory();
    _trimSearchQueryHistory();
    _sortCustomSmartPlaylists();
    _sortPodcastSubscriptions();
    _sortOfflineCacheQueue();
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
    _progressByTrackId.remove(id);
    await _save();
    notifyListeners();
  }

  Future<int> resolveDuplicateTracks({
    required String keepTrackId,
    required Iterable<String> duplicateTrackIds,
  }) async {
    final keepIndex = _tracks.indexWhere((track) => track.id == keepTrackId);
    if (keepIndex == -1) {
      return 0;
    }

    final removeIds = duplicateTrackIds
        .where((trackId) => trackId != keepTrackId)
        .where((trackId) => _tracks.any((track) => track.id == trackId))
        .toSet();
    if (removeIds.isEmpty) {
      return 0;
    }

    final duplicateIds = <String>{keepTrackId, ...removeIds};
    final shouldFavorite = _tracks
        .where((track) => duplicateIds.contains(track.id))
        .any((track) => track.isFavorite);
    if (shouldFavorite && !_tracks[keepIndex].isFavorite) {
      _tracks[keepIndex] = _tracks[keepIndex].copyWith(isFavorite: true);
    }

    _rewritePlaylistDuplicateReferences(keepTrackId, removeIds);
    _rewriteHistoryDuplicateReferences(keepTrackId, removeIds);
    _mergeDuplicateProgress(keepTrackId, removeIds);
    _mergeDuplicateLyrics(keepTrackId, removeIds);
    _tracks.removeWhere((track) => removeIds.contains(track.id));

    _sortTracks();
    _sortPlaylists();
    _sortHistory();
    _trimHistory();
    await _save();
    notifyListeners();

    return removeIds.length;
  }

  Future<void> clear() async {
    _tracks.clear();
    _playlists.clear();
    _customSmartPlaylists.clear();
    _podcastSubscriptions.clear();
    _history.clear();
    _searchQueryHistory.clear();
    _progressByTrackId.clear();
    _lyricsByTrackId.clear();
    _offlineCacheQueue.clear();
    await _save();
    notifyListeners();
  }

  Future<void> setOfflineModeEnabled(bool enabled) async {
    if (_offlineModeEnabled == enabled) {
      return;
    }

    _offlineModeEnabled = enabled;
    await _save();
    notifyListeners();
  }

  Future<void> setThemePreference(AppThemePreference preference) async {
    if (_themePreference == preference) {
      return;
    }

    _themePreference = preference;
    await _save();
    notifyListeners();
  }

  Future<OfflineCacheEntry> queueOfflineCache(
    Track track,
    OfflineMediaAction action,
    OfflineMediaPolicyDecision decision,
  ) async {
    if (decision.action != action) {
      throw ArgumentError.value(
        decision.action,
        'decision',
        'Offline policy decision action must match the queued action.',
      );
    }
    if (!decision.isAllowed) {
      throw StateError(decision.reason);
    }

    final now = _clock();
    final id = OfflineCacheEntry.stableIdFor(track, action);
    final index = _offlineCacheQueue.indexWhere((entry) => entry.id == id);
    final entry = index == -1
        ? OfflineCacheEntry(
            id: id,
            track: track,
            action: action,
            createdAt: now,
            updatedAt: now,
            reason: decision.reason,
          )
        : _offlineCacheQueue[index].copyWith(
            track: track,
            action: action,
            status: OfflineCacheEntryStatus.queued,
            updatedAt: now,
            reason: decision.reason,
          );

    if (index == -1) {
      _offlineCacheQueue.add(entry);
    } else {
      _offlineCacheQueue[index] = entry;
    }

    _sortOfflineCacheQueue();
    await _save();
    notifyListeners();

    return entry;
  }

  Future<void> removeOfflineCacheEntry(String id) async {
    final previousLength = _offlineCacheQueue.length;
    _offlineCacheQueue.removeWhere((entry) => entry.id == id);
    if (_offlineCacheQueue.length == previousLength) {
      return;
    }

    await _save();
    notifyListeners();
  }

  Future<void> clearOfflineCacheQueue() async {
    if (_offlineCacheQueue.isEmpty) {
      return;
    }

    _offlineCacheQueue.clear();
    await _save();
    notifyListeners();
  }

  OfflineCacheEntry? offlineCacheEntryById(String id) {
    final index = _offlineCacheQueue.indexWhere((entry) => entry.id == id);
    if (index == -1) {
      return null;
    }

    return _offlineCacheQueue[index];
  }

  Future<OfflineCacheEntry?> markOfflineCacheEntryProcessing(String id) {
    return _updateOfflineCacheEntry(
      id,
      status: OfflineCacheEntryStatus.processing,
      reason: 'Caching media...',
    );
  }

  Future<OfflineCacheEntry?> markOfflineCacheEntryCached(
    String id,
    Track cachedTrack, {
    required String reason,
  }) {
    return _updateOfflineCacheEntry(
      id,
      track: cachedTrack,
      status: OfflineCacheEntryStatus.cached,
      reason: reason,
      upsertCachedTrack: true,
    );
  }

  Future<OfflineCacheEntry?> markOfflineCacheEntryFailed(
    String id, {
    required String reason,
  }) {
    return _updateOfflineCacheEntry(
      id,
      status: OfflineCacheEntryStatus.failed,
      reason: reason,
    );
  }

  Future<OfflineCacheEntry?> markOfflineCacheEntryEvicted(
    String id, {
    required String reason,
  }) {
    final entry = offlineCacheEntryById(id);
    if (entry == null) {
      return Future<OfflineCacheEntry?>.value(null);
    }

    return _updateOfflineCacheEntry(
      id,
      track: entry.track.copyWith(localPath: ''),
      status: OfflineCacheEntryStatus.queued,
      reason: reason,
      upsertCachedTrack: true,
      addCachedTrackIfMissing: false,
    );
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

  Future<Track?> updateTrackMetadata(
    String id, {
    required String title,
    required String artist,
    required String album,
    required String genre,
  }) async {
    final index = _tracks.indexWhere((track) => track.id == id);
    if (index == -1) {
      return null;
    }

    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Track title cannot be empty.');
    }

    final current = _tracks[index];
    final updated = current.copyWith(
      title: normalizedTitle,
      artist: _nonEmptyMetadata(artist, 'Unknown Artist'),
      album: _nonEmptyMetadata(album, 'Unknown Album'),
      genre: _nonEmptyMetadata(genre, 'Unknown Genre'),
    );

    if (updated.title == current.title &&
        updated.artist == current.artist &&
        updated.album == current.album &&
        updated.genre == current.genre) {
      return updated;
    }

    _tracks[index] = updated;
    _sortTracks();
    await _save();
    notifyListeners();

    return updated;
  }

  List<Track> search(
    String query, {
    bool favoritesOnly = false,
    bool offlineOnly = false,
    LibrarySortMode sortMode = LibrarySortMode.recentlyAdded,
  }) {
    final normalized = _normalizeQuery(query);
    final source = (favoritesOnly ? favorites : tracks)
        .where((track) => !offlineOnly || track.hasLocalSource);

    final results = normalized.isEmpty
        ? source.toList(growable: false)
        : source
            .where((track) => _trackMatchesQuery(track, normalized))
            .toList(growable: false);

    return _sortTrackResults(results, sortMode);
  }

  List<SearchSuggestion> searchSuggestions(String query, {int limit = 8}) {
    if (limit <= 0) {
      return <SearchSuggestion>[];
    }

    final normalized = _normalizeQuery(query);
    final suggestions = <SearchSuggestion>[];
    final seenValues = <String>{};

    void addSuggestion(SearchSuggestionType type, String value) {
      if (suggestions.length >= limit) {
        return;
      }

      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }

      if (normalized.isNotEmpty &&
          !trimmed.toLowerCase().contains(normalized)) {
        return;
      }

      if (!seenValues.add(trimmed.toLowerCase())) {
        return;
      }

      suggestions.add(SearchSuggestion(type: type, value: trimmed));
    }

    for (final value in _searchQueryHistory) {
      addSuggestion(SearchSuggestionType.query, value);
    }

    for (final track in recentlyPlayedTracks(limit: limit)) {
      addSuggestion(SearchSuggestionType.recent, track.title);
    }

    for (final track in _tracks) {
      if (suggestions.length >= limit) {
        break;
      }

      addSuggestion(SearchSuggestionType.title, track.title);
      addSuggestion(
        SearchSuggestionType.artist,
        _browseLabelForTrack(track, LibraryBrowseType.artist),
      );
      addSuggestion(
        SearchSuggestionType.album,
        _browseLabelForTrack(track, LibraryBrowseType.album),
      );
      addSuggestion(
        SearchSuggestionType.genre,
        _browseLabelForTrack(track, LibraryBrowseType.genre),
      );
      addSuggestion(
        SearchSuggestionType.source,
        _browseLabelForTrack(track, LibraryBrowseType.source),
      );
      addSuggestion(
        SearchSuggestionType.folder,
        _browseLabelForTrack(track, LibraryBrowseType.folder),
      );
    }

    return suggestions;
  }

  Future<void> recordSearchQuery(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return;
    }

    final existingIndex = _searchQueryHistory.indexWhere(
      (value) => value.toLowerCase() == normalized.toLowerCase(),
    );
    if (existingIndex != -1) {
      _searchQueryHistory.removeAt(existingIndex);
    }

    _searchQueryHistory.insert(0, normalized);
    _trimSearchQueryHistory();
    await _save();
    notifyListeners();
  }

  List<DuplicateTrackGroup> duplicateTrackGroups() {
    final groupsByKey = <String, _MutableDuplicateTrackGroup>{};

    void addGroupTrack(
      DuplicateMatchType type,
      String keyPart,
      Track track,
    ) {
      final normalizedKey = _duplicateKeyPart(keyPart);
      if (normalizedKey.isEmpty) {
        return;
      }

      final key = '${type.name}:$normalizedKey';
      final group = groupsByKey.putIfAbsent(
        key,
        () => _MutableDuplicateTrackGroup(
          key: key,
          type: type,
        ),
      );
      group.add(track);
    }

    for (final track in _tracks) {
      addGroupTrack(
        DuplicateMatchType.localPath,
        track.localPath ?? '',
        track,
      );
      final externalId = track.externalId?.trim();
      if (externalId != null && externalId.isNotEmpty) {
        addGroupTrack(
          DuplicateMatchType.sourceExternalId,
          '${track.sourceId}:$externalId',
          track,
        );
      }
      addGroupTrack(
        DuplicateMatchType.streamUrl,
        track.streamUrl ?? '',
        track,
      );

      final metadataKey = _duplicateMetadataKey(track);
      if (metadataKey != null) {
        addGroupTrack(DuplicateMatchType.metadata, metadataKey, track);
      }
    }

    final groups = groupsByKey.values
        .where((group) => group.tracks.length > 1)
        .map((group) => group.toDuplicateTrackGroup())
        .toList(growable: false);
    groups.sort((a, b) {
      final byType = a.type.index.compareTo(b.type.index);
      if (byType != 0) {
        return byType;
      }

      return _compareText(a.tracks.first.title, b.tracks.first.title);
    });

    final seenTrackSets = <String>{};
    final uniqueGroups = <DuplicateTrackGroup>[];
    for (final group in groups) {
      final trackSetKey = group.tracks.map((track) => track.id).toList()
        ..sort();
      if (!seenTrackSets.add(trackSetKey.join('|'))) {
        continue;
      }

      uniqueGroups.add(group);
    }

    return uniqueGroups;
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

  List<LibraryHomeSection> homeFeedSections({int limit = 8}) {
    if (limit <= 0) {
      return <LibraryHomeSection>[];
    }

    final sections = <LibraryHomeSection>[];

    void addSection(LibraryHomeSectionType type, List<Track> tracks) {
      final sectionTracks = _uniqueTracks(tracks).take(limit).toList(
            growable: false,
          );
      if (sectionTracks.isEmpty) {
        return;
      }

      sections.add(LibraryHomeSection(type: type, tracks: sectionTracks));
    }

    addSection(
      LibraryHomeSectionType.continueListening,
      _continueListeningTracks(limit: limit),
    );
    addSection(
      LibraryHomeSectionType.recentlyPlayed,
      recentlyPlayedTracks(limit: limit),
    );
    addSection(
      LibraryHomeSectionType.radioSeeds,
      _homeRadioSeedTracks(limit: limit),
    );
    addSection(
      LibraryHomeSectionType.mostPlayed,
      _mostPlayedTracks(limit: limit),
    );
    addSection(
      LibraryHomeSectionType.favorites,
      tracksForSmartPlaylist(SmartPlaylistType.favorites, limit: limit),
    );
    addSection(
      LibraryHomeSectionType.recentlyAdded,
      recentlyAddedTracks(limit: limit),
    );

    return sections;
  }

  LibraryChartsSnapshot localCharts({
    LibraryChartRange range = LibraryChartRange.thirtyDays,
    int limit = 5,
  }) {
    final now = _clock();
    final from = _libraryChartRangeStart(range, now);
    final to = range == LibraryChartRange.allTime ? null : now;

    return LibraryChartsSnapshot(
      range: range,
      stats: libraryStats(limit: limit, from: from, to: to),
    );
  }

  CustomSmartPlaylist? customSmartPlaylistById(String id) {
    final index = _customSmartPlaylists.indexWhere((rule) => rule.id == id);
    if (index == -1) {
      return null;
    }

    return _customSmartPlaylists[index];
  }

  List<Track> tracksForCustomSmartPlaylist(String id) {
    final rule = customSmartPlaylistById(id);
    if (rule == null || rule.limit <= 0) {
      return <Track>[];
    }

    final normalizedQuery = _normalizeQuery(rule.query);
    final tracks = _tracks.where((track) {
      if (rule.favoritesOnly && !track.isFavorite) {
        return false;
      }

      if (rule.minimumPlayCount > 0 &&
          playCountForTrack(track.id) < rule.minimumPlayCount) {
        return false;
      }

      return normalizedQuery.isEmpty ||
          _trackMatchesQuery(track, normalizedQuery);
    }).toList(growable: false);

    _sortCustomSmartPlaylistTracks(tracks, rule.sortMode);

    return tracks.take(rule.limit).toList(growable: false);
  }

  TrackRadioSeedQueue? radioQueueForTrack(String seedTrackId, {int limit = 50}) {
    if (limit <= 0) {
      return null;
    }

    final seedIndex = _tracks.indexWhere((track) => track.id == seedTrackId);
    if (seedIndex == -1) {
      return null;
    }

    final seedTrack = _tracks[seedIndex];
    if (!seedTrack.isPlayable) {
      return null;
    }

    final candidates = <_TrackRadioCandidate>[];
    for (final track in _tracks) {
      if (track.id == seedTrack.id || !track.isPlayable) {
        continue;
      }

      final score = _radioScoreForTrack(seedTrack, track);
      if (score <= 0) {
        continue;
      }

      candidates.add(
        _TrackRadioCandidate(
          track: track,
          score: score,
          lastPlayedAt: lastPlayedAt(track.id),
        ),
      );
    }

    candidates.sort(_compareTrackRadioCandidates);

    return TrackRadioSeedQueue(
      seedTrack: seedTrack,
      tracks: <Track>[
        seedTrack,
        ...candidates
            .map((candidate) => candidate.track)
            .take(limit - 1),
      ],
    );
  }

  LibraryStatsSummary libraryStats({
    int limit = 5,
    DateTime? from,
    DateTime? to,
  }) {
    final normalizedLimit = limit < 0 ? 0 : limit;
    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };
    final trackPlayCounts = <String, int>{};
    final trackListeningDurations = <String, Duration>{};
    final trackLastPlayed = <String, DateTime>{};
    final artistGroups = <String, _MutableLibraryStatsGroup>{};
    final albumGroups = <String, _MutableLibraryStatsGroup>{};
    final genreGroups = <String, _MutableLibraryStatsGroup>{};
    var playbackCount = 0;
    var estimatedListeningDuration = Duration.zero;

    void addGroupPlay(
      Map<String, _MutableLibraryStatsGroup> groups,
      String label,
      Track track,
      DateTime playedAt,
    ) {
      final normalizedLabel = _nonEmptyMetadata(label, 'Unknown');
      final key = normalizedLabel.toLowerCase();
      groups
          .putIfAbsent(
            key,
            () => _MutableLibraryStatsGroup(label: normalizedLabel),
          )
          .add(track, playedAt);
    }

    for (final entry in _history) {
      if (!_historyEntryInRange(entry, from: from, to: to)) {
        continue;
      }

      final track = byId[entry.trackId];
      if (track == null) {
        continue;
      }

      playbackCount += 1;
      trackPlayCounts[track.id] = (trackPlayCounts[track.id] ?? 0) + 1;
      trackListeningDurations[track.id] =
          (trackListeningDurations[track.id] ?? Duration.zero) +
              track.duration;
      final currentLastPlayed = trackLastPlayed[track.id];
      if (currentLastPlayed == null ||
          entry.playedAt.isAfter(currentLastPlayed)) {
        trackLastPlayed[track.id] = entry.playedAt;
      }
      estimatedListeningDuration += track.duration;
      addGroupPlay(artistGroups, track.artist, track, entry.playedAt);
      addGroupPlay(albumGroups, track.album, track, entry.playedAt);
      addGroupPlay(genreGroups, track.genre, track, entry.playedAt);
    }

    final topTracks = trackPlayCounts.entries.map((entry) {
      return LibraryStatsTrack(
        track: byId[entry.key]!,
        playCount: entry.value,
        estimatedListeningDuration:
            trackListeningDurations[entry.key] ?? Duration.zero,
        lastPlayedAt: trackLastPlayed[entry.key],
      );
    }).toList(growable: false);
    topTracks.sort(_compareLibraryStatsTrack);

    final libraryDuration = _tracks.fold<Duration>(
      Duration.zero,
      (total, track) => total + track.duration,
    );

    return LibraryStatsSummary(
      from: from,
      to: to,
      trackCount: _tracks.length,
      libraryDuration: libraryDuration,
      favoriteTrackCount: favorites.length,
      playbackCount: playbackCount,
      uniquePlayedTrackCount: trackPlayCounts.length,
      estimatedListeningDuration: estimatedListeningDuration,
      topTracks: topTracks.take(normalizedLimit).toList(growable: false),
      topArtists: _topLibraryStatsGroups(artistGroups, normalizedLimit),
      topAlbums: _topLibraryStatsGroups(albumGroups, normalizedLimit),
      topGenres: _topLibraryStatsGroups(genreGroups, normalizedLimit),
    );
  }

  String exportLibraryStatsDocument({
    required LibraryStatsExportFormat format,
    int limit = 25,
    DateTime? from,
    DateTime? to,
  }) {
    switch (format) {
      case LibraryStatsExportFormat.json:
        return exportLibraryStatsJson(limit: limit, from: from, to: to);
      case LibraryStatsExportFormat.csv:
        return exportLibraryStatsCsv(limit: limit, from: from, to: to);
    }
  }

  String exportLibraryStatsJson({
    int limit = 25,
    DateTime? from,
    DateTime? to,
  }) {
    final stats = libraryStats(limit: limit, from: from, to: to);
    const encoder = JsonEncoder.withIndent('  ');

    return encoder.convert(<String, Object?>{
      'type': 'aethertune.library_stats',
      'version': _libraryStatsDocumentVersion,
      'exportedAt': _clock().toIso8601String(),
      'from': stats.from?.toIso8601String(),
      'to': stats.to?.toIso8601String(),
      'summary': _libraryStatsSummaryToJson(stats),
      'topTracks': stats.topTracks.map(_libraryStatsTrackToJson).toList(),
      'topArtists': stats.topArtists.map(_libraryStatsGroupToJson).toList(),
      'topAlbums': stats.topAlbums.map(_libraryStatsGroupToJson).toList(),
      'topGenres': stats.topGenres.map(_libraryStatsGroupToJson).toList(),
    });
  }

  String exportLibraryStatsCsv({
    int limit = 25,
    DateTime? from,
    DateTime? to,
  }) {
    final stats = libraryStats(limit: limit, from: from, to: to);
    final buffer = StringBuffer()
      ..writeln(
        <String>[
          'section',
          'label',
          'value',
          'trackId',
          'title',
          'artist',
          'album',
          'genre',
          'playCount',
          'trackCount',
          'estimatedListeningMs',
          'lastPlayedAt',
        ].map(_escapeCsvField).join(','),
      );

    void writeRow({
      required String section,
      required String label,
      String value = '',
      String trackId = '',
      String title = '',
      String artist = '',
      String album = '',
      String genre = '',
      String playCount = '',
      String trackCount = '',
      String estimatedListeningMs = '',
      String lastPlayedAt = '',
    }) {
      buffer.writeln(
        <String>[
          section,
          label,
          value,
          trackId,
          title,
          artist,
          album,
          genre,
          playCount,
          trackCount,
          estimatedListeningMs,
          lastPlayedAt,
        ].map(_escapeCsvField).join(','),
      );
    }

    writeRow(
      section: 'range',
      label: 'from',
      value: stats.from?.toIso8601String() ?? '',
    );
    writeRow(
      section: 'range',
      label: 'to',
      value: stats.to?.toIso8601String() ?? '',
    );
    writeRow(
      section: 'summary',
      label: 'trackCount',
      value: stats.trackCount.toString(),
    );
    writeRow(
      section: 'summary',
      label: 'libraryDurationMs',
      value: stats.libraryDuration.inMilliseconds.toString(),
    );
    writeRow(
      section: 'summary',
      label: 'favoriteTrackCount',
      value: stats.favoriteTrackCount.toString(),
    );
    writeRow(
      section: 'summary',
      label: 'playbackCount',
      value: stats.playbackCount.toString(),
    );
    writeRow(
      section: 'summary',
      label: 'uniquePlayedTrackCount',
      value: stats.uniquePlayedTrackCount.toString(),
    );
    writeRow(
      section: 'summary',
      label: 'estimatedListeningMs',
      value: stats.estimatedListeningDuration.inMilliseconds.toString(),
    );

    for (final trackStats in stats.topTracks) {
      writeRow(
        section: 'top_track',
        label: trackStats.track.title,
        trackId: trackStats.track.id,
        title: trackStats.track.title,
        artist: trackStats.track.artist,
        album: trackStats.track.album,
        genre: trackStats.track.genre,
        playCount: trackStats.playCount.toString(),
        trackCount: '1',
        estimatedListeningMs:
            trackStats.estimatedListeningDuration.inMilliseconds.toString(),
        lastPlayedAt: trackStats.lastPlayedAt?.toIso8601String() ?? '',
      );
    }

    void writeGroupRows(String section, List<LibraryStatsGroup> groups) {
      for (final group in groups) {
        writeRow(
          section: section,
          label: group.label,
          playCount: group.playCount.toString(),
          trackCount: group.trackCount.toString(),
          estimatedListeningMs:
              group.estimatedListeningDuration.inMilliseconds.toString(),
          lastPlayedAt: group.lastPlayedAt?.toIso8601String() ?? '',
        );
      }
    }

    writeGroupRows('top_artist', stats.topArtists);
    writeGroupRows('top_album', stats.topAlbums);
    writeGroupRows('top_genre', stats.topGenres);

    return buffer.toString();
  }

  String exportBackupJson() {
    const encoder = JsonEncoder.withIndent('  ');

    return encoder.convert(<String, Object?>{
      'version': _backupVersion,
      'exportedAt': _clock().toIso8601String(),
      'offlineModeEnabled': _offlineModeEnabled,
      'themePreference': _themePreference.name,
      'tracks': _tracks.map((track) => track.toJson()).toList(),
      'playlists': _playlists.map((playlist) => playlist.toJson()).toList(),
      'customSmartPlaylists':
          _customSmartPlaylists.map((rule) => rule.toJson()).toList(),
      'podcastSubscriptions':
          _podcastSubscriptions.map((item) => item.toJson()).toList(),
      'history': _history.map((entry) => entry.toJson()).toList(),
      'searchQueryHistory': _searchQueryHistory,
      'progress':
          _progressByTrackId.values.map((entry) => entry.toJson()).toList(),
      'lyrics': _lyricsByTrackId.values
          .map((lyrics) => lyrics.toJson())
          .toList(),
      'offlineCacheQueue':
          _offlineCacheQueue.map((entry) => entry.toJson()).toList(),
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
    final artworkUri = _parseOptionalUri(playlistData['artworkUri'] as String?);
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
      artworkUri: artworkUri,
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
    final restoredCustomSmartPlaylists = <CustomSmartPlaylist>[];
    final restoredPodcastSubscriptions = <PodcastSubscription>[];
    final restoredHistory = <PlaybackHistoryEntry>[];
    final restoredSearchQueryHistory = <String>[];
    final restoredProgress = <PlaybackProgressEntry>[];
    final restoredLyrics = <TrackLyrics>[];
    final restoredOfflineCacheQueue = <OfflineCacheEntry>[];
    var restoredOfflineModeEnabled = false;
    var restoredThemePreference = AppThemePreference.system;

    try {
      restoredOfflineModeEnabled = _jsonBool(
        backup,
        'offlineModeEnabled',
        isRequired: false,
      );
      restoredThemePreference = _appThemePreferenceFromName(
        _jsonOptionalString(backup, 'themePreference'),
      );
      restoredTracks.addAll(
        _jsonObjectList(backup, 'tracks').map(Track.fromJson),
      );
      restoredPlaylists.addAll(
        _jsonObjectList(backup, 'playlists').map(Playlist.fromJson),
      );
      restoredCustomSmartPlaylists.addAll(
        _jsonObjectList(
          backup,
          'customSmartPlaylists',
          isRequired: false,
        ).map(CustomSmartPlaylist.fromJson),
      );
      restoredHistory.addAll(
        _jsonObjectList(backup, 'history', isRequired: false).map(
          PlaybackHistoryEntry.fromJson,
        ),
      );
      restoredSearchQueryHistory.addAll(
        _jsonStringList(backup, 'searchQueryHistory', isRequired: false),
      );
      restoredPodcastSubscriptions.addAll(
        _jsonObjectList(
          backup,
          'podcastSubscriptions',
          isRequired: false,
        ).map(PodcastSubscription.fromJson),
      );
      restoredProgress.addAll(
        _jsonObjectList(backup, 'progress', isRequired: false).map(
          PlaybackProgressEntry.fromJson,
        ),
      );
      restoredLyrics.addAll(
        _jsonObjectList(backup, 'lyrics').map(TrackLyrics.fromJson),
      );
      restoredOfflineCacheQueue.addAll(
        _jsonObjectList(
          backup,
          'offlineCacheQueue',
          isRequired: false,
        ).map(OfflineCacheEntry.fromJson),
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
    final sanitizedProgress = <String, PlaybackProgressEntry>{
      for (final entry in restoredProgress)
        if (knownTrackIds.contains(entry.trackId) &&
            entry.position >= _minSavedProgress)
          entry.trackId: entry,
    };
    final sanitizedSearchQueryHistory = _dedupeSearchQueryHistory(
      restoredSearchQueryHistory,
    );
    final sanitizedPodcastSubscriptions = _dedupePodcastSubscriptions(
      restoredPodcastSubscriptions,
    );
    final sanitizedCustomSmartPlaylists = _dedupeCustomSmartPlaylists(
      restoredCustomSmartPlaylists,
    );

    _tracks
      ..clear()
      ..addAll(uniqueTracks.values);
    _playlists
      ..clear()
      ..addAll(sanitizedPlaylists);
    _customSmartPlaylists
      ..clear()
      ..addAll(sanitizedCustomSmartPlaylists);
    _podcastSubscriptions
      ..clear()
      ..addAll(sanitizedPodcastSubscriptions);
    _history
      ..clear()
      ..addAll(sanitizedHistory);
    _searchQueryHistory
      ..clear()
      ..addAll(sanitizedSearchQueryHistory);
    _progressByTrackId
      ..clear()
      ..addAll(sanitizedProgress);
    _lyricsByTrackId
      ..clear()
      ..addAll(sanitizedLyrics);
    _offlineCacheQueue
      ..clear()
      ..addAll(_dedupeOfflineCacheQueue(restoredOfflineCacheQueue));
    _offlineModeEnabled = restoredOfflineModeEnabled;
    _themePreference = restoredThemePreference;

    _sortTracks();
    _sortPlaylists();
    _sortCustomSmartPlaylists();
    _sortPodcastSubscriptions();
    _sortHistory();
    _sortOfflineCacheQueue();
    _trimHistory();
    _trimSearchQueryHistory();
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

  List<Track> recentlyPlayedTracks({
    int limit = 25,
    DateTime? from,
    DateTime? to,
  }) {
    if (limit <= 0) {
      return <Track>[];
    }

    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };
    final seen = <String>{};
    final recentTracks = <Track>[];

    for (final entry in _history) {
      if (!_historyEntryInRange(entry, from: from, to: to)) {
        continue;
      }

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

  List<Track> _continueListeningTracks({required int limit}) {
    if (limit <= 0) {
      return <Track>[];
    }

    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };
    final entries = _progressByTrackId.values.toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return entries
        .map((entry) => byId[entry.trackId])
        .whereType<Track>()
        .take(limit)
        .toList(growable: false);
  }

  List<Track> _homeRadioSeedTracks({required int limit}) {
    if (limit <= 0) {
      return <Track>[];
    }

    final candidates = _tracks.where((track) {
      if (!track.isPlayable) {
        return false;
      }

      final queue = radioQueueForTrack(track.id, limit: 2);
      return queue != null && queue.tracks.length > 1;
    }).toList(growable: false);

    candidates.sort(_compareHomeRadioSeedTracks);

    return candidates.take(limit).toList(growable: false);
  }

  List<Track> _uniqueTracks(Iterable<Track> tracks) {
    final seen = <String>{};
    final unique = <Track>[];
    for (final track in tracks) {
      if (seen.add(track.id)) {
        unique.add(track);
      }
    }

    return unique;
  }

  int playCountForTrack(String trackId, {DateTime? from, DateTime? to}) {
    return _history
        .where(
          (entry) =>
              entry.trackId == trackId &&
              _historyEntryInRange(entry, from: from, to: to),
        )
        .length;
  }

  DateTime? lastPlayedAt(String trackId, {DateTime? from, DateTime? to}) {
    for (final entry in _history) {
      if (entry.trackId == trackId &&
          _historyEntryInRange(entry, from: from, to: to)) {
        return entry.playedAt;
      }
    }

    return null;
  }

  bool _historyEntryInRange(
    PlaybackHistoryEntry entry, {
    DateTime? from,
    DateTime? to,
  }) {
    if (from != null && entry.playedAt.isBefore(from)) {
      return false;
    }

    if (to != null && !entry.playedAt.isBefore(to)) {
      return false;
    }

    return true;
  }

  DateTime? _libraryChartRangeStart(LibraryChartRange range, DateTime now) {
    switch (range) {
      case LibraryChartRange.allTime:
        return null;
      case LibraryChartRange.sevenDays:
        return now.subtract(const Duration(days: 7));
      case LibraryChartRange.thirtyDays:
        return now.subtract(const Duration(days: 30));
      case LibraryChartRange.year:
        return now.subtract(const Duration(days: 365));
    }
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

  PlaybackProgressEntry? playbackProgressForTrack(String trackId) {
    return _progressByTrackId[trackId];
  }

  Future<void> recordPlaybackProgress(
    String trackId,
    Duration position,
    Duration duration,
  ) async {
    if (!_tracks.any((track) => track.id == trackId)) {
      return;
    }

    if (_shouldClearProgress(position, duration)) {
      await clearPlaybackProgress(trackId);
      return;
    }

    _progressByTrackId[trackId] = PlaybackProgressEntry(
      trackId: trackId,
      position: position,
      duration: duration,
      updatedAt: _clock(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> clearPlaybackProgress(String trackId) async {
    if (!_progressByTrackId.containsKey(trackId)) {
      return;
    }

    _progressByTrackId.remove(trackId);
    await _save();
    notifyListeners();
  }

  PodcastSubscription? podcastSubscriptionById(String id) {
    final index = _podcastSubscriptions.indexWhere(
      (subscription) => subscription.id == id,
    );
    if (index == -1) {
      return null;
    }

    return _podcastSubscriptions[index];
  }

  Future<PodcastSubscription> savePodcastSubscription(
    PodcastSubscription subscription,
  ) async {
    final normalizedFeedUrl = subscription.feedUrl.trim();
    if (normalizedFeedUrl.isEmpty) {
      throw ArgumentError.value(
        subscription.feedUrl,
        'feedUrl',
        'Podcast feed URL cannot be empty.',
      );
    }

    final savedId = stablePodcastSubscriptionId(normalizedFeedUrl);
    final index = _podcastSubscriptions.indexWhere(
      (existing) => existing.id == savedId,
    );
    final existing = index == -1 ? null : _podcastSubscriptions[index];
    final saved = PodcastSubscription(
      id: savedId,
      feedUrl: normalizedFeedUrl,
      title: subscription.title.trim().isEmpty
          ? 'Untitled podcast'
          : subscription.title.trim(),
      description: subscription.description.trim(),
      author: subscription.author.trim(),
      artworkUri: subscription.artworkUri,
      addedAt: subscription.addedAt == DateTime.fromMillisecondsSinceEpoch(0)
          ? existing?.addedAt ?? _clock()
          : subscription.addedAt,
      lastFetchedAt: subscription.lastFetchedAt ?? existing?.lastFetchedAt,
      lastFetchError: subscription.lastFetchError.trim().isEmpty
          ? existing?.lastFetchError ?? ''
          : subscription.lastFetchError.trim(),
    );
    if (index == -1) {
      _podcastSubscriptions.add(saved);
    } else {
      _podcastSubscriptions[index] = saved;
    }

    _sortPodcastSubscriptions();
    await _save();
    notifyListeners();

    return saved;
  }

  Future<PodcastSubscription?> markPodcastSubscriptionFetched(String id) async {
    final index = _podcastSubscriptions.indexWhere(
      (subscription) => subscription.id == id,
    );
    if (index == -1) {
      return null;
    }

    final updated = _podcastSubscriptions[index].copyWith(
      lastFetchedAt: _clock(),
      lastFetchError: '',
    );
    _podcastSubscriptions[index] = updated;
    await _save();
    notifyListeners();

    return updated;
  }

  Future<PodcastSubscription?> markPodcastSubscriptionFetchFailed(
    String id,
    Object error,
  ) async {
    final index = _podcastSubscriptions.indexWhere(
      (subscription) => subscription.id == id,
    );
    if (index == -1) {
      return null;
    }

    final updated = _podcastSubscriptions[index].copyWith(
      lastFetchError: error.toString(),
    );
    _podcastSubscriptions[index] = updated;
    await _save();
    notifyListeners();

    return updated;
  }

  Future<void> deletePodcastSubscription(String id) async {
    final index = _podcastSubscriptions.indexWhere(
      (subscription) => subscription.id == id,
    );
    if (index == -1) {
      return;
    }

    _podcastSubscriptions.removeAt(index);
    await _save();
    notifyListeners();
  }

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

  Future<CustomSmartPlaylist> createCustomSmartPlaylist({
    required String name,
    String query = '',
    bool favoritesOnly = false,
    int minimumPlayCount = 0,
    CustomSmartPlaylistSortMode sortMode =
        CustomSmartPlaylistSortMode.recentlyAdded,
    int limit = 50,
  }) async {
    final normalizedName = _normalizeCustomSmartPlaylistName(name);
    final now = _clock();
    final rule = CustomSmartPlaylist(
      id: _customSmartPlaylistId(normalizedName, now),
      name: normalizedName,
      query: query.trim(),
      favoritesOnly: favoritesOnly,
      minimumPlayCount: _sanitizeMinimumPlayCount(minimumPlayCount),
      sortMode: sortMode,
      limit: _sanitizeCustomSmartPlaylistLimit(limit),
      createdAt: now,
      updatedAt: now,
    );

    _customSmartPlaylists.add(rule);
    _sortCustomSmartPlaylists();
    await _save();
    notifyListeners();

    return rule;
  }

  Future<CustomSmartPlaylist?> updateCustomSmartPlaylist(
    String id, {
    required String name,
    required String query,
    required bool favoritesOnly,
    required int minimumPlayCount,
    required CustomSmartPlaylistSortMode sortMode,
    required int limit,
  }) async {
    final index = _customSmartPlaylists.indexWhere((rule) => rule.id == id);
    if (index == -1) {
      return null;
    }

    final updated = _customSmartPlaylists[index].copyWith(
      name: _normalizeCustomSmartPlaylistName(name),
      query: query.trim(),
      favoritesOnly: favoritesOnly,
      minimumPlayCount: _sanitizeMinimumPlayCount(minimumPlayCount),
      sortMode: sortMode,
      limit: _sanitizeCustomSmartPlaylistLimit(limit),
      updatedAt: _clock(),
    );
    _customSmartPlaylists[index] = updated;
    _sortCustomSmartPlaylists();
    await _save();
    notifyListeners();

    return updated;
  }

  Future<void> deleteCustomSmartPlaylist(String id) async {
    final index = _customSmartPlaylists.indexWhere((rule) => rule.id == id);
    if (index == -1) {
      return;
    }

    _customSmartPlaylists.removeAt(index);
    await _save();
    notifyListeners();
  }

  Future<Playlist> createPlaylist(
    String name, {
    Iterable<String> trackIds = const <String>[],
    Uri? artworkUri,
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
      artworkUri: artworkUri,
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

  Future<Playlist?> updatePlaylistArtwork(
    String playlistId,
    Uri? artworkUri,
  ) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) {
      return null;
    }

    final updated = _playlists[index].copyWith(
      artworkUri: artworkUri,
      clearArtworkUri: artworkUri == null,
      updatedAt: _clock(),
    );
    _playlists[index] = updated;
    _sortPlaylists();
    await _save();
    notifyListeners();

    return updated;
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

  Uri? _parseOptionalUri(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) {
      return null;
    }

    return uri;
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

  Map<String, Object?> _libraryStatsSummaryToJson(
    LibraryStatsSummary stats,
  ) {
    return <String, Object?>{
      'trackCount': stats.trackCount,
      'libraryDurationMs': stats.libraryDuration.inMilliseconds,
      'favoriteTrackCount': stats.favoriteTrackCount,
      'playbackCount': stats.playbackCount,
      'uniquePlayedTrackCount': stats.uniquePlayedTrackCount,
      'estimatedListeningMs':
          stats.estimatedListeningDuration.inMilliseconds,
    };
  }

  Map<String, Object?> _libraryStatsTrackToJson(
    LibraryStatsTrack trackStats,
  ) {
    return <String, Object?>{
      'trackId': trackStats.track.id,
      'title': trackStats.track.title,
      'artist': trackStats.track.artist,
      'album': trackStats.track.album,
      'genre': trackStats.track.genre,
      'playCount': trackStats.playCount,
      'estimatedListeningMs':
          trackStats.estimatedListeningDuration.inMilliseconds,
      'lastPlayedAt': trackStats.lastPlayedAt?.toIso8601String(),
    };
  }

  Map<String, Object?> _libraryStatsGroupToJson(
    LibraryStatsGroup group,
  ) {
    return <String, Object?>{
      'label': group.label,
      'playCount': group.playCount,
      'trackCount': group.trackCount,
      'estimatedListeningMs': group.estimatedListeningDuration.inMilliseconds,
      'lastPlayedAt': group.lastPlayedAt?.toIso8601String(),
    };
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

  void _rewritePlaylistDuplicateReferences(
    String keepTrackId,
    Set<String> removeIds,
  ) {
    for (var index = 0; index < _playlists.length; index += 1) {
      final playlist = _playlists[index];
      final trackIds = <String>[];
      for (final trackId in playlist.trackIds) {
        final mappedTrackId = removeIds.contains(trackId) ? keepTrackId : trackId;
        if (!trackIds.contains(mappedTrackId)) {
          trackIds.add(mappedTrackId);
        }
      }

      if (!_listEquals(playlist.trackIds, trackIds)) {
        _playlists[index] = playlist.copyWith(
          trackIds: trackIds,
          updatedAt: _clock(),
        );
      }
    }
  }

  void _rewriteHistoryDuplicateReferences(
    String keepTrackId,
    Set<String> removeIds,
  ) {
    for (var index = 0; index < _history.length; index += 1) {
      final entry = _history[index];
      if (removeIds.contains(entry.trackId)) {
        _history[index] = PlaybackHistoryEntry(
          trackId: keepTrackId,
          playedAt: entry.playedAt,
        );
      }
    }
  }

  void _mergeDuplicateProgress(String keepTrackId, Set<String> removeIds) {
    final candidates = <PlaybackProgressEntry>[
      if (_progressByTrackId[keepTrackId] != null)
        _progressByTrackId[keepTrackId]!,
      for (final trackId in removeIds)
        if (_progressByTrackId[trackId] != null) _progressByTrackId[trackId]!,
    ];

    for (final trackId in removeIds) {
      _progressByTrackId.remove(trackId);
    }

    if (candidates.isEmpty) {
      return;
    }

    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final latest = candidates.first;
    _progressByTrackId[keepTrackId] = PlaybackProgressEntry(
      trackId: keepTrackId,
      position: latest.position,
      duration: latest.duration,
      updatedAt: latest.updatedAt,
    );
  }

  void _mergeDuplicateLyrics(String keepTrackId, Set<String> removeIds) {
    final candidates = <TrackLyrics>[
      if (_lyricsByTrackId[keepTrackId] != null) _lyricsByTrackId[keepTrackId]!,
      for (final trackId in removeIds)
        if (_lyricsByTrackId[trackId] != null) _lyricsByTrackId[trackId]!,
    ].where((lyrics) => !lyrics.isEmpty).toList(growable: false);

    for (final trackId in removeIds) {
      _lyricsByTrackId.remove(trackId);
    }

    if (candidates.isEmpty) {
      return;
    }

    candidates.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _lyricsByTrackId[keepTrackId] = candidates.first.copyWith(
      trackId: keepTrackId,
    );
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }

    for (var index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) {
        return false;
      }
    }

    return true;
  }

  String _duplicateKeyPart(String value) {
    return value.trim().replaceAll('\\', '/').toLowerCase();
  }

  String? _duplicateMetadataKey(Track track) {
    final title = _duplicateKeyPart(track.title);
    if (title.isEmpty) {
      return null;
    }

    final artist = _duplicateKeyPart(track.artist);
    final album = _duplicateKeyPart(track.album);
    if (track.duration == Duration.zero) {
      return null;
    }

    return '$title|$artist|$album|${track.duration.inSeconds}';
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
    return <String>[
      track.title,
      track.artist,
      track.album,
      track.genre,
      _browseLabelForTrack(track, LibraryBrowseType.source),
      _browseLabelForTrack(track, LibraryBrowseType.folder),
    ].any((value) => value.toLowerCase().contains(normalizedQuery));
  }

  void _sortCustomSmartPlaylistTracks(
    List<Track> tracks,
    CustomSmartPlaylistSortMode sortMode,
  ) {
    tracks.sort((a, b) {
      switch (sortMode) {
        case CustomSmartPlaylistSortMode.recentlyAdded:
          return _compareByDateThenTitle(a, b);
        case CustomSmartPlaylistSortMode.title:
          return _compareText(a.title, b.title);
        case CustomSmartPlaylistSortMode.artist:
          final byArtist = _compareText(a.artist, b.artist);
          return byArtist == 0 ? _compareText(a.title, b.title) : byArtist;
        case CustomSmartPlaylistSortMode.album:
          final byAlbum = _compareText(a.album, b.album);
          return byAlbum == 0 ? _compareText(a.title, b.title) : byAlbum;
        case CustomSmartPlaylistSortMode.recentlyPlayed:
          return _compareByLastPlayedThenTitle(a, b);
        case CustomSmartPlaylistSortMode.mostPlayed:
          return _compareByPlayCountThenLastPlayed(a, b);
      }
    });
  }

  int _compareByLastPlayedThenTitle(Track a, Track b) {
    final aLastPlayed = lastPlayedAt(a.id);
    final bLastPlayed = lastPlayedAt(b.id);
    if (aLastPlayed != null && bLastPlayed != null) {
      final byLastPlayed = bLastPlayed.compareTo(aLastPlayed);
      if (byLastPlayed != 0) {
        return byLastPlayed;
      }
    } else if (aLastPlayed != null) {
      return -1;
    } else if (bLastPlayed != null) {
      return 1;
    }

    return _compareText(a.title, b.title);
  }

  int _compareByPlayCountThenLastPlayed(Track a, Track b) {
    final byPlayCount =
        playCountForTrack(b.id).compareTo(playCountForTrack(a.id));
    if (byPlayCount != 0) {
      return byPlayCount;
    }

    return _compareByLastPlayedThenTitle(a, b);
  }

  int _compareHomeRadioSeedTracks(Track a, Track b) {
    if (a.isFavorite != b.isFavorite) {
      return a.isFavorite ? -1 : 1;
    }

    final byPlayCount =
        playCountForTrack(b.id).compareTo(playCountForTrack(a.id));
    if (byPlayCount != 0) {
      return byPlayCount;
    }

    final byLastPlayed = _compareNullableDateDesc(
      lastPlayedAt(a.id),
      lastPlayedAt(b.id),
    );
    if (byLastPlayed != 0) {
      return byLastPlayed;
    }

    return _compareByDateThenTitle(a, b);
  }

  int _radioScoreForTrack(Track seedTrack, Track track) {
    var score = 0;
    if (_sameKnownMetadata(seedTrack.artist, track.artist)) {
      score += 100;
    }
    if (_sameKnownMetadata(seedTrack.genre, track.genre)) {
      score += 40;
    }
    if (_sameKnownMetadata(seedTrack.album, track.album)) {
      score += 20;
    }
    if (score == 0) {
      return 0;
    }

    if (track.isFavorite) {
      score += 10;
    }
    score += playCountForTrack(track.id) * 3;

    return score;
  }

  bool _sameKnownMetadata(String left, String right) {
    final normalizedLeft = left.trim().toLowerCase();
    final normalizedRight = right.trim().toLowerCase();
    if (normalizedLeft.isEmpty ||
        normalizedRight.isEmpty ||
        normalizedLeft == 'unknown' ||
        normalizedRight == 'unknown' ||
        normalizedLeft.startsWith('unknown ') ||
        normalizedRight.startsWith('unknown ')) {
      return false;
    }

    return normalizedLeft == normalizedRight;
  }

  int _compareTrackRadioCandidates(
    _TrackRadioCandidate a,
    _TrackRadioCandidate b,
  ) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }

    final byLastPlayed = _compareNullableDateDesc(
      a.lastPlayedAt,
      b.lastPlayedAt,
    );
    if (byLastPlayed != 0) {
      return byLastPlayed;
    }

    return _compareText(a.track.title, b.track.title);
  }

  int _compareLibraryStatsTrack(
    LibraryStatsTrack a,
    LibraryStatsTrack b,
  ) {
    final byPlayCount = b.playCount.compareTo(a.playCount);
    if (byPlayCount != 0) {
      return byPlayCount;
    }

    final byLastPlayed = _compareNullableDateDesc(
      a.lastPlayedAt,
      b.lastPlayedAt,
    );
    if (byLastPlayed != 0) {
      return byLastPlayed;
    }

    return _compareText(a.track.title, b.track.title);
  }

  int _compareLibraryStatsGroup(
    LibraryStatsGroup a,
    LibraryStatsGroup b,
  ) {
    final byPlayCount = b.playCount.compareTo(a.playCount);
    if (byPlayCount != 0) {
      return byPlayCount;
    }

    final byDuration =
        b.estimatedListeningDuration.compareTo(a.estimatedListeningDuration);
    if (byDuration != 0) {
      return byDuration;
    }

    final byLastPlayed = _compareNullableDateDesc(
      a.lastPlayedAt,
      b.lastPlayedAt,
    );
    if (byLastPlayed != 0) {
      return byLastPlayed;
    }

    return _compareText(a.label, b.label);
  }

  int _compareNullableDateDesc(DateTime? a, DateTime? b) {
    if (a != null && b != null) {
      return b.compareTo(a);
    }
    if (a != null) {
      return -1;
    }
    if (b != null) {
      return 1;
    }

    return 0;
  }

  List<LibraryStatsGroup> _topLibraryStatsGroups(
    Map<String, _MutableLibraryStatsGroup> groups,
    int limit,
  ) {
    if (limit <= 0) {
      return <LibraryStatsGroup>[];
    }

    final statsGroups = groups.values
        .map((group) => group.toLibraryStatsGroup())
        .toList(growable: false);
    statsGroups.sort(_compareLibraryStatsGroup);

    return statsGroups.take(limit).toList(growable: false);
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

  String _normalizeCustomSmartPlaylistName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Smart playlist name cannot be empty.',
      );
    }

    return normalized;
  }

  int _sanitizeMinimumPlayCount(int value) {
    if (value < 0) {
      return 0;
    }

    return value;
  }

  int _sanitizeCustomSmartPlaylistLimit(int value) {
    if (value <= 0) {
      return 50;
    }

    if (value > 500) {
      return 500;
    }

    return value;
  }

  void _sortCustomSmartPlaylists() {
    _customSmartPlaylists.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );
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

  void _removeMissingProgress() {
    final knownTrackIds = _tracks.map((track) => track.id).toSet();
    _progressByTrackId.removeWhere(
      (trackId, _) => !knownTrackIds.contains(trackId),
    );
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

  void _trimSearchQueryHistory() {
    if (_searchQueryHistory.length <= _maxSearchQueryHistoryEntries) {
      return;
    }

    _searchQueryHistory.removeRange(
      _maxSearchQueryHistoryEntries,
      _searchQueryHistory.length,
    );
  }

  bool _shouldClearProgress(Duration position, Duration duration) {
    if (position < _minSavedProgress) {
      return true;
    }
    if (duration == Duration.zero) {
      return false;
    }

    return duration - position <= _completedProgressThreshold;
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

  String _customSmartPlaylistId(String name, DateTime createdAt) {
    final base = 'smart-${createdAt.microsecondsSinceEpoch}-$name';
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

  List<String> _jsonStringList(
    Map<String, Object?> backup,
    String key, {
    bool isRequired = true,
  }) {
    final rawList = backup[key];
    if (rawList == null && !isRequired) {
      return <String>[];
    }

    if (rawList is! List) {
      throw FormatException('Backup field "$key" must be a list.');
    }

    return rawList.map((item) {
      if (item is! String) {
        throw FormatException('Backup field "$key" contains a non-string.');
      }

      return item;
    }).toList(growable: false);
  }

  String? _jsonOptionalString(Map<String, Object?> backup, String key) {
    final rawValue = backup[key];
    if (rawValue == null) {
      return null;
    }
    if (rawValue is! String) {
      throw FormatException('Backup field "$key" must be a string.');
    }

    return rawValue;
  }

  bool _jsonBool(
    Map<String, Object?> backup,
    String key, {
    bool isRequired = true,
  }) {
    final rawValue = backup[key];
    if (rawValue == null && !isRequired) {
      return false;
    }

    if (rawValue is! bool) {
      throw FormatException('Backup field "$key" must be a boolean.');
    }

    return rawValue;
  }

  List<String> _dedupeSearchQueryHistory(Iterable<String> queries) {
    final values = <String>[];
    final seen = <String>{};
    for (final query in queries) {
      final normalized = query.trim();
      if (normalized.isEmpty) {
        continue;
      }

      if (!seen.add(normalized.toLowerCase())) {
        continue;
      }

      values.add(normalized);
      if (values.length >= _maxSearchQueryHistoryEntries) {
        break;
      }
    }

    return values;
  }

  List<CustomSmartPlaylist> _dedupeCustomSmartPlaylists(
    Iterable<CustomSmartPlaylist> rules,
  ) {
    final byId = <String, CustomSmartPlaylist>{};
    for (final rule in rules) {
      final id = rule.id.trim();
      final name = rule.name.trim();
      if (id.isEmpty || name.isEmpty) {
        continue;
      }

      byId[id] = rule.copyWith(
        id: id,
        name: name,
        query: rule.query.trim(),
        minimumPlayCount: _sanitizeMinimumPlayCount(rule.minimumPlayCount),
        limit: _sanitizeCustomSmartPlaylistLimit(rule.limit),
      );
    }

    return byId.values.toList(growable: false);
  }

  List<PodcastSubscription> _dedupePodcastSubscriptions(
    Iterable<PodcastSubscription> subscriptions,
  ) {
    final byId = <String, PodcastSubscription>{};
    for (final subscription in subscriptions) {
      if (subscription.feedUrl.trim().isEmpty) {
        continue;
      }

      final id = stablePodcastSubscriptionId(subscription.feedUrl);
      byId[id] = PodcastSubscription(
        id: id,
        feedUrl: subscription.feedUrl.trim(),
        title: subscription.title,
        description: subscription.description,
        author: subscription.author,
        artworkUri: subscription.artworkUri,
        addedAt: subscription.addedAt,
        lastFetchedAt: subscription.lastFetchedAt,
        lastFetchError: subscription.lastFetchError,
      );
    }

    return byId.values.toList(growable: false);
  }

  void _sortPodcastSubscriptions() {
    _podcastSubscriptions.sort(
      (a, b) => _compareText(a.title, b.title),
    );
  }

  List<OfflineCacheEntry> _dedupeOfflineCacheQueue(
    Iterable<OfflineCacheEntry> entries,
  ) {
    final byId = <String, OfflineCacheEntry>{};
    for (final entry in entries) {
      final existing = byId[entry.id];
      if (existing == null || entry.updatedAt.isAfter(existing.updatedAt)) {
        byId[entry.id] = entry;
      }
    }

    return byId.values.toList(growable: false);
  }

  void _sortOfflineCacheQueue() {
    _offlineCacheQueue.sort((a, b) {
      final updatedComparison = b.updatedAt.compareTo(a.updatedAt);
      if (updatedComparison != 0) {
        return updatedComparison;
      }

      return _compareText(a.track.title, b.track.title);
    });
  }

  Future<OfflineCacheEntry?> _updateOfflineCacheEntry(
    String id, {
    Track? track,
    OfflineCacheEntryStatus? status,
    String? reason,
    bool upsertCachedTrack = false,
    bool addCachedTrackIfMissing = true,
  }) async {
    final index = _offlineCacheQueue.indexWhere((entry) => entry.id == id);
    if (index == -1) {
      return null;
    }

    final updated = _offlineCacheQueue[index].copyWith(
      track: track,
      status: status,
      updatedAt: _clock(),
      reason: reason,
    );
    _offlineCacheQueue[index] = updated;
    if (upsertCachedTrack && track != null) {
      _upsertOfflineCachedTrack(
        track,
        addIfMissing: addCachedTrackIfMissing,
      );
    }

    _sortOfflineCacheQueue();
    await _save();
    notifyListeners();

    return updated;
  }

  void _upsertOfflineCachedTrack(
    Track cachedTrack, {
    bool addIfMissing = true,
  }) {
    final index = _tracks.indexWhere((track) => track.id == cachedTrack.id);
    if (index == -1) {
      if (!addIfMissing) {
        return;
      }

      _tracks.add(
        cachedTrack.copyWith(
          addedAt: cachedTrack.addedAt == DateTime.fromMillisecondsSinceEpoch(0)
              ? _clock()
              : cachedTrack.addedAt,
        ),
      );
      _sortTracks();
      return;
    }

    final existing = _tracks[index];
    _tracks[index] = existing.copyWith(
      localPath: cachedTrack.localPath,
      streamUrl: cachedTrack.streamUrl,
      sourceId: cachedTrack.sourceId,
      externalId: cachedTrack.externalId,
    );
    _sortTracks();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final encodedTracks = jsonEncode(
      _tracks.map((track) => track.toJson()).toList(),
    );
    final encodedPlaylists = jsonEncode(
      _playlists.map((playlist) => playlist.toJson()).toList(),
    );
    final encodedCustomSmartPlaylists = jsonEncode(
      _customSmartPlaylists.map((rule) => rule.toJson()).toList(),
    );
    final encodedPodcastSubscriptions = jsonEncode(
      _podcastSubscriptions.map((item) => item.toJson()).toList(),
    );
    final encodedHistory = jsonEncode(
      _history.map((entry) => entry.toJson()).toList(),
    );
    final encodedSearchQueryHistory = jsonEncode(_searchQueryHistory);
    final encodedProgress = jsonEncode(
      _progressByTrackId.values.map((entry) => entry.toJson()).toList(),
    );
    final encodedLyrics = jsonEncode(
      _lyricsByTrackId.values.map((lyrics) => lyrics.toJson()).toList(),
    );
    final encodedOfflineCacheQueue = jsonEncode(
      _offlineCacheQueue.map((entry) => entry.toJson()).toList(),
    );
    await prefs.setString(_tracksKey, encodedTracks);
    await prefs.setString(_playlistsKey, encodedPlaylists);
    await prefs.setString(
      _customSmartPlaylistsKey,
      encodedCustomSmartPlaylists,
    );
    await prefs.setString(
      _podcastSubscriptionsKey,
      encodedPodcastSubscriptions,
    );
    await prefs.setString(_historyKey, encodedHistory);
    await prefs.setString(_searchQueryHistoryKey, encodedSearchQueryHistory);
    await prefs.setString(_progressKey, encodedProgress);
    await prefs.setString(_lyricsKey, encodedLyrics);
    await prefs.setBool(_offlineModeKey, _offlineModeEnabled);
    await prefs.setString(_themePreferenceKey, _themePreference.name);
    await prefs.setString(_offlineCacheQueueKey, encodedOfflineCacheQueue);
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

class _MutableDuplicateTrackGroup {
  _MutableDuplicateTrackGroup({
    required this.key,
    required this.type,
  });

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
