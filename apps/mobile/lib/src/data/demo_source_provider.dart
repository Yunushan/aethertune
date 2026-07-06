import '../domain/music_source_provider.dart';
import '../domain/track.dart';

/// A safe provider example that does not contact a network service.
///
/// Use this as a template for real legal providers.
class DemoSourceProvider implements MusicSourceProvider {
  const DemoSourceProvider();

  @override
  String get id => 'demo';

  @override
  String get name => 'Demo Provider';

  @override
  String get description =>
      'Provider template with metadata-only sample tracks. Add legal adapters in this shape.';

  @override
  Future<List<Track>> search(String query) async {
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
