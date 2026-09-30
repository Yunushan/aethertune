part of 'library_store.dart';

enum LibrarySortMode { recentlyAdded, title, artist, album, rating }

final class _NewerLibrarySchema implements Exception {
  const _NewerLibrarySchema();
}

final class _LibrarySearchQuery {
  const _LibrarySearchQuery._({
    required this.text,
    this.artist,
    this.album,
    this.genre,
    this.source,
    this.folder,
    this.minimumRating,
    this.year,
  });

  factory _LibrarySearchQuery.parse(String query) {
    final textTerms = <String>[];
    SearchQuery? artist;
    SearchQuery? album;
    SearchQuery? genre;
    SearchQuery? source;
    SearchQuery? folder;
    int? minimumRating;
    int? year;

    for (final term in _terms(query)) {
      if (term.isEmpty) {
        continue;
      }
      final ratingMatch = RegExp(
        r'^rating>=(\d)$',
        caseSensitive: false,
      ).firstMatch(term);
      if (ratingMatch != null) {
        final value = int.tryParse(ratingMatch.group(1)!);
        if (value != null && value >= 1 && value <= 5) {
          minimumRating = value;
          continue;
        }
      }
      final yearMatch = RegExp(
        r'^year:(\d{4})$',
        caseSensitive: false,
      ).firstMatch(term);
      if (yearMatch != null) {
        final value = int.tryParse(yearMatch.group(1)!);
        if (value != null && value >= 1 && value <= 9999) {
          year = value;
          continue;
        }
      }

      final separator = term.indexOf(':');
      if (separator <= 0 || separator == term.length - 1) {
        textTerms.add(term);
        continue;
      }
      final value = SearchQuery.parse(term.substring(separator + 1));
      if (value.isEmpty) {
        textTerms.add(term);
        continue;
      }
      switch (term.substring(0, separator).toLowerCase()) {
        case 'artist':
          artist = value;
        case 'album':
          album = value;
        case 'genre':
          genre = value;
        case 'source':
          source = value;
        case 'folder':
          folder = value;
        default:
          textTerms.add(term);
      }
    }

    return _LibrarySearchQuery._(
      text: SearchQuery.parse(textTerms.join(' ')),
      artist: artist,
      album: album,
      genre: genre,
      source: source,
      folder: folder,
      minimumRating: minimumRating,
      year: year,
    );
  }

  final SearchQuery text;
  final SearchQuery? artist;
  final SearchQuery? album;
  final SearchQuery? genre;
  final SearchQuery? source;
  final SearchQuery? folder;
  final int? minimumRating;
  final int? year;

  bool get isEmpty =>
      text.isEmpty &&
      artist == null &&
      album == null &&
      genre == null &&
      source == null &&
      folder == null &&
      minimumRating == null &&
      year == null;

  bool matchesTrack(Track track) {
    if (!_matches(track.artist, artist) ||
        !_matches(track.album, album) ||
        !_matches(track.genre, genre) ||
        !_matches(track.sourceId, source)) {
      return false;
    }
    if (minimumRating != null && track.rating < minimumRating!) {
      return false;
    }
    if (year != null && track.year != year) {
      return false;
    }
    return true;
  }

  bool _matches(String value, SearchQuery? filter) {
    return filter == null || searchTextMatches(value, filter);
  }

  static Iterable<String> _terms(String query) sync* {
    final buffer = StringBuffer();
    String? quote;

    for (var index = 0; index < query.length; index += 1) {
      final character = query[index];
      if (character == '"' || character == "'") {
        if (quote == null) {
          quote = character;
          continue;
        }
        if (quote == character) {
          quote = null;
          continue;
        }
      }
      if (quote == null && RegExp(r'\s').hasMatch(character)) {
        if (buffer.isNotEmpty) {
          yield buffer.toString();
          buffer.clear();
        }
        continue;
      }
      buffer.write(character);
    }
    if (buffer.isNotEmpty) {
      yield buffer.toString();
    }
  }
}

LibrarySortMode _librarySortModeFromName(String? value) {
  return LibrarySortMode.values.firstWhere(
    (mode) => mode.name == value,
    orElse: () => LibrarySortMode.recentlyAdded,
  );
}

enum PlaylistDocumentFormat { json, m3u, pls, xspf, wpl, csv }

const _playlistImportLinkScheme = 'aethertune';
const _playlistImportLinkHost = 'playlist';
const _customSmartPlaylistImportLinkHost = 'smart-playlist';
const _maxPlaylistImportLinkBytes = 48 * 1024;
const _maxXspfPlaylistBytes = 2 * 1024 * 1024;
const _maxXspfTracks = 500;
const _maxWplPlaylistBytes = 2 * 1024 * 1024;
const _maxWplTracks = 500;

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
  audioFingerprint,
  sourceExternalId,
  streamUrl,
  metadata,
}

enum SmartPlaylistType { favorites, recentlyAdded, recentlyPlayed, mostPlayed }

enum LibraryHomeSectionType {
  continueListening,
  audiobooks,
  recentlyPlayed,
  followedArtists,
  radioSeeds,
  mostPlayed,
  favorites,
  subscribedEpisodes,
  recentlyAdded,
}

/// Whether [track] should retain an interrupted listening position.
///
/// Podcast episodes and imported DRM-free M4B audiobooks are long-form media;
/// normal music tracks deliberately continue from the beginning.
bool isLongFormProgressTrack(Track track) {
  final localPath = track.localPath?.trim().toLowerCase() ?? '';
  return track.genre.toLowerCase() == 'podcast' ||
      track.sourceId.startsWith('podcast-') ||
      localPath.endsWith('.m4b');
}

/// The source subset to include in the combined following feed.
enum FollowingFeedSource { all, artists, podcasts, youtube }

enum LibraryChartRange { allTime, sevenDays, thirtyDays, year }

enum LibraryRecapPeriod { month, year }

enum ListeningRecapVisualTheme { midnight, daylight, signal, monochrome }

enum ListeningHistoryRange { all, sevenDays, thirtyDays, year }

enum LibraryMoodMixType { focus, energy, chill, workout, sleep }

enum LibraryRecommendationReason {
  favoriteArtist,
  favoriteAlbum,
  favoriteGenre,
  recentlyPlayedArtist,
  recentlyPlayedAlbum,
  recentlyPlayedGenre,
  favoriteTrack,
  highlyRated,
  unplayed,
  recentlyAdded,
}

enum LibrarySimilarityReason { artist, album, genre, folder, source }

enum LibraryCollectionSimilarityReason { artist, album, genre }

enum LibraryCollectionRadioReason {
  seedCollection,
  artist,
  album,
  genre,
  favorite,
  playHistory,
}

enum CustomSmartPlaylistSortMode {
  recentlyAdded,
  title,
  artist,
  album,
  recentlyPlayed,
  mostPlayed,
}

enum CustomSmartPlaylistMatchMode { all, any }

const maxCustomSmartPlaylistRuleGroupDepth = 8;
const maxCustomSmartPlaylistRulesPerGroup = 50;
const maxCustomSmartPlaylistGroupsPerGroup = 25;

enum CustomSmartPlaylistRuleField {
  searchText,
  sourceId,
  artist,
  album,
  genre,
  minimumDurationSeconds,
  maximumDurationSeconds,
  favoritesOnly,
  minimumRating,
  minimumPlayCount,
  minimumDaysSinceLastPlayed,
}

enum AppThemePreference { system, light, dark, amoled }

enum AppAccentColor { system, indigo, teal, rose, amber, violet, green }

enum AppLanguagePreference { system, english, turkish, arabic }

enum DesktopDensityPreference { comfortable, compact }

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
      case AppAccentColor.system:
        return 'System colors';
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

extension ListeningRecapVisualThemeLabel on ListeningRecapVisualTheme {
  String get label {
    switch (this) {
      case ListeningRecapVisualTheme.midnight:
        return 'Midnight';
      case ListeningRecapVisualTheme.daylight:
        return 'Daylight';
      case ListeningRecapVisualTheme.signal:
        return 'Signal';
      case ListeningRecapVisualTheme.monochrome:
        return 'Monochrome';
    }
  }
}

extension DesktopDensityPreferenceLabel on DesktopDensityPreference {
  String get label {
    switch (this) {
      case DesktopDensityPreference.comfortable:
        return 'Comfortable';
      case DesktopDensityPreference.compact:
        return 'Compact';
    }
  }
}

class SearchSuggestion {
  const SearchSuggestion({required this.type, required this.value});

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

class DuplicateTrackResolution {
  DuplicateTrackResolution({
    required this.keepTrackId,
    required Iterable<String> duplicateTrackIds,
  }) : duplicateTrackIds = List<String>.unmodifiable(duplicateTrackIds);

  final String keepTrackId;
  final List<String> duplicateTrackIds;
}

/// Summary of a user-approved external listening-history import.
final class PlaybackHistoryImportResult {
  const PlaybackHistoryImportResult({
    required this.received,
    required this.matched,
    required this.imported,
    required this.duplicates,
  });

  final int received;
  final int matched;
  final int imported;
  final int duplicates;
}

class _DuplicateResolutionPlan {
  const _DuplicateResolutionPlan({
    required this.keepTrackId,
    required this.removeIds,
  });

  final String keepTrackId;
  final Set<String> removeIds;
}

class _DuplicateResolutionSnapshot {
  const _DuplicateResolutionSnapshot({
    required this.tracks,
    required this.playlists,
    required this.history,
    required this.progressByTrackId,
    required this.bookmarksByTrackId,
    required this.lyricsByTrackId,
    required this.playbackSpeedOverrides,
    required this.stateRevision,
  });

  final List<Track> tracks;
  final List<Playlist> playlists;
  final List<PlaybackHistoryEntry> history;
  final Map<String, PlaybackProgressEntry> progressByTrackId;
  final Map<String, List<TrackBookmark>> bookmarksByTrackId;
  final Map<String, TrackLyrics> lyricsByTrackId;
  final Map<String, double> playbackSpeedOverrides;
  final int stateRevision;

  _DuplicateResolutionSnapshot withStateRevision(int stateRevision) {
    return _DuplicateResolutionSnapshot(
      tracks: tracks,
      playlists: playlists,
      history: history,
      progressByTrackId: progressByTrackId,
      bookmarksByTrackId: bookmarksByTrackId,
      lyricsByTrackId: lyricsByTrackId,
      playbackSpeedOverrides: playbackSpeedOverrides,
      stateRevision: stateRevision,
    );
  }
}

class _BookmarkTombstone {
  const _BookmarkTombstone({required this.id, required this.deletedAt});

  final String id;
  final DateTime deletedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'deletedAt': deletedAt.toIso8601String(),
  };

  static _BookmarkTombstone? tryFromJson(Map<String, Object?> json) {
    final id = json['id'];
    final deletedAt = json['deletedAt'];
    if (id is! String || id.trim().isEmpty || deletedAt is! String) {
      return null;
    }
    final parsedDeletedAt = DateTime.tryParse(deletedAt);
    if (parsedDeletedAt == null) {
      return null;
    }
    return _BookmarkTombstone(id: id, deletedAt: parsedDeletedAt);
  }
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
    required this.parentKey,
    required this.path,
    required this.label,
    required this.depth,
    required this.trackCount,
    required this.directTrackCount,
    required this.totalDuration,
    required this.childCount,
  });

  final String key;
  final String? parentKey;
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
  const LibraryHomeSection({required this.type, required this.tracks});

  final LibraryHomeSectionType type;
  final List<Track> tracks;
}

class LibraryChartsSnapshot {
  const LibraryChartsSnapshot({required this.range, required this.stats});

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

class PersonalizedRecommendationMatch {
  const PersonalizedRecommendationMatch({
    required this.track,
    required this.reasons,
    required this.score,
  });

  final Track track;
  final List<LibraryRecommendationReason> reasons;
  final int score;
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

class RelatedLibraryCollectionMatch {
  const RelatedLibraryCollectionMatch({
    required this.group,
    required this.reasons,
    required this.score,
  });

  final LibraryBrowseGroup group;
  final List<LibraryCollectionSimilarityReason> reasons;
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
    if (field == CustomSmartPlaylistRuleField.minimumRating) {
      final value = int.tryParse(normalizedValue) ?? 0;
      return value > 0
          ? CustomSmartPlaylistRule(
              field: field,
              value: value.clamp(1, 5).toString(),
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
  }) : rules = List.unmodifiable(rules),
       groups = List.unmodifiable(groups);

  final CustomSmartPlaylistMatchMode matchMode;
  final List<CustomSmartPlaylistRule> rules;
  final List<CustomSmartPlaylistRuleGroup> groups;

  bool get isEmpty => rules.isEmpty && groups.isEmpty;

  CustomSmartPlaylistRuleGroup? normalized({int depth = 0}) {
    if (depth >= maxCustomSmartPlaylistRuleGroupDepth) {
      return null;
    }
    final normalizedRules = rules
        .map((rule) => rule.normalized())
        .whereType<CustomSmartPlaylistRule>()
        .take(maxCustomSmartPlaylistRulesPerGroup)
        .toList(growable: false);
    final normalizedGroups = groups
        .map((group) => group.normalized(depth: depth + 1))
        .whereType<CustomSmartPlaylistRuleGroup>()
        .take(maxCustomSmartPlaylistGroupsPerGroup)
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
    if (raw is! Map || depth >= maxCustomSmartPlaylistRuleGroupDepth) {
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
              .take(maxCustomSmartPlaylistRulesPerGroup)
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
              .take(maxCustomSmartPlaylistGroupsPerGroup)
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
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
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
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static List<CustomSmartPlaylistRuleGroup> _ruleGroupsFromJson(Object? raw) {
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
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
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
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// A reusable Library search/filter state. It intentionally contains no track
/// data, so it is safe to back up and synchronize between devices.
class SavedLibraryView {
  SavedLibraryView({
    required this.id,
    required this.name,
    this.query = '',
    this.favoritesOnly = false,
    this.offlineOnly = false,
    this.sortMode = LibrarySortMode.recentlyAdded,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
       updatedAt = updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  final String id;
  final String name;
  final String query;
  final bool favoritesOnly;
  final bool offlineOnly;
  final LibrarySortMode sortMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  SavedLibraryView copyWith({
    String? id,
    String? name,
    String? query,
    bool? favoritesOnly,
    bool? offlineOnly,
    LibrarySortMode? sortMode,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SavedLibraryView(
      id: id ?? this.id,
      name: name ?? this.name,
      query: query ?? this.query,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      offlineOnly: offlineOnly ?? this.offlineOnly,
      sortMode: sortMode ?? this.sortMode,
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
      'offlineOnly': offlineOnly,
      'sortMode': sortMode.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory SavedLibraryView.fromJson(Map<String, Object?> json) {
    return SavedLibraryView(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Untitled library view',
      query: json['query'] as String? ?? '',
      favoritesOnly: json['favoritesOnly'] as bool? ?? false,
      offlineOnly: json['offlineOnly'] as bool? ?? false,
      sortMode: _librarySortModeFromName(json['sortMode'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
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
    this.topSources = const <LibraryStatsGroup>[],
    this.topFolders = const <LibraryStatsGroup>[],
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
  final List<LibraryStatsGroup> topSources;
  final List<LibraryStatsGroup> topFolders;
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
  const TrackRadioSeedQueue({required this.seedTrack, required this.tracks});

  final Track seedTrack;
  final List<Track> tracks;
}

class LibraryCollectionRadioMatch {
  const LibraryCollectionRadioMatch({
    required this.track,
    required this.reasons,
    required this.score,
  });

  final Track track;
  final List<LibraryCollectionRadioReason> reasons;
  final int score;
}

class LibraryCollectionRadioQueue {
  const LibraryCollectionRadioQueue({
    required this.type,
    required this.key,
    required this.label,
    required this.seedTrack,
    required this.tracks,
    required this.matches,
  });

  final LibraryBrowseType type;
  final String key;
  final String label;
  final Track seedTrack;
  final List<Track> tracks;
  final List<LibraryCollectionRadioMatch> matches;
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

final class _CollectionRadioCandidate {
  const _CollectionRadioCandidate({
    required this.track,
    required this.reasons,
    required this.score,
    this.lastPlayedAt,
  });

  final Track track;
  final List<LibraryCollectionRadioReason> reasons;
  final int score;
  final DateTime? lastPlayedAt;
}

final class _RecommendationCandidate {
  const _RecommendationCandidate({
    required this.track,
    required this.reasons,
    required this.score,
    required this.playCount,
    this.lastPlayedAt,
  });

  final Track track;
  final List<LibraryRecommendationReason> reasons;
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
    orElse: () => AppAccentColor.system,
  );
}

ListeningRecapVisualTheme _listeningRecapVisualThemeFromName(String? value) {
  return ListeningRecapVisualTheme.values.firstWhere(
    (theme) => theme.name == value,
    orElse: () => ListeningRecapVisualTheme.midnight,
  );
}

DesktopDensityPreference _desktopDensityPreferenceFromName(String? value) {
  return DesktopDensityPreference.values.firstWhere(
    (preference) => preference.name == value,
    orElse: () => DesktopDensityPreference.comfortable,
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
