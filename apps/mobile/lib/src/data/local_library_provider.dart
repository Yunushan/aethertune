import '../domain/music_source_provider.dart';
import '../domain/search_matcher.dart';
import '../domain/track.dart';
import 'local_media_uri.dart';

typedef LocalLibraryTrackSearch = List<Track> Function(String query);

class LocalLibraryProvider implements MusicSourceSearchPagingProvider {
  const LocalLibraryProvider({
    this.tracks = const <Track>[],
    LocalLibraryTrackSearch? searchTracks,
  }) : _searchTracks = searchTracks;

  static const providerId = 'local-library';

  final List<Track> tracks;
  final LocalLibraryTrackSearch? _searchTracks;

  @override
  String get id => providerId;

  @override
  String get name => 'Local Library';

  @override
  String get description =>
      'On-device AetherTune library adapter for unified search.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
        MusicSourceCapability.directPlayback,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure();

  @override
  Future<List<Track>> search(String query) async {
    final searchTracks = _searchTracks;
    if (searchTracks != null) {
      return searchTracks(query);
    }

    final searchQuery = SearchQuery.parse(query);
    if (searchQuery.isEmpty) {
      return tracks;
    }

    return tracks
        .where((track) => _trackMatchesQuery(track, searchQuery))
        .toList(growable: false);
  }

  @override
  Future<MusicSourceSearchPage> searchPage(
    String query, {
    String? cursor,
    int limit = 20,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'Must be positive.');
    }
    final offset = _localSearchOffset(cursor);
    final matches = await search(query);
    if (offset >= matches.length) {
      return MusicSourceSearchPage(
        tracks: const <Track>[],
        totalCount: matches.length,
      );
    }
    final requestedEnd = offset + limit;
    final end = requestedEnd < matches.length ? requestedEnd : matches.length;
    return MusicSourceSearchPage(
      tracks: List<Track>.unmodifiable(matches.sublist(offset, end)),
      nextCursor: end < matches.length ? end.toString() : null,
      totalCount: matches.length,
    );
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    final streamUrl = track.streamUrl;
    if (streamUrl != null && streamUrl.trim().isNotEmpty) {
      return Uri.tryParse(streamUrl);
    }

    final localPath = track.localPath;
    if (localPath != null && localPath.trim().isNotEmpty) {
      return localMediaUri(localPath);
    }

    return null;
  }
}

int _localSearchOffset(String? cursor) {
  if (cursor == null) {
    return 0;
  }
  final offset = int.tryParse(cursor);
  if (offset == null || offset < 0) {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
  return offset;
}

bool _trackMatchesQuery(Track track, SearchQuery query) {
  return searchFieldsMatch(
    <String>[
      track.title,
      track.artist,
      track.album,
      track.genre,
      track.sourceId,
      track.localPath ?? '',
    ],
    query,
  );
}
