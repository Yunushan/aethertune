import 'dart:typed_data';

import 'music_source_provider.dart';
import 'track.dart';

enum MusicCatalogCollectionKind { artist, album, playlist }

final class MusicCatalogCollection {
  const MusicCatalogCollection({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.itemCount = 0,
    this.artworkId,
    this.artworkVersion,
  });

  final String id;
  final String title;
  final MusicCatalogCollectionKind kind;
  final String subtitle;
  final int itemCount;
  final String? artworkId;
  final String? artworkVersion;
}

final class MusicCatalogDetail {
  const MusicCatalogDetail({
    required this.collection,
    this.collections = const <MusicCatalogCollection>[],
    this.tracks = const <Track>[],
  });

  final MusicCatalogCollection collection;
  final List<MusicCatalogCollection> collections;
  final List<Track> tracks;
}

abstract interface class MusicCatalogProvider implements MusicSourceProvider {
  Future<List<MusicCatalogCollection>> browseCollections(
    MusicCatalogCollectionKind kind,
  );

  Future<MusicCatalogDetail> loadCollection(
    MusicCatalogCollection collection,
  );

  Future<Uint8List?> loadArtwork(
    String artworkId, {
    String? version,
    int maxWidth = 512,
  });
}
