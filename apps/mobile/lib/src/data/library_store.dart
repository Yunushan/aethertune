import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/lyrics_document.dart';
import '../domain/music_source_provider.dart';
import '../domain/offline_cache_cancellation.dart';
import '../domain/offline_cache_entry.dart';
import '../domain/playback_history_entry.dart';
import '../domain/playback_speed.dart';
import '../domain/playback_progress_entry.dart';
import '../domain/playlist.dart';
import '../domain/podcast_subscription.dart';
import '../domain/search_matcher.dart';
import '../domain/track.dart';
import '../domain/track_chapter.dart';
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

enum DuplicateMatchType {
  localPath,
  contentHash,
  sourceExternalId,
  streamUrl,
  metadata,
}

enum SmartPlaylistType { favorites, recentlyAdded, recentlyPlayed, mostPlayed }

enum LibraryHomeSectionType {
  continueListening,
  recentlyPlayed,
  followedArtists,
  radioSeeds,
  mostPlayed,
  favorites,
  subscribedEpisodes,
  recentlyAdded,
}

enum LibraryChartRange { allTime, sevenDays, thirtyDays, year }

enum LibraryRecapPeriod { month, year }

enum ListeningHistoryRange { all, sevenDays, thirtyDays, year }

enum LibraryMoodMixType { focus, energy, chill, workout, sleep }

enum LibrarySimilarityReason { artist, album, genre, folder, source }

enum CustomSmartPlaylistSortMode {
  recentlyAdded,
  title,
  artist,
  album,
  recentlyPlayed,
  mostPlayed,
}

enum CustomSmartPlaylistMatchMode { all, any }

enum CustomSmartPlaylistRuleField {
  searchText,
  sourceId,
  artist,
  album,
  genre,
  minimumDurationSeconds,
  maximumDurationSeconds,
  favoritesOnly,
  minimumPlayCount,
  minimumDaysSinceLastPlayed,
}

enum AppThemePreference { system, light, dark, amoled }

enum AppAccentColor { indigo, teal, rose, amber, violet, green }

enum AppLanguagePreference { system, english, turkish, arabic }

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

extension AppAccentColorLabel on AppAccentColor {
  String get label {
    switch (this) {
      case AppAccentColor.indigo:
        return 'Indigo';
      case AppAccentColor.teal:
        return 'Teal';
      case AppAccentColor.rose:
        return 'Rose';
      case AppAccentColor.amber:
        return 'Amber';
      case AppAccentColor.violet:
        return 'Violet';
      case AppAccentColor.green:
        return 'Green';
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

class LibraryFolderNode {
  const LibraryFolderNode({
    required this.key,
    required this.path,
    required this.label,
    required this.depth,
    required this.trackCount,
    required this.directTrackCount,
    required this.totalDuration,
    required this.childCount,
  });

  final String key;
  final String path;
  final String label;
  final int depth;
  final int trackCount;
  final int directTrackCount;
  final Duration totalDuration;
  final int childCount;
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

class LibraryMoodMix {
  const LibraryMoodMix({
    required this.type,
    required this.name,
    required this.description,
    required this.tracks,
  });

  final LibraryMoodMixType type;
  final String name;
  final String description;
  final List<Track> tracks;
}

class SimilarTrackMatch {
  const SimilarTrackMatch({
    required this.track,
    required this.reasons,
    required this.score,
  });

  final Track track;
  final List<LibrarySimilarityReason> reasons;
  final int score;
}

class CustomSmartPlaylistRule {
  const CustomSmartPlaylistRule({required this.field, required this.value});

  final CustomSmartPlaylistRuleField field;
  final String value;

  bool get isActive {
    final normalized = value.trim();
    return switch (field) {
      CustomSmartPlaylistRuleField.favoritesOnly => normalized == 'true',
      CustomSmartPlaylistRuleField.minimumDurationSeconds ||
      CustomSmartPlaylistRuleField.maximumDurationSeconds ||
      CustomSmartPlaylistRuleField.minimumPlayCount ||
      CustomSmartPlaylistRuleField.minimumDaysSinceLastPlayed =>
        (int.tryParse(normalized) ?? 0) > 0,
      _ => normalized.isNotEmpty,
    };
  }

  CustomSmartPlaylistRule? normalized() {
    final normalizedValue = value.trim();
    if (field == CustomSmartPlaylistRuleField.favoritesOnly) {
      return normalizedValue == 'true'
          ? const CustomSmartPlaylistRule(
              field: CustomSmartPlaylistRuleField.favoritesOnly,
              value: 'true',
            )
          : null;
    }
    if (field == CustomSmartPlaylistRuleField.minimumDurationSeconds ||
        field == CustomSmartPlaylistRuleField.maximumDurationSeconds ||
        field == CustomSmartPlaylistRuleField.minimumPlayCount ||
        field == CustomSmartPlaylistRuleField.minimumDaysSinceLastPlayed) {
      final value = int.tryParse(normalizedValue) ?? 0;
      return value > 0
          ? CustomSmartPlaylistRule(field: field, value: value.toString())
          : null;
    }
    return normalizedValue.isEmpty
        ? null
        : CustomSmartPlaylistRule(field: field, value: normalizedValue);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'field': field.name,
        'value': value,
      };

  static CustomSmartPlaylistRule? tryFromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final fieldName = raw['field'];
    final value = raw['value'];
    if (fieldName is! String || value is! String) {
      return null;
    }
    final field = CustomSmartPlaylistRuleField.values.firstWhere(
      (candidate) => candidate.name == fieldName,
      orElse: () => CustomSmartPlaylistRuleField.searchText,
    );
    if (!CustomSmartPlaylistRuleField.values.any(
      (candidate) => candidate.name == fieldName,
    )) {
      return null;
    }
    return CustomSmartPlaylistRule(field: field, value: value).normalized();
  }
}

class CustomSmartPlaylistRuleGroup {
  CustomSmartPlaylistRuleGroup({
    this.matchMode = CustomSmartPlaylistMatchMode.all,
    List<CustomSmartPlaylistRule> rules = const <CustomSmartPlaylistRule>[],
    List<CustomSmartPlaylistRuleGroup> groups =
        const <CustomSmartPlaylistRuleGroup>[],
  })  : rules = List.unmodifiable(rules),
        groups = List.unmodifiable(groups);

  final CustomSmartPlaylistMatchMode matchMode;
  final List<CustomSmartPlaylistRule> rules;
  final List<CustomSmartPlaylistRuleGroup> groups;

  bool get isEmpty => rules.isEmpty && groups.isEmpty;

  CustomSmartPlaylistRuleGroup? normalized({int depth = 0}) {
    if (depth >= 8) {
      return null;
    }
    final normalizedRules = rules
        .map((rule) => rule.normalized())
        .whereType<CustomSmartPlaylistRule>()
        .take(50)
        .toList(growable: false);
    final normalizedGroups = groups
        .map((group) => group.normalized(depth: depth + 1))
        .whereType<CustomSmartPlaylistRuleGroup>()
        .take(25)
        .toList(growable: false);
    if (normalizedRules.isEmpty && normalizedGroups.isEmpty) {
      return null;
    }
    return CustomSmartPlaylistRuleGroup(
      matchMode: matchMode,
      rules: normalizedRules,
      groups: normalizedGroups,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'matchMode': matchMode.name,
        'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
        'groups': groups.map((group) => group.toJson()).toList(growable: false),
      };

  static CustomSmartPlaylistRuleGroup? tryFromJson(
    Object? raw, {
    int depth = 0,
  }) {
    if (raw is! Map || depth >= 8) {
      return null;
    }
    final modeName = raw['matchMode'];
    final matchMode = _customSmartPlaylistMatchModeFromName(
      modeName is String ? modeName : null,
    );
    final rawRules = raw['rules'];
    final rawGroups = raw['groups'];
    final rules = rawRules is List
        ? rawRules
            .map(CustomSmartPlaylistRule.tryFromJson)
            .whereType<CustomSmartPlaylistRule>()
            .take(50)
            .toList(growable: false)
        : const <CustomSmartPlaylistRule>[];
    final groups = rawGroups is List
        ? rawGroups
            .map(
              (group) => CustomSmartPlaylistRuleGroup.tryFromJson(
                group,
                depth: depth + 1,
              ),
            )
            .whereType<CustomSmartPlaylistRuleGroup>()
            .take(25)
            .toList(growable: false)
        : const <CustomSmartPlaylistRuleGroup>[];
    return CustomSmartPlaylistRuleGroup(
      matchMode: matchMode,
      rules: rules,
      groups: groups,
    ).normalized(depth: depth);
  }
}

class CustomSmartPlaylist {
  CustomSmartPlaylist({
    required this.id,
    required this.name,
    this.query = '',
    this.sourceId = '',
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.minimumDurationSeconds = 0,
    this.maximumDurationSeconds = 0,
    this.favoritesOnly = false,
    this.minimumPlayCount = 0,
    this.minimumDaysSinceLastPlayed = 0,
    this.matchMode = CustomSmartPlaylistMatchMode.all,
    this.ruleGroups = const <CustomSmartPlaylistRuleGroup>[],
    this.artworkUri,
    this.sortMode = CustomSmartPlaylistSortMode.recentlyAdded,
    this.limit = 50,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final String query;
  final String sourceId;
  final String artist;
  final String album;
  final String genre;
  final int minimumDurationSeconds;
  final int maximumDurationSeconds;
  final bool favoritesOnly;
  final int minimumPlayCount;
  final int minimumDaysSinceLastPlayed;
  final CustomSmartPlaylistMatchMode matchMode;
  final List<CustomSmartPlaylistRuleGroup> ruleGroups;
  final Uri? artworkUri;
  final CustomSmartPlaylistSortMode sortMode;
  final int limit;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomSmartPlaylist copyWith({
    String? id,
    String? name,
    String? query,
    String? sourceId,
    String? artist,
    String? album,
    String? genre,
    int? minimumDurationSeconds,
    int? maximumDurationSeconds,
    bool? favoritesOnly,
    int? minimumPlayCount,
    int? minimumDaysSinceLastPlayed,
    CustomSmartPlaylistMatchMode? matchMode,
    List<CustomSmartPlaylistRuleGroup>? ruleGroups,
    Uri? artworkUri,
    bool clearArtworkUri = false,
    CustomSmartPlaylistSortMode? sortMode,
    int? limit,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CustomSmartPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      query: query ?? this.query,
      sourceId: sourceId ?? this.sourceId,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      genre: genre ?? this.genre,
      minimumDurationSeconds:
          minimumDurationSeconds ?? this.minimumDurationSeconds,
      maximumDurationSeconds:
          maximumDurationSeconds ?? this.maximumDurationSeconds,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      minimumPlayCount: minimumPlayCount ?? this.minimumPlayCount,
      minimumDaysSinceLastPlayed:
          minimumDaysSinceLastPlayed ?? this.minimumDaysSinceLastPlayed,
      matchMode: matchMode ?? this.matchMode,
      ruleGroups: ruleGroups ?? this.ruleGroups,
      artworkUri: clearArtworkUri ? null : artworkUri ?? this.artworkUri,
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
      'sourceId': sourceId,
      'artist': artist,
      'album': album,
      'genre': genre,
      'minimumDurationSeconds': minimumDurationSeconds,
      'maximumDurationSeconds': maximumDurationSeconds,
      'favoritesOnly': favoritesOnly,
      'minimumPlayCount': minimumPlayCount,
      'minimumDaysSinceLastPlayed': minimumDaysSinceLastPlayed,
      'matchMode': matchMode.name,
      'ruleGroups': ruleGroups.map((group) => group.toJson()).toList(),
      'artworkUri': artworkUri?.toString(),
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
      sourceId: json['sourceId'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      genre: json['genre'] as String? ?? '',
      minimumDurationSeconds: json['minimumDurationSeconds'] as int? ?? 0,
      maximumDurationSeconds: json['maximumDurationSeconds'] as int? ?? 0,
      favoritesOnly: json['favoritesOnly'] as bool? ?? false,
      minimumPlayCount: json['minimumPlayCount'] as int? ?? 0,
      minimumDaysSinceLastPlayed:
          json['minimumDaysSinceLastPlayed'] as int? ?? 0,
      matchMode: _customSmartPlaylistMatchModeFromName(
        json['matchMode'] as String?,
      ),
      ruleGroups: _ruleGroupsFromJson(json['ruleGroups']),
      artworkUri: _parseArtworkUri(json['artworkUri']),
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

  static List<CustomSmartPlaylistRuleGroup> _ruleGroupsFromJson(
    Object? raw,
  ) {
    if (raw is! List) {
      return const <CustomSmartPlaylistRuleGroup>[];
    }
    return raw
        .map(CustomSmartPlaylistRuleGroup.tryFromJson)
        .whereType<CustomSmartPlaylistRuleGroup>()
        .toList(growable: false);
  }

  static Uri? _parseArtworkUri(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return Uri.tryParse(raw.trim());
  }
}

class SavedHistoryView {
  SavedHistoryView({
    required this.id,
    required this.name,
    this.query = '',
    this.range = ListeningHistoryRange.all,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final String query;
  final ListeningHistoryRange range;
  final DateTime createdAt;
  final DateTime updatedAt;

  SavedHistoryView copyWith({
    String? id,
    String? name,
    String? query,
    ListeningHistoryRange? range,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SavedHistoryView(
      id: id ?? this.id,
      name: name ?? this.name,
      query: query ?? this.query,
      range: range ?? this.range,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'query': query,
      'range': range.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory SavedHistoryView.fromJson(Map<String, Object?> json) {
    return SavedHistoryView(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled history view',
      query: json['query'] as String? ?? '',
      range: _listeningHistoryRangeFromName(json['range'] as String?),
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

class LibraryListeningRecap {
  const LibraryListeningRecap({
    required this.period,
    required this.start,
    required this.end,
    required this.stats,
  });

  final LibraryRecapPeriod period;
  final DateTime start;
  final DateTime end;
  final LibraryStatsSummary stats;
}

class LibraryListeningHeatmapDay {
  const LibraryListeningHeatmapDay({
    required this.day,
    required this.playbackCount,
    required this.estimatedListeningDuration,
  });

  final DateTime day;
  final int playbackCount;
  final Duration estimatedListeningDuration;
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

final class _DiscoveryCandidate {
  const _DiscoveryCandidate({
    required this.track,
    required this.score,
    required this.playCount,
    this.lastPlayedAt,
  });

  final Track track;
  final int score;
  final int playCount;
  final DateTime? lastPlayedAt;
}

final class _SimilarityCandidate {
  const _SimilarityCandidate({
    required this.track,
    required this.score,
    required this.reasons,
    required this.playCount,
    this.lastPlayedAt,
  });

  final Track track;
  final int score;
  final List<LibrarySimilarityReason> reasons;
  final int playCount;
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

ListeningHistoryRange _listeningHistoryRangeFromName(String? value) {
  return ListeningHistoryRange.values.firstWhere(
    (range) => range.name == value,
    orElse: () => ListeningHistoryRange.all,
  );
}

AppThemePreference _appThemePreferenceFromName(String? value) {
  return AppThemePreference.values.firstWhere(
    (preference) => preference.name == value,
    orElse: () => AppThemePreference.system,
  );
}

AppAccentColor _appAccentColorFromName(String? value) {
  return AppAccentColor.values.firstWhere(
    (accent) => accent.name == value,
    orElse: () => AppAccentColor.indigo,
  );
}

CustomSmartPlaylistMatchMode _customSmartPlaylistMatchModeFromName(
  String? value,
) {
  return CustomSmartPlaylistMatchMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => CustomSmartPlaylistMatchMode.all,
  );
}

AppLanguagePreference _appLanguagePreferenceFromName(String? value) {
  return AppLanguagePreference.values.firstWhere(
    (preference) => preference.name == value,
    orElse: () => AppLanguagePreference.system,
  );
}

class LibraryStore extends ChangeNotifier {
  LibraryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _backupVersion = 1;
  static const _syncSnapshotVersion = 1;
  static const _playlistDocumentVersion = 1;
  static const _libraryStatsDocumentVersion = 1;
  static const _tracksKey = 'aethertune.tracks.v1';
  static const _playlistsKey = 'aethertune.playlists.v1';
  static const _customSmartPlaylistsKey =
      'aethertune.custom_smart_playlists.v1';
  static const _savedHistoryViewsKey = 'aethertune.saved_history_views.v1';
  static const _podcastSubscriptionsKey =
      'aethertune.podcast_subscriptions.v1';
  static const _followedArtistsKey = 'aethertune.followed_artists.v1';
  static const _lyricsKey = 'aethertune.lyrics.v1';
  static const _historyKey = 'aethertune.playback_history.v1';
  static const _progressKey = 'aethertune.playback_progress.v1';
  static const _searchQueryHistoryKey = 'aethertune.search_query_history.v1';
  static const _pauseListeningHistoryKey =
      'aethertune.pause_listening_history.v1';
  static const _offlineModeKey = 'aethertune.offline_mode.v1';
  static const _automaticOfflineQueueKey =
      'aethertune.automatic_offline_queue.v1';
  static const _themePreferenceKey = 'aethertune.theme_preference.v1';
  static const _accentColorKey = 'aethertune.accent_color.v1';
  static const _languagePreferenceKey = 'aethertune.language_preference.v1';
  static const _trackPlaybackSpeedOverridesKey =
      'aethertune.track_playback_speed_overrides.v1';
  static const _desktopQueuePaneWidthKey =
      'aethertune.desktop_queue_pane_width.v1';
  static const _onboardingCompletedKey =
      'aethertune.onboarding_completed.v1';
  static const _offlineCacheQueueKey = 'aethertune.offline_cache_queue.v1';
  static const _offlineCacheLimitMegabytesKey =
      'aethertune.offline_cache_limit_mb.v1';
  static const _offlineCacheProviderLimitMegabytesKey =
      'aethertune.offline_cache_provider_limit_mb.v1';
  static const _watchedLocalFolderPathsKey =
      'aethertune.watched_local_folder_paths.v1';
  static const defaultOfflineCacheLimitMegabytes = 500;
  static const minOfflineCacheLimitMegabytes = 50;
  static const minOfflineCacheProviderLimitMegabytes = 1;
  static const maxOfflineCacheLimitMegabytes = 51200;
  static const defaultDesktopQueuePaneWidth = 320.0;
  static const minDesktopQueuePaneWidth = 260.0;
  static const maxDesktopQueuePaneWidth = 480.0;
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
  final List<SavedHistoryView> _savedHistoryViews = <SavedHistoryView>[];
  final List<PodcastSubscription> _podcastSubscriptions =
      <PodcastSubscription>[];
  final List<String> _followedArtists = <String>[];
  final List<PlaybackHistoryEntry> _history = <PlaybackHistoryEntry>[];
  final List<String> _searchQueryHistory = <String>[];
  final Map<String, PlaybackProgressEntry> _progressByTrackId =
      <String, PlaybackProgressEntry>{};
  final Map<String, TrackLyrics> _lyricsByTrackId = <String, TrackLyrics>{};
  final Map<String, double> _trackPlaybackSpeedOverrides = <String, double>{};
  final List<OfflineCacheEntry> _offlineCacheQueue = <OfflineCacheEntry>[];
  final List<String> _watchedLocalFolderPaths = <String>[];
  final DateTime Function() _clock;
  bool _pauseListeningHistory = false;
  bool _offlineModeEnabled = false;
  bool _automaticOfflineQueueEnabled = false;
  AppThemePreference _themePreference = AppThemePreference.system;
  AppAccentColor _accentColor = AppAccentColor.indigo;
  AppLanguagePreference _languagePreference = AppLanguagePreference.system;
  double _desktopQueuePaneWidth = defaultDesktopQueuePaneWidth;
  bool _onboardingCompleted = false;
  int _offlineCacheLimitMegabytes = defaultOfflineCacheLimitMegabytes;
  final Map<String, int> _offlineCacheProviderLimitMegabytes = <String, int>{};
  bool _loaded = false;

  bool get loaded => _loaded;
  List<Track> get tracks => List.unmodifiable(_tracks);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<String> get playlistFolders {
    final folders = _playlists
        .map((playlist) => playlist.folder.trim())
        .where((folder) => folder.isNotEmpty)
        .toSet()
        .toList(growable: false);
    folders.sort(_compareText);
    return folders;
  }
  List<CustomSmartPlaylist> get customSmartPlaylists =>
      List.unmodifiable(_customSmartPlaylists);
  List<SavedHistoryView> get savedHistoryViews =>
      List.unmodifiable(_savedHistoryViews);
  List<PodcastSubscription> get podcastSubscriptions =>
      List.unmodifiable(_podcastSubscriptions);
  List<String> get followedArtists => List.unmodifiable(_followedArtists);
  List<PlaybackHistoryEntry> get playbackHistory =>
      List.unmodifiable(_history);
  List<String> get searchQueryHistory =>
      List.unmodifiable(_searchQueryHistory);
  List<PlaybackProgressEntry> get playbackProgress =>
      List.unmodifiable(_progressByTrackId.values);
  List<TrackLyrics> get lyrics => List.unmodifiable(_lyricsByTrackId.values);
  Map<String, double> get trackPlaybackSpeedOverrides =>
      Map.unmodifiable(_trackPlaybackSpeedOverrides);
  List<OfflineCacheEntry> get offlineCacheQueue =>
      List.unmodifiable(_offlineCacheQueue);
  List<String> get watchedLocalFolderPaths =>
      List.unmodifiable(_watchedLocalFolderPaths);
  List<Track> get favorites =>
      _tracks.where((track) => track.isFavorite).toList(growable: false);
  bool get pauseListeningHistory => _pauseListeningHistory;
  bool get offlineModeEnabled => _offlineModeEnabled;
  bool get automaticOfflineQueueEnabled => _automaticOfflineQueueEnabled;
  AppThemePreference get themePreference => _themePreference;
  AppAccentColor get accentColor => _accentColor;
  AppLanguagePreference get languagePreference => _languagePreference;
  double get desktopQueuePaneWidth => _desktopQueuePaneWidth;
  bool get onboardingCompleted => _onboardingCompleted;
  int get offlineCacheLimitMegabytes => _offlineCacheLimitMegabytes;
  int get offlineCacheLimitBytes => _offlineCacheLimitMegabytes * 1024 * 1024;
  Map<String, int> get offlineCacheProviderLimitMegabytes =>
      Map.unmodifiable(_offlineCacheProviderLimitMegabytes);

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

    final rawSavedHistoryViews = prefs.getString(_savedHistoryViewsKey);
    if (rawSavedHistoryViews != null && rawSavedHistoryViews.isNotEmpty) {
      final decoded = jsonDecode(rawSavedHistoryViews) as List<dynamic>;
      _savedHistoryViews
        ..clear()
        ..addAll(
          _dedupeSavedHistoryViews(
            decoded.whereType<Map>().map(
                  (item) => SavedHistoryView.fromJson(
                    Map<String, Object?>.from(item),
                  ),
                ),
          ),
        );
      _sortSavedHistoryViews();
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

    _followedArtists
      ..clear()
      ..addAll(
        _dedupeFollowedArtists(
          prefs.getStringList(_followedArtistsKey) ?? const <String>[],
        ),
      );

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
    _pauseListeningHistory =
        prefs.getBool(_pauseListeningHistoryKey) ?? false;
    _offlineModeEnabled = prefs.getBool(_offlineModeKey) ?? false;
    _automaticOfflineQueueEnabled =
        prefs.getBool(_automaticOfflineQueueKey) ?? false;
    _themePreference = _appThemePreferenceFromName(
      prefs.getString(_themePreferenceKey),
    );
    _accentColor = _appAccentColorFromName(
      prefs.getString(_accentColorKey),
    );
    _languagePreference = _appLanguagePreferenceFromName(
      prefs.getString(_languagePreferenceKey),
    );
    _trackPlaybackSpeedOverrides
      ..clear()
      ..addAll(
        _decodeTrackPlaybackSpeedOverrides(
          prefs.getString(_trackPlaybackSpeedOverridesKey),
        ),
      );
    _desktopQueuePaneWidth = _sanitizeDesktopQueuePaneWidth(
      prefs.getDouble(_desktopQueuePaneWidthKey) ??
          defaultDesktopQueuePaneWidth,
    );
    _onboardingCompleted = prefs.getBool(_onboardingCompletedKey) ?? false;
    _offlineCacheLimitMegabytes = _sanitizeOfflineCacheLimitMegabytes(
      prefs.getInt(_offlineCacheLimitMegabytesKey) ??
          defaultOfflineCacheLimitMegabytes,
    );
    _offlineCacheProviderLimitMegabytes
      ..clear()
      ..addAll(
        _decodeOfflineCacheProviderLimits(
          prefs.getString(_offlineCacheProviderLimitMegabytesKey),
        ),
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
    _watchedLocalFolderPaths
      ..clear()
      ..addAll(
        _dedupeWatchedLocalFolderPaths(
          prefs.getStringList(_watchedLocalFolderPathsKey) ?? const <String>[],
        ),
      );

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

  Future<void> watchLocalFolder(String rootPath) async {
    final normalized = _normalizeWatchedLocalFolderPath(rootPath);
    if (_watchedLocalFolderPaths.contains(normalized)) {
      return;
    }
    _watchedLocalFolderPaths.add(normalized);
    _watchedLocalFolderPaths.sort();
    await _save();
    notifyListeners();
  }

  Future<void> unwatchLocalFolder(String rootPath) async {
    final normalized = _normalizeWatchedLocalFolderPath(rootPath);
    if (!_watchedLocalFolderPaths.remove(normalized)) {
      return;
    }
    await _save();
    notifyListeners();
  }

  Future<void> reconcileWatchedLocalFolder(
    String rootPath, {
    required Iterable<Track> tracks,
    required Map<String, String> sidecarLyricsByTrackId,
    required bool pruneMissing,
  }) async {
    final root = _normalizeWatchedLocalFolderPath(rootPath);
    if (!_watchedLocalFolderPaths.contains(root)) {
      return;
    }
    final scannedTracks = tracks
        .where((track) => _isLocalTrackWithinFolder(track, root))
        .toList(growable: false);
    final scannedIds = scannedTracks.map((track) => track.id).toSet();
    var changed = false;

    for (final scanned in scannedTracks) {
      final index = _tracks.indexWhere((track) => track.id == scanned.id);
      if (index == -1) {
        _tracks.add(scanned);
        changed = true;
        continue;
      }
      final current = _tracks[index];
      if (current.contentHash == scanned.contentHash) {
        continue;
      }
      _tracks[index] = _scannedTrackWithPreservedUserState(current, scanned);
      changed = true;
    }

    if (pruneMissing) {
      final deletedIds = _tracks
          .where((track) => _isLocalTrackWithinFolder(track, root))
          .where((track) => !scannedIds.contains(track.id))
          .map((track) => track.id)
          .toList(growable: false);
      for (final trackId in deletedIds) {
        _tracks.removeWhere((track) => track.id == trackId);
        _removeTrackFromPlaylists(trackId);
        _lyricsByTrackId.remove(trackId);
        _history.removeWhere((entry) => entry.trackId == trackId);
        _progressByTrackId.remove(trackId);
        changed = true;
      }
    }

    for (final entry in sidecarLyricsByTrackId.entries) {
      if (_lyricsByTrackId.containsKey(entry.key) ||
          !_tracks.any((track) => track.id == entry.key) ||
          entry.value.trim().isEmpty) {
        continue;
      }
      _lyricsByTrackId[entry.key] = TrackLyrics(
        trackId: entry.key,
        plainText: entry.value.trim(),
        updatedAt: _clock(),
      );
      changed = true;
    }

    if (!changed) {
      return;
    }
    _sortTracks();
    await _save();
    notifyListeners();
  }

  Future<void> removeTrack(String id) async {
    _tracks.removeWhere((track) => track.id == id);
    _removeTrackFromPlaylists(id);
    _lyricsByTrackId.remove(id);
    _trackPlaybackSpeedOverrides.remove(id);
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
    _savedHistoryViews.clear();
    _podcastSubscriptions.clear();
    _history.clear();
    _searchQueryHistory.clear();
    _progressByTrackId.clear();
    _lyricsByTrackId.clear();
    _trackPlaybackSpeedOverrides.clear();
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

  Future<void> setPauseListeningHistory(bool paused) async {
    if (_pauseListeningHistory == paused) {
      return;
    }

    _pauseListeningHistory = paused;
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

  Future<void> setAccentColor(AppAccentColor accentColor) async {
    if (_accentColor == accentColor) {
      return;
    }

    _accentColor = accentColor;
    await _save();
    notifyListeners();
  }

  double? playbackSpeedForTrack(String trackId) {
    return _trackPlaybackSpeedOverrides[trackId.trim()];
  }

  Future<void> setTrackPlaybackSpeed(String trackId, double speed) async {
    final normalizedTrackId = trackId.trim();
    if (normalizedTrackId.isEmpty) {
      throw ArgumentError.value(trackId, 'trackId', 'Track ID cannot be empty.');
    }
    if (!isSupportedPlaybackSpeed(speed)) {
      throw ArgumentError.value(
        speed,
        'speed',
        'Playback speed must be one of the supported values.',
      );
    }
    if (_trackPlaybackSpeedOverrides[normalizedTrackId] == speed) {
      return;
    }
    _trackPlaybackSpeedOverrides[normalizedTrackId] = speed;
    await _save();
    notifyListeners();
  }

  Future<void> clearTrackPlaybackSpeed(String trackId) async {
    if (_trackPlaybackSpeedOverrides.remove(trackId.trim()) == null) {
      return;
    }
    await _save();
    notifyListeners();
  }

  Future<void> setDesktopQueuePaneWidth(double width) async {
    final sanitized = _sanitizeDesktopQueuePaneWidth(width);
    if (_desktopQueuePaneWidth == sanitized) {
      return;
    }

    _desktopQueuePaneWidth = sanitized;
    await _save();
    notifyListeners();
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    if (_onboardingCompleted == completed) {
      return;
    }

    _onboardingCompleted = completed;
    await _save();
    notifyListeners();
  }

  Future<void> setOfflineCacheLimitMegabytes(int megabytes) async {
    final sanitized = _sanitizeOfflineCacheLimitMegabytes(megabytes);
    if (_offlineCacheLimitMegabytes == sanitized) {
      return;
    }

    _offlineCacheLimitMegabytes = sanitized;
    await _save();
    notifyListeners();
  }

  int? offlineCacheProviderLimitMegabytesFor(String sourceId) {
    final normalized = _normalizeProviderLimitSourceId(sourceId);
    if (normalized.isEmpty) {
      return null;
    }

    return _offlineCacheProviderLimitMegabytes[normalized];
  }

  int? offlineCacheProviderLimitBytesFor(String sourceId) {
    final megabytes = offlineCacheProviderLimitMegabytesFor(sourceId);
    return megabytes == null ? null : megabytes * 1024 * 1024;
  }

  Future<void> setOfflineCacheProviderLimitMegabytes(
    String sourceId,
    int? megabytes,
  ) async {
    final normalized = _normalizeProviderLimitSourceId(sourceId);
    if (normalized.isEmpty) {
      return;
    }

    if (megabytes == null || megabytes <= 0) {
      if (!_offlineCacheProviderLimitMegabytes.containsKey(normalized)) {
        return;
      }

      _offlineCacheProviderLimitMegabytes.remove(normalized);
      await _save();
      notifyListeners();
      return;
    }

    final sanitized = _sanitizeOfflineCacheProviderLimitMegabytes(megabytes);
    if (_offlineCacheProviderLimitMegabytes[normalized] == sanitized) {
      return;
    }

    _offlineCacheProviderLimitMegabytes[normalized] = sanitized;
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
    OfflineCacheCancellationRegistry.instance.clear(id);
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
    OfflineCacheCancellationRegistry.instance.cancel(id);
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

    for (final entry in _offlineCacheQueue) {
      OfflineCacheCancellationRegistry.instance.cancel(entry.id);
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
    if (offlineCacheEntryById(id) == null) {
      return Future<OfflineCacheEntry?>.value(null);
    }
    OfflineCacheCancellationRegistry.instance.begin(id);
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
    int byteCount = 0,
    String checksum = '',
  }) {
    return _updateOfflineCacheEntry(
      id,
      track: cachedTrack,
      status: OfflineCacheEntryStatus.cached,
      reason: reason,
      cachedByteCount: byteCount,
      cachedMediaChecksum: checksum,
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

  Future<OfflineCacheEntry?> pauseOfflineCacheEntry(String id) {
    final entry = offlineCacheEntryById(id);
    if (entry == null ||
        (entry.status != OfflineCacheEntryStatus.queued &&
            entry.status != OfflineCacheEntryStatus.failed &&
            entry.status != OfflineCacheEntryStatus.processing)) {
      return Future<OfflineCacheEntry?>.value(entry);
    }

    OfflineCacheCancellationRegistry.instance.cancel(id);

    return _updateOfflineCacheEntry(
      id,
      status: OfflineCacheEntryStatus.paused,
      reason: 'Paused by user.',
    );
  }

  Future<OfflineCacheEntry?> resumeOfflineCacheEntry(String id) {
    final entry = offlineCacheEntryById(id);
    if (entry == null || entry.status != OfflineCacheEntryStatus.paused) {
      return Future<OfflineCacheEntry?>.value(entry);
    }

    OfflineCacheCancellationRegistry.instance.clear(id);
    return _updateOfflineCacheEntry(
      id,
      status: OfflineCacheEntryStatus.queued,
      reason: 'Ready to cache media.',
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
      cachedByteCount: 0,
      cachedMediaChecksum: '',
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

  Future<void> setLanguagePreference(
    AppLanguagePreference preference,
  ) async {
    if (_languagePreference == preference) {
      return;
    }

    _languagePreference = preference;
    await _save();
    notifyListeners();
  }

  bool canFollowArtist(String artist) {
    final normalized = artist.trim();
    return normalized.isNotEmpty &&
        normalized.toLowerCase() != 'unknown artist';
  }

  bool isArtistFollowed(String artist) {
    final key = _followedArtistKey(artist);
    return key.isNotEmpty &&
        _followedArtists.any((value) => _followedArtistKey(value) == key);
  }

  Future<bool> setArtistFollowed(String artist, bool followed) async {
    final normalized = artist.trim();
    if (!canFollowArtist(normalized)) {
      return false;
    }

    final key = _followedArtistKey(normalized);
    final existingIndex = _followedArtists.indexWhere(
      (value) => _followedArtistKey(value) == key,
    );
    if (followed) {
      if (existingIndex != -1) {
        return false;
      }
      _followedArtists.add(normalized);
      _sortFollowedArtists();
    } else {
      if (existingIndex == -1) {
        return false;
      }
      _followedArtists.removeAt(existingIndex);
    }

    await _save();
    notifyListeners();
    return true;
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

  Future<Track?> updateTrackArtwork(String id, Uri? artworkUri) async {
    final index = _tracks.indexWhere((track) => track.id == id);
    if (index == -1) {
      return null;
    }

    final current = _tracks[index];
    if (current.sourceId != 'local') {
      throw UnsupportedError(
        'Artwork editing is available for local library tracks only.',
      );
    }
    if (artworkUri != null &&
        artworkUri.scheme != 'file' &&
        artworkUri.scheme != 'http' &&
        artworkUri.scheme != 'https') {
      throw ArgumentError.value(
        artworkUri,
        'artworkUri',
        'Artwork must be a local file or an http/https URL.',
      );
    }

    final updated = artworkUri == null
        ? current.copyWith(
            artworkUri: current.artworkSourceUri,
            clearArtworkUri: current.artworkSourceUri == null,
            clearArtworkSourceUri: true,
            artworkIsUserManaged: false,
          )
        : current.copyWith(
            artworkUri: artworkUri,
            artworkSourceUri: current.artworkIsUserManaged
                ? current.artworkSourceUri
                : current.artworkUri,
            artworkIsUserManaged: true,
          );
    _tracks[index] = updated;
    await _save();
    notifyListeners();
    return updated;
  }

  Future<Track?> updateEmbeddedTrackArtwork(String id, Uri? artworkUri) async {
    final index = _tracks.indexWhere((track) => track.id == id);
    if (index == -1) {
      return null;
    }

    final current = _tracks[index];
    if (current.sourceId != 'local') {
      throw UnsupportedError(
        'Embedded artwork is available for local library tracks only.',
      );
    }
    if (artworkUri != null && artworkUri.scheme != 'data') {
      throw ArgumentError.value(
        artworkUri,
        'artworkUri',
        'Embedded artwork must use a data URI.',
      );
    }

    final updated = current.artworkIsUserManaged
        ? current.copyWith(
            artworkSourceUri: artworkUri,
            clearArtworkSourceUri: artworkUri == null,
          )
        : current.copyWith(
            artworkUri: artworkUri,
            clearArtworkUri: artworkUri == null,
            artworkSourceUri: artworkUri,
            clearArtworkSourceUri: artworkUri == null,
          );
    _tracks[index] = updated;
    await _save();
    notifyListeners();
    return updated;
  }

  Future<Track?> updateTrackChapters(
    String id,
    Iterable<TrackChapter> chapters,
  ) async {
    final index = _tracks.indexWhere((track) => track.id == id);
    if (index == -1) {
      return null;
    }

    final current = _tracks[index];
    final updated = current.copyWith(
      chapters: TrackChapter.normalize(
        chapters,
        maximum: current.duration,
      ),
    );
    if (_sameChapters(current.chapters, updated.chapters)) {
      return updated;
    }

    _tracks[index] = updated;
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
    final searchQuery = SearchQuery.parse(query);
    final source = (favoritesOnly ? favorites : tracks)
        .where((track) => !offlineOnly || track.hasLocalSource);

    final results = searchQuery.isEmpty
        ? source.toList(growable: false)
        : source
            .where((track) => _trackMatchesQuery(track, searchQuery))
            .toList(growable: false);

    return _sortTrackResults(results, sortMode);
  }

  List<SearchSuggestion> searchSuggestions(String query, {int limit = 8}) {
    if (limit <= 0) {
      return <SearchSuggestion>[];
    }

    final searchQuery = SearchQuery.parse(query);
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

      if (!searchTextMatches(trimmed, searchQuery)) {
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
      addGroupTrack(
        DuplicateMatchType.contentHash,
        track.contentHash ?? '',
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

    final searchQuery = SearchQuery.parse(query);
    final groups = groupsByKey.values
        .where(
          (group) => searchQuery.isEmpty ||
              searchTextMatches(group.label, searchQuery),
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

  List<LibraryFolderNode> folderTree({String query = ''}) {
    final nodesByKey = <String, _MutableFolderNode>{};

    for (final track in _tracks) {
      final localPath = track.localPath?.trim();
      if (localPath == null || localPath.isEmpty) {
        continue;
      }

      final context = _pathContextFor(localPath);
      final folderPath = _folderLabelForTrack(track);
      final ancestors = _folderAncestors(folderPath, context);
      String? parentKey;
      for (var index = 0; index < ancestors.length; index += 1) {
        final ancestorPath = ancestors[index];
        final key = _folderTreeKey(ancestorPath);
        final node = nodesByKey.putIfAbsent(
          key,
          () => _MutableFolderNode(
            key: key,
            path: ancestorPath,
            label: _folderTreeLabel(ancestorPath, context),
            depth: index,
          ),
        );

        if (parentKey != null) {
          nodesByKey[parentKey]?.addChild(key);
        }

        node.addTrack(track, direct: index == ancestors.length - 1);
        parentKey = key;
      }
    }

    final searchQuery = SearchQuery.parse(query);
    final nodes = nodesByKey.values
        .where(
          (node) => searchQuery.isEmpty ||
              searchFieldsMatch(<String>[node.label, node.path], searchQuery),
        )
        .map((node) => node.toFolderNode())
        .toList(growable: false);

    nodes.sort((a, b) => _compareText(a.key, b.key));
    return nodes;
  }

  List<Track> tracksForFolderNode(
    String key, {
    LibrarySortMode sortMode = LibrarySortMode.album,
  }) {
    final normalizedKey = _folderTreeKey(key);
    if (normalizedKey.isEmpty) {
      return <Track>[];
    }

    final tracks = _tracks.where((track) {
      final localPath = track.localPath?.trim();
      if (localPath == null || localPath.isEmpty) {
        return false;
      }

      final folderKey = _folderTreeKey(_folderLabelForTrack(track));
      return folderKey == normalizedKey ||
          folderKey.startsWith('$normalizedKey/');
    }).toList(growable: false);

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
      LibraryHomeSectionType.followedArtists,
      _followedArtistTracks(limit: limit),
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
      LibraryHomeSectionType.subscribedEpisodes,
      _subscribedPodcastEpisodeTracks(),
    );
    addSection(
      LibraryHomeSectionType.recentlyAdded,
      recentlyAddedTracks(limit: limit),
    );

    return sections;
  }

  List<Track> _subscribedPodcastEpisodeTracks() {
    final byId = <String, Track>{
      for (final subscription in _podcastSubscriptions)
        for (final episode in subscription.episodes) episode.id: episode,
    };
    for (final track in _tracks.where(
      (track) => track.sourceId.startsWith('podcast-'),
    )) {
      byId[track.id] = track;
    }

    final episodes = byId.values.toList(growable: false);
    episodes.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return episodes;
  }

  List<Track> _followedArtistTracks({required int limit}) {
    if (_followedArtists.isEmpty) {
      return <Track>[];
    }

    final followedKeys = _followedArtists
        .map(_followedArtistKey)
        .where((key) => key.isNotEmpty)
        .toSet();
    final tracks = _tracks
        .where((track) => followedKeys.contains(_followedArtistKey(track.artist)))
        .toList(growable: false);
    tracks.sort(_compareByDateThenTitle);
    return tracks.take(limit).toList(growable: false);
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

  List<LibraryListeningRecap> listeningRecaps({
    LibraryRecapPeriod period = LibraryRecapPeriod.month,
    int limit = 6,
    int statsLimit = 3,
  }) {
    if (limit <= 0 || statsLimit < 0) {
      return <LibraryListeningRecap>[];
    }

    final starts = <DateTime>{};
    for (final entry in _history) {
      starts.add(_listeningRecapStart(entry.playedAt, period));
    }

    final sortedStarts = starts.toList(growable: false)
      ..sort((left, right) => right.compareTo(left));
    final recaps = <LibraryListeningRecap>[];
    for (final start in sortedStarts.take(limit)) {
      final end = _listeningRecapEnd(start, period);
      final stats = libraryStats(limit: statsLimit, from: start, to: end);
      if (stats.playbackCount == 0) {
        continue;
      }

      recaps.add(
        LibraryListeningRecap(
          period: period,
          start: start,
          end: end,
          stats: stats,
        ),
      );
    }

    return recaps;
  }

  List<LibraryListeningHeatmapDay> listeningHeatmap({
    required DateTime from,
    required DateTime to,
  }) {
    final startDay = _calendarDay(from);
    final endDay = _calendarDay(to);
    if (endDay.isBefore(startDay)) {
      return <LibraryListeningHeatmapDay>[];
    }

    final tracksById = <String, Track>{
      for (final track in _tracks) track.id: track,
    };
    final playCounts = <DateTime, int>{};
    final listeningDurations = <DateTime, Duration>{};
    for (final entry in _history) {
      if (!_historyEntryInRange(entry, from: from, to: to)) {
        continue;
      }

      final day = _calendarDay(entry.playedAt);
      playCounts[day] = (playCounts[day] ?? 0) + 1;
      final track = tracksById[entry.trackId];
      if (track != null) {
        listeningDurations[day] =
            (listeningDurations[day] ?? Duration.zero) + track.duration;
      }
    }

    final days = <LibraryListeningHeatmapDay>[];
    for (var day = startDay; !day.isAfter(endDay);) {
      days.add(
        LibraryListeningHeatmapDay(
          day: day,
          playbackCount: playCounts[day] ?? 0,
          estimatedListeningDuration:
              listeningDurations[day] ?? Duration.zero,
        ),
      );
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return days;
  }

  List<LibraryMoodMix> localMoodMixes({int limit = 8}) {
    if (limit <= 0) {
      return <LibraryMoodMix>[];
    }

    final mixes = <LibraryMoodMix>[];
    for (final type in LibraryMoodMixType.values) {
      final tracks = tracksForMoodMix(type, limit: limit);
      if (tracks.isEmpty) {
        continue;
      }

      mixes.add(
        LibraryMoodMix(
          type: type,
          name: _moodMixName(type),
          description: _moodMixDescription(type),
          tracks: tracks,
        ),
      );
    }

    return mixes;
  }

  List<Track> tracksForMoodMix(
    LibraryMoodMixType type, {
    int limit = 50,
  }) {
    if (limit <= 0) {
      return <Track>[];
    }

    final candidates = <_DiscoveryCandidate>[];
    for (final track in _tracks) {
      if (!track.isPlayable) {
        continue;
      }

      final baseScore = _moodScoreForTrack(type, track);
      if (baseScore <= 0) {
        continue;
      }

      candidates.add(
        _DiscoveryCandidate(
          track: track,
          score: _boostedDiscoveryScore(baseScore, track),
          playCount: playCountForTrack(track.id),
          lastPlayedAt: lastPlayedAt(track.id),
        ),
      );
    }

    candidates.sort(_compareDiscoveryCandidates);

    return candidates
        .map((candidate) => candidate.track)
        .take(limit)
        .toList(growable: false);
  }

  List<Track> personalizedRecommendations({int limit = 12}) {
    if (limit <= 0) {
      return <Track>[];
    }

    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };
    final artistWeights = <String, int>{};
    final albumWeights = <String, int>{};
    final genreWeights = <String, int>{};

    void addWeight(Map<String, int> weights, String? key, int amount) {
      if (key == null || amount <= 0) {
        return;
      }

      weights[key] = (weights[key] ?? 0) + amount;
    }

    void addPreference(
      Track track, {
      required int artist,
      required int album,
      required int genre,
    }) {
      addWeight(artistWeights, _knownMetadataKey(track.artist), artist);
      addWeight(albumWeights, _knownMetadataKey(track.album), album);
      addWeight(genreWeights, _knownMetadataKey(track.genre), genre);
    }

    for (final track in favorites) {
      addPreference(track, artist: 28, album: 16, genre: 22);
    }

    final recentHistoryTrackIds = <String>{};
    for (final entry in _history.take(50)) {
      final track = byId[entry.trackId];
      if (track == null) {
        continue;
      }

      recentHistoryTrackIds.add(track.id);
      final firstRecentPlay = recentHistoryTrackIds.length <= 12;
      addPreference(
        track,
        artist: firstRecentPlay ? 18 : 8,
        album: firstRecentPlay ? 10 : 4,
        genre: firstRecentPlay ? 16 : 7,
      );
    }

    if (artistWeights.isEmpty && albumWeights.isEmpty && genreWeights.isEmpty) {
      return _recentPlayableTracks(limit: limit);
    }

    final candidates = <_DiscoveryCandidate>[];
    for (final track in _tracks) {
      if (!track.isPlayable) {
        continue;
      }

      if (recentHistoryTrackIds.contains(track.id)) {
        continue;
      }

      var score = 0;
      score += artistWeights[_knownMetadataKey(track.artist)] ?? 0;
      score += albumWeights[_knownMetadataKey(track.album)] ?? 0;
      score += genreWeights[_knownMetadataKey(track.genre)] ?? 0;

      if (track.isFavorite) {
        score += 8;
      }

      final playCount = playCountForTrack(track.id);
      if (playCount == 0) {
        score += 12;
      } else {
        score -= playCount * 2;
      }

      if (score <= 0) {
        continue;
      }

      candidates.add(
        _DiscoveryCandidate(
          track: track,
          score: score,
          playCount: playCount,
          lastPlayedAt: lastPlayedAt(track.id),
        ),
      );
    }

    candidates.sort(_compareRecommendationCandidates);

    if (candidates.isEmpty) {
      return _recentPlayableTracks(limit: limit);
    }

    return candidates
        .map((candidate) => candidate.track)
        .take(limit)
        .toList(growable: false);
  }

  List<SimilarTrackMatch> similarTracksForTrack(
    String seedTrackId, {
    int limit = 25,
  }) {
    if (limit <= 0) {
      return <SimilarTrackMatch>[];
    }

    final seedIndex = _tracks.indexWhere((track) => track.id == seedTrackId);
    if (seedIndex == -1) {
      return <SimilarTrackMatch>[];
    }

    final seedTrack = _tracks[seedIndex];
    final candidates = <_SimilarityCandidate>[];
    for (final track in _tracks) {
      if (track.id == seedTrack.id || !track.isPlayable) {
        continue;
      }

      final reasons = _similarityReasonsForTrack(seedTrack, track);
      if (!reasons.any(_isCoreSimilarityReason)) {
        continue;
      }

      candidates.add(
        _SimilarityCandidate(
          track: track,
          reasons: reasons,
          score: _similarityScoreForTrack(track, reasons),
          playCount: playCountForTrack(track.id),
          lastPlayedAt: lastPlayedAt(track.id),
        ),
      );
    }

    candidates.sort(_compareSimilarityCandidates);

    return candidates
        .map(
          (candidate) => SimilarTrackMatch(
            track: candidate.track,
            reasons: candidate.reasons,
            score: candidate.score,
          ),
        )
        .take(limit)
        .toList(growable: false);
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

    final searchQuery = SearchQuery.parse(rule.query);
    final lastPlayedByTrack = <String, DateTime>{};
    if (rule.minimumDaysSinceLastPlayed > 0 ||
        rule.ruleGroups.any(_customSmartPlaylistGroupUsesLastPlayed)) {
      for (final entry in _history) {
        final current = lastPlayedByTrack[entry.trackId];
        if (current == null || entry.playedAt.isAfter(current)) {
          lastPlayedByTrack[entry.trackId] = entry.playedAt;
        }
      }
    }
    final now = _clock();
    final tracks = _tracks
        .where(
          (track) => _matchesCustomSmartPlaylistRule(
            track,
            rule,
            searchQuery: searchQuery,
            lastPlayedAt: lastPlayedByTrack[track.id],
            now: now,
          ),
        )
        .toList(growable: false);

    _sortCustomSmartPlaylistTracks(tracks, rule.sortMode);

    return tracks.take(rule.limit).toList(growable: false);
  }

  bool _matchesCustomSmartPlaylistRule(
    Track track,
    CustomSmartPlaylist rule, {
    required SearchQuery searchQuery,
    required DateTime? lastPlayedAt,
    required DateTime now,
  }) {
    final matches = <bool>[
      if (rule.favoritesOnly) track.isFavorite,
      if (rule.minimumPlayCount > 0)
        playCountForTrack(track.id) >= rule.minimumPlayCount,
      if (rule.minimumDaysSinceLastPlayed > 0)
        lastPlayedAt == null ||
            now.difference(lastPlayedAt) >=
                Duration(days: rule.minimumDaysSinceLastPlayed),
      if (rule.sourceId.isNotEmpty)
        track.sourceId.toLowerCase() == rule.sourceId.toLowerCase(),
      if (rule.artist.isNotEmpty)
        track.artist.toLowerCase() == rule.artist.toLowerCase(),
      if (rule.album.isNotEmpty)
        track.album.toLowerCase() == rule.album.toLowerCase(),
      if (rule.genre.isNotEmpty)
        track.genre.toLowerCase() == rule.genre.toLowerCase(),
      if (rule.minimumDurationSeconds > 0)
        track.duration.inSeconds >= rule.minimumDurationSeconds,
      if (rule.maximumDurationSeconds > 0)
        track.duration.inSeconds <= rule.maximumDurationSeconds,
      if (!searchQuery.isEmpty) _trackMatchesQuery(track, searchQuery),
      for (final group in rule.ruleGroups)
        _matchesCustomSmartPlaylistRuleGroup(
          track,
          group,
          lastPlayedAt: lastPlayedAt,
          now: now,
        ),
    ];
    if (matches.isEmpty) {
      return true;
    }

    return switch (rule.matchMode) {
      CustomSmartPlaylistMatchMode.all => matches.every((match) => match),
      CustomSmartPlaylistMatchMode.any => matches.any((match) => match),
    };
  }

  bool _customSmartPlaylistGroupUsesLastPlayed(
    CustomSmartPlaylistRuleGroup group,
  ) {
    return group.rules.any(
          (rule) =>
              rule.field ==
              CustomSmartPlaylistRuleField.minimumDaysSinceLastPlayed,
        ) ||
        group.groups.any(_customSmartPlaylistGroupUsesLastPlayed);
  }

  bool _matchesCustomSmartPlaylistRuleGroup(
    Track track,
    CustomSmartPlaylistRuleGroup group, {
    required DateTime? lastPlayedAt,
    required DateTime now,
  }) {
    final matches = <bool>[
      for (final rule in group.rules)
        _matchesCustomSmartPlaylistCondition(
          track,
          rule,
          lastPlayedAt: lastPlayedAt,
          now: now,
        ),
      for (final nestedGroup in group.groups)
        _matchesCustomSmartPlaylistRuleGroup(
          track,
          nestedGroup,
          lastPlayedAt: lastPlayedAt,
          now: now,
        ),
    ];
    if (matches.isEmpty) {
      return true;
    }
    return switch (group.matchMode) {
      CustomSmartPlaylistMatchMode.all => matches.every((match) => match),
      CustomSmartPlaylistMatchMode.any => matches.any((match) => match),
    };
  }

  bool _matchesCustomSmartPlaylistCondition(
    Track track,
    CustomSmartPlaylistRule rule, {
    required DateTime? lastPlayedAt,
    required DateTime now,
  }) {
    final value = rule.value.trim();
    return switch (rule.field) {
      CustomSmartPlaylistRuleField.searchText =>
        _trackMatchesQuery(track, SearchQuery.parse(value)),
      CustomSmartPlaylistRuleField.sourceId =>
        track.sourceId.toLowerCase() == value.toLowerCase(),
      CustomSmartPlaylistRuleField.artist =>
        track.artist.toLowerCase() == value.toLowerCase(),
      CustomSmartPlaylistRuleField.album =>
        track.album.toLowerCase() == value.toLowerCase(),
      CustomSmartPlaylistRuleField.genre =>
        track.genre.toLowerCase() == value.toLowerCase(),
      CustomSmartPlaylistRuleField.minimumDurationSeconds =>
        track.duration.inSeconds >= (int.tryParse(value) ?? 0),
      CustomSmartPlaylistRuleField.maximumDurationSeconds =>
        track.duration.inSeconds <= (int.tryParse(value) ?? 0),
      CustomSmartPlaylistRuleField.favoritesOnly => track.isFavorite,
      CustomSmartPlaylistRuleField.minimumPlayCount =>
        playCountForTrack(track.id) >= (int.tryParse(value) ?? 0),
      CustomSmartPlaylistRuleField.minimumDaysSinceLastPlayed =>
        lastPlayedAt == null ||
            now.difference(lastPlayedAt) >=
                Duration(days: int.tryParse(value) ?? 0),
    };
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
      'pauseListeningHistory': _pauseListeningHistory,
      'offlineModeEnabled': _offlineModeEnabled,
      'themePreference': _themePreference.name,
      'accentColor': _accentColor.name,
      'languagePreference': _languagePreference.name,
      'offlineCacheLimitMegabytes': _offlineCacheLimitMegabytes,
      'offlineCacheProviderLimitMegabytes':
          Map<String, int>.from(_offlineCacheProviderLimitMegabytes),
      'tracks': _tracks.map(_portableTrackArtworkJson).toList(),
      'playlists': _playlists
          .map(_portablePlaylistJson)
          .toList(growable: false),
      'customSmartPlaylists':
          _customSmartPlaylists
              .map(_portableCustomSmartPlaylistJson)
              .toList(growable: false),
      'savedHistoryViews':
          _savedHistoryViews.map((view) => view.toJson()).toList(),
      'podcastSubscriptions':
          _podcastSubscriptions.map((item) => item.toJson()).toList(),
      'followedArtists': _followedArtists,
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

  String exportSyncSnapshotJson() {
    final backup = Map<String, Object?>.from(
      jsonDecode(exportBackupJson()) as Map,
    );
    backup
      ..['syncVersion'] = _syncSnapshotVersion
      ..remove('offlineModeEnabled')
      ..remove('offlineCacheLimitMegabytes')
      ..remove('offlineCacheProviderLimitMegabytes')
      ..['offlineCacheQueue'] = <Object?>[]
      ..['tracks'] = _tracks
          .map(_portableSyncTrackJson)
          .toList(growable: false)
      ..['playlists'] = _playlists
          .map(_portablePlaylistJson)
          .toList(growable: false);

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(backup);
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
      'playlist': _portablePlaylistJson(playlist),
      'tracks': tracks.map(_portableTrackArtworkJson).toList(),
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

  String? shareTrackText(String trackId) {
    final track = _trackById(trackId);
    if (track == null) {
      return null;
    }

    return _shareTrackText(track);
  }

  String? shareBrowseGroupText(LibraryBrowseType type, String key) {
    final tracks = tracksForBrowseGroup(type, key);
    if (tracks.isEmpty) {
      return null;
    }

    final buffer = StringBuffer()
      ..writeln('AetherTune ${_shareBrowseTypeName(type)}')
      ..writeln('Name: ${_shareBrowseGroupLabel(type, tracks.first)}')
      ..writeln('Tracks: ${tracks.length}')
      ..writeln('Duration: ${_shareDuration(_totalDuration(tracks))}')
      ..writeln();
    _writeShareTrackList(buffer, tracks);

    return buffer.toString().trimRight();
  }

  String? shareFolderNodeText(String key) {
    final tracks = tracksForFolderNode(key);
    if (tracks.isEmpty) {
      return null;
    }

    final node = folderTree().where((node) => node.key == _folderTreeKey(key));
    final label = node.isEmpty ? key : node.first.path;
    final buffer = StringBuffer()
      ..writeln('AetherTune folder')
      ..writeln('Name: ${_shareFolderName(label)}')
      ..writeln('Tracks: ${tracks.length}')
      ..writeln('Duration: ${_shareDuration(_totalDuration(tracks))}')
      ..writeln();
    _writeShareTrackList(buffer, tracks);

    return buffer.toString().trimRight();
  }

  String? sharePlaylistText(String playlistId) {
    final playlist = playlistById(playlistId);
    if (playlist == null) {
      return null;
    }

    final tracks = tracksForPlaylist(playlist.id);
    final buffer = StringBuffer()
      ..writeln('AetherTune playlist')
      ..writeln('Name: ${playlist.name}')
      ..writeln('Tracks: ${tracks.length}')
      ..writeln('Duration: ${_shareDuration(_totalDuration(tracks))}');
    final artworkUrl = _shareableWebUrl(playlist.artworkUri?.toString());
    if (artworkUrl != null) {
      buffer.writeln('Artwork: $artworkUrl');
    }
    if (tracks.isNotEmpty) {
      buffer.writeln();
      _writeShareTrackList(buffer, tracks);
    }

    return buffer.toString().trimRight();
  }

  String? shareLyricsText(
    String trackId, {
    String? plainText,
    int startLine = 0,
    int? endLine,
    int maxLines = 8,
  }) {
    final track = _trackById(trackId);
    if (track == null) {
      return null;
    }

    final lyrics = plainText == null
        ? _lyricsByTrackId[trackId]
        : TrackLyrics(trackId: trackId, plainText: plainText);
    if (lyrics == null || lyrics.isEmpty) {
      return null;
    }

    final lines = _shareLyricsLines(lyrics);
    if (lines.isEmpty) {
      return null;
    }

    final limit = maxLines <= 0 ? 8 : maxLines;
    final normalizedStartLine = startLine.clamp(0, lines.length - 1).toInt();
    final normalizedEndLine = (endLine ?? (lines.length - 1))
        .clamp(normalizedStartLine, lines.length - 1)
        .toInt();
    final selectedLines = lines.sublist(
      normalizedStartLine,
      normalizedEndLine + 1,
    );
    final visibleLines = selectedLines.take(limit).toList(growable: false);
    final buffer = StringBuffer()
      ..writeln('AetherTune lyrics')
      ..writeln('Track: ${_shareTextValue(track.title, 'Untitled')}')
      ..writeln('Artist: ${_shareTextValue(track.artist, 'Unknown Artist')}')
      ..writeln('Album: ${_shareTextValue(track.album, 'Unknown Album')}')
      ..writeln('Format: ${lyrics.hasSyncedLines ? 'Synced LRC' : 'Plain text'}');
    if (lyrics.hasProviderAttribution) {
      final recordSuffix = lyrics.sourceExternalId.trim().isEmpty
          ? ''
          : ' #${lyrics.sourceExternalId.trim()}';
      buffer.writeln('Source: ${lyrics.sourceName.trim()}$recordSuffix');
      if (lyrics.sourceUri != null) {
        buffer.writeln('Source URL: ${lyrics.sourceUri}');
      }
    }
    buffer
      ..writeln(
        'Lines: ${visibleLines.length} of ${lines.length} '
        '(selected ${normalizedStartLine + 1}-${normalizedEndLine + 1})',
      )
      ..writeln();
    for (final line in visibleLines) {
      buffer.writeln(line);
    }
    if (selectedLines.length > visibleLines.length) {
      buffer.writeln('...');
    }

    return buffer.toString().trimRight();
  }

  List<String> lyricsShareLines(String trackId, {String? plainText}) {
    if (_trackById(trackId) == null) {
      return const <String>[];
    }

    final lyrics = plainText == null
        ? _lyricsByTrackId[trackId]
        : TrackLyrics(trackId: trackId, plainText: plainText);
    if (lyrics == null || lyrics.isEmpty) {
      return const <String>[];
    }

    return List.unmodifiable(_shareLyricsLines(lyrics));
  }

  LyricsDocumentExport? exportLyricsDocument(String trackId) {
    final track = _trackById(trackId);
    final lyrics = _lyricsByTrackId[trackId];
    if (track == null || lyrics == null || lyrics.isEmpty) {
      return null;
    }

    return buildLyricsDocumentExport(
      title: track.title,
      artist: track.artist,
      plainText: lyrics.plainText,
    );
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
    final restoredSavedHistoryViews = <SavedHistoryView>[];
    final restoredPodcastSubscriptions = <PodcastSubscription>[];
    final restoredFollowedArtists = <String>[];
    final restoredHistory = <PlaybackHistoryEntry>[];
    final restoredSearchQueryHistory = <String>[];
    final restoredProgress = <PlaybackProgressEntry>[];
    final restoredLyrics = <TrackLyrics>[];
    final restoredOfflineCacheQueue = <OfflineCacheEntry>[];
    var restoredPauseListeningHistory = false;
    var restoredOfflineModeEnabled = false;
    var restoredThemePreference = AppThemePreference.system;
    var restoredAccentColor = AppAccentColor.indigo;
    var restoredLanguagePreference = AppLanguagePreference.system;
    var restoredOfflineCacheLimitMegabytes =
        defaultOfflineCacheLimitMegabytes;
    var restoredOfflineCacheProviderLimitMegabytes = <String, int>{};

    try {
      restoredPauseListeningHistory = _jsonBool(
        backup,
        'pauseListeningHistory',
        isRequired: false,
      );
      restoredOfflineModeEnabled = _jsonBool(
        backup,
        'offlineModeEnabled',
        isRequired: false,
      );
      restoredThemePreference = _appThemePreferenceFromName(
        _jsonOptionalString(backup, 'themePreference'),
      );
      restoredAccentColor = _appAccentColorFromName(
        _jsonOptionalString(backup, 'accentColor'),
      );
      restoredLanguagePreference = _appLanguagePreferenceFromName(
        _jsonOptionalString(backup, 'languagePreference'),
      );
      restoredOfflineCacheLimitMegabytes = _sanitizeOfflineCacheLimitMegabytes(
        _jsonInt(
          backup,
          'offlineCacheLimitMegabytes',
          isRequired: false,
          defaultValue: defaultOfflineCacheLimitMegabytes,
        ),
      );
      final restoredProviderLimits = _jsonIntMap(
        backup,
        'offlineCacheProviderLimitMegabytes',
        isRequired: false,
      );
      restoredOfflineCacheProviderLimitMegabytes = <String, int>{};
      for (final entry in restoredProviderLimits.entries) {
        final sourceId = _normalizeProviderLimitSourceId(entry.key);
        if (sourceId.isEmpty) {
          continue;
        }

        restoredOfflineCacheProviderLimitMegabytes[sourceId] =
            _sanitizeOfflineCacheProviderLimitMegabytes(entry.value);
      }
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
      restoredSavedHistoryViews.addAll(
        _jsonObjectList(
          backup,
          'savedHistoryViews',
          isRequired: false,
        ).map(SavedHistoryView.fromJson),
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
      restoredFollowedArtists.addAll(
        _jsonStringList(backup, 'followedArtists', isRequired: false),
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
    final sanitizedFollowedArtists = _dedupeFollowedArtists(
      restoredFollowedArtists,
    );
    final sanitizedCustomSmartPlaylists = _dedupeCustomSmartPlaylists(
      restoredCustomSmartPlaylists,
    );
    final sanitizedSavedHistoryViews = _dedupeSavedHistoryViews(
      restoredSavedHistoryViews,
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
    _savedHistoryViews
      ..clear()
      ..addAll(sanitizedSavedHistoryViews);
    _podcastSubscriptions
      ..clear()
      ..addAll(sanitizedPodcastSubscriptions);
    _followedArtists
      ..clear()
      ..addAll(sanitizedFollowedArtists);
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
    _pauseListeningHistory = restoredPauseListeningHistory;
    _offlineModeEnabled = restoredOfflineModeEnabled;
    _themePreference = restoredThemePreference;
    _accentColor = restoredAccentColor;
    _languagePreference = restoredLanguagePreference;
    _offlineCacheLimitMegabytes = restoredOfflineCacheLimitMegabytes;
    _offlineCacheProviderLimitMegabytes
      ..clear()
      ..addAll(restoredOfflineCacheProviderLimitMegabytes);

    _sortTracks();
    _sortPlaylists();
    _sortCustomSmartPlaylists();
    _sortSavedHistoryViews();
    _sortPodcastSubscriptions();
    _sortFollowedArtists();
    _sortHistory();
    _sortOfflineCacheQueue();
    _trimHistory();
    _trimSearchQueryHistory();
    await _save();
    notifyListeners();
  }

  Future<void> restoreSyncSnapshotJson(String snapshotJson) async {
    final decoded = jsonDecode(snapshotJson);
    if (decoded is! Map) {
      throw const FormatException('Sync snapshot must be a JSON object.');
    }
    final snapshot = Map<String, Object?>.from(decoded);
    if (snapshot['syncVersion'] != _syncSnapshotVersion) {
      throw FormatException(
        'Unsupported sync snapshot version: ${snapshot['syncVersion']}.',
      );
    }

    final rawTracks = snapshot['tracks'];
    if (rawTracks is! List) {
      throw const FormatException('Sync snapshot tracks must be a list.');
    }
    final byId = <String, Track>{for (final track in _tracks) track.id: track};
    final byContentHash = _uniqueSyncTrackIndex(
      _tracks,
      (track) => track.contentHash,
    );
    final byProviderIdentity = _uniqueSyncTrackIndex(
      _tracks,
      (track) {
        final externalId = track.externalId?.trim() ?? '';
        final sourceId = track.sourceId.trim();
        if (sourceId.isEmpty || externalId.isEmpty) {
          return null;
        }
        return '$sourceId|$externalId';
      },
    );
    final restoredTracks = <Map<String, Object?>>[];
    for (final item in rawTracks) {
      if (item is! Map) {
        throw const FormatException('Sync snapshot contains an invalid track.');
      }
      final trackJson = Map<String, Object?>.from(item);
      final remoteLocalPath = trackJson['localPath'];
      if (remoteLocalPath is String && remoteLocalPath.trim().isNotEmpty) {
        throw const FormatException(
          'Sync snapshot contains a device-local file path.',
        );
      }
      final id = _syncString(trackJson['id']);
      final contentHash = _syncString(trackJson['contentHash']);
      final sourceId = _syncString(trackJson['sourceId']);
      final externalId = _syncString(trackJson['externalId']);
      final providerKey = sourceId == null || externalId == null
          ? null
          : '$sourceId|$externalId';
      final localTrack = (id == null ? null : byId[id]) ??
          (contentHash == null ? null : byContentHash[contentHash]) ??
          (providerKey == null ? null : byProviderIdentity[providerKey]);
      final localPath = localTrack?.localPath?.trim() ?? '';
      trackJson['localPath'] = localPath.isEmpty ? null : localPath;
      if (contentHash == null && localTrack?.contentHash != null) {
        trackJson['contentHash'] = localTrack!.contentHash;
      }
      if (trackJson['artworkUri'] == null && localTrack?.artworkUri != null) {
        trackJson['artworkUri'] = localTrack!.artworkUri.toString();
      }
      restoredTracks.add(trackJson);
    }

    snapshot
      ..['tracks'] = restoredTracks
      ..['offlineModeEnabled'] = _offlineModeEnabled
      ..['offlineCacheLimitMegabytes'] = _offlineCacheLimitMegabytes
      ..['offlineCacheProviderLimitMegabytes'] =
          Map<String, int>.from(_offlineCacheProviderLimitMegabytes)
      ..['offlineCacheQueue'] = _offlineCacheQueue
          .map((entry) => entry.toJson())
          .toList(growable: false);
    await restoreBackupJson(jsonEncode(snapshot));
  }

  Future<void> mergeSyncSnapshotJson(String snapshotJson) async {
    final localPrivateArtworkByTrackId = <String, Track>{
      for (final track in _tracks)
        if (track.artworkIsUserManaged && track.artworkUri?.scheme == 'file')
          track.id: track,
    };
    final remote = _decodeSyncSnapshot(snapshotJson);
    final local = Map<String, Object?>.from(
      jsonDecode(exportSyncSnapshotJson()) as Map,
    );
    final merged = Map<String, Object?>.from(remote)..addAll(local);

    for (final key in const <String>[
      'customSmartPlaylists',
      'savedHistoryViews',
    ]) {
      merged[key] = _mergeSyncObjectLists(
        local[key],
        remote[key],
        identity: (item) => _syncString(item['id']),
      );
    }
    merged['tracks'] = _mergeSyncTracks(local['tracks'], remote['tracks']);
    merged['podcastSubscriptions'] = _mergeSyncPodcastSubscriptions(
      local['podcastSubscriptions'],
      remote['podcastSubscriptions'],
    );
    merged['followedArtists'] = _mergeSyncStrings(
      local['followedArtists'],
      remote['followedArtists'],
    );
    merged['history'] = _mergeSyncObjectLists(
      local['history'],
      remote['history'],
      identity: (item) {
        final trackId = _syncString(item['trackId']);
        final playedAt = _syncString(item['playedAt']);
        return trackId == null || playedAt == null ? null : '$trackId|$playedAt';
      },
    );
    merged['playlists'] = _mergeSyncPlaylists(local['playlists'], remote['playlists']);
    for (final key in const <String>['progress', 'lyrics']) {
      merged[key] = _mergeSyncObjectLists(
        local[key],
        remote[key],
        identity: (item) => _syncString(item['trackId']),
        preferNewerUpdatedAt: true,
      );
    }
    merged['searchQueryHistory'] = _mergeSyncStrings(
      local['searchQueryHistory'],
      remote['searchQueryHistory'],
    );
    await restoreSyncSnapshotJson(jsonEncode(merged));

    var restoredPrivateArtwork = false;
    for (final entry in localPrivateArtworkByTrackId.entries) {
      final index = _tracks.indexWhere((track) => track.id == entry.key);
      if (index == -1) {
        continue;
      }
      final restored = _tracks[index];
      if (restored.sourceId != 'local') {
        continue;
      }
      final original = entry.value;
      _tracks[index] = restored.copyWith(
        artworkUri: original.artworkUri,
        artworkSourceUri: original.artworkSourceUri,
        artworkIsUserManaged: true,
      );
      restoredPrivateArtwork = true;
    }
    if (restoredPrivateArtwork) {
      await _save();
      notifyListeners();
    }
  }

  Map<String, Object?> _decodeSyncSnapshot(String snapshotJson) {
    final decoded = jsonDecode(snapshotJson);
    if (decoded is! Map) {
      throw const FormatException('Sync snapshot must be a JSON object.');
    }
    final snapshot = Map<String, Object?>.from(decoded);
    if (snapshot['syncVersion'] != _syncSnapshotVersion) {
      throw FormatException(
        'Unsupported sync snapshot version: ${snapshot['syncVersion']}.',
      );
    }
    final tracks = snapshot['tracks'];
    if (tracks is! List) {
      throw const FormatException('Sync snapshot tracks must be a list.');
    }
    for (final item in tracks) {
      if (item is! Map) {
        throw const FormatException('Sync snapshot contains an invalid track.');
      }
      final localPath = item['localPath'];
      if (localPath is String && localPath.trim().isNotEmpty) {
        throw const FormatException('Sync snapshot contains a device-local file path.');
      }
    }
    return snapshot;
  }

  List<Object?> _mergeSyncObjectLists(
    Object? localValue,
    Object? remoteValue, {
    required String? Function(Map<String, Object?> item) identity,
    bool preferNewerUpdatedAt = false,
  }) {
    final merged = <String, Map<String, Object?>>{};
    void add(Object? value, {required bool local}) {
      if (value is! List) {
        return;
      }
      for (final item in value) {
        if (item is! Map) {
          continue;
        }
        final json = Map<String, Object?>.from(item);
        final id = identity(json);
        if (id == null || id.isEmpty) {
          continue;
        }
        final existing = merged[id];
        if (existing == null ||
            (preferNewerUpdatedAt
                ? _syncUpdatedAt(json).isAfter(_syncUpdatedAt(existing))
                : local)) {
          merged[id] = json;
        }
      }
    }

    add(remoteValue, local: false);
    add(localValue, local: true);
    return merged.values.toList(growable: false);
  }

  List<Object?> _mergeSyncPlaylists(Object? localValue, Object? remoteValue) {
    final remote = _mergeSyncObjectLists(
      null,
      remoteValue,
      identity: (item) => _syncString(item['id']),
    );
    final byId = <String, Map<String, Object?>>{
      for (final item in remote.whereType<Map>())
        if (_syncString(item['id']) case final id?) id: Map<String, Object?>.from(item),
    };
    if (localValue is List) {
      for (final item in localValue) {
        if (item is! Map) {
          continue;
        }
        final local = Map<String, Object?>.from(item);
        final id = _syncString(local['id']);
        if (id == null || id.isEmpty) {
          continue;
        }
        final remotePlaylist = byId[id];
        if (remotePlaylist != null) {
          local['trackIds'] = _mergeSyncStrings(
            local['trackIds'],
            remotePlaylist['trackIds'],
          );
        }
        byId[id] = local;
      }
    }
    return byId.values.toList(growable: false);
  }

  List<Object?> _mergeSyncTracks(Object? localValue, Object? remoteValue) {
    final remote = _mergeSyncObjectLists(
      null,
      remoteValue,
      identity: (item) => _syncString(item['id']),
    );
    final byId = <String, Map<String, Object?>>{
      for (final item in remote.whereType<Map>())
        if (_syncString(item['id']) case final id?)
          id: Map<String, Object?>.from(item),
    };
    if (localValue is List) {
      for (final item in localValue) {
        if (item is! Map) {
          continue;
        }
        final local = Map<String, Object?>.from(item);
        final id = _syncString(local['id']);
        if (id == null || id.isEmpty) {
          continue;
        }
        final remoteTrack = byId[id];
        if (remoteTrack != null) {
          local['isFavorite'] =
              local['isFavorite'] == true || remoteTrack['isFavorite'] == true;
        }
        byId[id] = local;
      }
    }
    return byId.values.toList(growable: false);
  }

  List<Object?> _mergeSyncPodcastSubscriptions(
    Object? localValue,
    Object? remoteValue,
  ) {
    final remote = _mergeSyncObjectLists(
      null,
      remoteValue,
      identity: (item) => _syncString(item['id']),
    );
    final byId = <String, Map<String, Object?>>{
      for (final item in remote.whereType<Map>())
        if (_syncString(item['id']) case final id?)
          id: Map<String, Object?>.from(item),
    };
    if (localValue is List) {
      for (final item in localValue) {
        if (item is! Map) {
          continue;
        }
        final local = Map<String, Object?>.from(item);
        final id = _syncString(local['id']);
        if (id == null || id.isEmpty) {
          continue;
        }
        final remoteSubscription = byId[id];
        if (remoteSubscription != null) {
          local['episodes'] = _mergeSyncPodcastEpisodes(
            local['episodes'],
            remoteSubscription['episodes'],
          );
        }
        byId[id] = local;
      }
    }
    return byId.values.toList(growable: false);
  }

  List<Object?> _mergeSyncPodcastEpisodes(
    Object? localValue,
    Object? remoteValue,
  ) {
    final merged = <Object?>[];
    final ids = <String>{};
    for (final value in <Object?>[localValue, remoteValue]) {
      if (value is! List) {
        continue;
      }
      for (final item in value) {
        if (item is! Map) {
          continue;
        }
        final episode = Map<String, Object?>.from(item);
        final id = _syncString(episode['id']);
        if (id == null || id.isEmpty || !ids.add(id)) {
          continue;
        }
        merged.add(episode);
        if (merged.length == maxCachedPodcastEpisodesPerSubscription) {
          return merged;
        }
      }
    }
    return merged;
  }

  List<Object?> _mergeSyncStrings(Object? localValue, Object? remoteValue) {
    final values = <String>[];
    for (final value in <Object?>[localValue, remoteValue]) {
      if (value is! List) {
        continue;
      }
      for (final item in value) {
        if (item is String && item.trim().isNotEmpty && !values.contains(item)) {
          values.add(item);
        }
      }
    }
    return values;
  }

  DateTime _syncUpdatedAt(Map<String, Object?> item) {
    return DateTime.tryParse(item['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  Playlist? playlistById(String id) {
    final index = _playlists.indexWhere((playlist) => playlist.id == id);
    if (index == -1) {
      return null;
    }

    return _playlists[index];
  }

  Track? _trackById(String id) {
    final index = _tracks.indexWhere((track) => track.id == id);
    if (index == -1) {
      return null;
    }

    return _tracks[index];
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
    final searchQuery = SearchQuery.parse(query);
    if (searchQuery.isEmpty) {
      return tracks;
    }

    return tracks
        .where((track) => _trackMatchesQuery(track, searchQuery))
        .toList(growable: false);
  }

  List<Track> recentlyPlayedTracks({
    int limit = 25,
    DateTime? from,
    DateTime? to,
    String query = '',
  }) {
    if (limit <= 0) {
      return <Track>[];
    }

    final searchQuery = SearchQuery.parse(query);
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

      if (!searchQuery.isEmpty && !_trackMatchesQuery(track, searchQuery)) {
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

  List<PlaybackHistoryEntry> playbackHistoryEntries({
    int limit = 50,
    DateTime? from,
    DateTime? to,
    String query = '',
  }) {
    if (limit <= 0) {
      return <PlaybackHistoryEntry>[];
    }

    final searchQuery = SearchQuery.parse(query);
    final byId = <String, Track>{
      for (final track in _tracks) track.id: track,
    };
    final entries = <PlaybackHistoryEntry>[];

    for (final entry in _history) {
      if (!_historyEntryInRange(entry, from: from, to: to)) {
        continue;
      }

      if (!searchQuery.isEmpty) {
        final track = byId[entry.trackId];
        if (track == null || !_trackMatchesQuery(track, searchQuery)) {
          continue;
        }
      }

      entries.add(entry);
      if (entries.length >= limit) {
        break;
      }
    }

    return entries;
  }

  Future<void> removePlaybackHistoryEntry(
    PlaybackHistoryEntry entryToRemove,
  ) async {
    final index = _history.indexWhere(
      (entry) => _samePlaybackHistoryEntry(entry, entryToRemove),
    );
    if (index == -1) {
      return;
    }

    _history.removeAt(index);
    await _save();
    notifyListeners();
  }

  List<Track> recentlyAddedTracks({int limit = 25}) {
    if (limit <= 0) {
      return <Track>[];
    }

    return tracks.take(limit).toList(growable: false);
  }

  List<Track> _recentPlayableTracks({required int limit}) {
    if (limit <= 0) {
      return <Track>[];
    }

    return _tracks
        .where((track) => track.isPlayable)
        .take(limit)
        .toList(growable: false);
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

  DateTime _calendarDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  bool _samePlaybackHistoryEntry(
    PlaybackHistoryEntry left,
    PlaybackHistoryEntry right,
  ) {
    return left.trackId == right.trackId &&
        left.playedAt.isAtSameMomentAs(right.playedAt);
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

  DateTime _listeningRecapStart(DateTime value, LibraryRecapPeriod period) {
    switch (period) {
      case LibraryRecapPeriod.month:
        return value.isUtc
            ? DateTime.utc(value.year, value.month)
            : DateTime(value.year, value.month);
      case LibraryRecapPeriod.year:
        return value.isUtc ? DateTime.utc(value.year) : DateTime(value.year);
    }
  }

  DateTime _listeningRecapEnd(DateTime start, LibraryRecapPeriod period) {
    switch (period) {
      case LibraryRecapPeriod.month:
        return start.isUtc
            ? DateTime.utc(start.year, start.month + 1)
            : DateTime(start.year, start.month + 1);
      case LibraryRecapPeriod.year:
        return start.isUtc
            ? DateTime.utc(start.year + 1)
            : DateTime(start.year + 1);
    }
  }

  int _moodScoreForTrack(LibraryMoodMixType type, Track track) {
    final text = _discoveryTextForTrack(track);
    var score = 0;

    for (final keyword in _moodKeywords(type)) {
      if (text.contains(keyword)) {
        score += 24;
      }
    }

    final genre = _knownMetadataKey(track.genre);
    if (genre != null) {
      for (final keyword in _moodKeywords(type)) {
        if (genre.contains(keyword)) {
          score += 18;
        }
      }
    }

    if (score <= 0) {
      return 0;
    }

    switch (type) {
      case LibraryMoodMixType.focus:
        if (track.duration >= const Duration(minutes: 4)) {
          score += 4;
        }
        break;
      case LibraryMoodMixType.energy:
      case LibraryMoodMixType.workout:
        if (track.duration <= const Duration(minutes: 6)) {
          score += 4;
        }
        break;
      case LibraryMoodMixType.chill:
      case LibraryMoodMixType.sleep:
        if (track.duration >= const Duration(minutes: 3)) {
          score += 4;
        }
        break;
    }

    return score;
  }

  int _boostedDiscoveryScore(int baseScore, Track track) {
    var score = baseScore;
    if (track.isFavorite) {
      score += 10;
    }
    score += playCountForTrack(track.id) * 3;
    return score;
  }

  String _discoveryTextForTrack(Track track) {
    return <String>[
      track.title,
      track.artist,
      track.album,
      track.genre,
    ].join(' ').toLowerCase();
  }

  List<String> _moodKeywords(LibraryMoodMixType type) {
    switch (type) {
      case LibraryMoodMixType.focus:
        return const <String>[
          'ambient',
          'classical',
          'deep',
          'focus',
          'instrumental',
          'lofi',
          'lo-fi',
          'piano',
          'study',
        ];
      case LibraryMoodMixType.energy:
        return const <String>[
          'dance',
          'edm',
          'electronic',
          'energy',
          'party',
          'pop',
          'power',
          'rock',
          'upbeat',
        ];
      case LibraryMoodMixType.chill:
        return const <String>[
          'acoustic',
          'chill',
          'jazz',
          'lounge',
          'mellow',
          'relax',
          'r&b',
          'soul',
        ];
      case LibraryMoodMixType.workout:
        return const <String>[
          'cardio',
          'energy',
          'gym',
          'hip hop',
          'metal',
          'power',
          'run',
          'running',
          'trap',
          'workout',
        ];
      case LibraryMoodMixType.sleep:
        return const <String>[
          'ambient',
          'calm',
          'drone',
          'lullaby',
          'meditation',
          'night',
          'sleep',
        ];
    }
  }

  String _moodMixName(LibraryMoodMixType type) {
    switch (type) {
      case LibraryMoodMixType.focus:
        return 'Focus mix';
      case LibraryMoodMixType.energy:
        return 'Energy mix';
      case LibraryMoodMixType.chill:
        return 'Chill mix';
      case LibraryMoodMixType.workout:
        return 'Workout mix';
      case LibraryMoodMixType.sleep:
        return 'Sleep mix';
    }
  }

  String _moodMixDescription(LibraryMoodMixType type) {
    switch (type) {
      case LibraryMoodMixType.focus:
        return 'Local tracks for deep listening';
      case LibraryMoodMixType.energy:
        return 'Upbeat local picks';
      case LibraryMoodMixType.chill:
        return 'Relaxed local picks';
      case LibraryMoodMixType.workout:
        return 'High-momentum local tracks';
      case LibraryMoodMixType.sleep:
        return 'Calm local tracks';
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
    if (_pauseListeningHistory) {
      return;
    }

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
    if (_pauseListeningHistory) {
      return;
    }

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
      episodes: subscription.episodes.isEmpty
          ? existing?.episodes ?? const <Track>[]
          : subscription.episodes,
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

  Future<void> setLyrics(
    String trackId,
    String plainText, {
    String sourceId = 'manual',
    String sourceName = '',
    String sourceExternalId = '',
    Uri? sourceUri,
  }) async {
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
      sourceId: sourceId.trim().isEmpty ? 'manual' : sourceId.trim(),
      sourceName: sourceName.trim(),
      sourceExternalId: sourceExternalId.trim(),
      sourceUri: sourceUri,
      updatedAt: _clock(),
    );
    await _save();
    notifyListeners();
  }

  Future<void> setLyricsIfAbsent(
    String trackId,
    String plainText, {
    String sourceId = 'manual',
    String sourceName = '',
    String sourceExternalId = '',
    Uri? sourceUri,
  }) async {
    if (_lyricsByTrackId.containsKey(trackId)) {
      return;
    }

    await setLyrics(
      trackId,
      plainText,
      sourceId: sourceId,
      sourceName: sourceName,
      sourceExternalId: sourceExternalId,
      sourceUri: sourceUri,
    );
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
    String sourceId = '',
    String artist = '',
    String album = '',
    String genre = '',
    int minimumDurationSeconds = 0,
    int maximumDurationSeconds = 0,
    bool favoritesOnly = false,
    int minimumPlayCount = 0,
    int minimumDaysSinceLastPlayed = 0,
    CustomSmartPlaylistMatchMode matchMode = CustomSmartPlaylistMatchMode.all,
    List<CustomSmartPlaylistRuleGroup> ruleGroups =
        const <CustomSmartPlaylistRuleGroup>[],
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
      sourceId: sourceId.trim(),
      artist: artist.trim(),
      album: album.trim(),
      genre: genre.trim(),
      minimumDurationSeconds: _sanitizeMinimumPlayCount(minimumDurationSeconds),
      maximumDurationSeconds: _sanitizeMinimumPlayCount(maximumDurationSeconds),
      favoritesOnly: favoritesOnly,
      minimumPlayCount: _sanitizeMinimumPlayCount(minimumPlayCount),
      minimumDaysSinceLastPlayed:
          _sanitizeMinimumPlayCount(minimumDaysSinceLastPlayed),
      matchMode: matchMode,
      ruleGroups: _normalizeCustomSmartPlaylistRuleGroups(ruleGroups),
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
    String? sourceId,
    String? artist,
    String? album,
    String? genre,
    int? minimumDurationSeconds,
    int? maximumDurationSeconds,
    required bool favoritesOnly,
    required int minimumPlayCount,
    int? minimumDaysSinceLastPlayed,
    required CustomSmartPlaylistMatchMode matchMode,
    List<CustomSmartPlaylistRuleGroup>? ruleGroups,
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
      sourceId: sourceId?.trim(),
      artist: artist?.trim(),
      album: album?.trim(),
      genre: genre?.trim(),
      minimumDurationSeconds: minimumDurationSeconds == null
          ? null
          : _sanitizeMinimumPlayCount(minimumDurationSeconds),
      maximumDurationSeconds: maximumDurationSeconds == null
          ? null
          : _sanitizeMinimumPlayCount(maximumDurationSeconds),
      favoritesOnly: favoritesOnly,
      minimumPlayCount: _sanitizeMinimumPlayCount(minimumPlayCount),
      minimumDaysSinceLastPlayed: minimumDaysSinceLastPlayed == null
          ? null
          : _sanitizeMinimumPlayCount(minimumDaysSinceLastPlayed),
      matchMode: matchMode,
      ruleGroups: ruleGroups == null
          ? null
          : _normalizeCustomSmartPlaylistRuleGroups(ruleGroups),
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

  Future<SavedHistoryView> createSavedHistoryView({
    required String name,
    String query = '',
    ListeningHistoryRange range = ListeningHistoryRange.all,
  }) async {
    final normalizedName = _normalizeSavedHistoryViewName(name);
    final now = _clock();
    final view = SavedHistoryView(
      id: _savedHistoryViewId(normalizedName, now),
      name: normalizedName,
      query: query.trim(),
      range: range,
      createdAt: now,
      updatedAt: now,
    );

    _savedHistoryViews.add(view);
    _sortSavedHistoryViews();
    await _save();
    notifyListeners();
    return view;
  }

  Future<SavedHistoryView?> updateSavedHistoryView(
    String id, {
    required String name,
    required String query,
    required ListeningHistoryRange range,
  }) async {
    final index = _savedHistoryViews.indexWhere((view) => view.id == id);
    if (index == -1) {
      return null;
    }

    final updated = _savedHistoryViews[index].copyWith(
      name: _normalizeSavedHistoryViewName(name),
      query: query.trim(),
      range: range,
      updatedAt: _clock(),
    );
    _savedHistoryViews[index] = updated;
    _sortSavedHistoryViews();
    await _save();
    notifyListeners();
    return updated;
  }

  Future<void> deleteSavedHistoryView(String id) async {
    final index = _savedHistoryViews.indexWhere((view) => view.id == id);
    if (index == -1) {
      return;
    }

    _savedHistoryViews.removeAt(index);
    await _save();
    notifyListeners();
  }

  Future<Playlist> createPlaylist(
    String name, {
    Iterable<String> trackIds = const <String>[],
    Uri? artworkUri,
    String folder = '',
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
      folder: folder.trim(),
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

  Future<Playlist?> updatePlaylistFolder(
    String playlistId,
    String folder,
  ) async {
    final index = _playlists.indexWhere((playlist) => playlist.id == playlistId);
    if (index == -1) {
      return null;
    }

    final normalizedFolder = folder.trim();
    final existing = _playlists[index];
    if (existing.folder == normalizedFolder) {
      return existing;
    }

    final updated = existing.copyWith(
      folder: normalizedFolder,
      updatedAt: _clock(),
    );
    _playlists[index] = updated;
    _sortPlaylists();
    await _save();
    notifyListeners();
    return updated;
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

  String _shareTrackText(Track track) {
    final buffer = StringBuffer()
      ..writeln('AetherTune track')
      ..writeln('Title: ${_shareTextValue(track.title, 'Untitled')}')
      ..writeln('Artist: ${_shareTextValue(track.artist, 'Unknown Artist')}')
      ..writeln('Album: ${_shareTextValue(track.album, 'Unknown Album')}')
      ..writeln('Genre: ${_shareTextValue(track.genre, 'Unknown Genre')}')
      ..writeln('Duration: ${_shareDuration(track.duration)}')
      ..writeln('Source: ${_shareTextValue(track.sourceId, 'local')}');

    final link = _shareableWebUrl(track.streamUrl);
    final artworkUrl = _shareableWebUrl(track.artworkUri?.toString());
    if (link != null) {
      buffer.writeln('Link: $link');
    } else if (track.hasLocalSource) {
      buffer.writeln('Availability: Local file');
    } else if (track.hasStreamSource) {
      buffer.writeln('Availability: Stream');
    } else {
      buffer.writeln('Availability: Metadata only');
    }
    if (artworkUrl != null) {
      buffer.writeln('Artwork: $artworkUrl');
    }

    return buffer.toString().trimRight();
  }

  void _writeShareTrackList(StringBuffer buffer, List<Track> tracks) {
    for (final entry in tracks.asMap().entries) {
      buffer.writeln('${entry.key + 1}. ${_shareTrackSummary(entry.value)}');
    }
  }

  String _shareTrackSummary(Track track) {
    final title = _shareTextValue(track.title, 'Untitled');
    final artist = _shareTextValue(track.artist, 'Unknown Artist');
    final album = _shareTextValue(track.album, 'Unknown Album');

    return '$artist - $title ($album)';
  }

  String _shareBrowseGroupLabel(LibraryBrowseType type, Track firstTrack) {
    final label = _browseLabelForTrack(firstTrack, type);
    if (type == LibraryBrowseType.folder) {
      return _shareFolderName(label);
    }

    return _shareTextValue(label, 'Unknown ${_shareBrowseTypeName(type)}');
  }

  String _shareFolderName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'Remote Streams') {
      return trimmed.isEmpty ? 'Unknown Folder' : trimmed;
    }

    final context = _looksLikeWindowsPath(trimmed)
        ? _windowsPathContext
        : _posixPathContext;
    final basename = context.basename(trimmed).trim();
    if (basename.isEmpty || basename == '.' || basename == trimmed) {
      return 'Local folder';
    }

    return basename;
  }

  String _shareBrowseTypeName(LibraryBrowseType type) {
    switch (type) {
      case LibraryBrowseType.artist:
        return 'artist';
      case LibraryBrowseType.album:
        return 'album';
      case LibraryBrowseType.genre:
        return 'genre';
      case LibraryBrowseType.source:
        return 'source';
      case LibraryBrowseType.folder:
        return 'folder';
    }
  }

  List<String> _shareLyricsLines(TrackLyrics lyrics) {
    final syncedLines = lyrics.syncedLines;
    if (syncedLines.isNotEmpty) {
      return syncedLines
          .map((line) => line.text.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false);
    }

    return lyrics.plainText
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
  }

  Duration _totalDuration(Iterable<Track> tracks) {
    return tracks.fold<Duration>(
      Duration.zero,
      (total, track) => total + track.duration,
    );
  }

  String _shareDuration(Duration duration) {
    if (duration <= Duration.zero) {
      return 'Unknown';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }

    return '${duration.inMinutes}:$seconds';
  }

  String _shareTextValue(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String? _shareableWebUrl(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }

    return trimmed;
  }

  Map<String, Object?> _portableSyncTrackJson(Track track) {
    final json = _portableTrackArtworkJson(track);
    json
      ..['localPath'] = null
      ..['streamUrl'] = _portableSyncUri(
        json['streamUrl'] as String?,
        allowData: false,
      );
    return json;
  }

  Future<CustomSmartPlaylist?> updateCustomSmartPlaylistArtwork(
    String id,
    Uri? artworkUri,
  ) async {
    final index = _customSmartPlaylists.indexWhere((rule) => rule.id == id);
    if (index == -1) {
      return null;
    }
    if (artworkUri != null &&
        artworkUri.scheme != 'file' &&
        artworkUri.scheme != 'http' &&
        artworkUri.scheme != 'https') {
      throw ArgumentError.value(
        artworkUri,
        'artworkUri',
        'Artwork must use a file, http, or https URI.',
      );
    }
    final updated = _customSmartPlaylists[index].copyWith(
      artworkUri: artworkUri,
      clearArtworkUri: artworkUri == null,
      updatedAt: _clock(),
    );
    _customSmartPlaylists[index] = updated;
    _sortCustomSmartPlaylists();
    await _save();
    notifyListeners();
    return updated;
  }

  Map<String, Object?> _portableTrackArtworkJson(Track track) {
    final json = track.toJson();
    final portableArtwork = _portableSyncUri(
      json['artworkUri'] as String?,
      allowData: true,
    );
    final portableSourceArtwork = _portableSyncUri(
      json['artworkSourceUri'] as String?,
      allowData: true,
    );
    final hasPortableManagedArtwork =
        track.artworkIsUserManaged && portableArtwork != null;
    json
      ..['artworkUri'] = portableArtwork ?? portableSourceArtwork
      ..['artworkSourceUri'] = hasPortableManagedArtwork
          ? portableSourceArtwork
          : null
      ..['artworkIsUserManaged'] = hasPortableManagedArtwork;
    return json;
  }

  Future<void> setAutomaticOfflineQueueEnabled(bool enabled) async {
    if (_automaticOfflineQueueEnabled == enabled) {
      return;
    }
    _automaticOfflineQueueEnabled = enabled;
    await _save();
    notifyListeners();
  }

  Map<String, Object?> _portablePlaylistJson(Playlist playlist) {
    final json = playlist.toJson();
    json['artworkUri'] = _portableSyncUri(
      json['artworkUri'] as String?,
      allowData: false,
    );
    return json;
  }

  String? _portableSyncUri(
    String? value, {
    required bool allowData,
  }) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return null;
    }
    if (allowData && uri.scheme == 'data') {
      return trimmed;
    }
    if ((uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    const sensitiveKeys = <String>{
      'api_key',
      'apikey',
      'p',
      'password',
      't',
      'token',
      'access_token',
      'authorization',
      'auth',
      'signature',
      'sig',
    };
    if (uri.queryParameters.keys.any(
      (key) => sensitiveKeys.contains(key.toLowerCase()),
    )) {
      return null;
    }
    return uri.toString();
  }

  Map<String, Track> _uniqueSyncTrackIndex(
    Iterable<Track> tracks,
    String? Function(Track track) keyFor,
  ) {
    final result = <String, Track>{};
    final duplicates = <String>{};
    for (final track in tracks) {
      final key = keyFor(track)?.trim();
      if (key == null || key.isEmpty || duplicates.contains(key)) {
        continue;
      }
      if (result.containsKey(key)) {
        result.remove(key);
        duplicates.add(key);
      } else {
        result[key] = track;
      }
    }
    return result;
  }

  String? _syncString(Object? value) => _stringValue(value);

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

  bool _trackMatchesQuery(Track track, SearchQuery query) {
    final metadataMatches = searchFieldsMatch(
      <String>[
        track.title,
        track.artist,
        track.album,
        track.genre,
        _browseLabelForTrack(track, LibraryBrowseType.source),
        _browseLabelForTrack(track, LibraryBrowseType.folder),
      ],
      query,
    );
    if (metadataMatches) {
      return true;
    }

    final lyrics = _lyricsByTrackId[track.id];
    if (lyrics == null) {
      return false;
    }

    return searchFieldsMatch(_shareLyricsLines(lyrics), query);
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

  int _compareDiscoveryCandidates(
    _DiscoveryCandidate a,
    _DiscoveryCandidate b,
  ) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }

    if (a.track.isFavorite != b.track.isFavorite) {
      return a.track.isFavorite ? -1 : 1;
    }

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

    return _compareByDateThenTitle(a.track, b.track);
  }

  int _compareRecommendationCandidates(
    _DiscoveryCandidate a,
    _DiscoveryCandidate b,
  ) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }

    final byPlayCount = a.playCount.compareTo(b.playCount);
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

    return _compareByDateThenTitle(a.track, b.track);
  }

  int _compareSimilarityCandidates(
    _SimilarityCandidate a,
    _SimilarityCandidate b,
  ) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) {
      return byScore;
    }

    if (a.track.isFavorite != b.track.isFavorite) {
      return a.track.isFavorite ? -1 : 1;
    }

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

    return _compareByDateThenTitle(a.track, b.track);
  }

  List<LibrarySimilarityReason> _similarityReasonsForTrack(
    Track seedTrack,
    Track track,
  ) {
    final reasons = <LibrarySimilarityReason>[];
    if (_sameKnownMetadata(seedTrack.artist, track.artist)) {
      reasons.add(LibrarySimilarityReason.artist);
    }
    if (_sameKnownMetadata(seedTrack.album, track.album)) {
      reasons.add(LibrarySimilarityReason.album);
    }
    if (_sameKnownMetadata(seedTrack.genre, track.genre)) {
      reasons.add(LibrarySimilarityReason.genre);
    }
    if (_sameKnownMetadata(
      _folderLabelForTrack(seedTrack),
      _folderLabelForTrack(track),
    )) {
      reasons.add(LibrarySimilarityReason.folder);
    }
    if (_sameKnownMetadata(seedTrack.sourceId, track.sourceId)) {
      reasons.add(LibrarySimilarityReason.source);
    }

    return reasons;
  }

  bool _isCoreSimilarityReason(LibrarySimilarityReason reason) {
    switch (reason) {
      case LibrarySimilarityReason.artist:
      case LibrarySimilarityReason.album:
      case LibrarySimilarityReason.genre:
        return true;
      case LibrarySimilarityReason.folder:
      case LibrarySimilarityReason.source:
        return false;
    }
  }

  int _similarityScoreForTrack(
    Track track,
    List<LibrarySimilarityReason> reasons,
  ) {
    var score = 0;
    for (final reason in reasons) {
      switch (reason) {
        case LibrarySimilarityReason.artist:
          score += 100;
          break;
        case LibrarySimilarityReason.album:
          score += 70;
          break;
        case LibrarySimilarityReason.genre:
          score += 35;
          break;
        case LibrarySimilarityReason.folder:
          score += 12;
          break;
        case LibrarySimilarityReason.source:
          score += 8;
          break;
      }
    }

    if (track.isFavorite) {
      score += 10;
    }
    score += playCountForTrack(track.id) * 3;

    return score;
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
    final normalizedLeft = _knownMetadataKey(left);
    final normalizedRight = _knownMetadataKey(right);
    if (normalizedLeft == null || normalizedRight == null) {
      return false;
    }

    return normalizedLeft == normalizedRight;
  }

  String? _knownMetadataKey(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == 'unknown' ||
        normalized.startsWith('unknown ')) {
      return null;
    }

    return normalized;
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

    final context = _pathContextFor(localPath);
    final directory = context.dirname(localPath);
    if (directory == '.' || directory == localPath) {
      return 'Unknown Folder';
    }

    return _nonEmptyMetadata(directory, 'Unknown Folder');
  }

  path.Context _pathContextFor(String value) {
    return _looksLikeWindowsPath(value)
        ? _windowsPathContext
        : _posixPathContext;
  }

  List<String> _folderAncestors(String folderPath, path.Context context) {
    final parts = context.split(folderPath);
    final ancestors = <String>[];
    var current = '';

    for (final part in parts) {
      if (part.trim().isEmpty) {
        continue;
      }

      current = current.isEmpty ? part : context.join(current, part);
      if (current == context.dirname(current)) {
        continue;
      }

      ancestors.add(current);
    }

    return ancestors;
  }

  String _folderTreeLabel(String folderPath, path.Context context) {
    final label = context.basename(folderPath).trim();
    return label.isEmpty ? folderPath : label;
  }

  String _folderTreeKey(String value) {
    return _nonEmptyMetadata(value, '').replaceAll('\\', '/').toLowerCase();
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

  String _normalizeSavedHistoryViewName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Saved history view name cannot be empty.',
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

  void _sortSavedHistoryViews() {
    _savedHistoryViews.sort(
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

  String _savedHistoryViewId(String name, DateTime createdAt) {
    final base = 'history-${createdAt.microsecondsSinceEpoch}-$name';
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

  int _jsonInt(
    Map<String, Object?> backup,
    String key, {
    bool isRequired = true,
    int defaultValue = 0,
  }) {
    final rawValue = backup[key];
    if (rawValue == null && !isRequired) {
      return defaultValue;
    }

    if (rawValue is! int) {
      throw FormatException('Backup field "$key" must be an integer.');
    }

    return rawValue;
  }

  Map<String, int> _jsonIntMap(
    Map<String, Object?> backup,
    String key, {
    bool isRequired = true,
  }) {
    final rawValue = backup[key];
    if (rawValue == null && !isRequired) {
      return <String, int>{};
    }
    if (rawValue is! Map) {
      throw FormatException('Backup field "$key" must be an object.');
    }

    final values = <String, int>{};
    for (final entry in rawValue.entries) {
      final sourceId = entry.key;
      final megabytes = entry.value;
      if (sourceId is! String || megabytes is! int) {
        throw FormatException(
          'Backup field "$key" must map strings to integers.',
        );
      }

      values[sourceId] = megabytes;
    }

    return values;
  }

  int _sanitizeOfflineCacheLimitMegabytes(int megabytes) {
    if (megabytes < minOfflineCacheLimitMegabytes) {
      return minOfflineCacheLimitMegabytes;
    }
    if (megabytes > maxOfflineCacheLimitMegabytes) {
      return maxOfflineCacheLimitMegabytes;
    }

    return megabytes;
  }

  Map<String, double> _decodeTrackPlaybackSpeedOverrides(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <String, double>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, double>{};
      }
      final overrides = <String, double>{};
      for (final entry in decoded.entries) {
        final trackId = entry.key.toString().trim();
        final speed = entry.value is num ? (entry.value as num).toDouble() : null;
        if (trackId.isNotEmpty && speed != null && isSupportedPlaybackSpeed(speed)) {
          overrides[trackId] = speed;
        }
      }
      return overrides;
    } on FormatException {
      return <String, double>{};
    }
  }

  double _sanitizeDesktopQueuePaneWidth(double width) {
    if (!width.isFinite) {
      return defaultDesktopQueuePaneWidth;
    }
    return width
        .clamp(minDesktopQueuePaneWidth, maxDesktopQueuePaneWidth)
        .toDouble();
  }

  int _sanitizeOfflineCacheProviderLimitMegabytes(int megabytes) {
    if (megabytes < minOfflineCacheProviderLimitMegabytes) {
      return minOfflineCacheProviderLimitMegabytes;
    }
    if (megabytes > maxOfflineCacheLimitMegabytes) {
      return maxOfflineCacheLimitMegabytes;
    }

    return megabytes;
  }

  String _normalizeProviderLimitSourceId(String sourceId) {
    return sourceId.trim().toLowerCase();
  }

  Map<String, int> _decodeOfflineCacheProviderLimits(String? rawJson) {
    if (rawJson == null || rawJson.isEmpty) {
      return <String, int>{};
    }

    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      return <String, int>{};
    }

    final limits = <String, int>{};
    for (final entry in decoded.entries) {
      final sourceId = entry.key;
      final megabytes = entry.value;
      if (sourceId is! String || megabytes is! int) {
        continue;
      }

      final normalized = _normalizeProviderLimitSourceId(sourceId);
      if (normalized.isEmpty) {
        continue;
      }

      limits[normalized] =
          _sanitizeOfflineCacheProviderLimitMegabytes(megabytes);
    }

    return limits;
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

  Map<String, Object?> _portableCustomSmartPlaylistJson(
    CustomSmartPlaylist playlist,
  ) {
    final json = playlist.toJson();
    json['artworkUri'] = _portableSyncUri(
      json['artworkUri'] as String?,
      allowData: false,
    );
    return json;
  }

  String _followedArtistKey(String artist) => artist.trim().toLowerCase();

  List<String> _dedupeFollowedArtists(Iterable<String> artists) {
    final values = <String>[];
    final seen = <String>{};
    for (final artist in artists) {
      final normalized = artist.trim();
      if (!canFollowArtist(normalized)) {
        continue;
      }
      if (!seen.add(_followedArtistKey(normalized))) {
        continue;
      }
      values.add(normalized);
    }
    values.sort(_compareText);
    return values;
  }

  void _sortFollowedArtists() {
    final normalized = _dedupeFollowedArtists(_followedArtists);
    _followedArtists
      ..clear()
      ..addAll(normalized);
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
        artist: rule.artist.trim(),
        album: rule.album.trim(),
        minimumPlayCount: _sanitizeMinimumPlayCount(rule.minimumPlayCount),
        minimumDaysSinceLastPlayed:
            _sanitizeMinimumPlayCount(rule.minimumDaysSinceLastPlayed),
        matchMode: rule.matchMode,
        ruleGroups: _normalizeCustomSmartPlaylistRuleGroups(rule.ruleGroups),
        limit: _sanitizeCustomSmartPlaylistLimit(rule.limit),
      );
    }

    return byId.values.toList(growable: false);
  }

  List<CustomSmartPlaylistRuleGroup> _normalizeCustomSmartPlaylistRuleGroups(
    Iterable<CustomSmartPlaylistRuleGroup> groups,
  ) {
    return groups
        .map((group) => group.normalized())
        .whereType<CustomSmartPlaylistRuleGroup>()
        .take(25)
        .toList(growable: false);
  }

  List<SavedHistoryView> _dedupeSavedHistoryViews(
    Iterable<SavedHistoryView> views,
  ) {
    final byId = <String, SavedHistoryView>{};
    for (final view in views) {
      final id = view.id.trim();
      final name = view.name.trim();
      if (id.isEmpty || name.isEmpty) {
        continue;
      }

      byId[id] = view.copyWith(
        id: id,
        name: name,
        query: view.query.trim(),
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
        episodes: subscription.episodes,
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
    int? cachedByteCount,
    String? cachedMediaChecksum,
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
      cachedByteCount: cachedByteCount,
      cachedMediaChecksum: cachedMediaChecksum,
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
    final encodedSavedHistoryViews = jsonEncode(
      _savedHistoryViews.map((view) => view.toJson()).toList(),
    );
    final encodedPodcastSubscriptions = jsonEncode(
      _podcastSubscriptions.map((item) => item.toJson()).toList(),
    );
    final followedArtists = _dedupeFollowedArtists(_followedArtists);
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
    await prefs.setString(_savedHistoryViewsKey, encodedSavedHistoryViews);
    await prefs.setString(
      _podcastSubscriptionsKey,
      encodedPodcastSubscriptions,
    );
    await prefs.setStringList(_followedArtistsKey, followedArtists);
    await prefs.setString(_historyKey, encodedHistory);
    await prefs.setString(_searchQueryHistoryKey, encodedSearchQueryHistory);
    await prefs.setString(_progressKey, encodedProgress);
    await prefs.setString(_lyricsKey, encodedLyrics);
    await prefs.setBool(_pauseListeningHistoryKey, _pauseListeningHistory);
    await prefs.setBool(_offlineModeKey, _offlineModeEnabled);
    await prefs.setBool(
      _automaticOfflineQueueKey,
      _automaticOfflineQueueEnabled,
    );
    await prefs.setString(_themePreferenceKey, _themePreference.name);
    await prefs.setString(_accentColorKey, _accentColor.name);
    await prefs.setString(
      _languagePreferenceKey,
      _languagePreference.name,
    );
    await prefs.setString(
      _trackPlaybackSpeedOverridesKey,
      jsonEncode(_trackPlaybackSpeedOverrides),
    );
    await prefs.setDouble(_desktopQueuePaneWidthKey, _desktopQueuePaneWidth);
    await prefs.setBool(_onboardingCompletedKey, _onboardingCompleted);
    await prefs.setInt(
      _offlineCacheLimitMegabytesKey,
      _offlineCacheLimitMegabytes,
    );
    await prefs.setString(
      _offlineCacheProviderLimitMegabytesKey,
      jsonEncode(_offlineCacheProviderLimitMegabytes),
    );
    await prefs.setString(_offlineCacheQueueKey, encodedOfflineCacheQueue);
    await prefs.setStringList(
      _watchedLocalFolderPathsKey,
      _watchedLocalFolderPaths,
    );
  }

  String _normalizeWatchedLocalFolderPath(String rootPath) {
    final trimmed = rootPath.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Folder path is required.');
    }
    return path.normalize(path.absolute(trimmed));
  }

  List<String> _dedupeWatchedLocalFolderPaths(Iterable<String> paths) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final rawPath in paths) {
      try {
        final value = _normalizeWatchedLocalFolderPath(rawPath);
        if (seen.add(value)) {
          normalized.add(value);
        }
      } on FormatException {
        continue;
      }
    }
    normalized.sort();
    return normalized;
  }

  bool _isLocalTrackWithinFolder(Track track, String rootPath) {
    final localPath = track.localPath;
    if (track.sourceId != 'local' || localPath == null || localPath.isEmpty) {
      return false;
    }
    final normalized = path.normalize(path.absolute(localPath));
    return normalized == rootPath || path.isWithin(rootPath, normalized);
  }

  Track _scannedTrackWithPreservedUserState(Track current, Track scanned) {
    return Track(
      id: scanned.id,
      title: scanned.title,
      artist: scanned.artist,
      album: scanned.album,
      genre: scanned.genre,
      duration: scanned.duration,
      artworkUri: current.artworkIsUserManaged
          ? current.artworkUri
          : scanned.artworkUri,
      artworkSourceUri: current.artworkIsUserManaged
          ? current.artworkSourceUri
          : null,
      artworkIsUserManaged: current.artworkIsUserManaged,
      artworkUriIsEphemeral: scanned.artworkUriIsEphemeral,
      providerArtworkId: scanned.providerArtworkId,
      providerArtworkVersion: scanned.providerArtworkVersion,
      localPath: scanned.localPath,
      contentHash: scanned.contentHash,
      streamUrl: scanned.streamUrl,
      streamUrlIsEphemeral: scanned.streamUrlIsEphemeral,
      sourceId: scanned.sourceId,
      externalId: scanned.externalId,
      isFavorite: current.isFavorite,
      chapters: current.chapters,
      addedAt: current.addedAt,
    );
  }

  bool _sameChapters(
    List<TrackChapter> left,
    List<TrackChapter> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].start != right[index].start ||
          left[index].title != right[index].title) {
        return false;
      }
    }
    return true;
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

class _MutableFolderNode {
  _MutableFolderNode({
    required this.key,
    required this.path,
    required this.label,
    required this.depth,
  });

  final String key;
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
