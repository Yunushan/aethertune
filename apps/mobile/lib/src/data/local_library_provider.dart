import '../domain/music_source_provider.dart';
import '../domain/track.dart';

typedef LocalLibraryTrackSearch = List<Track> Function(String query);

class LocalLibraryProvider implements MusicSourceProvider {
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

    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return tracks;
    }

    return tracks
        .where((track) => _trackMatchesQuery(track, normalized))
        .toList(growable: false);
  }

  @override
  Future<Uri?> resolveStream(Track track) async {
    final streamUrl = track.streamUrl;
    if (streamUrl != null && streamUrl.trim().isNotEmpty) {
      return Uri.tryParse(streamUrl);
    }

    final localPath = track.localPath;
    if (localPath != null && localPath.trim().isNotEmpty) {
      return Uri.file(localPath);
    }

    return null;
  }
}

bool _trackMatchesQuery(Track track, String normalizedQuery) {
  return track.title.toLowerCase().contains(normalizedQuery) ||
      track.artist.toLowerCase().contains(normalizedQuery) ||
      track.album.toLowerCase().contains(normalizedQuery) ||
      track.genre.toLowerCase().contains(normalizedQuery) ||
      track.sourceId.toLowerCase().contains(normalizedQuery) ||
      (track.localPath?.toLowerCase().contains(normalizedQuery) ?? false);
}
