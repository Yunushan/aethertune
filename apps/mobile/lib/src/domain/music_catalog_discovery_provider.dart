import 'music_catalog_provider.dart';

enum MusicCatalogDiscoveryKind {
  recentlyAdded,
  frequentlyPlayed,
  recentlyPlayed,
  random,
}

/// Optional catalog extension for server-defined album discovery lists.
///
/// These lists reflect the provider's documented ordering. They are not
/// necessarily personalized recommendations.
abstract interface class MusicCatalogDiscoveryProvider
    implements MusicCatalogProvider {
  List<MusicCatalogDiscoveryKind> get discoveryKinds;

  Future<List<MusicCatalogCollection>> browseDiscoveryCollections(
    MusicCatalogDiscoveryKind kind, {
    int limit = 6,
  });
}
