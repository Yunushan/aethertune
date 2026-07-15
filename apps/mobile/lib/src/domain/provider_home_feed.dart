import 'music_catalog_discovery_provider.dart';
import 'music_catalog_provider.dart';

final class ProviderHomeSection {
  const ProviderHomeSection({
    required this.provider,
    required this.kind,
    required this.collections,
    this.discoveryKind,
    this.nextOffset = 0,
    this.hasMore = false,
  });

  final MusicCatalogProvider provider;
  final MusicCatalogCollectionKind kind;
  final List<MusicCatalogCollection> collections;
  final MusicCatalogDiscoveryKind? discoveryKind;
  final int nextOffset;
  final bool hasMore;
}

final class ProviderHomeFeedError {
  const ProviderHomeFeedError({
    required this.providerId,
    required this.providerName,
    required this.kind,
    this.discoveryKind,
  });

  final String providerId;
  final String providerName;
  final MusicCatalogCollectionKind kind;
  final MusicCatalogDiscoveryKind? discoveryKind;
}

final class ProviderHomeFeed {
  const ProviderHomeFeed({
    this.sections = const <ProviderHomeSection>[],
    this.errors = const <ProviderHomeFeedError>[],
  });

  final List<ProviderHomeSection> sections;
  final List<ProviderHomeFeedError> errors;

  bool get hasContent => sections.isNotEmpty;
}

final class ProviderHomeDiscoveryContinuation {
  const ProviderHomeDiscoveryContinuation({this.section, this.error});

  final ProviderHomeSection? section;
  final ProviderHomeFeedError? error;
}

final class ProviderHomeFeedCoordinator {
  const ProviderHomeFeedCoordinator();

  static const List<MusicCatalogCollectionKind> _fallbackKinds =
      <MusicCatalogCollectionKind>[
        MusicCatalogCollectionKind.album,
        MusicCatalogCollectionKind.playlist,
      ];

  Future<ProviderHomeFeed> load(
    Iterable<MusicCatalogProvider> providers, {
    int limitPerSection = 6,
    int maxProviders = 8,
  }) async {
    if (limitPerSection <= 0 || maxProviders <= 0) {
      return const ProviderHomeFeed();
    }

    final uniqueProviders = <MusicCatalogProvider>[];
    final providerIds = <String>{};
    for (final provider in providers) {
      final providerId = provider.id.trim();
      if (providerId.isEmpty || !providerIds.add(providerId)) {
        continue;
      }
      uniqueProviders.add(provider);
      if (uniqueProviders.length == maxProviders) {
        break;
      }
    }
    if (uniqueProviders.isEmpty) {
      return const ProviderHomeFeed();
    }

    final results = await Future.wait<List<_ProviderHomeLoadResult>>(
      uniqueProviders.map(
        (provider) => _loadProvider(
          provider,
          limitPerSection: limitPerSection,
        ),
      ),
    );
    final sections = <ProviderHomeSection>[];
    final errors = <ProviderHomeFeedError>[];
    for (final providerResults in results) {
      for (final result in providerResults) {
        if (result.section != null) {
          sections.add(result.section!);
        }
        if (result.error != null) {
          errors.add(result.error!);
        }
      }
    }

    return ProviderHomeFeed(
      sections: List<ProviderHomeSection>.unmodifiable(sections),
      errors: List<ProviderHomeFeedError>.unmodifiable(errors),
    );
  }

  Future<ProviderHomeDiscoveryContinuation> loadMore(
    ProviderHomeSection section, {
    int limit = 6,
  }) async {
    final provider = section.provider;
    final discoveryKind = section.discoveryKind;
    if (limit <= 0 ||
        !section.hasMore ||
        discoveryKind == null ||
        provider is! MusicCatalogDiscoveryPagingProvider ||
        !provider.pagedDiscoveryKinds.contains(discoveryKind)) {
      return const ProviderHomeDiscoveryContinuation();
    }

    try {
      final page = await provider.browseDiscoveryCollectionsPage(
        discoveryKind,
        offset: section.nextOffset,
        limit: limit,
      );
      final additional = _visibleCollections(
        page.collections,
        MusicCatalogCollectionKind.album,
        limit: limit,
        excludingIds: section.collections.map((collection) => collection.id),
      );
      final canContinue = page.hasMore && page.nextOffset > section.nextOffset;
      return ProviderHomeDiscoveryContinuation(
        section: ProviderHomeSection(
          provider: provider,
          kind: MusicCatalogCollectionKind.album,
          collections: List<MusicCatalogCollection>.unmodifiable(<
            MusicCatalogCollection
          >[...section.collections, ...additional]),
          discoveryKind: discoveryKind,
          nextOffset: canContinue ? page.nextOffset : section.nextOffset,
          hasMore: canContinue,
        ),
      );
    } on Object {
      return ProviderHomeDiscoveryContinuation(
        error: ProviderHomeFeedError(
          providerId: provider.id,
          providerName: provider.name,
          kind: MusicCatalogCollectionKind.album,
          discoveryKind: discoveryKind,
        ),
      );
    }
  }

  Future<List<_ProviderHomeLoadResult>> _loadProvider(
    MusicCatalogProvider provider, {
    required int limitPerSection,
  }) {
    if (provider is MusicCatalogDiscoveryProvider) {
      final discoveryKinds = <MusicCatalogDiscoveryKind>[];
      final seenKinds = <MusicCatalogDiscoveryKind>{};
      for (final kind in provider.discoveryKinds) {
        if (seenKinds.add(kind)) {
          discoveryKinds.add(kind);
        }
      }
      if (discoveryKinds.isNotEmpty) {
        return Future.wait<_ProviderHomeLoadResult>(
          <Future<_ProviderHomeLoadResult>>[
            for (final kind in discoveryKinds)
              _loadDiscoverySection(
                provider,
                kind,
                limit: limitPerSection,
              ),
            _loadSection(
              provider,
              MusicCatalogCollectionKind.playlist,
              limit: limitPerSection,
            ),
          ],
        );
      }
    }

    return Future.wait<_ProviderHomeLoadResult>(
      _fallbackKinds.map(
        (kind) => _loadSection(provider, kind, limit: limitPerSection),
      ),
    );
  }

  Future<_ProviderHomeLoadResult> _loadSection(
    MusicCatalogProvider provider,
    MusicCatalogCollectionKind kind, {
    required int limit,
  }) async {
    try {
      final visible = _visibleCollections(
        await provider.browseCollections(kind),
        kind,
        limit: limit,
      );

      return _ProviderHomeLoadResult(
        section: visible.isEmpty
            ? null
            : ProviderHomeSection(
                provider: provider,
                kind: kind,
                collections: visible,
              ),
      );
    } on Object {
      return _ProviderHomeLoadResult(
        error: ProviderHomeFeedError(
          providerId: provider.id,
          providerName: provider.name,
          kind: kind,
        ),
      );
    }
  }

  Future<_ProviderHomeLoadResult> _loadDiscoverySection(
    MusicCatalogDiscoveryProvider provider,
    MusicCatalogDiscoveryKind discoveryKind, {
    required int limit,
  }) async {
    try {
      if (provider is MusicCatalogDiscoveryPagingProvider &&
          provider.pagedDiscoveryKinds.contains(discoveryKind)) {
        final page = await provider.browseDiscoveryCollectionsPage(
          discoveryKind,
          limit: limit,
        );
        final visible = _visibleCollections(
          page.collections,
          MusicCatalogCollectionKind.album,
          limit: limit,
        );
        final canContinue = page.hasMore && page.nextOffset > 0;
        return _ProviderHomeLoadResult(
          section: visible.isEmpty
              ? null
              : ProviderHomeSection(
                  provider: provider,
                  kind: MusicCatalogCollectionKind.album,
                  collections: visible,
                  discoveryKind: discoveryKind,
                  nextOffset: canContinue ? page.nextOffset : 0,
                  hasMore: canContinue,
                ),
        );
      }
      final visible = _visibleCollections(
        await provider.browseDiscoveryCollections(
          discoveryKind,
          limit: limit,
        ),
        MusicCatalogCollectionKind.album,
        limit: limit,
      );
      return _ProviderHomeLoadResult(
        section: visible.isEmpty
            ? null
            : ProviderHomeSection(
                provider: provider,
                kind: MusicCatalogCollectionKind.album,
                collections: visible,
                discoveryKind: discoveryKind,
              ),
      );
    } on Object {
      return _ProviderHomeLoadResult(
        error: ProviderHomeFeedError(
          providerId: provider.id,
          providerName: provider.name,
          kind: MusicCatalogCollectionKind.album,
          discoveryKind: discoveryKind,
        ),
      );
    }
  }
}

List<MusicCatalogCollection> _visibleCollections(
  Iterable<MusicCatalogCollection> collections,
  MusicCatalogCollectionKind kind, {
  required int limit,
  Iterable<String> excludingIds = const <String>[],
}) {
  final visible = <MusicCatalogCollection>[];
  final collectionIds = excludingIds.map((id) => id.trim()).toSet();
  for (final collection in collections) {
    final id = collection.id.trim();
    if (collection.kind != kind ||
        id.isEmpty ||
        collection.title.trim().isEmpty ||
        !collectionIds.add(id)) {
      continue;
    }
    visible.add(collection);
    if (visible.length == limit) {
      break;
    }
  }
  return List<MusicCatalogCollection>.unmodifiable(visible);
}

final class _ProviderHomeLoadResult {
  const _ProviderHomeLoadResult({this.section, this.error});

  final ProviderHomeSection? section;
  final ProviderHomeFeedError? error;
}
