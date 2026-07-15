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

/// Optional discovery extension for providers that can continue a discovery
/// list without changing the provider-defined ordering.
abstract interface class MusicCatalogDiscoveryPagingProvider
    implements MusicCatalogDiscoveryProvider {
  Set<MusicCatalogDiscoveryKind> get pagedDiscoveryKinds;

  Future<MusicCatalogCollectionPage> browseDiscoveryCollectionsPage(
    MusicCatalogDiscoveryKind kind, {
    int offset = 0,
    int limit = 6,
  });
}
