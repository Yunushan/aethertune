import 'dart:typed_data';

import 'music_source_provider.dart';
import 'track.dart';

enum MusicCatalogCollectionKind { artist, album, playlist }

enum MusicCatalogRadioSeedKind { track, artist, album }

final class MusicCatalogRadioSeed {
  const MusicCatalogRadioSeed({
    required this.kind,
    required this.id,
  });

  final MusicCatalogRadioSeedKind kind;
  final String id;
}

final class MusicCatalogCollection {
  const MusicCatalogCollection({
    required this.id,
    required this.title,
    required this.kind,
    this.subtitle = '',
    this.itemCount = 0,
    this.isFavorite = false,
    this.artworkId,
    this.artworkVersion,
  });

  final String id;
  final String title;
  final MusicCatalogCollectionKind kind;
  final String subtitle;
  final int itemCount;
  final bool isFavorite;
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

final class MusicCatalogCollectionPage {
  const MusicCatalogCollectionPage({
    required this.collections,
    required this.nextOffset,
    required this.hasMore,
    this.totalCount,
  });

  final List<MusicCatalogCollection> collections;
  final int nextOffset;
  final bool hasMore;
  final int? totalCount;
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

abstract interface class MusicCatalogPagingProvider
    implements MusicCatalogProvider {
  Set<MusicCatalogCollectionKind> get pagedCollectionKinds;

  Future<MusicCatalogCollectionPage> browseCollectionsPage(
    MusicCatalogCollectionKind kind, {
    int offset = 0,
    int limit = 100,
  });
}

/// Optional extension for providers with a documented radio or similar-items
/// endpoint.
abstract interface class MusicCatalogRadioProvider
    implements MusicCatalogProvider {
  Set<MusicCatalogRadioSeedKind> get radioSeedKinds;

  Future<List<Track>> loadRadio(
    MusicCatalogRadioSeed seed, {
    int limit = 50,
  });
}

abstract interface class MusicPlaylistMutationProvider {
  Future<void> createPlaylist(
    String name, {
    List<String> trackIds = const <String>[],
  });

  Future<void> renamePlaylist(String playlistId, String name);

  Future<void> deletePlaylist(String playlistId);

  Future<void> addPlaylistTracks(
    String playlistId,
    List<String> trackIds,
  );

  Future<void> replacePlaylistTracks(
    String playlistId,
    List<String> trackIds,
  );
}

/// Optional extension for user-owned catalogs that can persist a track's
/// favorite state on the remote server.
abstract interface class MusicTrackFavoriteMutationProvider {
  Future<void> setTrackFavorite(
    String trackId, {
    required bool isFavorite,
  });
}

/// Optional extension for user-owned catalogs that can persist an album's
/// favorite state on the remote server.
abstract interface class MusicAlbumFavoriteMutationProvider {
  Future<void> setAlbumFavorite(
    String albumId, {
    required bool isFavorite,
  });
}

abstract interface class MusicArtistFavoriteMutationProvider {
  Future<void> setArtistFavorite(
    String artistId, {
    required bool isFavorite,
  });
}
