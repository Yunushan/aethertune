import '../domain/music_source_provider.dart';
import '../domain/track.dart';

/// A safe provider example that does not contact a network service.
///
/// Use this as a template for real legal providers.
class DemoSourceProvider implements MusicSourceSearchPagingProvider {
  const DemoSourceProvider();

  @override
  String get id => 'demo';

  @override
  String get name => 'Demo Provider';

  @override
  String get description =>
      'Provider template with metadata-only sample tracks. Add legal adapters in this shape.';

  @override
  Set<MusicSourceCapability> get capabilities => const <MusicSourceCapability>{
        MusicSourceCapability.metadataSearch,
      };

  @override
  ProviderPrivacyDisclosure get disclosure => const ProviderPrivacyDisclosure();

  @override
  Future<List<Track>> search(String query) async {
    return _matchingTracks(query);
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
    final offset = _demoSearchOffset(cursor);
    final matches = _matchingTracks(query);
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

  List<Track> _matchingTracks(String query) {
    final all = <Track>[
      Track(
        id: 'demo-ambient-001',
        title: 'Provider Architecture Demo',
        artist: 'AetherTune Contributors',
        album: 'Open Source Samples',
        genre: 'Architecture',
        sourceId: id,
      ),
      Track(
        id: 'demo-local-001',
        title: 'Import local audio to play real music',
        artist: 'Your Library',
        album: 'Local Files',
        genre: 'Local Library',
        sourceId: id,
      ),
    ];

    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return all;
    }

    return all.where((track) {
      return track.title.toLowerCase().contains(normalized) ||
          track.artist.toLowerCase().contains(normalized) ||
          track.album.toLowerCase().contains(normalized) ||
          track.genre.toLowerCase().contains(normalized);
    }).toList(growable: false);
  }

  @override
  Future<Uri?> resolveStream(Track track) async => null;
}

int _demoSearchOffset(String? cursor) {
  if (cursor == null) {
    return 0;
  }
  final offset = int.tryParse(cursor);
  if (offset == null || offset < 0) {
    throw ArgumentError.value(cursor, 'cursor', 'Invalid search cursor.');
  }
  return offset;
}
